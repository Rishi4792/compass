#!/usr/bin/env bash
# Compass enforcement CLI — the real teeth.
# Deterministic checks over .claude/builds/<slug>/receipts.md and friends.
# Every subcommand exits NON-ZERO on failure, so a skill that runs it cannot
# proceed past a missing/failed/stale proof. This is what makes the gate real
# rather than prose the model grades itself against.
#
# Usage (single-build gate, unchanged):
#   compass.sh gate         <build-dir> <prior-stage>   # block unless prior receipt is PASS/complete/not-superseded
#   compass.sh scan-receipt <build-dir> <stage>         # self-check the stage's latest receipt
#   compass.sh supersede    <build-dir> <from-stage>    # on escalation/re-run: void from-stage + later receipts
#   compass.sh reconcile    <actual> <gold> <tol>       # numeric gate; tol like 0, 0.1, or 1%
#   compass.sh secret-scan  <build-dir> [files...]      # fail if a secret looks committed
#   compass.sh close        <build-dir> <slug>          # close: teardown DB + worktree, drop locks, clear CURRENT hint
#
# Usage (parallel-builds keystone — see docs/PARALLEL-BUILDS-KEYSTONE.md):
#   compass.sh state-root                               # canonical STATE_ROOT (main checkout's .claude/builds)
#   compass.sh active-builds                            # list in-flight slugs (status NOT terminal)
#   compass.sh worktree     <slug> [base-branch]        # create/ensure the build's worktree + branch (idempotent)
#   compass.sh promote      <slug>                      # move an in-flight build from the main checkout into a worktree
#   compass.sh worktree-rm  <slug> [--force]            # remove the build's worktree (refuse if dirty/unmerged)
#   compass.sh assert-worktree <slug>                   # exit non-zero unless cwd is that slug's worktree
#   compass.sh claim        <slug> [globs...|--from <file>]  # record claimed files (run IN the worktree)
#   compass.sh check-overlap <slug>                     # non-zero if claimed files intersect another active build
#   compass.sh check-db-isolation <slug> <has-schema-change:0|1> [db-provision-declared:0|1]
#   compass.sh install-guard                            # install the single slug-agnostic pre-commit hook
#   compass.sh audit-staged <slug>                      # post-hoc: fail if staged files escape the slug's claim
#   compass.sh gc                                        # remove worktrees/branches of terminal builds
#
# Lifecycle order (used by gate freshness + supersede):
#   contract review-contract plan review-plan build review-build ship
set -euo pipefail

LIFECYCLE="contract review-contract plan review-plan build review-build ship"
TERMINAL_STATUSES="CLOSED SHIPPED ROLLED-BACK"

die() { echo "COMPASS-GATE: FAIL — $*" >&2; exit 1; }
ok()  { echo "COMPASS-GATE: PASS — $*"; }

# ── path helpers ───────────────────────────────────────────────────────────
# STATE_ROOT = the MAIN checkout's .claude/builds, resolved identically from the
# main checkout OR any linked worktree (git-common-dir points at the main .git).
state_root() {
  git rev-parse --git-dir >/dev/null 2>&1 || die "not in a git repo — Compass state needs git."
  local common main_root
  common="$(cd "$(git rev-parse --git-common-dir)" && pwd)" || die "cannot resolve git-common-dir."
  main_root="$(cd "$(dirname "$common")" && pwd)"
  printf '%s/.claude/builds' "$main_root"
}
locks_dir() { printf '%s/.locks' "$(state_root)"; }

# ── v0.12.0 S2a: shared pinned-grammar parsers (contract v3a "Pinned gate-read grammars") ──
# norm_line: delete every `*` (bold-tolerant), used before any header match (RD-2).
norm_line() { printf '%s' "$1" | tr -d '*'; }
# hdr_get <file> <key>: print the FIRST pinned header line's value (post-normalization,
# `^[- ]*<key>:` anchored, trailing space trimmed); exit 1 if absent. Keys are fixed literals.
hdr_get() { # <file> <key>
  local f="${1:-}" key="${2:-}"
  [ -f "$f" ] && [ -n "$key" ] || return 1
  awk -v key="$key" '
    { line=$0; gsub(/\*/,"",line)
      pat="^[- ]*" key ":[ \t]*"
      if (line ~ pat) { sub(pat,"",line); sub(/[ \t]+$/,"",line); print line; found=1; exit } }
    END { exit (found ? 0 : 1) }' "$f"
}
# ps_open_rows <ledger-file>: count OPEN Crit/Maj PS- rows per the pinned grammar
# `| PS-<r>-<k> | R<r> | <SEV> | <where> | <finding> | <fix> | <OPEN|CLOSED> |`.
# Prints the count (0 on missing file). Deliberately NOT ledger_open_rows (RC-10).
ps_open_rows() { # <ledger-file>
  local f="${1:-}"
  [ -f "$f" ] || { printf '0'; return 0; }
  awk -F'|' '
    function trim(x){ gsub(/^[ \t]+|[ \t]+$/,"",x); return x }
    { id=trim($2); sev=trim($4); st=trim($8)
      if (id ~ /^PS-[0-9]+-[0-9]+$/ && (sev=="CRITICAL" || sev=="MAJOR") && st=="OPEN") n++ }
    END { printf "%d", n }' "$f"
}

# main checkout root (parent of the common .git)
main_root() {
  local common; common="$(cd "$(git rev-parse --git-common-dir)" && pwd)"
  cd "$(dirname "$common")" && pwd
}

# Portable mutex (macOS has no flock). mkdir is atomic on POSIX filesystems.
with_lock() { # <name> <command...>
  local lock; lock="$(locks_dir)/.$1.lock"; shift
  mkdir -p "$(dirname "$lock")"
  local tries=0
  until mkdir "$lock" 2>/dev/null; do
    tries=$((tries+1)); [ "$tries" -gt 600 ] && die "lock timeout on $lock"
    sleep 0.05
  done
  # shellcheck disable=SC2064
  trap "rmdir '$lock' 2>/dev/null || true" RETURN
  "$@"
}

atomic_write() { # <dest> ; content on stdin
  local dest="$1" tmp; tmp="$(mktemp "${dest}.XXXXXX")"
  cat > "$tmp"
  mv -f "$tmp" "$dest"
}

# v0.6.0 — centralized worktree home (out of the project's parent; overridable for tests).
managed_home() { printf '%s' "${COMPASS_WORKTREE_HOME:-$HOME/.compass/worktrees}"; }
# Stable, collision-safe id for this repo: <basename>-<cksum of abs main-root path>.
project_id() {
  local root; root="$(main_root)"
  printf '%s-%s' "$(basename "$root")" "$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
}
# slug → its worktree path  <home>/<project-id>/<slug>  (centralized; no longer a project sibling)
worktree_path() { # <slug>
  printf '%s/%s/%s' "$(managed_home)" "$(project_id)" "$1"
}
# Derive the build slug from the current worktree's BRANCH (`compass/<slug>`), not its path —
# location-independent (survives the centralized home + macOS /tmp↔/private symlinks). ONE source
# of truth: the guard + resume + assert-worktree all go through `compass.sh cwd-slug`.
cwd_slug() {
  local br; br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 0
  case "$br" in compass/*) printf '%s' "${br#compass/}" ;; *) printf '' ;; esac
}

# ── INDEX / status ─────────────────────────────────────────────────────────
# INDEX line: "slug · goal · status=X · ..."  — status field parsed loosely.
build_status() { # <slug>
  local idx; idx="$(state_root)/INDEX"
  [ -f "$idx" ] || { printf 'UNKNOWN'; return; }
  local line; line="$(grep -E "^${1}( |·|	)" "$idx" 2>/dev/null | head -n1 || true)"
  [ -n "$line" ] || { printf 'UNKNOWN'; return; }
  printf '%s' "$line" | sed -nE 's/.*status=([A-Za-z-]+).*/\1/p' | head -n1 | grep . || printf 'UNKNOWN'
}

is_terminal() { # <status>
  case " $TERMINAL_STATUSES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# ── v0.9.0: session ownership (window/session-scoped Stop hook) ──────────────
# owner_of: print the recorded owner session id for a slug, or empty. STRICT extract
# (session=<value>), trims CR + trailing ws. NEVER errors / never die()s — safe to call
# from the Stop hook under set -euo pipefail. Optional <locks-dir> lets the hook pass its
# inline-resolved dir (avoids locks_dir→state_root die() in edge contexts).
owner_of() { # <slug> [locks-dir]
  local ld="${2:-}"; [ -n "$ld" ] || ld="$(locks_dir 2>/dev/null || true)"
  [ -n "$ld" ] || { printf ''; return 0; }
  local f="$ld/$1.owner"
  [ -f "$f" ] || { printf ''; return 0; }
  sed -nE 's/^session=(.+)$/\1/p' "$f" 2>/dev/null | head -n1 | tr -d '\r' | sed 's/[[:space:]]*$//' 2>/dev/null || printf ''
}

# cmd_own: bind a build's owner = a session id. REFUSES an empty id (so an empty owner can
# never spuriously match an empty/absent stopping id). Logs when it displaces a DIFFERENT
# owner (the rare two-live-terminals-one-build case). Session = --session <id> or $CLAUDE_CODE_SESSION_ID.
cmd_own() { # <slug> [--session <id>]
  local slug="${1:-}"; shift || true
  [ -n "$slug" ] || die "usage: compass.sh own <slug> [--session <id>]"
  local sid=""
  if [ "${1:-}" = "--session" ]; then sid="${2:-}"; else sid="${CLAUDE_CODE_SESSION_ID:-}"; fi
  [ -n "$sid" ] || die "own '$slug': empty session id (pass --session <id> or set \$CLAUDE_CODE_SESSION_ID) — refusing to write an empty owner."
  local ld; ld="$(locks_dir)"; mkdir -p "$ld"
  local prev; prev="$(owner_of "$slug" "$ld")"
  if [ -n "$prev" ] && [ "$prev" != "$sid" ]; then
    echo "compass: own '$slug' — displacing previous owner session ($prev → $sid)." >&2
  fi
  printf 'session=%s\n' "$sid" | atomic_write "$ld/$slug.owner"
  ok "owner of '$slug' = session $sid."
}

# ── v0.9.0: ship coordination (single-flight + contention ordering) ─────────
# resolve_status: a build's status resolved the SAME way stop-guard does — progress.md
# **Status:** primary, INDEX `status=` fallback — lowercased. So a manually-corrected/stale
# INDEX can neither miss nor invent a ship contender. Empty → "unknown".
resolve_status() { # <slug>
  local sr; sr="$(state_root 2>/dev/null || true)"; [ -n "$sr" ] || { printf 'unknown'; return 0; }
  local s; s="$(sed -nE 's/^\*\*Status:\*\*[[:space:]]*([A-Za-z()0-9 -]+).*/\1/p' "$sr/$1/progress.md" 2>/dev/null | tail -1 | tr 'A-Z' 'a-z' || true)"
  [ -n "$s" ] || s="$(build_status "$1" 2>/dev/null | tr 'A-Z' 'a-z' || true)"
  printf '%s' "${s:-unknown}"
}

# ship-claim: single-flight ship mutex. Atomic mkdir; records holder+epoch ts. Self-healing
# (R2-06): steals ONLY when the holder is SHIPPED/ROLLED-BACK (truly done) or the lock is
# older than COMPASS_SHIP_LOCK_TTL (default 2h) — NEVER on CLOSED (that's the live mid-ship
# state). Otherwise refuses non-zero, naming the live holder. So a failed ship cannot deadlock.
cmd_ship_claim() { # <slug>
  local slug="${1:-}"; [ -n "$slug" ] || die "usage: compass.sh ship-claim <slug>"
  local ld; ld="$(locks_dir)"; mkdir -p "$ld"; local lock="$ld/.ship.lock"
  local ttl="${COMPASS_SHIP_LOCK_TTL:-7200}" now; now="$(date +%s 2>/dev/null || echo 0)"
  if mkdir "$lock" 2>/dev/null; then
    { printf 'holder=%s\n' "$slug"; printf 'ts=%s\n' "$now"; } > "$lock/info"
    ok "ship-claim: '$slug' holds the ship lock."; return 0
  fi
  local holder hts st age
  holder="$(sed -nE 's/^holder=(.*)/\1/p' "$lock/info" 2>/dev/null | head -1 || true)"
  hts="$(sed -nE 's/^ts=(.*)/\1/p' "$lock/info" 2>/dev/null | head -1 || true)"
  case "${hts:-}" in ''|*[!0-9]*) hts=0 ;; esac
  [ "$holder" = "$slug" ] && { ok "ship-claim: '$slug' already holds the lock (idempotent)."; return 0; }
  st="$(build_status "$holder" 2>/dev/null || echo UNKNOWN)"
  age=$(( now - hts ))
  # Steal a corrupt lock too: an empty holder or a missing/garbage ts (hts<=0) means a partial
  # write / crash in the mkdir→info window — by definition stale, never a live holder (a real
  # claim always writes holder + a large epoch ts). Else: terminal holder, or age past TTL.
  if [ -z "$holder" ] || [ "$hts" -le 0 ] || [ "$st" = "SHIPPED" ] || [ "$st" = "ROLLED-BACK" ] || [ "$age" -ge "$ttl" ]; then
    { printf 'holder=%s\n' "$slug"; printf 'ts=%s\n' "$now"; } > "$lock/info"
    ok "ship-claim: '$slug' STOLE a stale ship lock (prev '$holder' status=$st age=${age}s)."; return 0
  fi
  die "ship-claim: ship lock held by '$holder' (status=$st, age=${age}s) — one build ships at a time. Wait (self-heals after ${ttl}s) or have the holder run 'compass.sh ship-release $holder'."
}

# ship-release: drop the ship lock ONLY if this slug holds it (guarded; never errors if absent).
cmd_ship_release() { # <slug>
  local slug="${1:-}"; [ -n "$slug" ] || die "usage: compass.sh ship-release <slug>"
  local ld; ld="$(locks_dir 2>/dev/null || true)"; [ -n "$ld" ] || return 0
  local lock="$ld/.ship.lock"; [ -d "$lock" ] || { ok "ship-release: no ship lock held."; return 0; }
  local holder; holder="$(sed -nE 's/^holder=(.*)/\1/p' "$lock/info" 2>/dev/null | head -1 || true)"
  if [ "$holder" = "$slug" ]; then rm -rf "$lock" 2>/dev/null || true; ok "ship-release: '$slug' released the ship lock."
  else ok "ship-release: lock held by '${holder:-?}', not '$slug' — left intact."; fi
}

# ship-contenders: list OTHER same-project builds that are ship-ready = status CLOSED AND
# contract lacks `deploy: out-of-scope`. Self excluded. Status via resolve_status (R2-09).
cmd_ship_contenders() { # <slug>
  local self="${1:-}"; [ -n "$self" ] || die "usage: compass.sh ship-contenders <slug>"
  local sr; sr="$(state_root)"; [ -f "$sr/INDEX" ] || return 0
  local line slug st
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    slug="$(printf '%s' "$line" | sed -nE 's/^([^ ·	]+).*/\1/p')"; [ -n "$slug" ] || continue
    [ "$slug" = "$self" ] && continue
    st="$(resolve_status "$slug")"
    case "$st" in *shipped*|*rolled-back*) continue ;; esac
    case "$st" in *closed*) ;; *) continue ;; esac
    grep -qiE '^[[:space:]]*[-*]?[[:space:]]*deploy:[[:space:]]*out-of-scope' "$sr/$slug/contract.md" 2>/dev/null && continue
    echo "$slug"
  done < "$sr/INDEX"
  return 0
}

cmd_active_builds() {
  local idx; idx="$(state_root)/INDEX"
  [ -f "$idx" ] || { ok "no INDEX — 0 active builds."; return; }
  local any=0 slug st
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in \#*) continue ;; esac
    slug="$(printf '%s' "$line" | sed -nE 's/^([A-Za-z0-9_-]+).*/\1/p')"
    [ -n "$slug" ] || continue
    st="$(build_status "$slug")"
    if ! is_terminal "$st"; then echo "$slug ($st)"; any=1; fi
  done < "$idx"
  [ "$any" = 1 ] || ok "0 active builds."
}

# ── worktree lifecycle ─────────────────────────────────────────────────────
cmd_worktree() { # <slug> [base]
  local slug="$1" base="${2:-}" wt; wt="$(worktree_path "$slug")"
  # Default base = the REAL merge target's remote ref (never local main — it may be a feature branch).
  if [ -z "$base" ]; then
    if git show-ref --verify --quiet refs/remotes/origin/main; then base="origin/main"
    elif git symbolic-ref --quiet refs/remotes/origin/HEAD >/dev/null 2>&1; then base="$(git symbolic-ref --short refs/remotes/origin/HEAD)"
    else base="HEAD"; fi
  fi
  if git worktree list --porcelain | grep -qxF "worktree $wt"; then ok "worktree exists: $wt"; printf '%s\n' "$wt"; return; fi
  mkdir -p "$(dirname "$wt")"
  if git show-ref --verify --quiet "refs/heads/compass/$slug"; then
    git worktree add "$wt" "compass/$slug" >&2 || die "git worktree add failed for $slug"
  else
    git worktree add "$wt" -b "compass/$slug" "$base" >&2 || die "git worktree add -b failed for $slug"
  fi
  # Record the base anchor (branch + resolved SHA) in its OWN file so claim's meta-rewrite can't clobber it (RC-2).
  local ld; ld="$(locks_dir)"; mkdir -p "$ld"
  { printf 'base_branch=%s\n' "$base"; printf 'base_sha=%s\n' "$(git rev-parse "$base" 2>/dev/null || echo unknown)"; } > "$ld/$slug.base"
  ok "worktree ready: $wt (branch compass/$slug, base $base)"
  printf '%s\n' "$wt"
}

cmd_promote() { # <slug>  — move an in-flight build into a worktree
  local slug="$1" wt; wt="$(worktree_path "$slug")"
  if git worktree list --porcelain | grep -qxF "worktree $wt"; then ok "already promoted: $wt"; printf '%s\n' "$wt"; return; fi
  cmd_worktree "$slug" >/dev/null
  ok "promoted '$slug' to its own worktree — continue the build there: $wt"
  printf '%s\n' "$wt"
}

cmd_worktree_rm() { # <slug> [--force]
  local slug="$1" force="${2:-}" wt; wt="$(worktree_path "$slug")"
  git worktree list --porcelain | grep -qxF "worktree $wt" || { ok "no worktree for '$slug' (nothing to remove)."; return; }
  if [ "$force" = "--force" ]; then
    git worktree remove --force "$wt" >&2 || die "worktree remove --force failed."
  else
    git worktree remove "$wt" >&2 || die "worktree '$slug' is dirty or has unmerged work — commit/merge or pass --force."
  fi
  ok "removed worktree for '$slug'."
}

cmd_assert_worktree() { # <slug>
  local slug="$1" cur; cur="$(cwd_slug)"
  [ "$cur" = "$slug" ] || die "not in build '$slug' worktree (cwd slug='${cur:-<none>}'). cd to $(worktree_path "$slug") first."
  ok "cwd is the '$slug' worktree."
}

# ── claims / overlap ───────────────────────────────────────────────────────
_claim_write() { # <slug> ; files on stdin
  local slug="$1" ld; ld="$(locks_dir)"; mkdir -p "$ld"
  sort -u | grep . | atomic_write "$ld/$slug.files"
  printf 'worktree=%s\nbranch=compass/%s\nstatus=%s\n' "$(worktree_path "$slug")" "$slug" "$(build_status "$slug")" \
    | atomic_write "$ld/$slug.meta"
}

cmd_claim() { # <slug> [globs...|--from <file>]
  local slug="$1"; shift || true
  local files
  if [ "${1:-}" = "--from" ]; then
    [ -f "${2:-}" ] || die "claim --from: file not found: ${2:-}"
    files="$(cat "$2")"
  elif [ "$#" -gt 0 ]; then
    # Expand globs against the tracked tree IN THIS worktree (file-level, D7).
    files="$(git ls-files -- "$@" 2>/dev/null || true)"
  else
    die "claim needs globs or --from <file>."
  fi
  [ -n "$files" ] || die "claim for '$slug' expanded to ZERO files — pass real paths/globs or a --from list incl. NEW files."
  printf '%s\n' "$files" | with_lock "claim-$slug" _claim_write "$slug"
  ok "claimed $(printf '%s\n' "$files" | grep -c .) files for '$slug'."
}

# Is path $1 acked between the two slugs?
_is_acked() { # <slugA> <slugB> <path>
  local acks; acks="$(locks_dir)/acks"; [ -f "$acks" ] || return 1
  grep -qxF "ack:$1+$3:$2" "$acks" 2>/dev/null || grep -qxF "ack:$2+$3:$1" "$acks" 2>/dev/null \
    || grep -qxF "ack:$1+$2:$3" "$acks" 2>/dev/null
}

cmd_check_overlap() { # <slug>
  local slug="$1" ld; ld="$(locks_dir)"
  [ -f "$ld/$slug.files" ] || die "no claim for '$slug' — run 'claim' first."
  local other ost hits=0 acks; acks="$ld/acks"
  for f in "$ld"/*.files; do
    [ -e "$f" ] || continue
    other="$(basename "$f" .files)"; [ "$other" = "$slug" ] && continue
    ost="$(build_status "$other")"; is_terminal "$ost" && continue
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      if grep -qxF "$path" "$ld/$slug.files" 2>/dev/null; then
        if [ -f "$acks" ] && grep -qxF "ack:$slug+$other:$path" "$acks" 2>/dev/null; then continue; fi
        if [ -f "$acks" ] && grep -qxF "ack:$other+$slug:$path" "$acks" 2>/dev/null; then continue; fi
        echo "OVERLAP: $slug ↔ $other : $path" >&2; hits=$((hits+1))
      fi
    done < "$f"
  done
  [ "$hits" = 0 ] || die "$hits unacked file overlap(s) with active build(s). Coordinate additively, then ack:<slug>+<other>:<path> in $acks, or stop."
  ok "no unacked file overlap for '$slug'."
}

cmd_check_db_isolation() { # <slug> <has-schema-change> [db-provision-declared]
  local slug="$1" has_schema="${2:-0}" provided="${3:-0}"
  [ "$has_schema" = 1 ] || { ok "'$slug' has no schema change — DB isolation N/A."; return; }
  [ "$provided" = 1 ] && { ok "'$slug' brings db_provision — isolated DB per worktree."; return; }
  # schema change + no isolation: only safe if no OTHER build is active.
  local others; others="$(cmd_active_builds 2>/dev/null | grep -v "^$slug " | grep -v 'PASS —' || true)"
  [ -z "$others" ] || die "'$slug' changes schema with NO db_provision while other builds are active:
$others
Parallel schema-touching builds need contract isolation.db_provision (per-worktree DATABASE_URL). Refusing parallel mode."
  ok "'$slug' changes schema but is the only active build — safe."
}

# ── guard (pre-commit) ─────────────────────────────────────────────────────
cmd_install_guard() {
  local hooks; hooks="$(cd "$(git rev-parse --git-common-dir)" && pwd)/hooks"; mkdir -p "$hooks"
  local hook="$hooks/pre-commit"
  if [ -f "$hook" ] && ! grep -q 'COMPASS-GUARD' "$hook" 2>/dev/null; then
    mv "$hook" "$hook.precompass"   # chain the pre-existing hook
  fi
  cat > "$hook" <<'GUARD'
#!/usr/bin/env bash
# COMPASS-GUARD — blocks staged files that escape the active build's claim.
set -euo pipefail
[ -x "$(dirname "$0")/pre-commit.precompass" ] && "$(dirname "$0")/pre-commit.precompass"
SH="$(git config --get compass.scriptpath 2>/dev/null || true)"
[ -n "$SH" ] && [ -x "$SH" ] || exit 0   # guard off if script path unknown
common="$(cd "$(git rev-parse --git-common-dir)" && pwd)"
state="$(cd "$(dirname "$common")" && pwd)/.claude/builds"; ld="$state/.locks"
[ -d "$ld" ] || exit 0
staged="$(git diff --cached --name-only)"
[ -n "$staged" ] || exit 0
fail=0
slug="$("$SH" cwd-slug 2>/dev/null || true)"   # ONE source of truth for "which worktree am I in"
if [ -n "$slug" ]; then
  # inside a build worktree → must stay within THAT slug's claim
  [ -f "$ld/$slug.files" ] || exit 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -qxF "$f" "$ld/$slug.files" || { echo "COMPASS-GUARD: '$f' is outside build '$slug' claim — re-run compass.sh claim or unstage it." >&2; fail=1; }
  done <<< "$staged"
else
  # main checkout → must NOT commit any active build's claimed file
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    for cf in "$ld"/*.files; do
      [ -e "$cf" ] || continue
      grep -qxF "$f" "$cf" && { echo "COMPASS-GUARD: '$f' is claimed by build '$(basename "$cf" .files)' — commit it from that build's worktree, not the main checkout." >&2; fail=1; }
    done
  done <<< "$staged"
fi
[ "$fail" = 0 ] || { echo "COMPASS-GUARD: commit blocked. (Bypassing with --no-verify is banned; an audit will catch it.)" >&2; exit 1; }
exit 0
GUARD
  chmod +x "$hook"
  git config compass.scriptpath "$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  ok "installed slug-agnostic pre-commit guard at $hook"
}

cmd_audit_staged() { # <slug> — post-hoc bypass detector over the last commit
  local slug="$1" ld; ld="$(locks_dir)"
  [ -f "$ld/$slug.files" ] || die "no claim for '$slug' to audit against."
  local changed; changed="$(git show --name-only --pretty=format: HEAD 2>/dev/null | grep . || true)"
  local esc=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -qxF "$f" "$ld/$slug.files" || { echo "AUDIT: HEAD touched '$f' outside '$slug' claim (possible --no-verify bypass)." >&2; esc=1; }
  done <<< "$changed"
  [ "$esc" = 0 ] || die "last commit escaped build '$slug' claim — review for contamination."
  ok "HEAD commit stays within '$slug' claim."
}

# ── post-merge reconciliation gate ─────────────────────────────────────────
cmd_merged_recon() { # <slugA> <slugB> <base>
  local a="$1" b="$2" base="$3" tmp; tmp="$(worktree_path "_merged_${a}_${b}")"
  git worktree add --detach "$tmp" "$base" >&2 || die "cannot create merge-check worktree."
  # shellcheck disable=SC2064
  trap "git worktree remove --force '$tmp' 2>/dev/null || true" RETURN
  ( cd "$tmp" && git merge --no-edit "compass/$a" "compass/$b" >&2 ) || die "branches do not merge cleanly — resolve conflicts (package-lock/migrations) first."
  local sr; sr="$(state_root)"
  for s in "$a" "$b"; do
    local cmd; cmd="$(grep -E '^RECON-CMD:' "$sr/$s/receipts.md" 2>/dev/null | tail -n1 | sed -E 's/^RECON-CMD:[[:space:]]*//' || true)"
    [ -n "$cmd" ] || { echo "merged-recon: '$s' has no RECON-CMD in receipts — record one to gate the merge." >&2; continue; }
    ( cd "$tmp" && eval "$cmd" >&2 ) || die "post-merge reconciliation FAILED for '$s' on the merged tree — union is broken; do not merge."
  done
  ok "merged tree reconciles for both '$a' and '$b'."
}

# ── GC ─────────────────────────────────────────────────────────────────────
# THE shared dirty-safe removal (RP-3 / the v0.5.0 incident): NEVER force — a dirty/unmerged
# worktree refuses removal and is left intact. Returns 0 removed, 1 kept-dirty.
safe_remove_worktree() { # <path>
  git worktree remove "$1" 2>/dev/null
}
cmd_gc() {
  local removed=0 kept=0 home; home="$(managed_home)"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    local wt; wt="${line#worktree }"
    case "$wt" in "$home"/*) ;; *.compass/*) ;; *) continue ;; esac   # managed home OR legacy sibling only
    local slug; slug="$(basename "$wt")"
    case "$slug" in _merged_*) git worktree remove --force "$wt" 2>/dev/null && removed=$((removed+1)); continue ;; esac
    local st; st="$(build_status "$slug")"
    # orphan (no INDEX entry) OR terminal → eligible; but NEVER force — dirty survives (RP-3).
    if [ "$st" = "UNKNOWN" ] || is_terminal "$st"; then
      if safe_remove_worktree "$wt"; then
        removed=$((removed+1)); git branch -D "compass/$slug" 2>/dev/null || true
        # v0.9.0: only NOW (worktree actually gone) drop ownership/guard state, so a still-live
        # build whose worktree survived dirty is never orphaned (R2-09/L1). Guarded — never fails gc.
        local gld; gld="$(locks_dir 2>/dev/null || true)"
        [ -n "$gld" ] && rm -f "$gld/$slug.owner" "$gld/$slug.blocked" 2>/dev/null || true
        cmd_ship_release "$slug" >/dev/null 2>&1 || true
      else
        kept=$((kept+1)); echo "gc: '$slug' has uncommitted work — LEFT in place (resolve, then gc)." >&2
      fi
    fi
  done < <(git worktree list --porcelain | grep '^worktree ')
  ok "gc removed $removed worktree(s); kept $kept dirty."
}

# ── existing teeth (unchanged behavior) ────────────────────────────────────
last_block() { # <file> <stage>
  awk -v s="$2" '
    $0 ~ ("^## RECEIPT[ ]*[—-][ ]*" s "[ ]*[·|]") { buf=$0 "\n"; cap=1; next }
    cap && /^## / { last=buf; cap=0 }
    cap { buf=buf $0 "\n" }
    END { if (cap) last=buf; printf "%s", last }
  ' "$1"
}

# plan_routes: emit one declared route per line from plan.md's "## Affected routes"
# block. Each route = the first whitespace token starting with '/' (rest is prose).
plan_routes() { # <build-dir>
  local pf="$1/plan.md"
  [ -f "$pf" ] || return 0
  awk '
    /^##[[:space:]]+Affected[[:space:]]+routes/ { cap=1; next }
    cap && /^##[[:space:]]/ { cap=0 }
    cap {
      line=$0
      sub(/^[[:space:]]*[-*][[:space:]]*/, "", line)        # strip list marker
      sub(/^[[:space:]`*_">]+/, "", line)                   # strip leading markdown wrappers (RB3-01)
      if (line ~ /^\//) {                                   # a route, not prose
        match(line, /^\/[^[:space:]`*_"<>]+/)               # first /path token, stop at space/markdown
        if (RSTART > 0) print substr(line, RSTART, RLENGTH)
      }
    }
  ' "$pf" 2>/dev/null || true
}

cmd_gate() { # <build-dir> <prior-stage>
  local dir="$1" stage="$2" f="$1/receipts.md"
  [ -f "$f" ] || die "no receipts.md in $dir — prior stage '$stage' never ran. Start at the right earlier stage."
  local block; block="$(last_block "$f" "$stage")"
  [ -n "$block" ] || die "no receipt for '$stage' — it has not completed. Run compass:$stage first."
  local header; header="$(printf '%s' "$block" | head -n1)"
  case "$header" in
    *SUPERSEDED*) die "'$stage' receipt is SUPERSEDED (an escalation/re-run voided it). Re-run compass:$stage." ;;
    *·\ PASS*|*"· PASS"*|*"PASS"*) : ;;
    *) die "'$stage' latest receipt is not PASS: $header" ;;
  esac
  if printf '%s' "$block" | grep -q '^\- \[ \]'; then
    die "'$stage' receipt has an UNCHECKED box — its work is incomplete:
$(printf '%s' "$block" | grep '^\- \[ \]')"
  fi
  ok "prior stage '$stage' receipt present, PASS, complete, not superseded."
}

cmd_scan_receipt() { # <build-dir> <stage>
  local dir="$1" stage="$2" f="$1/receipts.md"
  [ -f "$f" ] || die "no receipts.md — emit the $stage receipt first."
  local block; block="$(last_block "$f" "$stage")"
  [ -n "$block" ] || die "no $stage receipt found to scan."
  if printf '%s' "$block" | grep -q '^\- \[ \]'; then
    die "$stage receipt still has unchecked boxes — set status FAIL and do not hand on:
$(printf '%s' "$block" | grep '^\- \[ \]')"
  fi
  printf '%s' "$block" | head -n1 | grep -q 'PASS' || die "$stage receipt is not marked PASS."
  ok "$stage receipt self-check: PASS, all boxes filled."
}

cmd_supersede() { # <build-dir> <from-stage>
  local dir="$1" from="$2" f="$1/receipts.md"; local hit=0
  [ -f "$f" ] || die "no receipts.md to supersede in $dir"
  for s in $LIFECYCLE; do
    if [ "$s" = "$from" ]; then hit=1; fi
    if [ "$hit" = 1 ]; then
      printf '\n## RECEIPT — %s · (auto) · SUPERSEDED (re-run required after escalation to %s)\n' "$s" "$from" >> "$f"
    fi
  done
  ok "superseded '$from' and all later receipts — they must re-run."
}

cmd_reconcile() { # <actual> <gold> <tol>
  local actual="$1" gold="$2" tol="$3"
  printf '%s\n' "$actual $gold $tol" | awk '
    { a=$1; g=$2; t=$3; rel=0
      if (t ~ /%$/) { sub(/%$/,"",t); rel=1 }
      d=a-g; if (d<0) d=-d
      lim = rel ? (g<0?-g:g)*t/100.0 : t
      if (d<=lim) { printf "RECONCILE: actual=%s gold=%s tol=%s diff=%.6g PASS\n", a, g, $3, d; exit 0 }
      else        { printf "RECONCILE: actual=%s gold=%s tol=%s diff=%.6g FAIL\n", a, g, $3, d; exit 1 }
    }' || die "reconciliation FAILED — actual=$actual vs gold=$gold exceeds tolerance $tol. Build cannot close."
  ok "reconciliation within tolerance."
}

cmd_secret_scan() { # <build-dir> [files...]
  shift_dir="$1"; shift || true
  local pat='(-----BEGIN [A-Z ]*PRIVATE KEY|eyJ[A-Za-z0-9_-]{10,}\.|sk-[A-Za-z0-9]{16,}|postgres(ql)?://[^ ]*:[^ @]*@|[A-Za-z0-9_]*_SECRET\s*=\s*["'"'"'][^"'"'"' ]+|AKIA[0-9A-Z]{12,}|xox[baprs]-[0-9A-Za-z-]+)'
  local target="$*"
  local found=""
  if [ -n "$target" ]; then
    found="$(grep -REnI "$pat" $target 2>/dev/null || true)"
  elif command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    local files; files="$(git diff --name-only HEAD 2>/dev/null; git diff --name-only --cached 2>/dev/null)"
    [ -n "$files" ] && found="$(printf '%s\n' "$files" | sort -u | xargs -I{} sh -c 'test -f "{}" && grep -EnI "'"$pat"'" "{}" | sed "s#^#{}:#"' 2>/dev/null || true)"
  fi
  if [ -n "$found" ]; then
    die "possible secret committed — remove it / read from env instead:
$found"
  fi
  ok "secret scan: 0 hits."
}

set_index_status() { # <slug> <status>  — update the status= token on the slug's INDEX line
  local idx; idx="$(state_root)/INDEX"; [ -f "$idx" ] || return 0
  local esc; esc="$(printf '%s' "$1" | sed 's/[.[\*^$/]/\\&/g')"
  sed -i.bak -E "/^${esc}[ ]/ s/status=[A-Za-z-]+/status=$2/" "$idx" 2>/dev/null && rm -f "$idx.bak" || true
}

cmd_close() { # <build-dir> <slug> [--abandon]
  local dir="$1" slug="$2" mode="${3:-}"
  if [ "$mode" = "--abandon" ]; then
    set_index_status "$slug" ROLLED-BACK
    ok "build '$slug' ABANDONED → status ROLLED-BACK (lifecycle-audit skipped); clearing state."
  else
    # Terminal-status guard (v0.7.0): a normal close must pass the CLOSED lifecycle audit.
    cmd_lifecycle_audit "$dir" CLOSED >/dev/null 2>&1 || die "close: lifecycle-audit CLOSED failed — refusing to close an incomplete build. Inspect: compass.sh lifecycle-audit '$dir' CLOSED   (or cancel it: compass.sh close '$dir' '$slug' --abandon)."
    set_index_status "$slug" CLOSED
  fi
  # Clear the CURRENT hint in the canonical state root (worktree-safe).
  local sr; sr="$(state_root 2>/dev/null || true)"
  if [ -n "$sr" ] && [ -f "$sr/CURRENT" ] && [ "$(cat "$sr/CURRENT" 2>/dev/null)" = "$slug" ]; then
    : > "$sr/CURRENT"
  fi
  # Drop the build's locks.
  if [ -n "$sr" ]; then rm -f "$sr/.locks/$slug.files" "$sr/.locks/$slug.meta" "$sr/.locks/$slug.base" "$sr/.locks/$slug.owner" "$sr/.locks/$slug.blocked" 2>/dev/null || true; fi
  cmd_ship_release "$slug" >/dev/null 2>&1 || true   # v0.9.0: drop ship lock if this slug held it (guarded; never fails the close)
  # Worktree removal is DIRTY-SAFE (RP-3 / v0.5.0 incident): never --force. Dirty → leave + warn, state still cleared.
  local wt; wt="$(worktree_path "$slug" 2>/dev/null)"
  if git worktree list --porcelain 2>/dev/null | grep -qxF "worktree $wt"; then
    if safe_remove_worktree "$wt"; then
      git branch -D "compass/$slug" 2>/dev/null || true
      ok "build '$slug' closed; CURRENT cleared, locks dropped, worktree removed."
    else
      ok "build '$slug' closed; CURRENT cleared, locks dropped. NOTE: worktree has uncommitted work — LEFT at $wt (never force-removed)."
    fi
  else
    ok "build '$slug' closed; CURRENT cleared, locks dropped."
  fi
}

# ── v0.7.0: migration-delivery gate + lifecycle audit + Stop-hook guard ───────

# Prisma canonical migrations dir: when schema lives under prisma/schema/, the deploy
# reads prisma/schema/migrations; otherwise prisma/migrations. (The exact incident class.)
prisma_canonical_dir() { # <repo-root>
  if [ -d "$1/prisma/schema" ]; then printf '%s' "$1/prisma/schema/migrations"
  else printf '%s' "$1/prisma/migrations"; fi
}

# A stage has a usable PASS receipt: present, not SUPERSEDED, header says PASS, no unchecked box.
stage_pass() { # <build-dir> <stage>
  local block; block="$(last_block "$1/receipts.md" "$2" 2>/dev/null)"
  [ -n "$block" ] || return 1
  printf '%s' "$block" | head -n1 | grep -q 'SUPERSEDED' && return 1
  printf '%s' "$block" | head -n1 | grep -q 'PASS' || return 1
  printf '%s' "$block" | grep -q '^- \[ \]' && return 1
  return 0
}

# migration-gate: a schema-touching build cannot pass unless a real migration in the
# deploy's canonical folder reproduces the schema on a fresh DB (STRICT, no waiver).
cmd_migration_gate() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] || die "usage: compass.sh migration-gate <build-dir>"
  local contract="$dir/contract.md"; [ -f "$contract" ] || die "migration-gate: no contract.md in $dir"
  # trigger
  local st; st="$(sed -nE 's/.*schema-touching:\**[[:space:]]*([A-Za-z]+).*/\1/p' "$contract" | head -1 | tr 'A-Z' 'a-z')"
  case "$st" in
    no) ok "no schema change — migration-gate N/A."; return 0 ;;
    yes) : ;;
    *) die "migration-gate: contract.md missing 'schema-touching: yes|no' field (required trigger)." ;;
  esac
  local root="${COMPASS_REPO_ROOT:-$(main_root)}"
  # recipe (declared block wins; else Prisma auto-detect)
  local canon diff_cmd fresh_cmd
  canon="$(sed -nE 's/^canonical_migrations_dir:[[:space:]]*(.+)/\1/p' "$contract" | head -1)"
  diff_cmd="$(sed -nE 's/^migrate_diff_cmd:[[:space:]]*(.+)/\1/p' "$contract" | head -1)"
  fresh_cmd="$(sed -nE 's/^migrate_deploy_fresh_cmd:[[:space:]]*(.+)/\1/p' "$contract" | head -1)"
  local prisma_mode=0
  if [ -z "$canon" ]; then prisma_mode=1; canon="$(prisma_canonical_dir "$root")"; fi
  [ -n "$diff_cmd" ]  || diff_cmd="cd '$root' && npx prisma migrate diff --from-migrations '$canon' --to-schema-datamodel prisma/schema --exit-code"
  [ -n "$fresh_cmd" ] || fresh_cmd="cd '$root' && npx prisma migrate deploy"
  # G-M3 stray-migration detector (Prisma auto-detect mode): a non-canonical migrations dir is IGNORED by deploy.
  if [ "$prisma_mode" = 1 ] && [ -d "$root/prisma/schema" ] && [ -d "$root/prisma/migrations" ]; then
    die "migration-gate: STRAY 'prisma/migrations' exists while schema is in 'prisma/schema/' — deploy reads '$canon' and IGNORES it. Move/remove (G-M3)."
  fi
  # G-M3 db-execute substitution (delivery must be a migration, not a hand-apply)
  grep -qiE 'db execute|prisma db execute' "$dir/receipts.md" "$dir/plan.md" 2>/dev/null \
    && die "migration-gate: receipt/plan references 'db execute' — schema must be delivered by a migration the deploy applies, not hand-applied (G-M3)."
  # G-M1 presence
  local nmig=0; [ -d "$canon" ] && nmig="$(find "$canon" -mindepth 1 -name '*.sql' 2>/dev/null | wc -l | tr -d ' ')"
  [ "${nmig:-0}" -gt 0 ] 2>/dev/null || die "migration-gate: no migration *.sql in canonical dir '$canon' (G-M1) — schema change not delivered as a migration."
  # G-M4 fresh-DB apply (STRICT) then G-M2 schema==migrations (diff empty)
  ( eval "$fresh_cmd" ) >/dev/null 2>&1 || die "migration-gate: fresh-DB apply failed (G-M4, STRICT) — history won't replay from scratch. Repair/baseline before shipping; no waiver."
  ( eval "$diff_cmd" )  >/dev/null 2>&1 || die "migration-gate: schema != migrations (G-M2) — migrations don't reproduce the live schema."
  ok "migration-gate: migration present, no stray dir, fresh-DB apply clean, schema==migrations (STRICT)."
}

# ── v0.8.0: blast-radius page-load coverage (the §3a gate) ─────────────────
# route-coverage: every route the plan declares as affected must carry a recorded
# canonical page-load proof in receipts.md. Honor-level (checks the RECORD); the
# real teeth are review-build's independent re-load. Read-only, idempotent.
cmd_route_coverage() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] || die "usage: compass.sh route-coverage <build-dir>"
  [ -d "$dir" ] || die "no such build dir: $dir"
  local pf="$dir/plan.md" rf="$dir/receipts.md"

  # changed-files (COMPASS_CHANGED_FILES override for testability, else git diff)
  local changed routey=0 is_web=0
  if [ -n "${COMPASS_CHANGED_FILES:-}" ]; then
    changed="$COMPASS_CHANGED_FILES"
  else
    changed="$(git diff --name-only 2>/dev/null || true)"
  fi
  printf '%s\n' "$changed" | grep -qE '(^|/)(page|route)\.(t|j)sx?$|/page($|/)|/route($|/)' && routey=1
  # facet=web from INDEX (normalized token list, never contract prose)
  local slug sr idxline facets
  slug="$(basename "$dir")"; sr="$(state_root 2>/dev/null || true)"
  if [ -n "$sr" ] && [ -f "$sr/INDEX" ]; then
    idxline="$(grep -E "^${slug} " "$sr/INDEX" 2>/dev/null | head -1 || true)"
    facets="$(printf '%s' "$idxline" | sed -nE 's/.*facets=([^ ·]*).*/\1/p')"
    printf '%s' "$facets" | grep -qE '(^|[+,])web([+,]|$)' && is_web=1
  fi

  local routes; routes="$(plan_routes "$dir")"

  # G-R0: declaration MANDATORY when route files changed or facet=web (anti-gaming)
  if [ "$routey" = 1 ] || [ "$is_web" = 1 ]; then
    [ -n "$routes" ] || die "route-coverage: build changed page/route files (or facet=web) but plan.md '## Affected routes' is empty/missing — declaration is MANDATORY (G-R0), not N/A."
  fi

  # N/A: nothing route-ish, nothing declared
  if [ -z "$routes" ]; then ok "route-coverage: no routes touched — N/A."; return 0; fi

  [ -f "$rf" ] || die "route-coverage: routes declared but no receipts.md to carry page-load proofs (G-R1)."

  # G-R2 advisory (R1-03): page/route step verified by typecheck only — surface, do NOT die
  local adv; adv="$(grep -nE '\.(t|j)sx?|/page|/route' "$pf" 2>/dev/null | grep -iE 'tsc|noemit|review-build interaction' | grep -ivE '200|loaded|curl|playwright|[[:space:]]get[[:space:]]' || true)"
  [ -n "$adv" ] && printf 'route-coverage: NOTE (G-R2 advisory) — page/route step(s) appear typecheck-only; G-R1 still requires a load proof:\n%s\n' "$adv" >&2

  # G-R1: per route, ONE canonical line — literal "route <path>:" (R2-01 grep -F defuses
  # [param] char-classes; R2-02 trailing colon stops a prefix route stealing a longer
  # route's line) AND 200|loaded AND a checked [x], all on the same line.
  local missing="" r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    grep -F -- "route $r:" "$rf" 2>/dev/null | grep -E '(200|loaded)' | grep -q '\[x\]' || missing="$missing $r"
  done <<EOF
$routes
EOF
  [ -n "$missing" ] && die "route-coverage: declared route(s) without a canonical page-load proof line (G-R1):$missing"
  local n; n="$(printf '%s\n' "$routes" | grep -c . || true)"
  ok "route-coverage: $n route(s), all with a canonical page-load proof."
}

# lifecycle-audit: full-chain receipt + terminal-status audit (the always-fire teeth).
cmd_lifecycle_audit() { # <build-dir> [CLOSED|SHIPPED]
  local dir="${1:-}" want="${2:-}"; [ -n "$dir" ] || die "usage: compass.sh lifecycle-audit <build-dir> [CLOSED|SHIPPED]"
  [ -f "$dir/receipts.md" ] || die "lifecycle-audit: no receipts.md in $dir"
  local deploy_waived=0
  grep -qiE '^[[:space:]]*[-*]?[[:space:]]*deploy:[[:space:]]*out-of-scope' "$dir/contract.md" 2>/dev/null && deploy_waived=1
  # G-L1 ordered chain through review-build
  local s
  for s in contract review-contract plan review-plan build review-build; do
    stage_pass "$dir" "$s" || die "lifecycle-audit: stage '$s' has no clean PASS receipt (missing / unchecked box / SUPERSEDED) — chain broken (G-L1)."
  done
  # G-L2 review-build human sign-off (for CLOSED/SHIPPED/completeness)
  case "$want" in
    CLOSED|SHIPPED|"")
      last_block "$dir/receipts.md" review-build | grep -qiE 'sign-?off|signed off|^- \[x\] auto-closed:' \
        || die "lifecycle-audit: review-build receipt has no human sign-off line, nor an --auto 'auto-closed:' marker (G-L2)." ;;
  esac
  # ship requirements
  local need_ship=0
  [ "$want" = "SHIPPED" ] && need_ship=1
  [ -z "$want" ] && [ "$deploy_waived" = 0 ] && need_ship=1
  if [ "$need_ship" = 1 ]; then
    stage_pass "$dir" ship || die "lifecycle-audit: ship required (SHIPPED, or deploy not out-of-scope) but no clean ship PASS receipt (G-L2/G-L3). Run compass:ship, or record 'deploy: out-of-scope — <reason>'."
    # RB-01: prod-verify must be PRESENT and CHECKED (omitting it is not a soft pass loophole).
    last_block "$dir/receipts.md" ship | grep -qiE '^- \[x\].*prod[ -]?(reconcile|verif|recon)' \
      || die "lifecycle-audit: ship receipt has no CHECKED prod-verify line (G-L2) — prod reconciliation is mandatory and cannot be omitted or soft-passed."
    # S2 (v0.8.0 §3b): per declared route, a prod route-smoke proof in the ship receipt
    # (route <path> + prod + 200|loaded, checked). No declared routes → no-op (back-compat).
    local sroutes; sroutes="$(plan_routes "$dir")"
    if [ -n "$sroutes" ]; then
      local shipblk; shipblk="$(last_block "$dir/receipts.md" ship)"
      local sb="" rr
      while IFS= read -r rr; do
        [ -n "$rr" ] || continue
        printf '%s\n' "$shipblk" | grep -F -- "route $rr:" | grep -iE 'prod' | grep -E '(200|loaded)' | grep -q '\[x\]' \
          || sb="$sb $rr"
      done <<EOF
$sroutes
EOF
      [ -n "$sb" ] && die "lifecycle-audit: SHIPPED but ship receipt missing a CHECKED prod route-smoke proof (route <path> + prod + 200|loaded) for:$sb (§3b)."
    fi
    # G-O1 (v0.12.0 S4): when the post-ship loop is REQUIRED, SHIPPED is unwritable until
    # loop-converged passes (converged / user-accepted). Legacy + waived builds skip (INV-BC).
    if cmd_postship_required "$dir" >/dev/null 2>&1; then
      cmd_loop_converged "$dir" postship >/dev/null 2>&1 || { echo "refuse: loop-open" >&2; die "lifecycle-audit: post-ship critique loop is OPEN (required, not converged, no valid user-accepted) — SHIPPED cannot be recorded (G-O1)."; }
    fi
  fi
  ok "lifecycle-audit: chain PASS${want:+, status '$want' consistent}${deploy_waived:+ }$([ "$deploy_waived" = 1 ] && echo '(deploy waived)')."
}

# is_mid_build (v0.8.0 §3d): exit 0 iff a BUILD step is genuinely in progress — the
# ONLY state where stopping risks half-applied artifacts. Everything else (gates,
# *-LOCKED, CONVERGED, CLOSED-awaiting-ship, mid-contract/plan/review) is a clean,
# resumable checkpoint → quiet. set -euo pipefail safe: every grep guarded, missing
# files ⇒ NOT mid-build; never dies (a Stop hook must never crash the session).
is_mid_build() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] || return 1
  local rf="$dir/receipts.md" pf="$dir/plan.md" lb=""
  # (a) the LAST build receipt block is IN-PROGRESS / carries a step k/n counter.
  #     The build-specific `step k/n` (only the build stage writes it) + hyphenated
  #     IN-PROGRESS marker — NEVER generic spaced prose like "review-plan — IN PROGRESS".
  if [ -f "$rf" ]; then
    lb="$(last_block "$rf" build 2>/dev/null || true)"
    if printf '%s' "$lb" | grep -qE 'IN-PROGRESS|step[[:space:]]*[0-9]+/[0-9]+' 2>/dev/null; then return 0; fi
  fi
  # (b) plan.md has a checked AND an unchecked step box (build partway). Line-leading
  #     task boxes only (not inline prose). Catches the post-step-1 case (a) may miss.
  if [ -f "$pf" ]; then
    if grep -qE '^- \[x\]' "$pf" 2>/dev/null && grep -qE '^- \[ \]' "$pf" 2>/dev/null; then return 0; fi
  fi
  return 1
}

# stop-guard: the Stop-hook command. Reads hook JSON on stdin. v0.8.0 (§3d): blocks ONLY
# on true mid-build abandonment (is_mid_build) — quiet at every gate/clean checkpoint, so
# the harness's red "Stop hook error" no longer fires on normal pauses. Honors
# stop_hook_active (anti-deadlock). Always exits 0 (Stop hooks signal via JSON); fail-open.
# _step_counter: a monotonic build-progress signal for the loop backstop (v0.9.0). The `k`
# from the latest build receipt's `step k/n`, else the count of checked plan.md boxes (the
# plan.md-half-checked path). Both advance only on real progress → cosmetic churn won't
# re-arm the guard; a genuine step flip will. Never errors.
_step_counter() { # <build-dir>
  local dir="$1" k=""
  if [ -f "$dir/receipts.md" ]; then
    k="$(grep -oE 'step[[:space:]]*[0-9]+/[0-9]+' "$dir/receipts.md" 2>/dev/null | tail -1 | sed -nE 's/.*step[[:space:]]*([0-9]+)\/[0-9]+.*/\1/p' || true)"
  fi
  if [ -z "$k" ] && [ -f "$dir/plan.md" ]; then
    k="$(grep -cE '^- \[x\]' "$dir/plan.md" 2>/dev/null || true)"
  fi
  printf '%s' "${k:-0}"
}

# stop-guard (v0.9.0 — window/session-scoped): blocks ONLY the session that OWNS a mid-build
# in THIS project. A no-build session, a foreign build's session, an orphaned build (owner
# session gone), another project — all stay quiet. So parallel builds and unrelated sessions
# never contaminate each other. `stop_hook_active` is the primary anti-deadlock; a
# session|slug|step-counter fingerprint is the backstop (block at most once per build-step).
# Honors set -euo pipefail throughout: every read guarded → never crashes a session (fail-open).
cmd_stop_guard() {
  local input; input="$(cat 2>/dev/null || true)"
  case "$input" in *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) printf '{}\n'; return 0 ;; esac
  # Stopping session id — FIELD-ANCHORED parse (never the uuid embedded in transcript_path),
  # whitespace-tolerant; env fallback. ${:-} keeps set -u happy; || true keeps set -e happy.
  local sid; sid="$(printf '%s' "$input" | sed -nE 's/.*"session_id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1 || true)"
  [ -n "$sid" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"
  # RB-02: resolve state-root INLINE — never call state_root (it die/exits, which under
  # set -e would crash the session instead of failing open). A Stop hook must never crash.
  local sr="" common
  if git rev-parse --git-dir >/dev/null 2>&1; then
    common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
    [ -n "$common" ] && sr="$(cd "$(dirname "$common")" 2>/dev/null && pwd || true)/.claude/builds"
  fi
  [ -n "$sr" ] && [ -f "$sr/INDEX" ] || { printf '{}\n'; return 0; }
  local ld="$sr/.locks"
  local line slug status stage next owner fp prev
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    slug="$(printf '%s' "$line" | sed -nE 's/^([^ ·	]+).*/\1/p')"; [ -n "$slug" ] || continue
    [ -f "$sr/$slug/receipts.md" ] && grep -q '^## RECEIPT — contract' "$sr/$slug/receipts.md" 2>/dev/null || continue   # bare draft → not mid-lifecycle
    status="$(sed -nE 's/^\*\*Status:\*\*[[:space:]]*([A-Za-z()0-9 -]+).*/\1/p' "$sr/$slug/progress.md" 2>/dev/null | tail -1 | tr 'A-Z' 'a-z' || true)"
    [ -n "$status" ] || status="$(printf '%s' "$line" | sed -nE 's/.*status=([A-Za-z-]+).*/\1/p' | tr 'A-Z' 'a-z' || true)"
    case "$status" in *shipped*|*rolled-back*|*paused*) continue ;; esac          # terminal/parked → allow
    # NOTE (v0.10.0): gate-wait-* are resumable human-gate checkpoints, NOT terminal/mid-build —
    # do NOT add them to the skip-case above. In --auto they are handled by _auto_spawn_maybe (which
    # refuses to spawn while a gate-lock is held), and can-advance blocks advancing past them.
    # v0.11.0 --auto (BEFORE the is_mid_build gated check, so it fires at EVERY continuable stage,
    # not only build — the v0.10 bug). In autonomous mode the Stop hook never blocks; it attempts a
    # cross-session spawn (or lets the build pause for a gate/budget/human) and ALWAYS allows this
    # session to stop. Gated by: this is the OWNING session, the build is continuable (real pending
    # work, not terminal/idle, no gate-lock — _auto_spawn_maybe re-checks the gate-lock too), and
    # `.auto-mode` is set. Emits no stray stdout (only the final {}). Gated mode (no marker) falls
    # through UNCHANGED below — INV-BC.
    if [ -f "$sr/$slug/.auto-mode" ]; then
      owner="$(owner_of "$slug" "$ld" 2>/dev/null || true)"
      if [ -n "$owner" ] && [ "$owner" = "$sid" ] && is_stage_continuable "$sr/$slug"; then
        _auto_spawn_maybe "$sr/$slug" "$slug" "$sid" "$ld" >/dev/null 2>&1 || true
      fi
      printf '{}\n'; return 0
    fi
    # ── gated mode (no .auto-mode) — UNCHANGED from v0.10 ──
    # §3d: only TRUE mid-build is a risky stop; gates/*-LOCKED/CONVERGED/CLOSED-awaiting-ship → quiet.
    is_mid_build "$sr/$slug" || continue
    # v0.9.0 OWNERSHIP: block ONLY the session that owns this mid-build. Orphan (no owner) or
    # a foreign session → quiet. Exact POSIX compare (no glob); owner_of never errors.
    owner="$(owner_of "$slug" "$ld" 2>/dev/null || true)"
    [ -n "$owner" ] && [ "$owner" = "$sid" ] || continue
    # Loop backstop: block at most once per build-step. Inline mkdir-mutex, FAILS OPEN.
    fp="${sid}|${slug}|$(_step_counter "$sr/$slug" 2>/dev/null || true)"
    mkdir -p "$ld" 2>/dev/null || true
    mkdir "$ld/.$slug.bl.lock" 2>/dev/null || true                                # best-effort; proceed either way
    prev="$(cat "$ld/$slug.blocked" 2>/dev/null || true)"
    if [ "$prev" = "$fp" ]; then
      rmdir "$ld/.$slug.bl.lock" 2>/dev/null || true
      printf '{}\n'; return 0                                                      # same build-step already blocked once → allow
    fi
    printf '%s' "$fp" | atomic_write "$ld/$slug.blocked" 2>/dev/null || printf '%s' "$fp" > "$ld/$slug.blocked" 2>/dev/null || true
    rmdir "$ld/.$slug.bl.lock" 2>/dev/null || true
    stage="$(sed -nE 's/^\*\*Stage:\*\*[[:space:]]*(.*)/\1/p' "$sr/$slug/progress.md" 2>/dev/null | tail -1 || true)"
    next="$(sed -nE 's/^\*\*Next:\*\*[[:space:]]*(.*)/\1/p' "$sr/$slug/progress.md" 2>/dev/null | tail -1 || true)"
    stage="$(printf '%s' "${stage:-?}" | sed 's/"/\\"/g')"; next="$(printf '%s' "${next:-?}" | sed 's/"/\\"/g')"
    printf '{"decision":"block","reason":"Compass: build %s is mid-BUILD with a step in progress (stage: %s). Next: %s. Finish the build step (or write a clean pause to progress.md) before stopping — work can be left half-applied."}\n' "$slug" "$stage" "$next"
    return 0
  done < "$sr/INDEX"
  printf '{}\n'; return 0
}

# ── v0.5.0: design-fidelity gate + status (the anti-ceremony teeth) ─────────
# A build is "design-scoped" iff its INDEX `facets=` token list contains `web`
# (normalized, prose-free — NEVER grep contract.md prose: it says "web" in text).
is_design_scoped() { # <build-dir>
  local dir="$1" slug sr idxline facets
  slug="$(basename "$dir")"; sr="$(state_root 2>/dev/null || true)"
  [ -n "$sr" ] && [ -f "$sr/INDEX" ] || return 1
  idxline="$(grep -E "^${slug} " "$sr/INDEX" 2>/dev/null | head -1)"
  facets="$(printf '%s' "$idxline" | sed -nE 's/.*facets=([^ ·]*).*/\1/p')"
  printf '%s' "$facets" | grep -qE '(^|[+,])web([+,]|$)'
}

# Open rows in a ledger = markdown table data rows whose Status (last real cell)
# does NOT contain CLOSED/FIXED/RESOLVED/N/A. Header + separator rows skipped.
ledger_open_rows() { # <ledger-file> [severity-filter-regex]
  local f="$1" sevre="${2:-}"
  [ -f "$f" ] || { echo 0; return; }
  awk -F'|' -v sevre="$sevre" '
    /^\|/ {
      if ($0 ~ /^\|[-: ]+\|/) next                       # separator
      hdr=0; for(i=1;i<=NF;i++){c=$i; gsub(/^[ \t]+|[ \t]+$/,"",c); if(c=="ID"||c=="Status"||c=="Sev"||c=="Severity")hdr=1}
      if(hdr) next                                        # header
      if (sevre!="") { ok=0; for(i=1;i<=NF;i++){c=toupper($i); gsub(/^[ \t]+|[ \t]+$/,"",c); if(c ~ sevre)ok=1} if(!ok)next }
      last=$(NF-1); gsub(/^[ \t]+|[ \t]+$/,"",last)
      if (toupper(last) ~ /CLOSED|FIXED|RESOLVED|N\/A/) next
      n++
    } END{print n+0}' "$f"
}

cmd_design_drift_gate() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] || die "usage: compass.sh design-drift-gate <build-dir>"
  [ -d "$dir" ] || die "no such build dir: $dir"
  local ledger="$dir/design-ledger.md"
  if is_design_scoped "$dir"; then
    [ -f "$ledger" ] || die "design-scoped build but design-ledger.md MISSING — design review not done (≠ clean)."
    grep -qiE 'design-review:[[:space:]]*complete' "$ledger" || die "design-ledger.md has no 'design-review: complete' marker — review not finished."
    local open; open="$(ledger_open_rows "$ledger")"
    [ "$open" -gt 0 ] 2>/dev/null && die "design-drift ledger has $open OPEN row(s) — one drift = FAIL, cannot converge."
    ok "design-drift ledger complete + 0 open rows."
  else
    [ -f "$ledger" ] || { ok "no web facet — design gate N/A."; return 0; }
    local open; open="$(ledger_open_rows "$ledger")"
    [ "$open" -gt 0 ] 2>/dev/null && die "design-drift ledger has $open OPEN row(s)."
    ok "design-drift ledger clean."
  fi
}

cmd_converge_gate() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] || die "usage: compass.sh converge-gate <build-dir>"
  [ -d "$dir" ] || die "no such build dir: $dir"
  local corr; corr="$(ledger_open_rows "$dir/review-ledger.md" 'CRITICAL|MAJOR')"
  [ "$corr" -gt 0 ] 2>/dev/null && die "correctness ledger has $corr OPEN Critical/Major — cannot converge."
  cmd_design_drift_gate "$dir" >/dev/null || die "design-drift gate not clean — cannot converge."
  ok "converge-gate: correctness AND design ledgers both clean."
}

cmd_design_style_diff() { # <ref.html> <build.html> <token>
  local ref="${1:-}" build="${2:-}" token="${3:-}"
  [ -n "$ref" ] && [ -n "$build" ] && [ -n "$token" ] || die "usage: compass.sh design-style-diff <ref> <build> <token>"
  [ -f "$ref" ] || die "no ref file: $ref"; [ -f "$build" ] || die "no build file: $build"
  local rv bv
  rv="$( { grep -oE -- "${token}[[:space:]]*:[[:space:]]*[^;\"'}]*" "$ref" || true; } | head -1 | sed -E "s/.*:[[:space:]]*//" | tr -d ' ')"
  [ -n "$rv" ] || { echo "design-style-diff: token '$token' not declared in REF — usage error." >&2; exit 2; }
  bv="$( { grep -oE -- "${token}[[:space:]]*:[[:space:]]*[^;\"'}]*" "$build" || true; } | head -1 | sed -E "s/.*:[[:space:]]*//" | tr -d ' ')"
  [ -n "$bv" ] || { echo "DRIFT: token '$token' MISSING in build (ref=$rv)." >&2; exit 1; }
  [ "$rv" = "$bv" ] || { echo "DRIFT: '$token' ref=$rv build=$bv." >&2; exit 1; }
  ok "design-style-diff: '$token' matches ($rv)."
}

cmd_status() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] || die "usage: compass.sh status <build-dir>"
  [ -d "$dir" ] || die "no such build dir: $dir"
  local slug; slug="$(basename "$dir")"
  local p="$dir/progress.md"
  local status stage next total done_ lastpass
  status="$(sed -nE 's/^\*\*Status:\*\*[[:space:]]*(.*)/\1/p' "$p" 2>/dev/null | head -1)"
  stage="$(sed -nE 's/^\*\*Stage:\*\*[[:space:]]*(.*)/\1/p' "$p" 2>/dev/null | head -1)"
  next="$(sed -nE 's/^\*\*Next:\*\*[[:space:]]*(.*)/\1/p' "$p" 2>/dev/null | head -1)"
  total="$(grep -cE '^[[:space:]]*- \[[ x]\] \*\*S' "$dir/plan.md" 2>/dev/null || echo 0)"
  done_="$(grep -cE '^[[:space:]]*- \[x\] \*\*S' "$dir/plan.md" 2>/dev/null || echo 0)"
  lastpass="$( { grep -E '^## RECEIPT —' "$dir/receipts.md" 2>/dev/null | grep -i 'PASS' | tail -1 | sed -E 's/^## RECEIPT — //'; } || true)"
  echo "── Compass status: $slug ───────────────────────────"
  echo "Status:  ${status:-unknown}"
  echo "Stage:   ${stage:-unknown}"
  [ "${total:-0}" -gt 0 ] 2>/dev/null && echo "Steps:   ${done_}/${total} checked"
  echo "Last ✓:  ${lastpass:-none}"
  echo "Next:    ${next:-unknown}"
  # v0.12.0 S6 (F-STATUS): post-ship loop position + suspend visibility — file-derived, no guesses.
  if [ -f "$dir/loop.log" ]; then
    local psb pscl pscap psrounds psclean psopen
    psb="$(_ps_bounds "$dir/contract.md")"; pscl="${psb% *}"; pscap="${psb#* }"
    psrounds="$(awk -F'|' '$2=="postship"{n++}END{print n+0}' "$dir/loop.log")"
    psclean="$(awk -F'|' '$2=="postship"{ if($4=="CLEAN") t++; else t=0 }END{print t+0}' "$dir/loop.log")"
    psopen="$(ps_open_rows "$dir/review-ledger.md")"
    echo "Post-ship: round ${psrounds}/${pscap} · consecutive-clean ${psclean}/${pscl} · open PS ${psopen}"
  fi
  [ -f "$dir/.auto-suspended" ] && echo "auto: SUSPENDED (driver)"
  echo "────────────────────────────────────────────────────"
}

# ── v0.6.0: parallel-build identification + merge-consequence gate ───────────
# Live view of every in-flight (non-terminal) build on this repo.
cmd_builds() {
  local idx; idx="$(state_root)/INDEX"
  [ -f "$idx" ] || { ok "no INDEX — 0 builds."; return; }
  local any=0
  printf '%-26s %-12s %-16s %s\n' "SLUG" "STATUS" "BRANCH" "WORKTREE"
  while IFS= read -r line; do
    [ -n "$line" ] || continue; case "$line" in \#*) continue ;; esac
    local slug; slug="$(printf '%s' "$line" | sed -nE 's/^([A-Za-z0-9_-]+).*/\1/p')"
    [ -n "$slug" ] || continue
    local st; st="$(build_status "$slug")"; is_terminal "$st" && continue
    local wt br; wt="$(worktree_path "$slug")"
    if git worktree list --porcelain | grep -qxF "worktree $wt"; then br="compass/$slug"; else wt="(main checkout)"; br="-"; fi
    printf '%-26s %-12s %-16s %s\n' "$slug" "$st" "$br" "$wt"; any=1
  done < "$idx"
  [ "$any" = 1 ] || ok "0 in-flight builds."
}

# Merge-consequence gate: when another build merged to the base, gate this build.
# Base = recorded base's REMOTE ref (origin/<base>) + fetch — NEVER local main (RC-1).
cmd_post_merge_check() { # <slug>
  local slug="${1:-}"; [ -n "$slug" ] || die "usage: compass.sh post-merge-check <slug>"
  local ld basef; ld="$(locks_dir)"; basef="$ld/$slug.base"
  [ -f "$basef" ] || die "no recorded base for '$slug' — its worktree was not created via 'compass.sh worktree'."
  local base_branch base_sha; base_branch="$(sed -nE 's/^base_branch=(.*)/\1/p' "$basef")"; base_sha="$(sed -nE 's/^base_sha=(.*)/\1/p' "$basef")"
  local remote_ref="$base_branch"; case "$base_branch" in origin/*) ;; *) remote_ref="origin/$base_branch" ;; esac
  [ -n "$(git remote 2>/dev/null)" ] || { ok "post-merge-check '$slug': no remote — skipped (no upstream to advance)."; return 0; }
  git fetch -q origin 2>/dev/null || true
  git show-ref --verify --quiet "refs/remotes/$remote_ref" || { ok "post-merge-check '$slug': no upstream '$remote_ref' — skipped."; return 0; }
  local advanced; advanced="$(git rev-list --count "${base_sha}..refs/remotes/$remote_ref" 2>/dev/null || echo 0)"
  [ "${advanced:-0}" = "0" ] && { ok "post-merge-check '$slug': base current — no merge consequences."; return 0; }
  local hits=""
  if [ -f "$ld/$slug.files" ]; then
    local changed; changed="$(git diff --name-only "${base_sha}..refs/remotes/$remote_ref" 2>/dev/null || true)"
    while IFS= read -r f; do [ -n "$f" ] || continue; grep -qxF "$f" "$ld/$slug.files" 2>/dev/null && hits="${hits}  $f"$'\n'; done <<< "$changed"
  fi
  [ -n "$hits" ] && die "post-merge-check '$slug': '$remote_ref' advanced $advanced commit(s) AND touched your claimed files:
$hits Integrate '$remote_ref' + re-verify (blast radius) before ship."
  die "post-merge-check '$slug': '$remote_ref' advanced $advanced commit(s) (disjoint from your claim) — integrate '$remote_ref' + re-verify before ship."
}

# doctor: classify every worktree (managed/stray/main) + status + dirty; --migrate relocates CLEAN strays.
cmd_doctor() { # [--migrate]
  local migrate=0; [ "${1:-}" = "--migrate" ] && migrate=1
  local home main_wt; home="$(managed_home)"; main_wt="$(main_root)"
  # canonicalize (resolve symlinks like macOS /tmp→/private/tmp) so prefix matching is reliable
  local home_real; home_real="$(cd "$home" 2>/dev/null && pwd -P || printf '%s' "$home")"
  echo "Compass doctor — worktrees for this repo (home: $home):"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    local wt; wt="${line#worktree }"
    if [ "$wt" = "$main_wt" ]; then echo "  [main]    $wt"; continue; fi
    local slug; slug="$(basename "$wt")"
    local wt_real; wt_real="$(cd "$wt" 2>/dev/null && pwd -P || printf '%s' "$wt")"
    local cls="stray"; case "$wt_real" in "$home_real"/*) cls="managed" ;; esac
    local st dirty; st="$(build_status "$slug")"; dirty="clean"; [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ] && dirty="DIRTY"
    echo "  [$cls] $slug  status=$st  $dirty"
    if [ "$migrate" = 1 ]; then
      case "$slug" in _merged_*) continue ;; esac
      if [ "$cls" = "stray" ] && [ "$dirty" = "clean" ]; then
        local dest; dest="$(worktree_path "$slug")"; mkdir -p "$(dirname "$dest")"
        if git worktree move "$wt" "$dest" 2>/dev/null; then echo "    → migrated → $dest"; else echo "    → migrate FAILED — left in place" >&2; fi
      elif [ "$dirty" = "DIRTY" ]; then
        echo "    → DIRTY: left untouched (resolve manually, never auto-moved)"
      fi
    fi
  done < <(git worktree list --porcelain | grep '^worktree ')
  ok "doctor done."
}

# ── v0.10.0: opt-in --auto autonomous loop ──────────────────────────────────
# State files are LINE-ORIENTED (no JSON — POSIX shell, macOS bash 3.2, no jq).
# budget.env: key=value. session-chain.log: pipe-delimited 7 fields.
# Locks always taken gate-$slug THEN budget-$slug, never the reverse (no deadlock).
AUTO_EVENTS="start gate-wait-G1 gate-wait-G2 gate-cleared spawn spawn-failed budget-stop auto-suspended auto-resumed"
BUDGET_DEFAULT_WALL=3600; BUDGET_DEFAULT_SESSIONS=6; BUDGET_DEFAULT_STAGES=40

_now_epoch() { date +%s 2>/dev/null || echo 0; }
_be_file() { printf '%s/budget.env' "$1"; }
_be_get() { # <file> <key>  → value or empty
  [ -f "$1" ] || { printf ''; return 0; }
  sed -nE "s/^$2=(.*)$/\1/p" "$1" 2>/dev/null | tail -1 | tr -d '\r' || printf ''
}
_be_set() { # <file> <key> <val>  (caller holds the lock)
  local f="$1" k="$2" v="$3" tmp
  tmp="$(mktemp "${f}.XXXXXX")"
  { [ -f "$f" ] && grep -vE "^$k=" "$f" 2>/dev/null || true; printf '%s=%s\n' "$k" "$v"; } > "$tmp"
  mv -f "$tmp" "$f"
}
_chain_file() { printf '%s/session-chain.log' "$1"; }
_chain_append() { # <dir> <stage> <event>  (best-effort, never fails the caller)
  local dir="$1" stage="${2:--}" event="$3" be sid
  be="$(_be_file "$dir")"; sid="${CLAUDE_CODE_SESSION_ID:-local}"
  printf '%s|%s|%s|%s|%s|%s|%s\n' "$(_now_epoch)" "$sid" "$stage" "$event" \
    "$(_be_get "$be" spent_wall)" "$(_be_get "$be" spent_sessions)" "$(_be_get "$be" spent_stages)" \
    >> "$(_chain_file "$dir")" 2>/dev/null || true
}

# S1: reject --auto + --unattended together; echo the resolved mode. Default (neither)=gated.
cmd_auto_precheck() { # <flags...>
  local has_auto=0 has_un=0 a
  for a in "$@"; do case "$a" in --auto) has_auto=1 ;; --unattended) has_un=1 ;; esac; done
  [ "$has_auto" = 1 ] && [ "$has_un" = 1 ] && die "auto-precheck: --auto and --unattended are mutually exclusive — choose one."
  [ "$has_auto" = 1 ] && { ok "mode=auto"; return 0; }
  ok "mode=gated"
}

# S1: mark a build mode=auto. REQUIRES a declared budget.env w/ ceilings (INV-3).
cmd_auto_init() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] || die "usage: compass.sh auto-init <build-dir>"
  [ -d "$dir" ] || die "no such build dir: $dir"
  local be; be="$(_be_file "$dir")"
  { [ -f "$be" ] && [ -n "$(_be_get "$be" ceiling_wall)" ]; } || die "auto-init: --auto requires a declared budget — run 'compass.sh budget-init $dir' first (budget required)."
  : > "$dir/.auto-mode"   # the mode:auto marker (machine-checked by stop-guard/can-advance)
  ok "build is mode=auto (budget ceilings present)."
}

# S2: write ceilings + a fresh session_start_ts + zeroed spend.
cmd_budget_init() { # <build-dir> [--wall N --sessions N --stages N]
  local dir="${1:-}"; shift || true
  [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh budget-init <build-dir> [--wall N --sessions N --stages N]"
  local wall="$BUDGET_DEFAULT_WALL" sess="$BUDGET_DEFAULT_SESSIONS" stg="$BUDGET_DEFAULT_STAGES"
  while [ $# -gt 0 ]; do case "$1" in
    --wall) wall="${2:-}"; shift 2 ;; --sessions) sess="${2:-}"; shift 2 ;; --stages) stg="${2:-}"; shift 2 ;;
    *) shift ;; esac; done
  local be; be="$(_be_file "$dir")"
  # RB-04: preserve cumulative spend on re-init (must NOT reset spent_* to 0 and bypass the
  # ceiling). The read+write is done INSIDE the lock (no read-outside-lock race — review-build R2).
  with_lock "budget-$(basename "$dir")" _budget_init_locked "$be" "$wall" "$sess" "$stg" "$(_now_epoch)"
  ok "budget-init: wall=${wall}s sessions=${sess} stages=${stg} (spend preserved if re-init)."
}

# S2: enforce ceilings (INV-3 required, INV-4 binds). Wall is cumulative across sessions.
cmd_budget_check() { # <build-dir> [--bump-stage|--bump-session]
  local dir="${1:-}" bump="${2:-}"
  [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh budget-check <build-dir> [--bump-stage|--bump-session]"
  local be; be="$(_be_file "$dir")"
  [ -f "$be" ] && [ -n "$(_be_get "$be" ceiling_wall)" ] || die "budget-check: no declared budget (budget required)."
  # BUG-3 fix: die OUTSIDE the critical section so the mutex always releases (see _budget_check_locked).
  BUDGET_FAIL_MSG=""
  with_lock "budget-$(basename "$dir")" _budget_check_locked "$dir" "$be" "$bump" || \
    die "${BUDGET_FAIL_MSG:-budget-check: failed.}"
}
_is_num() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }   # non-negative integer only
_elapsed() { local e=$(( ${1:-0} - ${2:-0} )); [ "$e" -lt 0 ] && e=0; printf '%s' "$e"; }  # now,start → ≥0 (clock-skew safe)
_budget_init_locked() { # <be> <wall> <sess> <stg> <now>  (under budget lock) — preserves spend on re-init
  local be="$1" w="$2" s="$3" g="$4" now="$5" psw=0 pss=1 psg=0 pg2=0 x
  if [ -f "$be" ]; then
    x="$(_be_get "$be" spent_wall)";     _is_num "$x" && psw="$x"
    x="$(_be_get "$be" spent_sessions)"; _is_num "$x" && pss="$x"
    x="$(_be_get "$be" spent_stages)";   _is_num "$x" && psg="$x"
    x="$(_be_get "$be" g2_fires)";       _is_num "$x" && pg2="$x"
  fi
  { printf 'ceiling_wall=%s\n' "$w"; printf 'ceiling_sessions=%s\n' "$s"; printf 'ceiling_stages=%s\n' "$g";
    printf 'spent_wall=%s\n' "$psw"; printf 'spent_sessions=%s\n' "$pss"; printf 'spent_stages=%s\n' "$psg";
    printf 'tokens_best_effort=0\n'; printf 'g2_fires=%s\n' "$pg2"; printf 'session_start_ts=%s\n' "$now"; } > "$be"
}
_budget_check_locked() { # <dir> <be> <bump>  (under lock)
  local dir="$1" be="$2" bump="$3" now; now="$(_now_epoch)"
  local cw cs cg sw ss sg st
  cw="$(_be_get "$be" ceiling_wall)";  cs="$(_be_get "$be" ceiling_sessions)"; cg="$(_be_get "$be" ceiling_stages)"
  sw="$(_be_get "$be" spent_wall)";    ss="$(_be_get "$be" spent_sessions)";   sg="$(_be_get "$be" spent_stages)"
  st="$(_be_get "$be" session_start_ts)"
  # ceilings: fall back to the safe defaults; spent: fall back to 0. Then FAIL CLOSED on any
  # non-numeric value (a corrupt budget.env must never fail open into an unbounded loop — RB-02).
  _is_num "$cw" || cw="$BUDGET_DEFAULT_WALL"; _is_num "$cs" || cs="$BUDGET_DEFAULT_SESSIONS"; _is_num "$cg" || cg="$BUDGET_DEFAULT_STAGES"
  : "${sw:=0}"; : "${ss:=0}"; : "${sg:=0}"; : "${st:=$now}"
  # BUG-3 fix (v0.12.0): never `die` INSIDE the with_lock critical section — an exit skips the
  # RETURN trap and leaks the budget mutex (same class as the fire-g1/g2 leak). The locked fn
  # sets BUDGET_FAIL_MSG + returns 1; cmd_budget_check dies OUTSIDE with the identical message.
  for v in "$sw" "$ss" "$sg" "$st"; do _is_num "$v" || { BUDGET_FAIL_MSG="budget-check: corrupt budget.env (non-numeric '$v') — refusing (fail closed)."; return 1; }; done
  case "$bump" in
    --bump-stage)   sg=$((sg+1)); _be_set "$be" spent_stages "$sg" ;;
    --bump-session) sw=$(( sw + $(_elapsed "$now" "$st") )); _be_set "$be" spent_wall "$sw"; _be_set "$be" session_start_ts "$now"; ss=$((ss+1)); _be_set "$be" spent_sessions "$ss" ;;
  esac
  local cum_wall=$(( sw + $(_elapsed "$now" "$st") ))   # cumulative wall = persisted + this session's elapsed (clock-skew safe)
  # ceiling test (INV-4) — any dimension at/over → non-zero
  if [ "$cum_wall" -ge "$cw" ] || [ "$ss" -ge "$cs" ] || [ "$sg" -ge "$cg" ]; then
    _chain_append "$dir" "-" "budget-stop"
    BUDGET_FAIL_MSG="budget-check: ceiling reached (wall ${cum_wall}/${cw}s, sessions ${ss}/${cs}, stages ${sg}/${cg}) — fire G2."
    return 1
  fi
  # 80% warn (any dimension)
  local pct=80
  if [ $(( cum_wall * 100 )) -ge $(( cw * pct )) ] || [ $(( ss * 100 )) -ge $(( cs * pct )) ] || [ $(( sg * 100 )) -ge $(( cg * pct )) ]; then
    echo "compass: budget approaching ceiling (wall ${cum_wall}/${cw}s, sessions ${ss}/${cs}, stages ${sg}/${cg})." >&2
  fi
  ok "budget-check: within ceilings (wall ${cum_wall}/${cw}s, sessions ${ss}/${cs}, stages ${sg}/${cg})."
}

# S3: validate the session-chain log schema + recompute dims.
cmd_check_session_chain() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh check-session-chain <build-dir>"
  local f; f="$(_chain_file "$dir")"
  [ -f "$f" ] || { ok "check-session-chain: no log yet (0 events)."; return 0; }
  awk -F'|' -v ev="$AUTO_EVENTS" -v lc="$LIFECYCLE" '
    BEGIN{ n=split(ev,E," "); for(i=1;i<=n;i++)EV[E[i]]=1; m=split(lc,L," "); for(i=1;i<=m;i++)LC[L[i]]=1; LC["-"]=1 }
    /^[[:space:]]*$/ { next }
    { if (NF!=7) { printf("check-session-chain: line %d has %d fields (want 7): %s\n",NR,NF,$0) > "/dev/stderr"; bad=1; next }
      if (!($4 in EV)) { printf("check-session-chain: line %d bad event \"%s\"\n",NR,$4) > "/dev/stderr"; bad=1 }
      if (!($3 in LC)) { printf("check-session-chain: line %d bad stage \"%s\"\n",NR,$3) > "/dev/stderr"; bad=1 }
      for(c=5;c<=7;c++){ if($c !~ /^[0-9]+$/){ printf("check-session-chain: line %d field %d not numeric \"%s\"\n",NR,c,$c) > "/dev/stderr"; bad=1 } }
      if($5+0>mw)mw=$5; if($6+0>ms)ms=$6; if($7+0>mg)mg=$7; rows++ }
    END{ if(bad)exit 1; printf("check-session-chain: %d events OK; max wall=%d sessions=%d stages=%d\n",rows,mw,ms,mg) }' "$f" \
    || die "check-session-chain: malformed log (see stderr)."
  ok "check-session-chain: log valid."
}

# S4: fire the G2 feasibility gate. gate-lock FIRST (under lock), then banner/event/g2_fires. exit≠0.
cmd_fire_g2() { # <build-dir> <reason>
  local dir="${1:-}" reason="${2:-feasibility}"
  [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh fire-g2 <build-dir> <reason>"
  local slug; slug="$(basename "$dir")"
  # die OUTSIDE the critical section: an exit inside with_lock skips the RETURN trap and
  # leaks the mutex, deadlocking the next gate-clear (leak found live 2026-07-21).
  with_lock "gate-$slug" _fire_g2_locked "$dir" "$slug" "$reason" || \
    die "G2 (feasibility) fired: ${reason}. Build is gate-wait-G2 — a human must resume. (Autonomous spawn is blocked while this gate is held.)"
}
_fire_g2_locked() { # <dir> <slug> <reason>  (under gate lock)
  local dir="$1" slug="$2" reason="$3" ld; ld="$(locks_dir)"; mkdir -p "$ld"
  mkdir "$ld/$slug.gate-lock" 2>/dev/null || true            # gate-lock FIRST (RP-03)
  # write Status banner (replace the **Status:** line, else APPEND it — never silently drop it, RB-03)
  local p="$dir/progress.md" tmp banner
  banner="**Status:** gate-wait-G2 — G2 fired: ${reason}. Resume with /compass:resume ${slug} (choices: ship-despite-miss / relax / keep-trying / abort)."
  if [ -f "$p" ] && grep -qE '^\*\*Status:\*\*' "$p"; then
    tmp="$(mktemp "${p}.XXXXXX")"; sed -E "s|^\*\*Status:\*\*.*|${banner}|" "$p" > "$tmp"; mv -f "$tmp" "$p"
  else
    printf '\n%s\n' "$banner" >> "$p"
  fi
  _chain_append "$dir" "-" "gate-wait-G2"
  # bump g2_fires
  local be; be="$(_be_file "$dir")"
  if [ -f "$be" ]; then local g; g="$(_be_get "$be" g2_fires)"; : "${g:=0}"; g=$((g+1)); _be_set "$be" g2_fires "$g"
    if [ "$g" -ge 3 ]; then echo "compass: G2 fired ${g}× — 'keep-trying' withdrawn; only ship-despite-miss / abort." >&2; fi
  fi
  return 1
}

# v0.11.0 S3 — fire-g1: the UPFRONT gate now takes a real gate-lock (same surface as G2, so the
# self-spawn refuses past it — RC-3). Only one gate is ever active at a time. exit≠0 (it's a stop).
cmd_fire_g1() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh fire-g1 <build-dir>"
  local slug; slug="$(basename "$dir")"
  # die OUTSIDE the critical section (same mutex-leak class as fire-g2 — see comment there).
  with_lock "gate-$slug" _fire_g1_locked "$dir" "$slug" || \
    die "G1 (upfront) fired: a human must approve the contract+intent before the loop runs."
}
_fire_g1_locked() { # <dir> <slug>  (under gate lock)
  local dir="$1" slug="$2" ld; ld="$(locks_dir)"; mkdir -p "$ld"
  mkdir "$ld/$slug.gate-lock" 2>/dev/null || true            # gate-lock FIRST (shared surface)
  local p="$dir/progress.md" tmp banner
  banner="**Status:** gate-wait-G1 — upfront approval needed. Approve to continue (/compass:resume ${slug}); autonomous spawn is blocked while this gate is held."
  if [ -f "$p" ] && grep -qE '^\*\*Status:\*\*' "$p"; then
    tmp="$(mktemp "${p}.XXXXXX")"; sed -E "s|^\*\*Status:\*\*.*|${banner}|" "$p" > "$tmp"; mv -f "$tmp" "$p"
  else printf '\n%s\n' "$banner" >> "$p"; fi
  _chain_append "$dir" "-" "gate-wait-G1"
  return 1
}

# v0.11.0 S3 — gate-clear: release the gate-lock on human approval (G1 or G2) so the lifecycle (and,
# in auto, the self-spawn) may continue. Appends a `gate-cleared` event. Idempotent.
cmd_gate_clear() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh gate-clear <build-dir>"
  local slug ld; slug="$(basename "$dir")"; ld="$(locks_dir)"
  with_lock "gate-$slug" sh -c 'rmdir "$1/'"$slug"'.gate-lock" 2>/dev/null || true' _ "$ld"
  _chain_append "$dir" "-" "gate-cleared"
  ok "gate-clear: gate-lock released for '$slug'."
}

# v0.11.0 S2 — is_stage_continuable: may the autonomous loop continue this build across a session?
# TRUE iff NOT terminal, NOT gate-held, AND there is a real clean checkpoint to resume from (a
# stage PASS with ship not yet done, OR a true mid-build). FALSE for terminal/idle/stuck/gate-held
# → no no-op spawn loop (RC-2). Never errors (safe from the Stop hook).
is_stage_continuable() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || return 1
  local slug; slug="$(basename "$dir")"
  # terminal status → not continuable
  local status; status="$(sed -nE 's/^\*\*Status:\*\*[[:space:]]*(.*)/\1/p' "$dir/progress.md" 2>/dev/null | tail -1 | tr 'A-Z' 'a-z' || true)"
  case "$status" in *shipped*|*rolled-back*|*paused*) return 1 ;; esac
  # gate held → not continuable (a human must act)
  [ -d "$(locks_dir 2>/dev/null)/$slug.gate-lock" ] && return 1
  # v0.12.0 S4 (RD-6): a build mid-post-ship-loop IS continuable — recognized BEFORE the
  # shipped-clean early-return below, because every mid-loop build HAS a ship PASS receipt
  # (F-REG demands a fresh one per redeploy). Status token: column-0 `post-ship (round k/cap)`
  # — deliberately lacks the "shipped" substring, so the terminal case above never eats it.
  case "$status" in post-ship\ \(round*) return 0 ;; esac
  # mid-build → continuable
  is_mid_build "$dir" && return 0
  # else: continuable iff some stage has a clean PASS receipt AND ship is not done
  stage_pass "$dir" ship 2>/dev/null && return 1   # already shipped-clean → nothing to continue
  local s
  for s in review-build build review-plan plan review-contract contract; do
    if stage_pass "$dir" "$s" 2>/dev/null; then return 0; fi
  done
  return 1   # no clean checkpoint → not continuable (stuck/never-started)
}

# v0.11.0 S4 — auto-start: ONE command to enter autonomous mode (precheck + budget-init + auto-init).
# The explicit, discoverable trigger. Idempotent (budget-init preserves spend). Rejects --unattended.
cmd_auto_start() { # <build-dir> [--wall S --sessions N --stages N] [--unattended(REJECTED)]
  local dir="${1:-}"; shift || true
  [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh auto-start <build-dir> [--wall S --sessions N --stages N]"
  local args=""
  while [ $# -gt 0 ]; do case "$1" in
    --unattended) die "auto-start: --auto and --unattended are mutually exclusive — choose one." ;;
    --wall|--sessions|--stages) args="$args $1 $2"; shift 2 ;;
    *) shift ;; esac; done
  cmd_auto_precheck --auto >/dev/null || die "auto-start: precheck failed."
  # shellcheck disable=SC2086
  cmd_budget_init "$dir"$args >/dev/null || die "auto-start: budget-init failed."
  cmd_auto_init "$dir" >/dev/null || die "auto-start: auto-init failed."
  ok "auto-start: '$(basename "$dir")' is now AUTONOMOUS (--auto). Budget set, .auto-mode written. Run /compass:start (it will auto-advance, stopping only at G1/G2)."
}

# S5 helper: attempt an autonomous cross-session spawn. Emits ZERO stdout (RP-04). Returns 0 if it
# spawned, 1 otherwise. Caller (stop-guard) handles the JSON. Refuses at gate-lock / foreign owner /
# cap, and is idempotent vs a recent spawn (RP-12). Increments spent_sessions BEFORE spawn (RP-02/07).
_auto_spawn_maybe() { # <dir> <slug> <sid> <locks-dir>
  local dir="$1" slug="$2" sid="$3" ld="$4"
  [ -f "$dir/.auto-mode" ] || return 1
  # v0.12.0 S6a (F-SUSPEND): an interactive driver has suspended the self-spawn — refuse at THIS
  # seam so BOTH entry points (stop-guard AND direct auto-spawn) are dormant. .auto-mode stays,
  # so budget metering + the RC-8/VF-4 human-eyes refusals REMAIN ARMED while suspended.
  [ -f "$dir/.auto-suspended" ] && { echo "compass: auto-spawn refused — suspended by the interactive driver (auto-resume to re-arm)." >&2; return 1; }
  # (1) gate held? (INV-6) — never spawn past a human gate
  [ -d "$ld/$slug.gate-lock" ] && { echo "compass: auto-spawn refused — gate-lock held (no gate bypass)." >&2; return 1; }
  # (2) single-flight (INV-5): a live foreign owner holds the build
  local owner; owner="$(owner_of "$slug" "$ld" 2>/dev/null || true)"
  [ -n "$owner" ] && [ "$owner" != "$sid" ] && { echo "compass: auto-spawn refused — single-flight (owner $owner)." >&2; return 1; }
  # (3) idempotency (RP-12): a recent spawn already recorded for this build
  local cf recent; cf="$(_chain_file "$dir")"
  recent="$(tail -3 "$cf" 2>/dev/null | grep -c '|spawn|' || true)"; _is_num "$recent" || recent=0
  if [ -f "$cf" ] && [ "$recent" -gt 0 ]; then
    echo "compass: auto-spawn skipped — recent spawn already recorded (idempotent)." >&2; return 1
  fi
  # (4) budget RESERVE under the lock (RB3-1): re-read, ceiling-check, increment, write — then RELEASE
  # the lock. The launch+probe happen OUTSIDE the lock, so a fast spawned child can take the budget
  # lock immediately (no parent-holds-lock-while-child-waits contention). Reserve = atomic; the slot
  # is counted BEFORE the spawn (crash-safe/conservative — a launch that then dies never UNDER-counts).
  local be; be="$(_be_file "$dir")"
  [ -f "$be" ] || { echo "compass: auto-spawn refused — no budget." >&2; return 1; }
  with_lock "budget-$slug" _budget_reserve_session "$dir" "$slug" "$be" || return 1
  # (5) launch + honest liveness check, NO lock held. The probe tells a launcher that started from one
  # that died immediately (INV-DEGRADE): exited non-zero → spawn-failed; still-running/exited-0 → spawn.
  # (For a real detached `nohup claude`, this confirms the LAUNCH; the session slot is already reserved,
  # so even a later child crash can never exceed the cap — safety does not depend on child liveness.)
  local cmd; cmd="${COMPASS_SPAWN_CMD:-nohup claude -p \"/compass:resume $slug --auto\"}"
  sh -c "$cmd" >"$dir/spawn-session.log" 2>&1 &
  local pid=$!
  sleep 0.15
  if kill -0 "$pid" 2>/dev/null; then _chain_append "$dir" "-" "spawn"; return 0; fi
  local rc=0; wait "$pid" 2>/dev/null || rc=$?
  if [ "$rc" -eq 0 ]; then _chain_append "$dir" "-" "spawn"; return 0
  else _chain_append "$dir" "-" "spawn-failed"; return 1; fi
}
# Reserve one session slot atomically under the budget lock (RB3-1). 0 = reserved (go), 1 = refuse.
# NO launch here → the lock is held only for the brief read-modify-write, never during sleep/spawn.
_budget_reserve_session() { # <dir> <slug> <be>  (under budget lock)
  local dir="$1" slug="$2" be="$3" ss cs sw cw st sg cg now; now="$(_now_epoch)"
  ss="$(_be_get "$be" spent_sessions)"; cs="$(_be_get "$be" ceiling_sessions)"
  sw="$(_be_get "$be" spent_wall)"; cw="$(_be_get "$be" ceiling_wall)"; st="$(_be_get "$be" session_start_ts)"
  sg="$(_be_get "$be" spent_stages)"; cg="$(_be_get "$be" ceiling_stages)"
  : "${ss:=0}"; : "${sw:=0}"; : "${sg:=0}"; : "${st:=$now}"
  _is_num "$cs" || cs="$BUDGET_DEFAULT_SESSIONS"; _is_num "$cw" || cw="$BUDGET_DEFAULT_WALL"; _is_num "$cg" || cg="$BUDGET_DEFAULT_STAGES"
  # FAIL CLOSED on corrupt spend (a garbage spent_* must not read as 0 and bypass the cap — RB-02)
  for v in "$ss" "$sw" "$sg" "$st"; do _is_num "$v" || { echo "compass: auto-spawn refused — corrupt budget.env ('$v')." >&2; return 1; }; done
  # Enforce ALL ceilings in the spawn path itself so a cross-session continuation can NEVER exceed
  # wall/sessions/stages — RB-01. Checked BEFORE the increment, all under this one lock (INV-HALT).
  local cumw; cumw=$(( sw + $(_elapsed "$now" "$st") ))
  [ "$ss" -ge "$cs" ] && { echo "compass: auto-spawn refused — session cap ${ss}/${cs} (INV-7)." >&2; return 1; }
  [ "$cumw" -ge "$cw" ] && { echo "compass: auto-spawn refused — wall ceiling ${cumw}/${cw}s (INV-4)." >&2; return 1; }
  [ "$sg" -ge "$cg" ] && { echo "compass: auto-spawn refused — stage ceiling ${sg}/${cg} (INV-4)." >&2; return 1; }
  sw="$cumw"; _be_set "$be" spent_wall "$sw"; _be_set "$be" session_start_ts "$now"
  ss=$((ss+1)); _be_set "$be" spent_sessions "$ss"
  return 0   # slot reserved (explicit, set -e safe)
}

# S5 entry: attempt the autonomous spawn for a build (used by stop-guard inline; also callable for
# diagnostics/tests). Resolves slug/session/locks and delegates. Exit 0 iff a spawn fired.
cmd_auto_spawn() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh auto-spawn <build-dir>"
  _auto_spawn_maybe "$dir" "$(basename "$dir")" "${CLAUDE_CODE_SESSION_ID:-local}" "$(locks_dir)" \
    && ok "auto-spawn: spawned." || die "auto-spawn: did not spawn (gate/owner/cap/idempotent/budget)."
}

# S7: may the loop auto-advance? exit 0 only if NO gate-lock and status is not gate-wait-*.
cmd_can_advance() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh can-advance <build-dir>"
  local slug; slug="$(basename "$dir")"
  # RB-05: an absent/unreadable progress.md is an UNKNOWN state — fail closed (never auto-advance
  # from a state we can't read), else a missing status string would slip past the gate-wait check.
  [ -f "$dir/progress.md" ] || die "can-advance: NO — progress.md absent (unknown state, fail closed)."
  [ -d "$(locks_dir)/$slug.gate-lock" ] && die "can-advance: NO — gate-lock held (human gate pending)."
  local status; status="$(sed -nE 's/^\*\*Status:\*\*[[:space:]]*([A-Za-z()0-9 -]+).*/\1/p' "$dir/progress.md" 2>/dev/null | tail -1 || true)"
  case "$status" in *gate-wait-*) die "can-advance: NO — status is '$status' (human gate)." ;; esac
  ok "can-advance: yes."
}

# ── v0.12.0 S2: post-ship loop policy + external-verifier pre-flight (contract F-REQ/F-SIGNAL) ──
# postship-required <build-dir>: is the post-ship critique loop REQUIRED for this build?
#   exit 0 = required · exit 1 = N/A or waived (reason printed). Policy (contract v3a F-REQ):
#   deploy waived → N/A · header `on (clean N / cap M)` → required · header `off — <reason>`
#   → waived · header ABSENT → N/A "legacy — pre-v0.12 contract" (INV-BC: old builds untouched).
#   All header reads go through hdr_get (bold-tolerant, VZ-3) — never the legacy [-*]? grep.
cmd_postship_required() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh postship-required <build-dir>"
  local c="$dir/contract.md"; [ -f "$c" ] || die "postship-required: no contract.md in $dir"
  local dep; dep="$(hdr_get "$c" deploy || true)"
  case "$dep" in
    out-of-scope*) ok "postship-required: N/A — deploy waived (${dep})."; return 1 ;;
  esac
  local v; v="$(hdr_get "$c" post-ship-loop || true)"
  case "$v" in
    on*)      ok "postship-required: REQUIRED (${v})."; return 0 ;;
    off*)     ok "postship-required: waived — ${v#off}"; return 1 ;;
    "")       ok "postship-required: N/A — legacy (pre-v0.12 contract, no post-ship-loop header)."; return 1 ;;
    *)        die "postship-required: unparseable post-ship-loop header value '${v}'." ;;
  esac
}

# postship-signal <build-dir>: does at least ONE external verifier exist for the loop to grade
# against? exit 0 iff any of: RECON-CMD in receipts.md · non-empty '## Affected routes' in
# plan.md · a `post-ship-check:` line · an `observation-channel:` line (both via hdr_get).
# Non-zero → the loop must NOT run on model self-critique alone (INV-PS-NOVERIFIER): fire G2.
cmd_postship_signal() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh postship-signal <build-dir>"
  local c="$dir/contract.md" r="$dir/receipts.md" found=""
  [ -f "$r" ] && grep -qE '^RECON-CMD:' "$r" && found="RECON-CMD (receipts.md)"
  [ -z "$found" ] && [ -n "$(plan_routes "$dir")" ] && found="declared routes (plan.md)"
  [ -z "$found" ] && [ -f "$c" ] && hdr_get "$c" post-ship-check >/dev/null 2>&1 && found="post-ship-check line (contract.md)"
  [ -z "$found" ] && [ -f "$c" ] && hdr_get "$c" observation-channel >/dev/null 2>&1 && found="observation-channel line (contract.md)"
  if [ -n "$found" ]; then ok "postship-signal: external verifier present — ${found}."; return 0; fi
  echo "refuse: no-verifier" >&2
  die "postship-signal: NO external verifier (no RECON-CMD, no declared routes, no post-ship-check, no observation-channel) — the loop must not run on self-critique alone. Fire G2: compass.sh fire-g2 $dir \"post-ship: no external verifier\"."
}

# ── v0.12.0 S3: loop-round — register one post-ship critique round (contract F-REG) ──
# _ps_bounds <contract>: prints "clean cap" parsed from the post-ship-loop header (defaults 2 5).
_ps_bounds() { # <contract.md>
  local v; v="$(hdr_get "$1" post-ship-loop || true)"
  local n c
  n="$(printf '%s' "$v" | sed -nE 's/^on \(clean ([0-9]+) \/ cap ([0-9]+)\).*/\1/p')"
  c="$(printf '%s' "$v" | sed -nE 's/^on \(clean ([0-9]+) \/ cap ([0-9]+)\).*/\2/p')"
  printf '%s %s' "${n:-2}" "${c:-5}"
}
# _png_ok <dir>: any *.png in dir with PNG magic bytes AND size ≥ 20480 → 0.
_png_ok() { # <evidence-round-dir>
  local f sz magic
  for f in "$1"/*.png; do
    [ -f "$f" ] || continue
    sz=$(wc -c < "$f" | tr -d ' ')
    [ "$sz" -ge 20480 ] || continue
    magic="$(head -c 8 "$f" | od -An -tx1 | tr -d ' \n')"
    [ "$magic" = "89504e470d0a1a0a" ] && return 0
  done
  return 1
}
# _round_block <receipts> <round> <verdict>: print the receipt block for that exact round header.
_round_block() { # <receipts.md> <round> <CLEAN|MATERIAL>  (LAST matching block wins — a re-run
  # round writes a FRESH receipt after the redeploy; the last one is the live one, like last_block)
  awk -v hdr="## RECEIPT — post-ship-critique · round $2 · $3" '
    index($0, hdr)==1 { cap=1; buf=$0 ORS; next }
    cap && /^## / { cap=0 }
    cap { buf=buf $0 ORS }
    END { printf "%s", buf }' "$1"
}
_refuse() { echo "refuse: $1" >&2; die "loop-round: $2"; }

cmd_loop_round() { # <build-dir> <phase> <CLEAN|MATERIAL> --sig <sha12|nogit>
  local dir="${1:-}" phase="${2:-}" verdict="${3:-}" sigflag="${4:-}" sig="${5:-}"
  [ -n "$dir" ] && [ -d "$dir" ] && [ "$phase" = "postship" ] || die "usage: compass.sh loop-round <build-dir> postship <CLEAN|MATERIAL> --sig <sha12|nogit>"
  case "$verdict" in CLEAN|MATERIAL) : ;; *) die "loop-round: verdict must be CLEAN or MATERIAL." ;; esac
  [ "$sigflag" = "--sig" ] && [ -n "$sig" ] || die "loop-round: --sig <git sha-12 | nogit> is required."
  local c="$dir/contract.md" r="$dir/receipts.md" lg="$dir/loop.log" ledger="$dir/review-ledger.md"
  [ -f "$c" ] || die "loop-round: no contract.md"; [ -f "$r" ] || die "loop-round: no receipts.md"
  local bounds cleanN cap; bounds="$(_ps_bounds "$c")"; cleanN="${bounds% *}"; cap="${bounds#* }"
  # previous state from loop.log (truth — receipts alone don't count)
  local prev_round=0 prev_verdict="" prev_sig="" prev2_sig="" prev3_sig=""
  if [ -f "$lg" ]; then
    prev_round="$(awk -F'|' -v p="$phase" '$2==p{r=$3}END{print r+0}' "$lg")"
    prev_verdict="$(awk -F'|' -v p="$phase" '$2==p{v=$4}END{print v}' "$lg")"
    prev_sig="$(awk -F'|' -v p="$phase" '$2==p{s[NR]=$5}END{print s[NR]}' "$lg")"
    prev2_sig="$(awk -F'|' -v p="$phase" '$2==p{a=b;b=$5}END{print a}' "$lg")"
    prev3_sig="$(awk -F'|' -v p="$phase" '$2==p{x=a;a=b;b=$5}END{print x}' "$lg")"
  fi
  local round=$((prev_round+1))
  # 1 cap
  [ "$round" -le "$cap" ] || _refuse cap "round $round exceeds cap $cap — fire G2 (compass.sh fire-g2 $dir \"post-ship cap\")."
  # 2 receipt block exists, matches round+verdict, zero unchecked boxes, ≥1 checked backtick-command evidence line
  local blk; blk="$(_round_block "$r" "$round" "$verdict")"
  [ -n "$blk" ] || _refuse receipt "no round receipt '## RECEIPT — post-ship-critique · round $round · $verdict' in receipts.md."
  printf '%s\n' "$blk" | grep -qE '^\- \[ \]' && _refuse receipt "round $round receipt has unchecked boxes."
  printf '%s\n' "$blk" | grep -qE '^\- \[x\].*`.*`.*→' || _refuse receipt "round $round receipt lacks a checked backtick-command evidence line (cmd → output)."
  # 3 evidence floors (web via contract Facets; HUMAN-OBSERVED gated-only)
  local ev="$dir/evidence/round-$round" facets; facets="$(hdr_get "$c" Facets || true)"
  local human=""; printf '%s\n' "$blk" | grep -qE 'HUMAN-OBSERVED: "..*"' && human=1
  if [ -n "$human" ] && [ -f "$dir/.auto-mode" ]; then _refuse human-observed-auto "HUMAN-OBSERVED is gated-mode only — an unattended session cannot fabricate human eyes (fire G2 instead)."; fi
  case "$facets" in
    *web*)
      if [ -z "$human" ]; then
        [ -d "$ev" ] && _png_ok "$ev" || _refuse evidence "web round needs ≥1 real PNG ≥20KB in evidence/round-$round/ (or a gated HUMAN-OBSERVED line)."
      fi ;;
    *)
      local ob="$ev/observe.txt"
      [ -s "$ob" ] || _refuse evidence "non-web round needs non-empty evidence/round-$round/observe.txt."
      local decl comp l1
      decl="$(hdr_get "$c" observation-channel || true)"; comp="${decl#* = }"
      l1="$(head -1 "$ob")"
      l1="$(norm_line "$l1")"; comp="\`$(norm_line "$comp")\`"
      [ "$l1" = "$comp" ] || _refuse evidence "observe.txt line 1 must be the declared digest command in backticks (comparand mechanic VF-2/VZ)." ;;
  esac
  # 4 ledger coupling (ps_open_rows — never ledger_open_rows)
  local openps; openps="$(ps_open_rows "$ledger")"
  if [ "$verdict" = "CLEAN" ]; then
    [ "$openps" = "0" ] || _refuse ledger "CLEAN with $openps open PS Crit/Maj rows — verdict and ledger disagree."
  else
    grep -qE "^\| PS-$round-[0-9]+ \|" "$ledger" 2>/dev/null || _refuse ledger "MATERIAL without a new PS-$round-* row in review-ledger.md."
  fi
  # 5 order: previous MATERIAL → fresh ship PASS receipt between the two round receipts
  if [ "$prev_verdict" = "MATERIAL" ]; then
    local slug; slug="$(basename "$dir")"
    awk -v prevh="## RECEIPT — post-ship-critique · round $prev_round · MATERIAL" \
        -v ship="## RECEIPT — ship · $slug · PASS" -v curh="## RECEIPT — post-ship-critique · round $round · $verdict" '
      index($0,prevh)==1 { seenprev=1 }
      seenprev && index($0,ship)==1 { seenship=1 }
      index($0,curh)==1 { lastok = seenship }
      END { exit lastok?0:1 }' "$r" || _refuse order "MATERIAL round $prev_round must be followed by a fresh '## RECEIPT — ship · <slug> · PASS' BEFORE the (latest) round $round receipt."
  fi
  # 6/7/8 stall detection (sig semantics; nogit degrade replaces sig-equality checks)
  if [ "$sig" = "nogit" ]; then
    if [ "$verdict" = "MATERIAL" ] && [ "$prev_verdict" = "MATERIAL" ] && [ "$prev_sig" = "nogit" ]; then
      _refuse nogit-stall "2 consecutive MATERIAL rounds at sig=nogit — degrade: fire G2."
    fi
  else
    if [ "$verdict" = "MATERIAL" ] && [ "$sig" = "$prev_sig" ]; then
      _refuse no-progress "MATERIAL with unchanged sig $sig — the code didn't change; fire G2."
    fi
    if [ -n "$prev3_sig" ] && [ "$sig" = "$prev2_sig" ] && [ "$prev_sig" = "$prev3_sig" ] && [ "$sig" != "$prev_sig" ]; then
      _refuse ping-pong "sig alternation A,B,A,B — oscillating fixes; fire G2."
    fi
  fi
  # 9 budget is loop-round-OWNED under .auto-mode (subshell: die() exits cannot escape it — VZ-4)
  if [ -f "$dir/.auto-mode" ]; then
    if ( cmd_budget_check "$dir" --bump-stage >/dev/null ); then :; else
      _refuse budget "budget ceiling — fire G2 (compass.sh fire-g2 $dir \"post-ship budget\")."
    fi
  fi
  # register (append-only; duplicate rounds impossible by construction: round = last+1)
  printf '%s|%s|%s|%s|%s|%s\n' "$(_now_epoch)" "$phase" "$round" "$verdict" "$sig" "$openps" >> "$lg"
  ok "loop-round: registered $phase round $round/$cap · $verdict · sig=$sig · open PS=$openps."
}

# ── v0.12.0 S4: loop-converged — is the post-ship critique loop DONE? (contract F-CONV) ──
# exit 0 iff (a) rounds ≥ clean-bound N (header-parsed) AND the last N registered rounds are all
# CLEAN AND 0 open PS Crit/Maj; or (b) a pinned `user-accepted: ship-as-is — <PS ids> · <ts>`
# line exists AND every OPEN PS row id is in the recorded list (SET semantics, VF-3/VZ).
# Refusal codes (Q8): clean-run · open-ps · accepted-void.
cmd_loop_converged() { # <build-dir> <phase>
  local dir="${1:-}" phase="${2:-}"
  [ -n "$dir" ] && [ -d "$dir" ] && [ "$phase" = "postship" ] || die "usage: compass.sh loop-converged <build-dir> postship"
  local c="$dir/contract.md" lg="$dir/loop.log" ledger="$dir/review-ledger.md" r="$dir/receipts.md"
  local bounds cleanN; bounds="$(_ps_bounds "$c")"; cleanN="${bounds% *}"
  local rounds trailing_clean openps
  rounds="$(awk -F'|' -v p="$phase" '$2==p{n++}END{print n+0}' "${lg:-/dev/null}" 2>/dev/null || printf 0)"
  trailing_clean="$(awk -F'|' -v p="$phase" '$2==p{ if($4=="CLEAN") t++; else t=0 }END{print t+0}' "${lg:-/dev/null}" 2>/dev/null || printf 0)"
  openps="$(ps_open_rows "$ledger")"
  if [ "$rounds" -ge "$cleanN" ] && [ "$trailing_clean" -ge "$cleanN" ] && [ "$openps" = "0" ]; then
    ok "loop-converged: $trailing_clean consecutive CLEAN (need $cleanN), 0 open PS — CONVERGED ($rounds rounds)."
    return 0
  fi
  # user-accepted escape (cap path): SET semantics — every OPEN PS id must be in the recorded list
  local ua; ua="$(hdr_get "$r" user-accepted 2>/dev/null || true)"
  if [ -n "$ua" ]; then
    case "$ua" in ship-as-is*) : ;; *) echo "refuse: accepted-void" >&2; die "loop-converged: user-accepted line present but not the pinned 'ship-as-is — <PS ids> · <ts>' form." ;; esac
    local missing=""
    if [ -f "$ledger" ]; then
      local id
      while IFS= read -r id; do
        [ -n "$id" ] || continue
        printf '%s' "$ua" | grep -qF "$id" || missing="$missing $id"
      done <<EOF
$(awk -F'|' 'function trim(x){gsub(/^[ \t]+|[ \t]+$/,"",x);return x}
   { id=trim($2); sev=trim($4); st=trim($8)
     if (id ~ /^PS-[0-9]+-[0-9]+$/ && (sev=="CRITICAL"||sev=="MAJOR") && st=="OPEN") print id }' "$ledger")
EOF
    fi
    if [ -n "$missing" ]; then
      echo "refuse: accepted-void" >&2
      die "loop-converged: user-accepted VOID — open PS rows not in the recorded list:$missing (a later finding voids the acceptance)."
    fi
    ok "loop-converged: user-accepted ship-as-is honored (open PS ⊆ recorded list) — loop closed by explicit human decision."
    return 0
  fi
  if [ "$openps" != "0" ]; then echo "refuse: open-ps" >&2; die "loop-converged: $openps open PS Crit/Maj rows."; fi
  echo "refuse: clean-run" >&2
  die "loop-converged: need $cleanN consecutive CLEAN rounds (have $trailing_clean of $rounds registered)."
}

# ── v0.12.0 S5: coldgo-gate — the 2×cold-GO design gate as an exit code (contract F-COLDGO) ──
# Applicability (VZ-2, authoring-time model): applies iff the contract declares web facets AND a
# `cold-critic:` line with the pinned ON form. `off — <reason>` → waived. No line → N/A (legacy,
# INV-BC; the v0.12 contract skill always writes `cold-critic: on` for web contracts). Non-web → N/A.
# PASS iff the LAST 2 cold-critic receipts are GO with the IDENTICAL tree sha, each with a checked
# clean-tree box, AND that sha == the CURRENT `git rev-parse --short=12 HEAD` (a commit after the
# last GO invalidates — RD-7). Fallback: ONE `HUMAN-GO · "<quote>" · tree=<sha>` when the contract
# declares `cold-critic-fallback: human-eyeball` — GATED MODE ONLY (VF-4). Codes: streak ·
# dirty-tree · stale-head · human-go-auto · no-fallback.
cmd_coldgo_gate() { # <build-dir>   (run from within the target repo)
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh coldgo-gate <build-dir>"
  local c="$dir/contract.md" r="$dir/receipts.md"
  [ -f "$c" ] || die "coldgo-gate: no contract.md"
  local facets cc; facets="$(hdr_get "$c" Facets || true)"; cc="$(hdr_get "$c" cold-critic || true)"
  case "$facets" in *web*) : ;; *) ok "coldgo-gate: N/A — not a web-facet build."; return 0 ;; esac
  case "$cc" in
    "")    ok "coldgo-gate: N/A — legacy web build (no cold-critic header, pre-v0.12)."; return 0 ;;
    off*)  ok "coldgo-gate: waived — ${cc#off}"; return 0 ;;
    on*)   : ;;
    *)     die "coldgo-gate: unparseable cold-critic header value '${cc}'." ;;
  esac
  [ -f "$r" ] || { echo "refuse: streak" >&2; die "coldgo-gate: no receipts.md — no cold-critic runs recorded."; }
  local head12; head12="$(git rev-parse --short=12 HEAD 2>/dev/null || printf nogit)"
  # HUMAN-GO path first (one suffices; gated-only; fallback must be declared)
  local hg; hg="$(grep -E '^## RECEIPT — cold-critic · HUMAN-GO · ".+" · tree=[a-z0-9]+' "$r" | tail -1 || true)"
  if [ -n "$hg" ]; then
    [ -f "$dir/.auto-mode" ] && { echo "refuse: human-go-auto" >&2; die "coldgo-gate: HUMAN-GO under .auto-mode — an unattended session cannot certify human eyes (fire G2)."; }
    local fb; fb="$(hdr_get "$c" cold-critic-fallback || true)"
    [ "$fb" = "human-eyeball" ] || { echo "refuse: no-fallback" >&2; die "coldgo-gate: HUMAN-GO recorded but the contract does not declare 'cold-critic-fallback: human-eyeball'."; }
    local hsha; hsha="$(printf '%s' "$hg" | sed -nE 's/.*tree=([a-z0-9]+).*/\1/p')"
    [ "$hsha" = "$head12" ] || { echo "refuse: stale-head" >&2; die "coldgo-gate: HUMAN-GO tree=$hsha but current HEAD is $head12 — a later commit invalidates the sign-off."; }
    ok "coldgo-gate: HUMAN-GO honored (gated, fallback declared, tree=$hsha == HEAD)."
    return 0
  fi
  # machine path: last 2 GO receipts, identical sha, clean-tree boxes, sha == HEAD
  local last2; last2="$(grep -E '^## RECEIPT — cold-critic · (GO|NO-GO) · tree=' "$r" | tail -2)"
  local n; n="$(printf '%s\n' "$last2" | grep -c 'cold-critic' || true)"
  [ "$n" = "2" ] || { echo "refuse: streak" >&2; die "coldgo-gate: need 2 consecutive cold GO receipts (have $n runs recorded)."; }
  printf '%s\n' "$last2" | grep -q 'NO-GO' && { echo "refuse: streak" >&2; die "coldgo-gate: a NO-GO sits in the last 2 runs — streak reset."; }
  local s1 s2
  s1="$(printf '%s\n' "$last2" | sed -n '1p' | sed -nE 's/.*tree=([a-z0-9]+).*/\1/p')"
  s2="$(printf '%s\n' "$last2" | sed -n '2p' | sed -nE 's/.*tree=([a-z0-9]+).*/\1/p')"
  [ "$s1" = "$s2" ] || { echo "refuse: streak" >&2; die "coldgo-gate: the 2 GOs carry different tree shas ($s1 vs $s2) — a commit between GOs resets the streak."; }
  # each of the last two GO blocks needs a checked clean-tree box
  local blocks; blocks="$(awk -v want="## RECEIPT — cold-critic · GO · tree=$s1" '
    index($0,want)==1 { cap=1; cnt++; buf[cnt]=$0 ORS; next }
    cap && /^## / { cap=0 }
    cap { buf[cnt]=buf[cnt] $0 ORS }
    END { printf "%s%s", buf[cnt-1], buf[cnt] }' "$r")"
  local nboxes; nboxes="$(printf '%s' "$blocks" | grep -cE '^\- \[x\] clean-tree: .*porcelain.*empty' || true)"
  [ "$nboxes" -ge 2 ] || { echo "refuse: dirty-tree" >&2; die "coldgo-gate: both GO receipts need a checked 'clean-tree: git status --porcelain empty' box (the sha must pin the pixels)."; }
  [ "$s2" = "$head12" ] || { echo "refuse: stale-head" >&2; die "coldgo-gate: GOs at tree=$s2 but current HEAD is $head12 — a commit after the final GO invalidates it (RD-7)."; }
  ok "coldgo-gate: 2 consecutive cold GOs @ tree=$s2 == HEAD, clean trees — design gate PASS."
}

# ── v0.12.0 S6a: auto-suspend / auto-resume — the interactive-driver lever (contract F-SUSPEND,
# born from the live spawn race during this build's own R1). auto-suspend creates `.auto-suspended`
# ALONGSIDE `.auto-mode` (never deletes it — metering and the human-eyes refusals stay armed),
# appends the `auto-suspended` chain event, and refuses while a LIVE FOREIGN owner holds the build
# (kill the spawn → `own` → suspend). auto-resume removes the marker, REQUIRES declared budget
# ceilings (the auto-init precondition — flag-only precheck validates nothing), appends `auto-resumed`.
cmd_auto_suspend() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh auto-suspend <build-dir>"
  [ -f "$dir/.auto-mode" ] || die "auto-suspend: '$(basename "$dir")' is not an --auto build (no .auto-mode)."
  local slug ld owner sid; slug="$(basename "$dir")"; ld="$(locks_dir)"; sid="${CLAUDE_CODE_SESSION_ID:-}"
  owner="$(owner_of "$slug" "$ld" 2>/dev/null || true)"
  if [ -n "$owner" ] && [ -n "$sid" ] && [ "$owner" != "$sid" ]; then
    die "auto-suspend: a foreign session owns this build (owner $owner) — kill its spawn (pgrep -fl 'compass:resume $slug'), take ownership (compass.sh own $slug --session \"\$CLAUDE_CODE_SESSION_ID\"), then suspend. The engine never kills a process itself."
  fi
  : > "$dir/.auto-suspended"
  _chain_append "$dir" "-" "auto-suspended"
  ok "auto-suspend: self-spawn dormant for '$slug' (.auto-mode kept — metering stays armed). Re-arm: compass.sh auto-resume $dir"
}
cmd_auto_resume() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh auto-resume <build-dir>"
  [ -f "$dir/.auto-suspended" ] || { ok "auto-resume: '$(basename "$dir")' is not suspended — nothing to do."; return 0; }
  local be; be="$(_be_file "$dir")"
  { [ -f "$be" ] && [ -n "$(_be_get "$be" ceiling_wall)" ] && [ -n "$(_be_get "$be" ceiling_sessions)" ] && [ -n "$(_be_get "$be" ceiling_stages)" ]; } \
    || die "auto-resume: refusing — no declared budget ceilings in budget.env (--auto requires a measurable budget; run budget-init/auto-start first)."
  rm -f "$dir/.auto-suspended"
  _chain_append "$dir" "-" "auto-resumed"
  ok "auto-resume: self-spawn re-armed for '$(basename "$dir")'."
}

# v0.12.0 S2a: __match — TEST SURFACE ONLY. Whitelist-guarded to the *_match helper namespace;
# reads ONE candidate line/block on stdin, exits 0/1. Lets the suites drive the exact matchers
# the gates use (INV-TEMPLATES) without sourcing tricks. Not for production flows.
cmd___match() { # <helper-name>  (candidate on stdin)
  local h="${1:-}"
  case "$h" in
    *_match) : ;;
    *) die "__match: '$h' is not in the *_match helper namespace." ;;
  esac
  type "$h" >/dev/null 2>&1 || die "__match: unknown helper '$h'."
  "$h"
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    state-root)        state_root; echo ;;
    cwd-slug)          cwd_slug ;;
    builds)            cmd_builds "$@" ;;
    post-merge-check)  cmd_post_merge_check "$@" ;;
    doctor)            cmd_doctor "$@" ;;
    status)            cmd_status "$@" ;;
    design-drift-gate) cmd_design_drift_gate "$@" ;;
    converge-gate)     cmd_converge_gate "$@" ;;
    design-style-diff) cmd_design_style_diff "$@" ;;
    active-builds)     cmd_active_builds "$@" ;;
    worktree)          cmd_worktree "$@" ;;
    promote)           cmd_promote "$@" ;;
    worktree-rm)       cmd_worktree_rm "$@" ;;
    assert-worktree)   cmd_assert_worktree "$@" ;;
    claim)             cmd_claim "$@" ;;
    check-overlap)     cmd_check_overlap "$@" ;;
    check-db-isolation) cmd_check_db_isolation "$@" ;;
    install-guard)     cmd_install_guard "$@" ;;
    audit-staged)      cmd_audit_staged "$@" ;;
    merged-recon)      cmd_merged_recon "$@" ;;
    gc)                cmd_gc "$@" ;;
    gate)              cmd_gate "$@" ;;
    scan-receipt)      cmd_scan_receipt "$@" ;;
    supersede)         cmd_supersede "$@" ;;
    reconcile)         cmd_reconcile "$@" ;;
    secret-scan)       cmd_secret_scan "$@" ;;
    migration-gate)    cmd_migration_gate "$@" ;;
    route-coverage)    cmd_route_coverage "$@" ;;
    lifecycle-audit)   cmd_lifecycle_audit "$@" ;;
    stop-guard)        cmd_stop_guard "$@" ;;
    own)               cmd_own "$@" ;;
    ship-claim)        cmd_ship_claim "$@" ;;
    ship-release)      cmd_ship_release "$@" ;;
    ship-contenders)   cmd_ship_contenders "$@" ;;
    close)             cmd_close "$@" ;;
    auto-precheck)     cmd_auto_precheck "$@" ;;
    auto-init)         cmd_auto_init "$@" ;;
    budget-init)       cmd_budget_init "$@" ;;
    budget-check)      cmd_budget_check "$@" ;;
    postship-required) cmd_postship_required "$@" ;;
    loop-round)        cmd_loop_round "$@" ;;
    loop-converged)    cmd_loop_converged "$@" ;;
    coldgo-gate)       cmd_coldgo_gate "$@" ;;
    auto-suspend)      cmd_auto_suspend "$@" ;;
    auto-resume)       cmd_auto_resume "$@" ;;
    postship-signal)   cmd_postship_signal "$@" ;;
    __match)           cmd___match "$@" ;;
    check-session-chain) cmd_check_session_chain "$@" ;;
    fire-g2)           cmd_fire_g2 "$@" ;;
    fire-g1)           cmd_fire_g1 "$@" ;;
    gate-clear)        cmd_gate_clear "$@" ;;
    stage-continuable) is_stage_continuable "$@" && ok "continuable" || die "not continuable" ;;
    auto-start)        cmd_auto_start "$@" ;;
    auto-spawn)        cmd_auto_spawn "$@" ;;
    can-advance)       cmd_can_advance "$@" ;;
    *) echo "compass.sh: unknown subcommand '$sub'" >&2; exit 2 ;;
  esac
}
# v0.12.0 S2a: source-guard — `source compass.sh` loads the library without running main,
# so the suites can unit-drive internal helpers (hdr_get/ps_open_rows/*_match). CLI unchanged.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then main "$@"; fi
