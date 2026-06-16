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

# slug → its worktree path  <parent>/<basename>.compass/<slug>
worktree_path() { # <slug>
  local root parent base; root="$(main_root)"
  parent="$(dirname "$root")"; base="$(basename "$root")"
  printf '%s/%s.compass/%s' "$parent" "$base" "$1"
}

# Derive slug from the current worktree's top-level dir, else empty.
cwd_slug() {
  local top; top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  case "$top" in
    *.compass/*) basename "$top" ;;
    *) printf '' ;;
  esac
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
  local slug="$1" base="${2:-HEAD}" wt; wt="$(worktree_path "$slug")"
  if git worktree list --porcelain | grep -qxF "worktree $wt"; then ok "worktree exists: $wt"; printf '%s\n' "$wt"; return; fi
  mkdir -p "$(dirname "$wt")"
  if git show-ref --verify --quiet "refs/heads/compass/$slug"; then
    git worktree add "$wt" "compass/$slug" >&2 || die "git worktree add failed for $slug"
  else
    git worktree add "$wt" -b "compass/$slug" "$base" >&2 || die "git worktree add -b failed for $slug"
  fi
  ok "worktree ready: $wt (branch compass/$slug)"
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
top="$(git rev-parse --show-toplevel)"; staged="$(git diff --cached --name-only)"
[ -n "$staged" ] || exit 0
fail=0
case "$top" in
  *.compass/*)   # inside a build worktree → must stay within THAT slug's claim
    slug="$(basename "$top")"
    [ -f "$ld/$slug.files" ] || exit 0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      grep -qxF "$f" "$ld/$slug.files" || { echo "COMPASS-GUARD: '$f' is outside build '$slug' claim — re-run compass.sh claim or unstage it." >&2; fail=1; }
    done <<< "$staged" ;;
  *)             # main checkout → must NOT commit any active build's claimed file
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      for cf in "$ld"/*.files; do
        [ -e "$cf" ] || continue
        grep -qxF "$f" "$cf" && { echo "COMPASS-GUARD: '$f' is claimed by build '$(basename "$cf" .files)' — commit it from that build's worktree, not the main checkout." >&2; fail=1; }
      done
    done <<< "$staged" ;;
esac
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
cmd_gc() {
  local removed=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in worktree\ *.compass/*) ;; *) continue ;; esac
    local wt slug st; wt="${line#worktree }"; slug="$(basename "$wt")"
    case "$slug" in _merged_*) git worktree remove --force "$wt" 2>/dev/null && removed=$((removed+1)); continue ;; esac
    st="$(build_status "$slug")"
    if is_terminal "$st"; then
      git worktree remove --force "$wt" 2>/dev/null && removed=$((removed+1))
      git branch -D "compass/$slug" 2>/dev/null || true
    fi
  done < <(git worktree list --porcelain | grep '^worktree ')
  ok "gc removed $removed stale worktree(s)."
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

cmd_close() { # <build-dir> <slug>
  local dir="$1" slug="$2"
  # Clear the CURRENT hint in the canonical state root (worktree-safe).
  local sr; sr="$(state_root 2>/dev/null || true)"
  if [ -n "$sr" ] && [ -f "$sr/CURRENT" ] && [ "$(cat "$sr/CURRENT" 2>/dev/null)" = "$slug" ]; then
    : > "$sr/CURRENT"
  fi
  # Drop the build's locks.
  if [ -n "$sr" ]; then rm -f "$sr/.locks/$slug.files" "$sr/.locks/$slug.meta" 2>/dev/null || true; fi
  # Best-effort worktree removal (no-op if none / dirty handled by --force at gc).
  git worktree list --porcelain 2>/dev/null | grep -qxF "worktree $(worktree_path "$slug" 2>/dev/null)" \
    && cmd_worktree_rm "$slug" --force >/dev/null 2>&1 || true
  ok "build '$slug' closed; CURRENT cleared, locks dropped, worktree GC'd."
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
  echo "────────────────────────────────────────────────────"
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    state-root)        state_root; echo ;;
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
    close)             cmd_close "$@" ;;
    *) echo "compass.sh: unknown subcommand '$sub'" >&2; exit 2 ;;
  esac
}
main "$@"
