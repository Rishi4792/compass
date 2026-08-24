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
# portable mtime (epoch) of a path — macOS `stat -f %m`, GNU `stat -c %Y`; 0 (→ treated as ancient) if both fail.
_lock_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

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
  # status = the LAST real cell ($(NF-1), before the trailing empty field), NOT a hardcoded
  # column — a `|` inside the free-text finding/fix/where cells shifts field numbers and would
  # otherwise hide an OPEN row (matches the pre-existing ledger_open_rows convention).
  awk -F'|' '
    function trim(x){ gsub(/^[ \t\r]+|[ \t\r]+$/,"",x); return x }
    /^[[:space:]]*\|/ {
      if ($0 ~ /^[[:space:]]*\|[-: |]+$/) next                      # separator row
      id=trim($2); if (id !~ /^PS-[0-9]+-[0-9]+$/) next
      sev=toupper(trim($4)); if (sev!="CRITICAL" && sev!="MAJOR") next
      st=toupper(trim($(NF-1)))
      exo=0; for(i=1;i<=NF;i++){ c=toupper(trim($i)); if(c ~ /^(OPEN|REOPENED)([ \t]*[(:—-]|$)/) exo=1 }
      # OPEN unless the status cell is a close token (close word at a word boundary) AND no clean OPEN cell.
      if (exo || st !~ /^(CLOSED|FIXED|RESOLVED|N\/A)([^A-Z0-9]|$)/) n++
    }
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


# ── v0.32.0 S10 — THE STREAM LIST IS THE DENOMINATOR, AND IT IS NOT THE RECEIPT'S TO CHOOSE ─────
# Measured on this repo before the gate was written: 31 build folders, 20 receipts carrying an
# "all streams run" line — the exact literal "all streams run; ledger updated" is in 7 of them, a
# correction an independent reviewer forced — and exactly ONE folder with an agents/ directory
# in it. Twenty reviews recorded that every stream ran, with zero evidence files on disk, and no
# check could tell the difference — because the only thing anything read was the receipt's own
# claim about itself.
# So the denominator moves OUT of the receipt and into the review skill, where it is a machine-read
# list between COMPASS-STREAMS markers. Contract §4: a stream id is "derived, never a hardcoded
# letter range". The [A]..[F] labels in those skills are a reading aid; these ids are the count.
_streams_file() { printf '%s' "$(dirname "${BASH_SOURCE[0]}")/../skills/$1/SKILL.md"; }

cmd_review_streams() { # <review>
  local rv="${1:-}"
  case "$rv" in
    review-contract|review-plan|review-build) ;;
    *) die "review-streams: usage: review-streams <review-contract|review-plan|review-build>" ;;
  esac
  local f; f="$(_streams_file "$rv")"
  [ -f "$f" ] || die "review-streams: no skill file for '$rv' at $f — the denominator has no source."
  local line
  line="$(sed -n '/<!-- COMPASS-STREAMS:START -->/,/<!-- COMPASS-STREAMS:END -->/p' "$f" \
          | sed -nE 's/^`streams: (.*)`$/\1/p' | head -1)"
  # An EMPTY list is an ERR, never an empty denominator. "0 of 0 streams present" is the vacuity
  # class this build keeps finding: an assertion that passes because it is measuring nothing.
  [ -n "$line" ] || die "review-streams: '$rv' declares no machine-readable stream list between the COMPASS-STREAMS markers. A review with no declared streams has no denominator, and 0 of 0 is not a pass."
  # PATHNAME EXPANSION OFF. An independent reviewer put `*` in the list and the declared count
  # became whatever the current directory held — 3 in an empty dir, 29 in scripts/, 14 at the repo
  # root. The denominator that "is not the receipt's to choose" was the shell's to choose.
  # VALIDATE EVERYTHING, THEN PRINT. A first version checked inside the printing loop, so a list
  # with a bad id in the middle emitted the ids before it and then died — a caller reading stdout
  # got a partial denominator, which is worse than none.
  local n=0 sid bad=""
  set -f
  for sid in $line; do
    n=$((n+1))
    case "$sid" in *'*'*|*'?'*|*'['*|*']'*) bad="$sid" ;; esac
  done
  set +f
  [ -z "$bad" ] || die "review-streams: '$rv' declares a stream id containing a glob character ('$bad'). A stream id is a name, not a pattern — an unquoted one made the declared count depend on the current directory (3 in an empty dir, 29 in scripts/, 14 at the repo root)."
  [ "$n" -ge 3 ] || die "review-streams: '$rv' declares only $n stream(s). A fan-out of fewer than three is not a fan-out; if that is genuinely intended, it is a contract change, not a list edit."
  set -f
  for sid in $line; do printf '%s\n' "$sid"; done
  set +f
}

# review-evidence-gate <build-dir> <review> <round>
# One evidence file per DECLARED stream. Guard-first: a build with no agents/ directory and no
# `streams:` receipt line predates this format — it N/A-PASSES and SAYS SO, in words, rather than
# passing silently. It does not escape scrutiny by that route: with no evidence present, S11's
# disclosure fires and the page and receipt must both say the review was NOT independently verified.
cmd_review_evidence_gate() {
  local dir="${1:-}" rv="${2:-}" round="${3:-}"
  [ -n "$dir" ] && [ -d "$dir" ] || die "review-evidence-gate: usage: review-evidence-gate <build-dir> <review> <round>"
  case "$rv" in review-contract|review-plan|review-build) ;; *) die "review-evidence-gate: '$rv' is not a review skill." ;; esac
  case "${round:-}" in ''|*[!0-9]*) die "review-evidence-gate: round must be a positive integer, got '${round:-}'." ;; esac
  local rec="$dir/receipts.md" claim=""
  [ -f "$rec" ] && claim="$(sed -nE "s/^.*streams: *$rv +r$round +-> *([0-9]+) +of +([0-9]+).*$/\1 \2/p" "$rec" | head -1)"
  if [ ! -d "$dir/agents" ] && [ -z "$claim" ]; then
    ok "review-evidence-gate '$(basename "$dir")' $rv r$round: N/A — this round predates per-stream evidence (no agents/ directory and no 'streams:' receipt line), so there is nothing to check and nothing is claimed. NOT a statement that the review was independently verified; INV-DISCLOSE-UNVERIFIED covers that case."
    return 0
  fi
  local declared; declared="$(cmd_review_streams "$rv")" || exit 1
  local total=0 present=0 missing="" bad="" sid f
  for sid in $declared; do
    total=$((total+1)); f="$dir/agents/$rv-r$round-$sid.md"
    if [ -s "$f" ]; then present=$((present+1)); else missing="$missing $sid"; fi
  done
  # The receipt may state a denominator. If it does, it must be the DECLARED one — a receipt that
  # gets to pick its own denominator can report "1 of 1 streams" and be arithmetically perfect.
  if [ -n "$claim" ]; then
    local cnum cden; cnum="${claim%% *}"; cden="${claim##* }"
    [ "$cden" = "$total" ] || die "review-evidence-gate: the receipt claims a denominator of $cden but $rv declares $total streams. The denominator is the skill's list, never the receipt's own claim."
    [ "$cnum" = "$present" ] || die "review-evidence-gate: the receipt claims $cnum stream file(s) present but $present are on disk. A receipt is a record, not a source."
  fi
  [ -z "$missing" ] || die "review-evidence-gate: $present of $total declared streams have an evidence file. MISSING:$missing — expected at $dir/agents/$rv-r$round-<stream>.md. A review that claims its streams ran leaves one file per stream."
  # Shape, delegated to the §4 validator, which treats a file missing `nonce` or `target-sha` as
  # ABSENT rather than as a nearly-good pass.
  local esc; esc="$(dirname "${BASH_SOURCE[0]}")/evidence-shape-check.sh"
  if [ -f "$esc" ]; then
    # Only THIS round's stream files. `evidence-shape-check.sh` validates every .md in a directory,
    # and agents/ legitimately holds other things (an identity probe, a reviewer's working note) —
    # handing it the whole directory would fail a round because of a file that is not evidence and
    # never claimed to be.
    local _sd; _sd="$(mktemp -d)"
    for sid in $declared; do cp "$dir/agents/$rv-r$round-$sid.md" "$_sd/" 2>/dev/null || true; done
    if ! bash "$esc" "$_sd" --expect-streams "$(printf '%s' "$declared" | tr '\n' ',' | sed 's/,$//')" >/dev/null 2>&1; then
      rm -rf "$_sd"
      die "review-evidence-gate: one or more evidence files fail contract §4's shape. Run: evidence-shape-check.sh $dir/agents"
    fi
    rm -rf "$_sd"
  fi
  # COULD-NOT-VERIFY is the honest verdict when a spawn fails — and §8 makes it HARD-BLOCK closure
  # unless there is MACHINE evidence of the failed spawn beside it. Without that rule it is simply
  # the cheapest verdict to write.
  local cnv=0
  for sid in $declared; do
    f="$dir/agents/$rv-r$round-$sid.md"
    grep -qE '^verdict: *COULD-NOT-VERIFY' "$f" 2>/dev/null || continue
    cnv=$((cnv+1))
    [ -s "$dir/agents/$rv-r$round-$sid.spawn.log" ] \
      || die "review-evidence-gate: stream '$sid' records COULD-NOT-VERIFY with no machine evidence of the failed spawn. Expected a non-empty $rv-r$round-$sid.spawn.log beside it. HARD STOP — COULD-NOT-VERIFY must cost more than writing the words."
  done
  ok "review-evidence-gate '$(basename "$dir")' $rv r$round: $present of $total declared streams have a well-formed evidence file$( [ "$cnv" -gt 0 ] && printf ' · %s COULD-NOT-VERIFY, each with its spawn log' "$cnv" ). Denominator read from the skill's own stream list, not from the receipt."
}


# ── v0.32.0 S11, INV-DISCLOSE-UNVERIFIED — the receipt half ─────────────────────────────────────
# Contract §4, after Rishi's decision: proving independence is impossible in this environment, so
# §8's "independence positively established" branch is UNREACHABLE by design and the disclosure is
# unconditional. What this gate refuses is a review receipt that stays SILENT about it.
# The page half lives in gen.mjs (`unverifiedBanner`), styled as a red-ruled block at the top of the
# review page rather than muted small print — two cold readers walked past the previous treatment,
# and moving it changed nothing, because a reader skips by style before position matters.
# GUARD-FIRST, re-measured after an independent reviewer showed the first figure was wrong: 30 of
# this repo's 31 build folders carry a review receipt, and the earlier note said 20. (20 was the
# count of files containing the looser string "all streams run"; the exact literal it quoted appears
# in 7.) A wrong number in the comment justifying a guard is this build's own subject.
COMPASS_DISCLOSE_SENTENCE='this review was NOT independently verified'

cmd_review_disclose_gate() { # <build-dir>
  local dir="${1:-}"
  [ -n "$dir" ] && [ -d "$dir" ] || die "review-disclose-gate: usage: review-disclose-gate <build-dir>"
  local slug; slug="$(basename "$dir")"
  # ── SCOPE IS NOT THE RECEIPT'S TO CHOOSE ────────────────────────────────────────────────────
  # The first version keyed scope on a `streams:` line in the receipt, and an independent reviewer
  # showed five of seven natural ways to write that line took the rule out of scope — including
  # backticks, which the skill's own template uses on that very line. The gate then said, about a
  # brand-new receipt, "this receipt predates the per-stream format". That is S10's own defect —
  # "the denominator was the receipt's own claim about itself" — reintroduced one level up.
  # The discriminator is now the v0.30 `.compass-format` stamp, which the review stage cannot author.
  if [ ! -f "$dir/.compass-format" ]; then
    ok "review-disclose-gate '$slug': N/A — no .compass-format stamp, so this build predates the rule. 30 of this repo's 31 build folders carry a review receipt and 27 are in this state. NOT a statement that any review was independently verified."
    return 0
  fi
  local rec="$dir/receipts.md"
  if [ ! -f "$rec" ]; then
    ok "review-disclose-gate '$slug': N/A — no receipts.md, so there is no review receipt to check."
    return 0
  fi
  if _build_finished "$dir/progress.md"; then
    ok "review-disclose-gate '$slug': N/A — this build's STATUS line says it is finished; adding the sentence to its receipts now would be back-dating, not disclosure."
    return 0
  fi
  # ── EACH ROUND DISCLOSES FOR ITSELF ─────────────────────────────────────────────────────────
  # The first version compared two GLOBAL counts, so a round that said nothing passed because
  # another round said it twice. Blocks are split on the receipt heading and each review block is
  # checked in its own right.
  local silent="" total=0
  local blk="" head=""
  while IFS= read -r ln || [ -n "$ln" ]; do
    case "$ln" in
      '#'*[Rr][Ee][Cc][Ee][Ii][Pp][Tt]*)
        _st="$(_receipt_stage "$ln")"
        [ -n "$_st" ] || { blk="$blk
$ln"; continue; }
        if [ -n "$head" ]; then
          case "$head" in review-*)
            total=$((total+1))
            case "$blk" in *"$COMPASS_DISCLOSE_SENTENCE"*) : ;; *) silent="$silent $head" ;; esac ;;
          esac
        fi
        head="$_st"; blk="" ;;
      *) blk="$blk
$ln" ;;
    esac
  done < "$rec"
  if [ -n "$head" ]; then
    case "$head" in review-*)
      total=$((total+1))
      case "$blk" in *"$COMPASS_DISCLOSE_SENTENCE"*) : ;; *) silent="$silent $head" ;; esac ;;
    esac
  fi
  if [ "$total" -eq 0 ]; then
    ok "review-disclose-gate '$slug': N/A — no review receipt block on a stamped, unshipped build. Nothing is claimed about independence because no review is recorded."
    return 0
  fi
  [ -z "$silent" ] || die "review-disclose-gate: $total review round(s) recorded and these say nothing about independence:$silent. Contract §4 deleted the claim that independence can be proven here; a round that stays silent reads as though it was verified. Each round discloses for ITSELF — one line elsewhere in the file does not speak for it. HARD STOP (INV-DISCLOSE-UNVERIFIED)."
  ok "review-disclose-gate '$slug': all $total recorded review round(s) disclose in their own block. The page carries the same sentence (gen.mjs unverifiedBanner)."
}


# ── v0.32.0, from an independent review of S16/S17 ─────────────────────────────────────────────
# TWO SHAPES THAT BOTH NEW GATES GOT WRONG, fixed once, here.
#
# 1. "IS THIS BUILD FINISHED" was `case "$(head -c 400 progress.md)" in *SHIPPED*|*CLOSED*)`. That
#    reads PROSE. A build with `Blockers: none — F-3 was CLOSED in S12` in its opening paragraph —
#    visibly mid-loop, `wakeups_used: 12/40`, an unticked next step — was told "this build has
#    shipped, so its loop is over". Compass progress files discuss findings being CLOSED constantly;
#    this repo's own has the word eight times. It now reads the STATUS LINE's value and nothing else.
# 2. "IS THERE A RECEIPT FOR STAGE X" was an exact `^## RECEIPT — <stage>`. Six of twelve natural
#    spellings escaped: an ASCII hyphen instead of an em dash, `###`, `Receipt`, a capitalised
#    stage, no space around the dash. That is the previous review's finding 3 — the receipt choosing
#    its own scope — reintroduced in the gate written to answer it.
_build_finished() { # <progress.md> -> 0 if the STATUS line says finished
  local f="${1:-}" v
  [ -f "$f" ] || return 1
  v="$(LC_ALL=C sed -nE 's/^[[:space:]*_-]*[Ss]tatus[[:space:]*_]*:[[:space:]*]*(.*)$/\1/p' "$f" | head -1)"
  [ -n "$v" ] || return 1
  # THE LEADING TOKEN OF THE VALUE, not the whole value. The value is prose too: this build's own
  # status reads "BUILDING — S17 and S18 shipped, plus all TEN findings…", and matching anywhere in
  # it declared an actively-building build finished. Leading emoji and punctuation are stripped
  # first, because "✅ SHIPPED v0.31.0" is a real line in this repo.
  v="$(printf '%s' "$v" | LC_ALL=C sed -E 's/^[^A-Za-z]*//' | tr 'a-z' 'A-Z')"
  case "$v" in
    SHIPPED*|CLOSED*|ABANDONED*|SUPERSEDED*) return 0 ;;
  esac
  return 1
}
_has_receipt() { # <receipts.md> <stage-alternation>
  local f="${1:-}" st="${2:-}"
  [ -f "$f" ] || return 1
  # ALTERNATION, NOT A BRACKET CLASS. An em dash is multibyte, so `[—–-]` matches individual BYTES
  # and the trailing `-` forms a range — the first attempt at this made every em-dash heading escape
  # and only the ASCII hyphen work, which is the opposite of the bug it was fixing.
  LC_ALL=C grep -qiE "^#{2,4}[[:space:]]*RECEIPT[[:space:]]*(—|–|-)[[:space:]]*($st)([^A-Za-z0-9]|$)" "$f"
}
_receipt_stage() { # <heading line> -> the stage word, lowercased, or empty
  LC_ALL=C printf '%s' "${1:-}" | sed -E 's/^#{2,4}[[:space:]]*[Rr][Ee][Cc][Ee][Ii][Pp][Tt][[:space:]]*(—|–|-)[[:space:]]*/\x01/' | sed -nE 's/^\x01([A-Za-z-]+).*/\1/p' | tr 'A-Z' 'a-z'
}
# ── v0.32.0 S17 — ARM THE ENGINE, AND SAY SO WHEN YOU CANNOT ────────────────────────────────────
# Compass's own `--auto` stalls: it finishes a step, writes a paragraph and waits. The long-build
# skill is the engine that replaces that continuation, and S16's counter is what BOUNDS it. Arming
# it is therefore a build-level decision that belongs in progress.md and on the receipt, in both
# auto and human-gated modes — a loop nobody recorded is a loop nobody can audit or stop.
#
# GUARD-FIRST, measured on this repo before the gate was written: 31 build folders, 4 carrying the
# v0.30 `.compass-format` stamp, 0 with an `engine:` line. So the gate arms on the STAMP — the same
# discriminator mode-gate uses — and the other 27 N/A-pass and say so.
#
# AND IT N/A-PASSES WHEN THE SKILL IS ABSENT. You cannot arm an engine that is not installed, and
# refusing a build for that would be a gate demanding the user install something to pass. It says
# which case it is, in words, because "PASS" alone reads as "armed" and it is not.
_engine_skill_present() {
  local d
  for d in "${COMPASS_ENGINE_SKILL_DIR:-}" \
           "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/skills/long-build" \
           "$HOME/.claude/skills/long-build"; do
    [ -n "$d" ] || continue
    [ -f "$d/SKILL.md" ] && { printf '%s' "$d"; return 0; }
  done
  return 1
}

cmd_engine_gate() { # <build-dir>
  local dir="${1:-}"
  [ -n "$dir" ] && [ -d "$dir" ] || die "engine-gate: usage: engine-gate <build-dir>"
  local slug; slug="$(basename "$dir")"
  if [ ! -f "$dir/.compass-format" ]; then
    ok "engine-gate '$slug': N/A — no .compass-format stamp, so this build predates the engine rule (27 of this repo's 31 build folders do). NOT a statement that a loop is armed or bounded."
    return 0
  fi
  # ── v0.33.0 S11 — THE EXCUSE IS GONE, BECAUSE COMPASS NOW OWNS THE DOCTRINE ─────────────────
  # This gate used to N/A-pass whenever the user-level `long-build` skill was absent, on the
  # reasoning that you cannot arm an engine that is not installed. Its own message admitted the
  # cost: "for most installs this gate is inert BY DESIGN". Inert on every install but one.
  #
  # That reasoning no longer holds. v0.33 ships `shared/engine.md`, so the ENGINE DOCTRINE is
  # present on every installation, and what this gate asks for is not a skill — it is a RECORDED
  # DECISION. A build with no loop writes `engine: none · reason=<why>`; a build with one writes
  # its cap. Both are answerable with nothing installed.
  #
  # BLAST RADIUS, measured over BOTH sets before the arm was removed — the second set is the one
  # S4 forgot, and forgetting it there cost two reverts:
  #   live build folders, with HOME emptied so the skill is genuinely absent : pass=32 refuse=0
  #   the suite's own fixtures, via a full smoke run                         : 972 passed, 0 failed
  local skilldir _engine_where
  skilldir="$(_engine_skill_present || true)"
  if [ -n "$skilldir" ]; then
    _engine_where="The long-build skill is installed at $skilldir, so a loop is available and arming it is a decision this build must state."
  else
    _engine_where="The long-build skill is not installed here and Compass does not ship it — but Compass DOES ship the engine doctrine at shared/engine.md, so this is still your decision to record, not a question about what is installed. A build driven by hand writes 'engine: none · reason=<why>'."
  fi

  # ── SCOPE, in the order the states actually occur ─────────────────────────────────────────
  # The engine is armed at the BUILD stage, so the seam is a BUILD receipt. Two guard-first misses
  # in a row taught this: measuring the 31 folders on disk said 31 pass / 0 refused, and a
  # brand-new build still went red — because a build is a SEQUENCE OF STATES and only its last one
  # is on disk. A contract-stage receipt is not build work, and this test has to come before any
  # progress.md test, because a build at contract lock has receipts and no progress.md yet.
  # The seam is the PLAN receipt, not the build receipt: building begins when the plan locks, and
  # the build-stage receipt is not written until the stage ENDS. Keying on it left a build that is
  # visibly mid-build — plan locked, twenty-odd steps committed — reading "has not started looping".
  if ! _has_receipt "$dir/receipts.md" 'plan|build|ship'; then
    ok "engine-gate '$slug': N/A — the plan is not locked yet, so this build has not started looping. The engine is armed once building begins, not at contract lock."
    return 0
  fi
  local prog="$dir/progress.md"
  # No progress.md, no loop. The engine exists to BOUND a long-build loop and progress.md is that
  # loop's state, so a build without one is not looping — it is being driven a step at a time by a
  # human. Dying here made engine-gate refuse a legitimate v0.30 post-ship fixture, which is a gate
  # reaching outside its own remit.
  if [ ! -f "$prog" ]; then
    ok "engine-gate '$slug': N/A — no progress.md, so there is no loop state to bound. NOT a statement that a loop is armed."
    return 0
  fi
  # A FINISHED build's loop is over. Demanding it record an engine retroactively would be a gate
  # rewriting history — and two of this repo's four stamped builds shipped before this rule existed.
  if _build_finished "$prog"; then
    ok "engine-gate '$slug': N/A — this build's STATUS line says it is finished, so its loop is over and there is nothing left to bound. NOT a retroactive claim that it was."
    return 0
  fi
  local line; line="$(LC_ALL=C sed -nE 's/^engine:[[:space:]]*(.+)$/\1/p' "$prog" | head -1)"
  [ -n "$line" ] || die "engine-gate: '$slug' records no 'engine:' line in progress.md. $_engine_where WRITE THIS LINE in progress.md — 'engine: long-build · armed=yes · cap=40 · counter=.compass-wakeups' — and stamp '- [x] engine: long-build armed, cap 40' on a receipt. (An independent reviewer found this gate hard-stopping on a line nothing on the tree told anyone to write; the build skill's receipt template now carries it.) HARD STOP (S17)."
  # BOUNDED, and bounded by a NUMBER. "armed" on its own is the unbounded loop the 2026-04-28
  # runaway was — 1.16B tokens spent re-scheduling. A cap is what makes arming safe to record.
  local cap; cap="$(printf '%s' "$line" | LC_ALL=C sed -nE 's/.*cap=([0-9]+).*/\1/p' | head -1)"
  case "${cap:-}" in
    ''|*[!0-9]*) die "engine-gate: '$slug' arms the engine but states no cap=<N>. An armed loop with no bound is the failure this gate exists to prevent. HARD STOP (S17)." ;;
  esac
  [ "$cap" -ge 1 ] || die "engine-gate: '$slug' states cap=$cap. A cap below 1 arms nothing."
  # The receipt must carry it too. progress.md is working state and gets rewritten; the receipt is
  # the record. One without the other is half a record.
  local rec="$dir/receipts.md"
  [ -f "$rec" ] && grep -qE '^-? *\[x\] *engine: ' "$rec" \
    || die "engine-gate: '$slug' records the engine in progress.md but never stamps it on a receipt. progress.md is working state and is rewritten; the receipt is what survives. HARD STOP (S17)."
  # And if S16's counter exists, it must not already be past the cap.
  local ctr="$dir/.compass-wakeups" n=0
  if [ -f "$ctr" ]; then
    n="$(LC_ALL=C awk '{ if ($1+0 > m) m = $1+0 } END { print m+0 }' "$ctr" 2>/dev/null || printf '0')"
    [ "$n" -le "$cap" ] || die "engine-gate: '$slug' is at wakeup $n against a stated cap of $cap. The loop ran past its own bound. HARD STOP (S17)."
  fi
  ok "engine-gate '$slug': engine armed and BOUNDED — cap=$cap, counter at $n, recorded in progress.md and stamped on a receipt. Skill found at $skilldir."
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
  # v0.28.0: case-INSENSITIVE. `ship` writes `status=shipped` (lowercase) into
  # the INDEX while TERMINAL_STATUSES lists `SHIPPED`, so every finished build
  # was classified ACTIVE forever: `active-builds` reported 12 shipped builds as
  # in flight, `/compass:go` offered to resume long-finished work, and parallel
  # detection thought 13 builds were running. Found while rendering the v0.28
  # orientation block, which was wrong for exactly this reason.
  # v0.32.0 S24 (§17-11): it case-folded but NEVER TRIMMED, and the compare below is
  # exact — so `SHIPPED ` (one trailing space, or a CR from a CRLF file) was not terminal.
  local s t
  s="$(printf '%s' "${1:-}" | tr -d '\r' | tr 'a-z' 'A-Z')"
  s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"
  for t in $TERMINAL_STATUSES; do
    [ "$s" = "$(printf '%s' "$t" | tr 'a-z' 'A-Z')" ] && return 0
  done
  return 1
}

# ── v0.32.0 S24 (§17-11, Rishi's reported bug): the ONE **Status:** parser ────
# There were FIVE copies of this regex — :198 resolve_status, :1574 cmd_stop_guard,
# :1696 cmd_status, :2173 is_stage_continuable, :2293 cmd_can_advance — and they
# DISAGREED WITH EACH OTHER: three folded case and two did not, one read the FIRST
# status line and four the LAST, two kept the whole rest of the line and three cut at
# a character class. Not one of them trimmed. So `**Status:** SHIPPED ` (one trailing
# space) was not equal to `shipped` in any exact compare, and a status line indented
# by even one space was invisible to all five.
#
# One source now; callers pick a MODE and nobody re-writes the regex.
#   --first  read the FIRST **Status:** line (display)   · default: the LAST (decisions)
#   --raw    do not fold case (the callers that PRINT it) · default: fold to lowercase
#   --token  cut at the legacy [A-Za-z()0-9 -] run, so a banner sentence cannot widen
#            a glob match                                 · default: the whole rest of the line
#
# NEVER errors and never exits non-zero — cmd_stop_guard calls it and a Stop hook must
# never crash. An absent or unreadable file is the empty string, which every caller
# already treats as unknown.
status_line() { # <progress.md> [--first] [--raw] [--token]
  local p="${1:-}" first=0 raw=0 token=0 s=""
  shift || true
  while [ $# -gt 0 ]; do
    case "${1:-}" in --first) first=1 ;; --raw) raw=1 ;; --token) token=1 ;; *) : ;; esac
    shift || break
  done
  [ -n "$p" ] && [ -f "$p" ] || { printf ''; return 0; }
  s="$(sed -nE 's/^[[:space:]]*\*\*Status:\*\*[[:space:]]*(.*)$/\1/p' "$p" 2>/dev/null || true)"
  [ -n "$s" ] || { printf ''; return 0; }
  if [ "$first" = 1 ]; then s="$(printf '%s\n' "$s" | head -n1 || true)"
  else                      s="$(printf '%s\n' "$s" | tail -n1 || true)"; fi
  s="$(printf '%s' "$s" | tr -d '\r' || true)"
  # v0.32.0 S24b — REGRESSION FOUND BY THE INDEPENDENT REVIEWER OF S24, and it was real.
  # A status may be written in markdown emphasis: `**Status:** **SHIPPED (post-ship …)**`. The old
  # character class could not see past the leading `**`, but because a SPACE is in that class it
  # backtracked and returned a single space — junk, yet non-empty, which happened to suppress the
  # stale-INDEX fallback. The rewrite correctly returned empty, the fallback then fired, and
  # `perf-fmea-method-v0-20-p2` — a build whose own progress.md says SHIPPED — was advertised as a
  # SHIP CONTENDER. Emphasis is decoration, never part of the status, so it is stripped here for
  # every mode. That makes the value more correct than either previous version, not just different.
  s="$(printf '%s' "$s" | sed -E 's/^[*_`[:space:]]+//; s/[*_`[:space:]]+$//' 2>/dev/null || true)"
  [ "$token" = 0 ] || s="$(printf '%s' "$s" | sed -E 's/^([A-Za-z()0-9 -]*).*/\1/' 2>/dev/null || true)"
  s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"
  [ "$raw" = 1 ] || s="$(printf '%s' "$s" | tr 'A-Z' 'a-z' || true)"
  printf '%s' "$s"
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
  local s; s="$(status_line "$sr/$1/progress.md" --token)"   # v0.32 S24: one parser, and it trims
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
    # v0.28.0: alternation, NOT bracket expressions. `[—-]` and `[·|]` contain
    # multibyte characters; under LC_ALL=C awk reads them byte-wise, turning
    # `[—-]` into an invalid/reversed byte range that never matches — so EVERY
    # receipt lookup returned empty and EVERY gate reported "no receipt" under a
    # C locale (CI, cron, minimal containers). Found by the v0.28 determinism
    # check rendering the same fixture under LC_ALL=C vs a UTF-8 locale.
    $0 ~ ("^## RECEIPT[ ]*(—|-)[ ]*" s "[ ]*(·|\\|)") { buf=$0 "\n"; cap=1; next }
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
  # v0.13.0 seams (script-owned invocation, RC-5/RC-6): the co-construct + sketch gates ride the
  # ordinary gate call — legacy builds (no declarations, no artifacts) pass byte-identically.
  if [ "$stage" = "contract" ]; then
    cmd_intake_gate "$dir" >/dev/null || die "gate: intake-gate FAILED for '$dir' (see stderr)."
    if type cmd_sketch_gate >/dev/null 2>&1; then
      cmd_sketch_gate "$dir" >/dev/null || die "gate: sketch-gate FAILED for '$dir' (see stderr)."
    fi
    # v0.21 contract-header pins (INV-SCHEMA-PIN, INV-PERFBUDGET) — guard-first N/A-pass on legacy.
    if type cmd_schema_pin_gate >/dev/null 2>&1; then
      cmd_schema_pin_gate "$dir" >/dev/null || die "gate: schema-pin-gate FAILED for '$dir' (see stderr)."
    fi
    if type cmd_perf_budget_gate >/dev/null 2>&1; then
      cmd_perf_budget_gate "$dir" >/dev/null || die "gate: perf-budget-gate FAILED for '$dir' (see stderr)."
    fi
    # v0.30 INV-10 — a self-referential reconciliation gold hard-stops here, at the seam every
    # downstream stage crosses. Guard-first: no ## Reconciliation section → N/A-pass.
    if type cmd_gold_gate >/dev/null 2>&1; then
      cmd_gold_gate "$dir" >/dev/null || die "gate: gold-gate FAILED for '$dir' (see stderr)."
    fi
    # v0.30 INV-3 — the build dir must have been created by `new-build` if it claims the format.
    if type cmd_contract_gate >/dev/null 2>&1; then
      cmd_contract_gate "$dir" >/dev/null || die "gate: contract-gate FAILED for '$dir' (see stderr)."
    fi
    # v0.28 INV-MODE-ASKED — contract-header driven, guard-first N/A-pass on legacy.
    if type cmd_mode_gate >/dev/null 2>&1; then
      cmd_mode_gate "$dir" >/dev/null || die "gate: mode-gate FAILED for '$dir' (see stderr)."
    fi
  fi

  # v0.32.0 S17 — a gate nobody runs is not a gate, so the engine check rides the same seam as
  # mode-gate. It N/A-passes a legacy dir, a parked one, a shipped one, and a machine with no
  # long-build skill installed, so wiring it here refuses nothing that was passing before.
  if type cmd_engine_gate >/dev/null 2>&1; then
      cmd_engine_gate "$dir" >/dev/null || die "gate: engine-gate FAILED for '$dir' (see stderr)."
  fi
  # ── v0.33.0 S4 — TWO MORE GATES NOBODY CALLED ────────────────────────────────────────────
  # `unwired-gate-check` (this build) found four dispatchable commands with no caller anywhere —
  # not a skill, not a command, not a hook, not another function. Two of them are GATES that v0.32
  # built, in its own steps S12/S13/S15, to fire at every stage end. They never fired once.
  # That is the defect v0.32 named twice in its own release notes and shipped anyway, and it was
  # found here in one second by a script rather than by a sixth adversarial review.
  #
  # Both are file-based — they read receipts.md — so they ride this seam exactly as engine-gate
  # does, and no skill file is edited (which keeps them clear of the 14 pinned string-counts the
  # suite holds over skill markdown).
  #
  # BLAST RADIUS MEASURED BEFORE WIRING, over every build folder on this machine:
  #   cockpit-gate    pass=32  refuse=0
  #   stage-end-gate  pass=32  refuse=0
  # Zero newly refused. Had any legitimate folder refused, that would have been a finding against
  # the gate, not an acceptable cost.
  if type cmd_stage_end_gate >/dev/null 2>&1; then
      cmd_stage_end_gate "$dir" >/dev/null || die "gate: stage-end-gate FAILED for '$dir' (see stderr)."
  fi
  # ── cockpit-gate is NOT wired here, and this is the record of two honest attempts to wire it ──
  #
  # ATTEMPT 1: wired as-is. Suite went 968 passed / 4 FAILED. It refused the suite's own minimal
  # fixtures. My blast radius had been measured over the live build folders and NOT the fixtures —
  # the wrong set, the same denominator error this build keeps finding in other people's work.
  #
  # ATTEMPT 2: widened its guard to N/A-pass a dir with no progress.md (measured first: 0 of 32 real
  # builds are receipts-only, so it excused nothing that could have complied). Suite went 971 / 1.
  # One fixture remained: it HAS a progress.md, four lines long, and the cockpit cannot state "what
  # is next" from it.
  #
  # STOPPED THERE, deliberately. A third widening would have made the gate pass anything without a
  # rich progress.md — which is most things — to fit a seam it does not belong on. That is how a
  # gate becomes inert while still being called: the exact disease this build exists to cure. Two
  # widenings to fit a seam is the signal that the seam is wrong, not the gate.
  #
  # WHY ITS PROPER HOME IS CLOSED: cockpit-gate validates a block the model PRINTS at a stage
  # transition, so it belongs in the stage skills' own gate block. INV-7 asserts that block is
  # BYTE-IDENTICAL across all seven stage skills, with `shared/gate.md` as the canonical source —
  # and gate.md is a no-touch zone for this build.
  #
  # So it stays unwired, declared KNOWN-OPEN in unwired-allow.txt, printed on every run of
  # unwired-gate-check, and carried in contract §17. Recorded as a gap, never dressed up as a
  # decision — and no test was weakened to pretend otherwise.
  # ── v0.32.0 S10/S11 — A GATE NOBODY RUNS IS NOT A GATE ────────────────────────────────────
  # An independent reviewer's first finding: neither review gate was invoked by any skill, by
  # cmd_gate, or by any hook. The only callers on the whole tree were the corpus fixtures and the
  # smoke suite. Two steps built to replace the honour system left it exactly where it was — one
  # extra template line a model is trusted to type. They ride this seam now.
  # Blast radius measured before wiring: review-disclose-gate over all 31 build folders = 31 pass,
  # 0 refused; review-evidence-gate likewise, because both N/A-pass legacy, shipped and unstarted
  # builds and say which case it is.
  if type cmd_review_disclose_gate >/dev/null 2>&1; then
      cmd_review_disclose_gate "$dir" >/dev/null || die "gate: review-disclose-gate FAILED for '$dir' (see stderr)."
  fi
  # And every round the receipt CLAIMS must have the evidence it claims. The rounds come from the
  # receipt, but what they are checked against does not — that is the whole point of S10.
  if type cmd_review_evidence_gate >/dev/null 2>&1 && [ -f "$dir/receipts.md" ]; then
      while IFS=' ' read -r _rv _rd; do
        [ -n "$_rv" ] && [ -n "$_rd" ] || continue
        cmd_review_evidence_gate "$dir" "$_rv" "$_rd" >/dev/null \
          || die "gate: review-evidence-gate FAILED for '$dir' $_rv r$_rd (see stderr)."
      done <<EOF_STREAMS
$(LC_ALL=C sed -nE 's/^[-* ]*\[[xX ]\] *streams: *.?(review-(contract|plan|build)).? +r([0-9]+).*/\1 \3/p' "$dir/receipts.md" 2>/dev/null | sort -u)
EOF_STREAMS
  fi
  # v0.30 INV-0 — every INVARIANT must carry a recorded pre-change RED, checked when the work is
  # handed on as DONE. It was wired to the CONTRACT seam, which cannot work: evidence of a
  # pre-change failure can only exist once the work has started, so a brand-new build could never
  # lock its own contract. Found by dogfooding v0.31's first stage against the shipped v0.30.0.
  # INV-0's own wording is "before its step is ticked" — that is here, not at contract.
  # Guard-first is unchanged: a dir with no stamp and no evidence file N/A-passes.
  if { [ "$stage" = "build" ] || [ "$stage" = "review-build" ]; } \
     && type cmd_redfirst_check >/dev/null 2>&1 \
     && { [ -f "$dir/.compass-format" ] || [ -f "$dir/red-first-evidence.md" ]; }; then
    cmd_redfirst_check "$dir" >/dev/null || die "gate: redfirst-check FAILED for '$dir' (see stderr)."
  fi
  if [ "$stage" = "review-build" ] && type cmd_sketch_gate >/dev/null 2>&1; then
    cmd_sketch_gate "$dir" >/dev/null || die "gate: sketch-gate (leak re-check) FAILED for '$dir' (see stderr)."
    # v0.21 migration-safety gates ride the review-build seam — guard-first N/A-pass on legacy.
    if type cmd_expand_contract_gate >/dev/null 2>&1; then
      cmd_expand_contract_gate "$dir" >/dev/null || die "gate: expand-contract-gate FAILED for '$dir' (see stderr)."
    fi
    if type cmd_backfill_recon_gate >/dev/null 2>&1; then
      cmd_backfill_recon_gate "$dir" >/dev/null || die "gate: backfill-recon-gate FAILED for '$dir' (see stderr)."
    fi
    if type cmd_green_ci_gate >/dev/null 2>&1; then
      cmd_green_ci_gate "$dir" >/dev/null || die "gate: green-ci-gate FAILED for '$dir' (see stderr)."
    fi
    # v0.31 the GOLD rides the review-build seam. Rounds 4-7 all recorded the same finding: the gold
    # checks existed and NOTHING CALLED THEM, so every baseline was a number a human ran by hand.
    # Guard-first N/A-pass: a tree with no proven-numbers.sh is untouched, so every legacy build
    # still gates byte-identically.
    if type cmd_gold_numbers_gate >/dev/null 2>&1; then
      cmd_gold_numbers_gate "$dir" >/dev/null || die "gate: gold-numbers-gate FAILED for '$dir' (see stderr)."
    fi
  fi
  # v0.21 compliance/PII gate rides the PLAN seam — guard-first N/A-pass on legacy (no `pii:` header).
  if [ "$stage" = "plan" ] && type cmd_pii_gate >/dev/null 2>&1; then
    cmd_pii_gate "$dir" >/dev/null || die "gate: pii-gate FAILED for '$dir' (see stderr)."
  fi
  ok "prior stage '$stage' receipt present, PASS, complete, not superseded."
}

cmd_scan_receipt() { # <build-dir> <stage>
  local dir="$1" stage="$2" f="$1/receipts.md"
  [ -f "$f" ] || die "no receipts.md — emit the $stage receipt first."
  local block; block="$(last_block "$f" "$stage")"
  [ -n "$block" ] || die "no $stage receipt found to scan."
  # A user-signed convergence waiver. Compass could previously express only two states for a
  # review: PASS, or blocked. There is a third that really happens — the review did NOT converge
  # and a human decided to ship anyway, knowing what is open. With no way to say that, the only
  # route forward was to tick a box that was not true, which is precisely the falsification this
  # whole build exists to prevent. So the state is now sayable, and it is sayable ONLY by the user:
  # a `converge-waiver: user-signed` line, the same shape as the cold-critic waiver, never a header
  # the checked party writes. The unchecked box then STAYS unchecked — it is the record of what was
  # not achieved — and every downstream surface must repeat that this build shipped un-converged.
  if printf '%s' "$block" | grep -qE '^- \[x\] converge-waiver: user-signed'; then
    local _unchecked; _unchecked="$(printf '%s' "$block" | grep -c '^- \[ \]' || echo 0)"
    ok "$stage receipt: ACCEPTED WITH OPEN FINDINGS — user-signed convergence waiver present; $_unchecked box(es) deliberately left unchecked as the record."
    printf '%s' "$block" | grep '^- \[ \]' | sed 's/^/    NOT ACHIEVED: /' >&2
    return 0
  fi
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

cmd_secret_scan() { # <build-dir|--commits <range>|files...>
  local first="${1:-}"
  # Pattern with NO embedded ASCII single-quote (a literal ' in the _SECRET class used to terminate
  # the xargs sh -c string — a pre-existing latent bug; the value side now just excludes whitespace).
  local pat='(-----BEGIN [A-Z ]*PRIVATE KEY|eyJ[A-Za-z0-9_-]{10,}\.|sk-[A-Za-z0-9]{16,}|postgres(ql)?://[^ ]*:[^ @]*@|[A-Za-z0-9_]*_SECRET[[:space:]]*=[[:space:]]*[^[:space:]]+|AKIA[0-9A-Z]{12,}|xox[baprs]-[0-9A-Za-z-]+)'
  local found=""
  _ss_hit() { [ -z "$1" ] || die "possible secret — remove it / read from env instead:
$1"; }
  if [ "$first" = "--commits" ]; then
    local range="${2:-}"; [ -n "$range" ] || die "usage: compass.sh secret-scan --commits <range>"
    git rev-parse --git-dir >/dev/null 2>&1 || die "secret-scan --commits: not a git repo."
    git rev-list --quiet "$range" -- >/dev/null 2>&1 || die "secret-scan --commits: bad range '$range'."
    found="$(git log -p "$range" -- 2>/dev/null | grep -E '^\+' | grep -EnI "$pat" || true)"
    _ss_hit "$found"; ok "secret scan (--commits $range): 0 hits."; return 0
  fi
  if [ -d "$first" ]; then
    found="$(grep -REnI --exclude-dir='.git' "$pat" "$first" 2>/dev/null || true)"
    _ss_hit "$found"; ok "secret scan ($first): 0 hits."; return 0
  fi
  if [ -n "$first" ]; then   # explicit file list
    found="$(grep -EnI "$pat" "$@" 2>/dev/null || true)"
    _ss_hit "$found"; ok "secret scan: 0 hits."; return 0
  fi
  # legacy no-arg: staged + working-tree-modified files (while-read loop, no sh -c pattern splice)
  if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    local f
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      local h; h="$(grep -EnI "$pat" "$f" 2>/dev/null || true)"
      [ -n "$h" ] && found="$found$f: $h
"
    done <<EOF
$( { git diff --name-only HEAD 2>/dev/null; git diff --name-only --cached 2>/dev/null; } | sort -u )
EOF
  fi
  _ss_hit "$found"; ok "secret scan: 0 hits."
}

# ── v0.15.0 prod-safety floor (F-RESTORE / F-PARITY) ──────────────────────────
# Both model cmd_migration_gate: a required signal ABSENT → die (never a soft pass);
# an N/A-pass fires ONLY when the contract explicitly declares "nothing to protect/verify".
_cv_dir() { # <slug-or-build-dir> → resolves to a build dir with a contract.md (fixture dir OR registered slug)
  local a="${1:-}"
  if [ -d "$a" ] && [ -f "$a/contract.md" ]; then printf '%s' "$a"; else printf '%s' "$(state_root)/$a"; fi
}

# a snapshot attestation field is REAL only if non-empty AND not an obvious placeholder token
# (none/n/a/tbd/todo/pending/- and placeholder-PREFIXED forms like "none-yet"/"pending-soon") — a
# placeholder is the operator falsely attesting (R3-n2 + R3-R2-D-min hardening).
_attest_real() {
  local v; v="$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z' | tr -d '[:space:]')"
  case "$v" in
    ''|none|n/a|na|tbd|tba|tbc|todo|pending|-) return 1 ;;
    none[!a-z0-9]*|n/a[!a-z0-9]*|tbd[!a-z0-9]*|todo[!a-z0-9]*|pending[!a-z0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

cmd_restore_point() { # <slug|build-dir> — HARD STOP before a destructive migration/backfill (F-RESTORE)
  local a="${1:-}"; [ -n "$a" ] || die "usage: compass.sh restore-point <slug|build-dir>"
  local dir contract; dir="$(_cv_dir "$a")"; contract="$dir/contract.md"
  [ -f "$contract" ] || die "restore-point: no contract.md in $dir"
  # Parse the FIRST alpha token per header, and defend against two soft-pass tricks the round-1 fix missed:
  #  1) hdr_get returns the WHOLE value incl. trailing prose ("yes → <reason>"), so an exact "!= yes" test
  #     misreads a declared-destructive build as N/A (R3-C1). Extract the token, not the line.
  #  2) ANCHOR to line-start so a `schema-touching: no` in PROSE can't steal the parse, and take a FAIL-SAFE
  #     UNION across all anchored header lines — destructive if ANY reads yes, so a stale `no` stub above a
  #     real `yes` (or a leading-prose decoy) cannot hide it (R3-R2-D1). schema-touching stays REQUIRED.
  # Anchor allows list/bold markers AND leading whitespace incl. TABS, then the value is coerced FAIL-SAFE:
  # destructive unless EVERY anchored value is exactly `no`. A truthy synonym (`true`/`y`), a quoted value,
  # or any unrecognized token is treated as destructive — matching migration-gate's `*) die` fail-safe, so a
  # `destructive-backfill: true` can't soft-pass the sole snapshot guard (R3-C1 → R3-R2-D1 → R3-R3-D2).
  local st_vals bf_vals st bf
  st_vals="$(sed -nE 's/^[-*[:space:]]*schema-touching:\**[[:space:]]*([A-Za-z]+).*/\1/p' "$contract" | tr 'A-Z' 'a-z')"
  bf_vals="$(sed -nE 's/^[-*[:space:]]*destructive-backfill:\**[[:space:]]*([A-Za-z]+).*/\1/p' "$contract" | tr 'A-Z' 'a-z')"
  [ -n "$st_vals" ] || die "restore-point: contract.md missing required 'schema-touching: yes|no' — cannot judge destructiveness (HARD STOP, never a soft pass)."
  if printf '%s\n' "$st_vals" | grep -vqx no; then st=yes; else st=no; fi
  if [ -n "$bf_vals" ] && printf '%s\n' "$bf_vals" | grep -vqx no; then bf=yes; else bf=no; fi
  if [ "$st" != "yes" ] && [ "$bf" != "yes" ]; then
    ok "restore-point: no destructive migration/backfill declared (schema-touching:$st, destructive-backfill:$bf) — N/A-pass. (Honest boundary: an UNDECLARED destructive backfill is not detectable here; the contract interview elicits the declaration.)"
    return 0
  fi
  # destructive is declared → require a COMPLETE snapshot attestation: all three fields non-empty.
  local sid sts scmd; sid="$(hdr_get "$contract" snapshot-id || true)"; sts="$(hdr_get "$contract" snapshot-ts || true)"; scmd="$(hdr_get "$contract" restore-cmd || true)"
  { _attest_real "$sid" && _attest_real "$sts" && _attest_real "$scmd"; } || die "restore-point: DESTRUCTIVE op declared (schema-touching:$st, destructive-backfill:${bf:-no}) but the snapshot attestation is INCOMPLETE or placeholder — need a REAL snapshot-id + snapshot-ts + restore-cmd (got id='$sid' ts='$sts' cmd='$scmd'). HARD STOP — never a soft pass."
  ok "restore-point: confirmed snapshot — id=$sid ts=$sts; restore: $scmd"
}

cmd_config_parity() { # <slug|build-dir> — HARD STOP if new code needs a prod env key prod lacks (F-PARITY)
  local a="${1:-}"; [ -n "$a" ] || die "usage: compass.sh config-parity <slug|build-dir>"
  local dir contract; dir="$(_cv_dir "$a")"; contract="$dir/contract.md"
  [ -f "$contract" ] || die "config-parity: no contract.md in $dir"
  # UNION all anchored env-keys-referenced / prod-keys lines and drop the literal `none` placeholder token —
  # first-match-wins (hdr_get) let a stale `env-keys-referenced: none` stub above a real-keys line soft-pass
  # the parity check (R3-R2-D3). Anchored to line-start so a prose mention can't steal the parse.
  local refs prod ref_keys="" k
  # strip trailing comments (`# …`, `<!-- … -->`) from each captured line BEFORE tokenizing — a key NAME
  # inside a comment on the prod-keys line must NOT count as a declared prod key (post-ship PS-1 soft-pass).
  refs="$(sed -nE 's/^[-*[:space:]]*env-keys-referenced:\**[[:space:]]*(.+)/\1/p' "$contract" | sed -E 's/<!--.*-->//g; s/#.*$//' | tr '\n' ' ')"
  prod="$(sed -nE 's/^[-*[:space:]]*prod-keys:\**[[:space:]]*(.+)/\1/p' "$contract" | sed -E 's/<!--.*-->//g; s/#.*$//' | tr '\n' ' ')"
  for k in $refs; do case "$(printf '%s' "$k" | tr 'A-Z' 'a-z')" in none|n/a|-|'') : ;; *) ref_keys="$ref_keys $k" ;; esac; done
  ref_keys="$(printf '%s' "$ref_keys" | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')"
  # no REAL new env keys referenced (absent, or only the explicit `none` placeholder) → nothing to verify.
  if [ -z "$ref_keys" ]; then
    ok "config-parity: no new env keys referenced (env-keys-referenced:${refs:-<none>}) — N/A-pass. (Honest boundary: a key referenced in code but not declared is not caught here; the F-FLAG/config interview elicits the declaration.)"
    return 0
  fi
  # real keys ARE referenced → a prod-key declaration MUST exist and cover every one (absent → die, never a soft pass).
  [ -n "$(printf '%s' "$prod" | tr -d '[:space:]')" ] || die "config-parity: the change references env keys [$ref_keys] but there is NO 'prod-keys:' declaration to diff against — HARD STOP (never a soft pass)."
  local missing=""
  for k in $ref_keys; do case " $prod " in *" $k "*) : ;; *) missing="$missing $k" ;; esac; done
  [ -z "$missing" ] || die "config-parity: prod is MISSING env key(s):$missing — referenced by the change, absent from prod-keys. HARD STOP before deploy."
  ok "config-parity: all referenced env keys present in prod ($ref_keys)."
}

# ── v0.21.0 data / migration / compliance safety gates (contract 6) ────────────
# Gate-authoring rule (INV-BC, LOAD-BEARING): every gate below is GUARD-FIRST — it
# N/A-passes (return 0) on a missing contract.md OR an absent trigger header, and
# treats an ABSENT trigger as N/A, never as `yes`. This mirrors cmd_sketch_gate /
# cmd_intake_gate (the byte-inert-on-legacy seam gates), NEVER cmd_restore_point
# (which die()s on a missing file and on an absent field). The cmd_gate seam runs
# these on every `gate <dir> <stage>` call, so a legacy build-dir (no contract.md,
# or a contract with none of these headers) MUST pass byte-identically.

cmd_schema_pin_gate() { # <slug|build-dir> — schema-touching build MUST carry a filled field-schema block (item 1, INV-SCHEMA-PIN)
  local a="${1:-}"; [ -n "$a" ] || die "usage: compass.sh schema-pin-gate <slug|build-dir>"
  local dir contract; dir="$(_cv_dir "$a")"; contract="$dir/contract.md"
  [ -f "$contract" ] || { ok "schema-pin: N/A — no contract.md (legacy)."; return 0; }
  # trigger = schema-touching (anchored-union token parse; ABSENT ⇒ N/A, never yes)
  local st_vals st
  st_vals="$(sed -nE 's/^[-*[:space:]]*schema-touching:\**[[:space:]]*([A-Za-z]+).*/\1/p' "$contract" | tr 'A-Z' 'a-z')"
  [ -n "$st_vals" ] || { ok "schema-pin: N/A — schema-touching absent (legacy)."; return 0; }
  if printf '%s\n' "$st_vals" | grep -vqx no; then st=yes; else st=no; fi
  [ "$st" = "yes" ] || { ok "schema-pin: N/A — schema-touching:$st (no schema surface)."; return 0; }
  # schema-touching: yes → an explicit `schema-pin: N/A — <reason>` opts out (honest boundary)
  local pin; pin="$(sed -nE 's/^[-*[:space:]]*schema-pin:\**[[:space:]]*(.+)/\1/p' "$contract" | head -1)"
  case "$pin" in [Nn]/[Aa]*) ok "schema-pin: explicit N/A — ${pin}."; return 0 ;; esac
  # else require a FILLED field-schema block: a NON-EMPTY evolution-rules value AND a real field-schema
  # header row with the pinned name/type columns (RB-R1-C2: an empty key or an unrelated 2-pipe table
  # — a decision/CHANGELOG table, even fenced — must NOT pass).
  local evr; evr="$(sed -nE 's/^[-*[:space:]]*evolution-rules:\**[[:space:]]*(.+)/\1/p' "$contract" | head -1)"
  _attest_real "$evr" \
    || die "schema-pin: schema-touching:yes but 'evolution-rules:' is absent or empty/placeholder (need a real rule) and no 'schema-pin: N/A — <reason>'. HARD STOP (INV-SCHEMA-PIN)."
  grep -qiE '^[[:space:]]*\|[^|]*\bname\b[^|]*\|[^|]*\btype\b' "$contract" \
    || die "schema-pin: schema-touching:yes but no field-schema table with the pinned '| name | type | …' columns (an unrelated 2-pipe table is not a field schema). HARD STOP (INV-SCHEMA-PIN)."
  ok "schema-pin: field-schema block present (evolution-rules filled + name/type table)."
}

cmd_perf_budget_gate() { # <slug|build-dir> — non-trivial-Scale build MUST pin p95/peak-mem/cost + SLO ranges (item 7, INV-PERFBUDGET)
  local a="${1:-}"; [ -n "$a" ] || die "usage: compass.sh perf-budget-gate <slug|build-dir>"
  local dir contract; dir="$(_cv_dir "$a")"; contract="$dir/contract.md"
  [ -f "$contract" ] || { ok "perf-budget: N/A — no contract.md (legacy)."; return 0; }
  # trigger = the perf-budget HEADER LINE. It must EXIST at all (RB-R4-F2: a bare `perf-budget:` with the
  # budget in a block BELOW is DECLARED, not absent — it must not silently N/A-pass). Absent line ⇒ N/A.
  grep -qiE '^[-*[:space:]]*perf-budget:' "$contract" \
    || { ok "perf-budget: N/A — header absent (legacy/trivial scale)."; return 0; }
  local pb; pb="$(sed -nE 's/^[-*[:space:]]*perf-budget:\**[[:space:]]*(.+)/\1/p' "$contract" | head -1)"
  # inline N/A branch: an explicit reason is REQUIRED — a bare `N/A` fails (INV-PERFBUDGET)
  case "$pb" in
    [Nn]/[Aa])
      die "perf-budget: bare 'N/A' with NO reason — need 'perf-budget: N/A — <reason>' (INV-PERFBUDGET)." ;;
    [Nn]/[Aa]*)
      local reason; reason="$(printf '%s' "$pb" | sed -E 's/^[Nn]\/[Aa][[:space:]]*[—–-]*[[:space:]]*//')"
      [ -n "$reason" ] || die "perf-budget: 'N/A' with NO reason — need 'perf-budget: N/A — <reason>' (INV-PERFBUDGET)."
      ok "perf-budget: explicit N/A — ${reason}."; return 0 ;;
  esac
  # DECLARED (inline value that isn't N/A, OR an empty inline value with the budget in a block below) →
  # DECOUPLED enforcement (RB-R1-C1 + RB-R3/R4): each axis NAMED (generous aliases) + a literal of its KIND
  # exists anywhere — no fragile proximity window. This is a DECLARED-surface discipline gate: it proves a
  # budget with real numbers was written; whether those numbers are the RIGHT budget is a review judgment.
  grep -qiE '\bp95\b|\bp99\b|\bp99\.9\b|latency' "$contract" \
    || die "perf-budget: declared but no latency axis named (p95/p99/latency) (INV-PERFBUDGET)."
  grep -qiE '[0-9]+(\.[0-9]+)? ?(ms|µs|us|sec|secs|seconds?)\b|[0-9]+(\.[0-9]+)?s\b' "$contract" \
    || die "perf-budget: declared but no latency LITERAL (a number+ms/s) (INV-PERFBUDGET)."
  grep -qiE 'peak[ -]?mem|peak memory|\bmemory\b|\bmem\b' "$contract" \
    || die "perf-budget: declared but no memory axis named (peak-mem/memory) (INV-PERFBUDGET)."
  grep -qiE '[0-9]+(\.[0-9]+)? ?([kmgt]i?b|[kmgt]i)\b' "$contract" \
    || die "perf-budget: declared but no memory LITERAL (a number+MB/GB/GiB/Mi) (INV-PERFBUDGET)."
  grep -qiF 'cost' "$contract" \
    || die "perf-budget: declared but 'cost' is not named (INV-PERFBUDGET)."
  grep -qiE '[$][0-9]|[0-9]+(\.[0-9]+)? ?(usd|cents?|/req|per[ -](request|call|op))' "$contract" \
    || die "perf-budget: declared but no cost LITERAL (a currency/number, not the prose word 'cost-effective') (INV-PERFBUDGET)."
  grep -qiE '\bslo\b|healthy[ -]?range|availability|error[ -]?rate' "$contract" \
    || die "perf-budget: declared but no SLO / healthy-range named (its literal range is verified in review) (INV-PERFBUDGET)."
  ! grep -qiE '\b(no|not|without|zero)\b[ -]+(slo|healthy|availability)' "$contract" \
    || die "perf-budget: the SLO/healthy-range is explicitly negated ('no SLO') — declare a real healthy range (INV-PERFBUDGET)."
  # ── v0.32.0 S22 — A LITERAL IS NOT A MEASUREMENT ────────────────────────────────────────────
  # Everything above proves a NUMBER WAS WRITTEN. It cannot tell a measured 200ms from an invented
  # one, and §17-7 recorded exactly that: three earlier perf claims in this repo were carried over
  # from a previous build's contract and never run. This contract's own perf line says so — "v1
  # stated 28.4s and a derived 48.4s ceiling; neither was ever run".
  #
  # THIS IS DELIBERATELY NOT A GREP FOR THE WORD "MEASURED". Requiring a word is the sin this build
  # is named after: it would pass any contract that types six letters. What is checked instead is
  # ARITHMETIC — the same move S18 makes. A real baseline leaves a RUN SERIES behind it (three or
  # more observations of one unit), and the figure the bound is derived from must RECONCILE with
  # that series. You cannot satisfy this by writing a word; you have to supply numbers that agree.
  #
  # GUARD-FIRST, measured before the rule was written: 31 build folders · 12 declare a perf-budget
  # header · 9 of those are an explicit N/A · so 3 carry a real budget, and only builds carrying the
  # v0.30 `.compass-format` stamp are in scope. Both stamped builds with a real budget reconcile
  # today (medians 25.2s and 26.18s); the unstamped one N/A-passes and says so.
  if [ ! -f "$dir/.compass-format" ]; then
    ok "perf-budget: latency + memory + cost named with numeric literals + SLO/healthy-range. The measurement behind those literals is NOT checked here — this build predates the v0.30 stamp, and 27 of this repo's 31 folders are in that state."
    return 0
  fi
  local _pbv
  _pbv="$(printf '%s' "$pb" | awk '''
    { line = line " " $0 }
    END {
      # QUOTED SPANS ARE EXAMPLES, NOT MEASUREMENTS. This gate’s own error text tells an author to
      # write a sample series, and quoting that sample then blocked the build. Both quote characters
      # are built with sprintf, because a literal apostrophe here would close the awk program itself —
      # which is exactly what the first attempt at this comment did.
      _sq = sprintf("%c", 39); _bt = sprintf("%c", 96)
      scan = line
      gsub(_sq "[^" _sq "]*" _sq, " ", scan)
      gsub(_bt "[^" _bt "]*" _bt, " ", scan)
      best_n = 0; s = scan
      # A RUN SERIES: three or more numbers separated by "/", sharing one unit.
      while (match(s, /[0-9]+(\.[0-9]+)?[ ]*\/[ ]*[0-9]+(\.[0-9]+)?[ ]*\/[ ]*[0-9]+(\.[0-9]+)?[ ]*[a-zA-Z\xc2\xb5]*/)) {
        seg = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        unit = seg; gsub(/[0-9.\/ ]/, "", unit)
        tmp = seg; gsub(/[a-zA-Z\xc2\xb5]/, "", tmp)
        n = split(tmp, parts, /\//)
        if (n < 3) continue
        for (i = 1; i <= n; i++) { gsub(/ /, "", parts[i]); v[i] = parts[i] + 0 }
        # A RUN SERIES IS THREE MEASUREMENTS OF THE SAME THING, so its values CLUSTER. Without that,
        # an independent reviewer showed the rule hard-stopping honest budgets: a date written the
        # ordinary way ("Measured 2026/08/21") parsed as a series with median 21, and so did
        # "Suite: 951 / 0 / 38.6s" and a quoted EXAMPLE series — the very one the gate error text
        # tells you to write. A gate that refuses correct work is the one that gets switched off.
        lo = v[1]; hi = v[1]
        for (i = 2; i <= n; i++) { if (v[i] < lo) lo = v[i]; if (v[i] > hi) hi = v[i] }
        if (lo <= 0) continue                       # a zero cannot be one of three runs of anything
        if (hi / lo > 3) continue                   # 2026/08/21 is a date; 951/0/38.6 is not a series
        if (unit == "") continue                    # and a series with no unit is not a measurement
        for (i = 1; i <= n; i++) for (j = i+1; j <= n; j++) if (v[j] < v[i]) { t = v[i]; v[i] = v[j]; v[j] = t }
        med = (n % 2) ? v[int(n/2)+1] : (v[n/2] + v[n/2+1]) / 2
        # EVERY series, not just the longest. Checking one meant a budget could carry a real
        # measurement beside an invented one and pass on the strength of the real one — which is
        # precisely the shape this rule exists to refuse, one level up.
        ns++; MED[ns] = med; UNIT[ns] = unit; CNT[ns] = n
        if (n > best_n) { best_n = n; best_med = med; best_unit = unit }
      }
      if (best_n == 0) { print "NOSERIES"; exit }
      # THE DERIVED FIGURE MUST BE STATED OUTSIDE THE SERIES. A first version searched the whole
      # line, and the median of an odd-length series IS one of its own members — so the rule matched
      # itself and passed a budget whose stated median was 99.9s against observations of 25.2s. The
      # series text is removed before looking for the figure it is supposed to support.
      rest = line
      s2 = line
      while (match(s2, /[0-9]+(\.[0-9]+)?[ ]*\/[ ]*[0-9]+(\.[0-9]+)?[ ]*\/[ ]*[0-9]+(\.[0-9]+)?[ ]*[a-zA-Z\xc2\xb5]*/)) {
        seg2 = substr(s2, RSTART, RLENGTH); s2 = substr(s2, RSTART + RLENGTH)
        i2 = index(rest, seg2)
        if (i2 > 0) rest = substr(rest, 1, i2 - 1) " \xc2\xa7 " substr(rest, i2 + length(seg2))
      }
      # THE UNIT IS REQUIRED, and the unit-less alternative is gone. It matched "25" inside the SLO
      # range "25-50s" and passed a budget claiming a median of 99.9s over observations of 25.2s.
      # A bare integer appears in almost any sentence; a figure carrying its unit is a claim.
      okc = 0
      for (k = 1; k <= ns; k++) {
        found = 0
        for (p = 3; p >= 0; p--) {
          want = sprintf("%." p "f", MED[k]); pat = want; gsub(/\./, "\\.", pat)
          if (rest ~ ("[^0-9.]" pat "[ ]*" UNIT[k] "([^a-zA-Z0-9]|$)")) { found = 1; lastwant = want; break }
        }
        # A parenthesised ternary inside a concatenation is not portable awk — it was a syntax
        # error on this machine, and the gate then refused two honest budgets with no message at all.
        if (found) {
          okc++
          if (SEEN == "") { SEEN = want UNIT[k] } else { SEEN = SEEN ", " want UNIT[k] }
        }
        else { printf "NORECONCILE %d %s%s\n", CNT[k], MED[k], UNIT[k]; exit }
      }
      # EVERY series, named. Reporting one of them picked whichever was checked last, and on this
      # this repo own contract that was the SUPERSEDED over-ceiling figure: the gate announced 59.1s
      # as the reconciled measurement when the current one is 38.6s. A gate that reports an
      # arbitrary one of several true numbers is the shape this whole build is about.
      printf "OK %d %s\n", okc, SEEN
    }''')"
  case "$_pbv" in
    NOSERIES)
      die "perf-budget: the budget states literals but no RUN SERIES behind them — three or more observations of one unit, e.g. '25.4 / 25.2 / 25.2s'. A number with no runs behind it is a number somebody typed; §17-7 records three such figures in this repo that were carried over from an earlier contract and never run. HARD STOP (INV-PERFBUDGET, S22). This is not satisfied by writing the word MEASURED." ;;
    NORECONCILE*)
      die "perf-budget: a run series is present but NOTHING IN THE BUDGET MATCHES IT — $_pbv. The figure a bound is derived from must reconcile with the observations behind it, or the series is decoration. HARD STOP (INV-PERFBUDGET, S22)." ;;
  esac
  _pbn="$(printf '%s' "$_pbv" | awk '{print $2}')"
  _pbl="$(printf '%s' "$_pbv" | awk '{ $1=""; $2=""; sub(/^  */, ""); print }')"
  ok "perf-budget: latency + memory + cost named with numeric literals + SLO/healthy-range, and EVERY run series behind it reconciles — ${_pbn} series: ${_pbl}."
}

cmd_expand_contract_gate() { # <slug|build-dir> — a declared migration is phased expand/contract with an old-code probe recipe (item 2, INV-EXPAND-CONTRACT)
  local a="${1:-}"; [ -n "$a" ] || die "usage: compass.sh expand-contract-gate <slug|build-dir>"
  local dir contract; dir="$(_cv_dir "$a")"; contract="$dir/contract.md"
  [ -f "$contract" ] || { ok "expand-contract: N/A — no contract.md (legacy)."; return 0; }
  local st_vals st
  st_vals="$(sed -nE 's/^[-*[:space:]]*schema-touching:\**[[:space:]]*([A-Za-z]+).*/\1/p' "$contract" | tr 'A-Z' 'a-z')"
  [ -n "$st_vals" ] || { ok "expand-contract: N/A — schema-touching absent (legacy)."; return 0; }
  if printf '%s\n' "$st_vals" | grep -vqx no; then st=yes; else st=no; fi
  [ "$st" = "yes" ] || { ok "expand-contract: N/A — schema-touching:$st."; return 0; }
  # schema-touching: yes → require the discipline RECORDS (a recipe, never a live migration — honest boundary)
  grep -qE '^[-*[:space:]]*migration-phase:\**[[:space:]]*(expand|contract)' "$contract" \
    || die "expand-contract: schema-touching:yes but no 'migration-phase: expand|contract' classification. HARD STOP (INV-EXPAND-CONTRACT)."
  # RB-R1-C3: an EMPTY old-code-probe, or a dry-run that NEGATES prod-shaped ("NOT prod-shaped",
  # "tiny fixture"), must NOT pass — the presence-only key check + substring match were the holes.
  local ocp; ocp="$(sed -nE 's/^[-*[:space:]]*old-code-probe:\**[[:space:]]*(.+)/\1/p' "$contract" | head -1)"
  _attest_real "$ocp" \
    || die "expand-contract: 'old-code-probe:' absent or empty/placeholder (need a real old-code-on-new-schema recipe). HARD STOP (INV-EXPAND-CONTRACT)."
  local dry; dry="$(sed -nE 's/^[-*[:space:]]*dry-run:\**[[:space:]]*(.+)/\1/p' "$contract" | head -1)"
  # require prod-shaped; reject a diminutive OR a negation SCOPED to prod-shaped — but ALLOW a clean
  # "no diffs"/"without errors" (those describe a passing run, not a fake dry-run). RB-R2-M2
  { printf '%s' "$dry" | grep -qi 'prod-shaped' \
      && ! printf '%s' "$dry" | grep -qiE '\b(tiny|toy|small|pending|todo|tbd)\b' \
      && ! printf '%s' "$dry" | grep -qiE '\b(not|no|non|never|without|isn.?t|skip(ped|s)?)\b[^.]{0,30}prod-shaped' \
      && ! printf '%s' "$dry" | grep -qiE '\b(will|going|planned|later)\b[^.]{0,30}prod-shaped' \
      && ! printf '%s' "$dry" | grep -qiE 'prod-shaped[^.]{0,20}\b(later|planned|tbd|todo|pending)\b'; } \
    || die "expand-contract: 'dry-run:' is not a real prod-shaped record (absent, diminutive, future/skipped, or a 'did not … prod-shaped' negation). A clean-result 'no diffs/no errors' AFTER prod-shaped is fine. HARD STOP (INV-EXPAND-CONTRACT)."
  # a `contract` op (DROP/RENAME/type-narrow) MUST be deferred to a separate post-bake build
  if grep -qE '^[-*[:space:]]*migration-phase:\**[[:space:]]*contract' "$contract"; then
    grep -qiE '^[-*[:space:]]*contract-op:\**[[:space:]]*deferred' "$contract" \
      || die "expand-contract: migration-phase:contract (DROP/RENAME/type-narrow) but not 'contract-op: deferred' to a separate post-bake build. HARD STOP (INV-EXPAND-CONTRACT)."
  fi
  ok "expand-contract: phasing + old-code probe + prod-shaped dry-run recorded."
}

cmd_backfill_recon_gate() { # <slug|build-dir> — a declared backfill ties rows to source by count+checksum (item 3, INV-BACKFILL-RECON)
  local a="${1:-}"; [ -n "$a" ] || die "usage: compass.sh backfill-recon-gate <slug|build-dir>"
  local dir contract; dir="$(_cv_dir "$a")"; contract="$dir/contract.md"
  [ -f "$contract" ] || { ok "backfill-recon: N/A — no contract.md (legacy)."; return 0; }
  local bf df
  bf="$(sed -nE 's/^[-*[:space:]]*backfill:\**[[:space:]]*([A-Za-z]+).*/\1/p' "$contract" | tr 'A-Z' 'a-z' | grep -xc yes || true)"
  df="$(sed -nE 's/^[-*[:space:]]*destructive-backfill:\**[[:space:]]*([A-Za-z]+).*/\1/p' "$contract" | tr 'A-Z' 'a-z' | grep -xc yes || true)"
  if [ "${bf:-0}" = "0" ] && [ "${df:-0}" = "0" ]; then
    ok "backfill-recon: N/A — no backfill declared (backfill/destructive-backfill not yes)."; return 0
  fi
  local rec; rec="$(sed -nE 's/^[-*[:space:]]*backfill-recon:\**[[:space:]]*(.+)/\1/p' "$contract" | head -1)"
  # RB-R1-M1 / RB-R2-M3: word-boundary so 'account'↛count and 'summary'↛sum, but accept the plural 'counts'/'checksums'.
  { [ -n "$rec" ] && printf '%s' "$rec" | grep -qiwE 'counts?' && printf '%s' "$rec" | grep -qiE 'checksums?|\bsums?\b'; } \
    || die "backfill-recon: a backfill is declared but no 'backfill-recon: count+checksum tie-to-source' record ('account'/'summary' do not count — word-boundary). HARD STOP (INV-BACKFILL-RECON)."
  ok "backfill-recon: count+checksum tie-to-source recorded."
}

cmd_rollback_fwdcompat_gate() { # <slug|build-dir> — a schema/data change RECORDS old-code-reads-new-writes safety (item 4, INV-ROLLBACK-FWDCOMPAT)
  local a="${1:-}"; [ -n "$a" ] || die "usage: compass.sh rollback-fwdcompat-gate <slug|build-dir>"
  local dir contract; dir="$(_cv_dir "$a")"; contract="$dir/contract.md"
  [ -f "$contract" ] || { ok "rollback-fwdcompat: N/A — no contract.md (legacy)."; return 0; }
  local st bf df
  st="$(sed -nE 's/^[-*[:space:]]*schema-touching:\**[[:space:]]*([A-Za-z]+).*/\1/p' "$contract" | tr 'A-Z' 'a-z' | grep -vx no | head -1 || true)"
  bf="$(sed -nE 's/^[-*[:space:]]*backfill:\**[[:space:]]*([A-Za-z]+).*/\1/p' "$contract" | tr 'A-Z' 'a-z' | grep -x yes | head -1 || true)"
  df="$(sed -nE 's/^[-*[:space:]]*destructive-backfill:\**[[:space:]]*([A-Za-z]+).*/\1/p' "$contract" | tr 'A-Z' 'a-z' | grep -x yes | head -1 || true)"
  if [ -z "$st" ] && [ -z "$bf" ] && [ -z "$df" ]; then
    ok "rollback-fwdcompat: N/A — no schema/data change declared."; return 0
  fi
  grep -qiE '^[-*[:space:]]*rollback data-safety:.*old-code reads new-version writes.*OK' "$contract" \
    || die "rollback-fwdcompat: a schema/data change is declared but no recorded 'rollback data-safety: old-code reads new-version writes → OK' line. HARD STOP (INV-ROLLBACK-FWDCOMPAT); review-build re-challenges this recorded line — it is never independent proof."
  ok "rollback-fwdcompat: forward-compat rollback record present."
}

cmd_gold_numbers_gate() { # <slug|build-dir> — every number a page states is accounted for (v0.31)
  local a="${1:-}"; [ -n "$a" ] || die "usage: compass.sh gold-numbers-gate <slug|build-dir>"
  local root; root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  local gold="$root/plugins/compass/scripts/proven-numbers.sh"
  # Guard-first: absent script = this tree predates the gold. N/A-pass, recorded, never silent.
  [ -f "$gold" ] || { ok "gold-numbers-gate: N/A — no proven-numbers.sh in this tree."; return 0; }
  # ARM ON PRESENCE, never on absence. v0.28's mode-gate armed on a missing header and refused 25 of
  # 26 existing builds; this gate armed on nothing at all and failed a LEGACY contract for a
  # repo-wide reason that had nothing to do with the build being gated. A build predating the
  # artefact-data format N/A-passes byte-identically.
  local dir_res; dir_res="$(_cv_dir "$a")"
  [ -f "$dir_res/.compass-format" ] || { ok "gold-numbers-gate: N/A — $(basename "$dir_res") predates the artefact-data format."; return 0; }
  # THE INSTALLER GUARD. The gold's manifest pins the 28 build dirs of THIS repo; an installer has
  # none of them. Without this, a brand-new user's very first stamped build hit this seam, the gold
  # reported "compared 0 dirs, expected 28", and the gate failed — SILENTLY. That is v0.28's
  # mode-gate all over again: a check that arms on someone else's data and refuses every real build.
  # Found by exporting the staged tree and running it as an installer would, not by reasoning.
  local man="$root/plugins/compass/scripts/gold-manifest.txt" present=0 first=""
  if [ -f "$man" ]; then
    while read -r _slug _rest || [ -n "${_slug:-}" ]; do
      case "${_slug:-#}" in \#*|"") continue ;; esac
      [ -z "$first" ] && first="$_slug"
      [ -f "$root/.claude/builds/$_slug/contract.md" ] && { present=1; break; }
    done < "$man"
  fi
  if [ "$present" -eq 0 ]; then
    ok "gold-numbers-gate: N/A — this tree carries none of the gold's pinned build dirs (it is an install, not the Compass repo). The gold is a repo-specific measurement; your build still gates on everything else."
    return 0
  fi
  # R9-C1: this ran the gold over the whole 28-dir corpus and NEVER LOOKED AT THE BUILD IT WAS
  # HANDED. Gating `artefacts-from-data-v0-31` — which is deliberately outside the manifest —
  # audited 28 other dirs and reported PASS while that build's own pages declared 999 steps over a
  # 16-checkbox plan. Two skills print the promise "cross-checks every declared field against its
  # source file and fails on a disagreement"; it was false on both halves.
  #
  # The dir being gated is audited FIRST, on its own terms, whether or not it is in the manifest.
  local fail=0
  if [ -f "$dir_res/plan.md" ]; then
    local blk st sd bt bd
    blk="$(awk '/^ {0,3}`{3,}compass-artefact-data[ \t]*\r?$/{f=1;next} f&&/^ {0,3}`{3,}[ \t]*\r?$/{exit} f{print}' "$dir_res"/*.md 2>/dev/null)"
    if [ -n "$blk" ]; then
      st="$(awk '/^[[:space:]]*```/ { f = !f; next } !f && /^[[:space:]]*- \[[ xX~]\]/ { n++ } END { print n+0 }' "$dir_res/plan.md")"
      sd="$(awk '/^[[:space:]]*```/ { f = !f; next } !f && /^[[:space:]]*- \[[xX]\]/ { n++ } END { print n+0 }' "$dir_res/plan.md")"
      bt="$(printf '%s' "$blk" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const b=JSON.parse(s);console.log(b["steps.total"]??"")}catch(e){console.log("")}})')"
      bd="$(printf '%s' "$blk" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const b=JSON.parse(s);console.log(b["steps.done"]??"")}catch(e){console.log("")}})')"
      [ -n "$bt" ] && [ "$bt" != "$st" ] && { echo "COMPASS-GATE: gold-numbers-gate: $(basename "$dir_res") declares steps.total=$bt but plan.md holds $st checkboxes."; fail=1; }
      [ -n "$bd" ] && [ "$bd" != "$sd" ] && { echo "COMPASS-GATE: gold-numbers-gate: $(basename "$dir_res") declares steps.done=$bd but plan.md has $sd ticked."; fail=1; }
    fi
  fi
  [ "$fail" -eq 0 ] || die "gold-numbers-gate: the build's own declared data contradicts its files."

  # Round 3 C2 / item 3: the two checks above are the ONLY thing this gate ever did to the build it
  # was handed, and they cover two fields of eleven. Nothing scored the build's own PAGES, so
  # `artefacts-from-data-v0-31` — the build shipping this very gate — carried the new-format stamp
  # with no data block, scored `noblock=5`, and the gate reported PASS because the 28 dirs it DID
  # audit were clean. A gate that measures everything except its subject is decoration.
  #
  # `--only` runs the full auditor over this dir's own pages, on its own terms: every counter, plus
  # the `invariants.total` cross-check that also never ran here. Corpus floors and the pinned-baseline
  # checksum do not apply to a live build, and the flag skips exactly those.
  local sout srrc
  if sout="$(bash "$gold" "$root" --only "$(basename "$dir_res")" 2>&1)"; then srrc=0; else srrc=$?; fi
  if [ "$srrc" -ne 0 ]; then
    printf '%s\n' "$sout" | grep -E '^gold: ' >&2 || true
    die "gold-numbers-gate: $(basename "$dir_res") does not pass the rule its own stamp selects (exit $srrc)."
  fi

  # Then the corpus-wide measurement, when this tree is the Compass repo.
  local out rc
  # `out="$(cmd)" || true; rc=$?` reads the exit of `true` — always 0. I introduced that while
  # fixing the set -e abort and it made the gate report PASS over a corpus with 13 unmarked numbers.
  if out="$(bash "$gold" "$root" 2>&1)"; then rc=0; else rc=$?; fi
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$out" | grep -E '^gold: ' >&2 || true
    die "gold-numbers-gate: the gold is not at target (exit $rc). A number on a page is unaccounted for."
  fi
  ok "gold-numbers-gate: $(basename "$dir_res") clean; corpus $(printf '%s\n' "$out" | grep '^dirs=' | tail -1)"
  return 0
}

cmd_green_ci_gate() { # <slug|build-dir> — a CI-declaring repo RECORDS a green-CI merge proof (item 6, INV-GREEN-CI)
  local a="${1:-}"; [ -n "$a" ] || die "usage: compass.sh green-ci-gate <slug|build-dir>"
  local dir contract; dir="$(_cv_dir "$a")"; contract="$dir/contract.md"
  [ -f "$contract" ] || { ok "green-ci: N/A — no contract.md (legacy)."; return 0; }
  # trigger = the repo declares CI (contract header `ci: yes`); absent/no → N/A-pass (this repo's own path)
  local ci_vals ci
  ci_vals="$(sed -nE 's/^[-*[:space:]]*ci:\**[[:space:]]*([A-Za-z]+).*/\1/p' "$contract" | tr 'A-Z' 'a-z')"
  ci=no; printf '%s\n' "$ci_vals" | grep -qx yes && ci=yes
  [ "$ci" = "yes" ] || { ok "green-ci: N/A — no CI declared (ci:${ci_vals:-absent})."; return 0; }
  # CI declared → require a RECORDED green-CI merge proof (presence-of-record, NOT a live gh/API query).
  # RB-R1-m3: reject a NEGATED value ("build did not pass", "not green", "failed/red").
  local gci; gci="$(sed -nE 's/^[-*[:space:]]*green-ci:\**[[:space:]]*(.+)/\1/p' "$contract" | head -1)"
  # PRESENCE gate (honor-level, re-challenged by review-build): require a positive-green token AND reject
  # only an explicit NEGATED-green phrase ('not green' / 'did not pass' / 'isn't green'). We do NOT try to
  # classify free-text failure prose (that whack-a-mole caused false-rejects of 'zero failures'/'no
  # regressions'/'succeeded'); a lying-but-green-worded record is caught by the review-build re-challenge. RB-R2/R3
  { printf '%s' "$gci" | grep -qiE '(green|pass|success|succeed)' \
      && ! printf '%s' "$gci" | grep -qiE '\b(not|no|never|isn.?t|did[ -]?not)\b[ -]+[a-z]{0,8}[ -]?(green|pass|passed|success)'; } \
    || die "green-ci: repo declares CI (ci: yes) but the recorded 'green-ci:' line is absent or an explicit NOT-green phrase. HARD STOP (INV-GREEN-CI); review-build re-challenges this recorded line — it is never independent proof."
  ok "green-ci: recorded green-CI merge proof present."
}

cmd_pii_gate() { # <slug|build-dir> — a PII/financial build's plan states the compliance/PII gate (item 8, INV-PII-GATE)
  local a="${1:-}"; [ -n "$a" ] || die "usage: compass.sh pii-gate <slug|build-dir>"
  local dir contract; dir="$(_cv_dir "$a")"; contract="$dir/contract.md"
  [ -f "$contract" ] || { ok "pii: N/A — no contract.md (legacy)."; return 0; }
  # trigger = machine-readable header `pii: yes` (symmetric with schema-touching/backfill); absent/no → N/A-pass
  local pii_vals pii
  pii_vals="$(sed -nE 's/^[-*[:space:]]*pii:\**[[:space:]]*([A-Za-z]+).*/\1/p' "$contract" | tr 'A-Z' 'a-z')"
  pii=no; printf '%s\n' "$pii_vals" | grep -qx yes && pii=yes
  [ "$pii" = "yes" ] || { ok "pii: N/A — no PII/financial surface (pii:${pii_vals:-absent})."; return 0; }
  # pii: yes → require the plan (or contract) compliance/PII line asserting no raw PII/secret in logs
  { grep -qiE '^[-*[:space:]]*compliance/PII:.*no raw PII/secret in logs' "$contract" 2>/dev/null \
      || { [ -f "$dir/plan.md" ] && grep -qiE '^[-*[:space:]]*compliance/PII:.*no raw PII/secret in logs' "$dir/plan.md" 2>/dev/null; }; } \
    || die "pii: pii:yes but no 'compliance/PII: logged(no raw PII/secret in logs)·retention·residency·no regulated field crosses out-of-scope view' plan line. HARD STOP (INV-PII-GATE)."
  ok "pii: compliance/PII plan line present."
}

cmd_ship_prodsafety_receipt_match() { # <build-dir> — the ship receipt MUST record both prod-safety invocations (F-RESTORE/PARITY)
  local dir="${1:-}"; [ -n "$dir" ] || die "usage: compass.sh ship-prodsafety-receipt-match <build-dir>"
  local f="$dir/receipts.md"; [ -f "$f" ] || die "ship-prodsafety-receipt-match: no receipts.md in $dir"
  local blk; blk="$(last_block "$f" ship)"
  [ -n "$blk" ] || die "ship-prodsafety-receipt-match: no ship receipt to check."
  printf '%s' "$blk" | grep -qE 'restore-point: exit' || die "ship-prodsafety-receipt-match: ship receipt is MISSING the 'restore-point: exit N' line — the pre-deploy HARD STOP was skipped (never allowed)."
  printf '%s' "$blk" | grep -qE 'config-parity: exit'  || die "ship-prodsafety-receipt-match: ship receipt is MISSING the 'config-parity: exit N' line — the pre-deploy HARD STOP was skipped (never allowed)."
  # v0.21 (RB-R1-M2): the rollback-fwdcompat Step-0.6 record is enforced the same way — a schema/data
  # build must not reach SHIPPED with the forward-compat check never invoked (the honor-level-fake-pass target).
  printf '%s' "$blk" | grep -qE 'rollback-fwdcompat: exit' || die "ship-prodsafety-receipt-match: ship receipt is MISSING the 'rollback-fwdcompat: exit N' line — the Step 0.6 forward-compat HARD STOP was skipped (never allowed; INV-ROLLBACK-FWDCOMPAT)."
  ok "ship-prodsafety-receipt-match: restore-point + config-parity + rollback-fwdcompat all invoked and recorded."
}

# ── v0.16.0 survive-the-cutover: the production-cutover safety net ─────────────
# Five gates Compass hands to the MANAGED build's prod, in the restore-point/config-parity shape:
# fail-CLOSED, line-anchored, UNION-across-lines-take-WORST, _attest_real on any attestation token,
# byte-inert (N/A-pass) for any contract that declares no cutover config. See the survive-cutover
# contract INV-CANARY/BAKE/BURNRATE/WATCHER/ABORT/NA-EXPLICIT/BC.

# INV-ABORT — the mid-flight abort sentinel. `abort` sets it; the build step-loop checks it at the top
# of each step AND before every mutating op (build/SKILL.md) → a set abort halts before the next
# mutation, bounding blast radius. abort-check exits 3 (distinct) when active so callers can branch.
_abort_file() { printf '%s/.abort' "$1"; }   # <build-dir>
cmd_abort() { # <slug|build-dir> — SET the abort sentinel (idempotent)
  local a="${1:-}"; [ -n "$a" ] || die "usage: compass.sh abort <slug|build-dir>"
  local dir; dir="$(_cv_dir "$a")"; [ -d "$dir" ] || die "abort: no build dir for '$a'."
  : > "$(_abort_file "$dir")"
  ok "abort: sentinel SET for $(basename "$dir") — the build halts before its next step / mutating op. Clear with: compass.sh abort-clear $(basename "$dir")."
}
cmd_abort_check() { # <slug|build-dir> — 0 = clear, 3 = aborting
  local a="${1:-}"; [ -n "$a" ] || die "usage: compass.sh abort-check <slug|build-dir>"
  local dir; dir="$(_cv_dir "$a")"
  if [ -e "$(_abort_file "$dir")" ]; then echo "ABORT: ACTIVE"; return 3; fi   # -e: a dir sentinel also counts (fail-safe)
  echo "ABORT: clear"; return 0
}
cmd_abort_clear() { # <slug|build-dir> — CLEAR the sentinel (idempotent)
  local a="${1:-}"; [ -n "$a" ] || die "usage: compass.sh abort-clear <slug|build-dir>"
  local dir; dir="$(_cv_dir "$a")"; rm -f "$(_abort_file "$dir")"
  ok "abort-clear: sentinel cleared for $(basename "$dir")."
}

# INV-BAKE — a required soak under load before the terminal SHIPPED write. The bound is a DECLARED
# INPUT (bake-bound:), NEVER inferred: NUMERIC (err/lat/mem ceilings) or LIBRARY (re-run the suites).
# FAIL-CLOSED on every ambiguity (R2-C1): a signal with no ceiling OR no reading is NEVER in-bound
# (esp. memory); multi-line bake-observed is UNIONed to the WORST reading (R2-M4).
_dur_secs() { # <5m|600|2h|30s> → integer seconds; empty on garbage (set -e/pipefail safe → always returns 0)
  local d="${1:-}" n
  case "$d" in
    *h) n="${d%h}"; if _is_num "$n"; then echo $((n*3600)); fi ;;
    *m) n="${d%m}"; if _is_num "$n"; then echo $((n*60));   fi ;;
    *s) n="${d%s}"; if _is_num "$n"; then echo "$n";        fi ;;
    *)               if _is_num "$d"; then echo "$d";        fi ;;
  esac
  return 0
}
_nofence() { awk '/^[[:space:]]*(```|~~~)/{f=!f; next} !f' "$1"; }   # print only lines OUTSIDE ``` or ~~~ fences (RB-M6 + RB2-M1)
_thdr_lines() { # <dir> <key> → every anchored value of <key>, tab-tolerant + fence-skipped, from contract.md + receipts.md
  local dir="$1" key="$2" f
  for f in "$dir/contract.md" "$dir/receipts.md"; do
    if [ -f "$f" ]; then _nofence "$f" | sed -nE "s/^[-*[:space:]]*$key:\\**[[:space:]]*(.+)/\\1/p"; fi
  done 2>/dev/null
  return 0
}
_bake_tok() { # <token> <min|max> ; stdin lines → the min/max non-negative-int value of token=…, or empty
  awk -v t="$1" -v mode="$2" '
    { for(i=1;i<=NF;i++){ if($i ~ ("^" t "=")){ v=substr($i,length(t)+2)
        if(v ~ /^[0-9]+$/){ if(!seen){best=v+0;seen=1}
          else if(mode=="max"&&v+0>best)best=v+0
          else if(mode=="min"&&v+0<best)best=v+0 } } } }
    END{ if(seen)print best }'
}
cmd_bake_gate() { # <slug|build-dir> — INV-BAKE
  local a="${1:-}"; [ -n "$a" ] || die "usage: compass.sh bake-gate <slug|build-dir>"
  local dir; dir="$(_cv_dir "$a")"; local c="$dir/contract.md"
  [ -f "$c" ] || die "bake-gate: no contract.md in $dir"
  # bake-window: MAX seconds across all declared lines (tab-tolerant; stale-stub safe). N/A if none.
  local wl; wl="$(_thdr_lines "$dir" bake-window)"
  [ -n "$wl" ] || { ok "bake-gate: no bake-window declared — N/A-pass (byte-inert). BAKE: N/A"; return 0; }
  local winsec=0 w s
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    s="$(_dur_secs "$w")"
    if _is_num "$s" && [ "$s" -gt "$winsec" ]; then winsec="$s"; fi
  done <<<"$wl"
  { [ "$winsec" -ge 1 ] && [ "$winsec" -le 31536000 ]; } || die "bake-gate: bake-window unparseable/out-of-range (from '$wl' → ${winsec}s; need 1s..1y — guards overflow + a zero soak). BAKE: NO-BOUND (fail-closed)"
  # bake-bound: UNION all anchored lines (RB-C3 — no first-match stale stub).
  local bound; bound="$(_thdr_lines "$dir" bake-bound)"
  [ -n "$bound" ] || die "bake-gate: bake-window declared but NO bake-bound — an undefined bound is NEVER in-bound. BAKE: NO-BOUND (fail-closed)"
  # observed soak: MIN dur across all (fence-skipped) lines — the least-elapsed reading wins.
  local dur; dur="$(printf '%s\n' "$(_thdr_lines "$dir" bake-observed)" | _bake_tok dur min)"
  [ -n "$dur" ] || die "bake-gate: no numeric bake-observed 'dur=' reading — cannot prove the soak elapsed. BAKE: NO-READING (dur)"
  # MODE by STRUCTURE, not free-text substring (RB-C1): any numeric err=/lat=/mem= token → NUMERIC (enforce
  # ALL three); otherwise a library keyword → LIBRARY (re-run the channel); neither → fail-closed.
  if printf '%s\n' "$bound" | grep -qE '(err|lat|mem)=[0-9]'; then
    local sig ceil rdg
    for sig in err lat mem; do
      ceil="$(printf '%s\n' "$bound" | _bake_tok "$sig" min)"   # UNION → TIGHTEST (min) ceiling
      [ -n "$ceil" ] || die "bake-gate: NUMERIC bound missing a numeric '${sig}=' ceiling — an undefined signal is never in-bound (esp. memory). BAKE: NO-BOUND (fail-closed)"
    done
    [ "$dur" -ge "$winsec" ] || die "bake-gate: soak dur=${dur}s < window ${winsec}s. BAKE: NOT-ELAPSED"
    for sig in err lat mem; do
      ceil="$(printf '%s\n' "$bound" | _bake_tok "$sig" min)"
      rdg="$(printf '%s\n' "$(_thdr_lines "$dir" bake-observed)" | _bake_tok "$sig" max)"   # UNION → WORST (max) reading
      [ -n "$rdg" ] || die "bake-gate: bound has a '${sig}=' ceiling but NO '${sig}=' reading — an absent signal is NEVER in-bound. BAKE: NO-READING (${sig})"
      [ "$rdg" -le "$ceil" ] || die "bake-gate: signal ${sig}=${rdg} exceeds tightest ceiling ${ceil}. BAKE: OUT-OF-BOUND (${sig})"
    done
    ok "bake-gate: NUMERIC bound — soak ${dur}s ≥ ${winsec}s; err/lat/mem each have a ceiling+reading and are within bound. BAKE: ${dur}s IN-BOUND"; return 0
  fi
  if printf '%s\n' "$bound" | grep -qiE 'suite|observation-channel|recon'; then   # LIBRARY bound — re-run the channel (R2-M3)
    [ "$dur" -ge "$winsec" ] || die "bake-gate: soak dur=${dur}s < window ${winsec}s. BAKE: NOT-ELAPSED"
    local scr obscmd; scr="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    obscmd="${COMPASS_BAKE_OBSCMD:-bash \"$scr/compass.recon.sh\"}"
    if eval "$obscmd" >/dev/null 2>&1; then
      ok "bake-gate: LIBRARY bound — soak ${dur}s ≥ ${winsec}s AND observation-channel green (no floor regression). BAKE: ${dur}s IN-BOUND"; return 0
    else
      die "bake-gate: LIBRARY bound — observation-channel NOT green (suites/recon failed or regressed). BAKE: OUT-OF-BOUND"
    fi
  fi
  die "bake-gate: bake-bound names neither numeric ceilings (err=/lat=/mem=) nor a library channel (suites/recon) — cannot assert. BAKE: NO-BOUND (fail-closed)"
}

# INV-CANARY + INV-BURNRATE — promote a canary slice only on INDEPENDENT green; a burn-rate breach must
# auto-fire the rehearsed rollback. Only literal `none` routes to SUBSTITUTED-BAKE, which REQUIRES a
# bake-window (R2-C2); green may never be self-computed — gold-cmd≠slice-cmd + gold not the build's own
# artifacts (R2-M2). Reads the canary block from contract.md + receipts.md (fixtures put it in contract.md).
_hdr1() { sed -nE "s/^[-*[:space:]]*$1:\**[[:space:]]*(.+)/\1/p" | head -1; }   # first anchored value of <key> from stdin
_normcmd() { printf '%s' "${1:-}" | tr -d '*' | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//'; }   # strip *, collapse+trim ws (RB-C2)
# _attest_cmd: attest a COMMAND value, stripping wrapping punctuation first so a parenthesized placeholder
# like `(todo)` / `[tbd]` cannot dodge _attest_real's bare-token list (RB-M1 miss).
_attest_cmd() { local v; v="$(printf '%s' "${1:-}" | sed -E 's/^[^A-Za-z0-9]+//; s/[^A-Za-z0-9]+$//')"; _attest_real "$v"; }
_last_out() { printf '%s' "${1:-}" | sed -E 's/.*(→|->)[[:space:]]*//'; }   # text AFTER the last arrow (the real outcome; RB4)
_is_neg()   { printf '%s' "${1:-}" | grep -qiE 'fail|not[[:space:]]|n[o0]t-|error|drift|deny|reject|✗'; }   # a recorded-failure word
cmd_canary_analysis() { # <slug|build-dir> — INV-CANARY + INV-BURNRATE
  local a="${1:-}"; [ -n "$a" ] || die "usage: compass.sh canary-analysis <slug|build-dir>"
  local dir; dir="$(_cv_dir "$a")"; local c="$dir/contract.md"
  [ -f "$c" ] || die "canary-analysis: no contract.md in $dir"
  local cv; cv="$(hdr_get "$c" canary || true)"
  [ -n "$cv" ] || { ok "canary-analysis: no canary declared — N/A-pass (byte-inert). CANARY: N/A"; return 0; }
  local tok; tok="$(printf '%s' "$cv" | sed -nE 's/^[^A-Za-z]*([A-Za-z]+).*/\1/p' | tr 'A-Z' 'a-z')"
  if [ "$tok" = "none" ]; then
    local win; win="$(hdr_get "$c" bake-window || true)"
    [ -n "$win" ] || die "canary-analysis: canary:none (no traffic split) but NO bake-window — a no-traffic-split cutover MUST bake. CANARY: SUBSTITUTED-BAKE-NO-WINDOW (fail-closed)"
    ok "canary-analysis: no traffic split → SUBSTITUTED-BAKE (bake-window ${win} declared; ship asserts bake-gate IN-BOUND). CANARY: SUBSTITUTED-BAKE"; return 0
  fi
  # a real segment → require the FULL canary block (contract.md + receipts.md, fence-skipped). Greps use a
  # HERESTRING (no pipe → no SIGPIPE×pipefail false-negative on a large blob — RB-M3).
  local blob; blob="$( { _nofence "$c"; [ -f "$dir/receipts.md" ] && _nofence "$dir/receipts.md"; } 2>/dev/null; true )"
  # TAKE-WORST across lines, LAST-arrow per line (RB4-M1): EVERY canary-reconcile line's real outcome must be
  # PASS and EVERY canary-route-smoke line's must be 200/loaded — one recorded failure (a failing route decoy,
  # a multi-arrow `→ PASS … → 500`, a negation word) blocks. A truly adversarial prose recording that begins
  # with PASS/200 and carries no failure word is the disclosed best-effort residual (these are operator-recorded
  # receipt lines — the structural teeth are gold≠slice, fail-closed-on-absence, breach⇒rollback).
  local rl sl line out any
  rl="$(grep -iE '^[-*[:space:]]*canary-reconcile:' <<<"$blob" || true)"
  [ -n "$rl" ] || die "canary-analysis: canary segment '$cv' but no 'canary-reconcile: … → PASS' line. CANARY: NO-RECONCILE (fail-closed)"
  any=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue; any=1; out="$(_last_out "$line")"
    { printf '%s' "$out" | grep -qE '^PASS(ED)?([^A-Za-z]|$)'; } && ! _is_neg "$out" \
      || die "canary-analysis: a canary-reconcile outcome (after its last arrow) is not a clean PASS: '$out'. CANARY: RECONCILE-FAILED (fail-closed)"
  done <<<"$rl"
  [ "$any" = 1 ] || die "canary-analysis: no non-empty canary-reconcile line. CANARY: NO-RECONCILE (fail-closed)"
  sl="$(grep -iE '^[-*[:space:]]*canary-route-smoke:' <<<"$blob" || true)"
  [ -n "$sl" ] || die "canary-analysis: no 'canary-route-smoke: <route> → 200' line. CANARY: NO-ROUTE-SMOKE (fail-closed)"
  any=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue; any=1; out="$(_last_out "$line")"
    { printf '%s' "$out" | grep -qiE '^(200([^0-9]|$)|loaded([^a-z]|$))'; } && ! _is_neg "$out" \
      || die "canary-analysis: a canary-route-smoke outcome (after its last arrow) is not a clean 200/loaded: '$out'. CANARY: ROUTE-SMOKE-FAILED (fail-closed)"
  done <<<"$sl"
  [ "$any" = 1 ] || die "canary-analysis: no non-empty canary-route-smoke line. CANARY: NO-ROUTE-SMOKE (fail-closed)"
  local goldc slicec
  goldc="$(_hdr1 canary-gold-cmd <<<"$blob")"
  slicec="$(_hdr1 canary-slice-cmd <<<"$blob")"
  { _attest_real "$goldc" && _attest_real "$slicec"; } || die "canary-analysis: canary-gold-cmd / canary-slice-cmd missing or placeholder — green provenance unproven. CANARY: NO-PROVENANCE (fail-closed)"
  # NORMALIZE before comparing (RB-C2): strip `*`, collapse internal whitespace, trim — so a trailing space
  # or a **bold** wrapper cannot disguise a self-computed green as independent.
  [ "$(_normcmd "$goldc")" != "$(_normcmd "$slicec")" ] || die "canary-analysis: canary-gold-cmd ≡ canary-slice-cmd (after normalizing) — green is SELF-COMPUTED (the canary reconciles against itself). CANARY: SELF-COMPUTED (fail-closed)"
  case "$(printf '%s' "$goldc" | tr 'A-Z' 'a-z')" in   # lowercase — a case-insensitive FS resolves CONTRACT.MD (RB2-M2)
    *contract.md*|*receipts.md*|*.claude/builds*) die "canary-analysis: canary-gold-cmd reads the build's OWN artifacts — the gold must be independent/external. CANARY: GOLD-IN-BUILDDIR (fail-closed)" ;;
  esac
  # INV-BURNRATE: a recorded burn-rate BREACH must have auto-fired the rehearsed rollback, and never promotes.
  # Match anywhere (even a commented/blockquoted breach must trip — RB-m8). Herestring, not a pipe (RB-M3).
  if grep -qiE 'burn-rate.*BREACH' <<<"$blob"; then
    grep -qE '^[-*[:space:]]*rollback-fired:' <<<"$blob" \
      || die "canary-analysis: a burn-rate BREACH is recorded but NO 'rollback-fired:' line — a breach MUST auto-fire the rehearsed rollback. CANARY: BREACH-NO-ROLLBACK (fail-closed)"
    die "canary-analysis: burn-rate BREACH → rehearsed rollback fired; promotion REFUSED. CANARY: BREACH (rolled back — not a ship)"
  fi
  ok "canary-analysis: canary GREEN — reconcile PASS + route-smoke 200 + INDEPENDENT gold (gold-cmd≠slice-cmd, external). Promote. CANARY: PASS"
}

# INV-WATCHER — an opted-in cutover cannot reach SHIPPED without a NAMED watcher (real name via
# _attest_real, R2-M5) OR, in --auto, a PROVEN-armed rollback (`rollback-rehearsed: … → exit 0`, not a
# bare `armed`, R2-M1). Byte-inert for a build that declares no cutover config.
cmd_watcher_check() { # <slug|build-dir> — INV-WATCHER
  local a="${1:-}"; [ -n "$a" ] || die "usage: compass.sh watcher-check <slug|build-dir>"
  local dir; dir="$(_cv_dir "$a")"; local c="$dir/contract.md"
  [ -f "$c" ] || die "watcher-check: no contract.md in $dir"
  local cv win; cv="$(hdr_get "$c" canary || true)"; win="$(hdr_get "$c" bake-window || true)"
  if [ -z "$cv" ] && [ -z "$win" ]; then ok "watcher-check: no cutover declared — N/A-pass (byte-inert). WATCHER: N/A"; return 0; fi
  local blob; blob="$( { _nofence "$c"; [ -f "$dir/receipts.md" ] && _nofence "$dir/receipts.md"; } 2>/dev/null; true )"
  local wl name after; wl="$(_hdr1 watcher <<<"$blob")"
  if [ -n "$wl" ]; then
    # `watcher: <name> · window <…>` — the window token MUST be AFTER the `·`, and the name must contain a
    # real alphanumeric run (RB-m9: `windowsill` in the name, or a punctuation-only name, no longer count).
    name="$(printf '%s' "$wl" | sed -nE 's/^([^·]*)·.*/\1/p')"
    after="$(printf '%s' "$wl" | sed -nE 's/^[^·]*·(.*)/\1/p')"
    if [ -n "$name" ] && _attest_real "$name" && printf '%s' "$name" | grep -qE '[A-Za-z0-9]' && grep -qi 'window' <<<"$after"; then
      ok "watcher-check: named watcher '$(_normcmd "$name")' + a watch window. WATCHER: NAMED"; return 0
    fi
  fi
  if [ -f "$dir/.auto-mode" ]; then
    # the --auto substitute: a PROVEN-armed rollback. The command before the arrow must itself pass
    # _attest_real (RB-M1: `rollback-rehearsed: (todo) → exit 0` / `none → exit 0` no longer count), and
    # the outcome must be literally `exit 0` (a `→ exit 1` fails). Herestring, not a pipe (RB-M3).
    local rr rcmd; rr="$(_hdr1 rollback-rehearsed <<<"$blob")"
    rcmd="${rr%%→*}"; rcmd="${rcmd%%->*}"
    # require a clean `exit 0` AND no recorded non-zero exit anywhere (take-worst — RB4-M3: `→ exit 1 → exit 0`
    # is not armed), AND a real command (RB-M1).
    if [ -n "$rr" ] && grep -qE '(→|->)[[:space:]]*exit 0([^0-9]|$)' <<<"$rr" && ! grep -qE 'exit[[:space:]]*[1-9]' <<<"$rr" && _attest_cmd "$rcmd"; then
      ok "watcher-check: --auto with a PROVEN-armed rollback (rollback-rehearsed '$(_normcmd "$rcmd")' → exit 0). WATCHER: AUTO-ARMED"; return 0
    fi
    die "watcher-check: --auto but NO proven-armed rollback — need 'rollback-rehearsed: <real-cmd> → exit 0' (a placeholder command or a bare 'armed' is not proof). WATCHER: AUTO-UNARMED (fail-closed)"
  fi
  die "watcher-check: opted into the cutover net but NEITHER a named watcher NOR (in --auto) a proven-armed rollback. WATCHER: NONE (HARD STOP)"
}

# INV-NA-EXPLICIT — the ship receipt MUST record all three cutover invocations (canary/bake/watcher),
# N/A or real — a silent skip fails the suite (mirrors ship-prodsafety-receipt-match). And for a
# `deploy: in scope` build, the three cannot ALL be N/A without an explicit `cutover: waived — <reason>`
# (a real deploy must not fail-OPEN by omitting cutover config — R2-M6).
cmd_ship_cutover_receipt_match() { # <build-dir> — INV-NA-EXPLICIT
  local dir="${1:-}"; [ -n "$dir" ] || die "usage: compass.sh ship-cutover-receipt-match <build-dir>"
  local f="$dir/receipts.md"; [ -f "$f" ] || die "ship-cutover-receipt-match: no receipts.md in $dir"
  local blk; blk="$(last_block "$f" ship)"
  [ -n "$blk" ] || die "ship-cutover-receipt-match: no ship receipt to check."
  grep -qE 'canary: exit'  <<<"$blk" || die "ship-cutover-receipt-match: ship receipt MISSING the 'canary: exit N' line — the cutover gate was skipped (never allowed)."
  grep -qE 'bake: exit'    <<<"$blk" || die "ship-cutover-receipt-match: ship receipt MISSING the 'bake: exit N' line — the cutover gate was skipped (never allowed)."
  grep -qE 'watcher: exit' <<<"$blk" || die "ship-cutover-receipt-match: ship receipt MISSING the 'watcher: exit N' line — the cutover gate was skipped (never allowed)."
  # R2-M6 fail-open guard for deploy:in-scope. Anchor the DISPOSITION to the value start (RB-M2): prose after
  # the disposition (e.g. `in scope — canary out-of-scope for now`) must not flip the guard off.
  local c="$dir/contract.md" deploy="" dl
  [ -f "$c" ] && deploy="$(hdr_get "$c" deploy || true)"
  dl="$(printf '%s' "$deploy" | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//')"
  case "$dl" in
    ""|out-of-scope*|out_of_scope*|"out of scope"*) : ;;   # deploy waived/absent → N/As are fine
    *)
      local allna=1 g
      for g in canary bake watcher; do
        # match the disposition token N/A / NA / N/A-pass (RB2-m3 + RB4-M2), preceded by a separator so mid-word
        # "na" (e.g. in "canary"/"NAMED") never counts, and followed by a word boundary so `N/A-pass` DOES.
        grep -iE "^[-*[:space:]]*\[x\][[:space:]]*$g: exit" <<<"$blk" | grep -qiE '(^|[[:space:]:·])n/?a([^a-z0-9]|$)' || allna=0
      done
      if [ "$allna" = 1 ]; then
        grep -qiE '^[-*[:space:]]*cutover: waived [—-]' <<<"$blk" \
          || die "ship-cutover-receipt-match: deploy IS in scope but canary+bake+watcher are ALL N/A and there is no 'cutover: waived — <reason>' — a real deploy must not fail-OPEN by omitting cutover config (R2-M6). CUTOVER: FAIL-OPEN"
      fi
      ;;
  esac
  ok "ship-cutover-receipt-match: canary + bake + watcher all invoked and recorded (and not a silent fail-open)."
}

set_index_status() { # <slug> <status>  — update the status= token on the slug's INDEX line
  local idx; idx="$(state_root)/INDEX"; [ -f "$idx" ] || return 0
  local esc; esc="$(printf '%s' "$1" | sed 's/[.[\*^$/]/\\&/g')"
  sed -i.bak -E "/^${esc}[ ]/ s/status=[A-Za-z-]+/status=$2/" "$idx" 2>/dev/null && rm -f "$idx.bak" || true
}

# ── v0.32.0 S27 — THE KILL SWITCH, §12 ─────────────────────────────────────────────────────────
# `COMPASS_V32_STRICT` is documented in §12 with a default of ON and a one-command disable. Round 2
# of the contract review found the flag as first designed reintroduced the exact defect §12 exists
# to remove: it returned EVERY new gate to an N/A-pass, including the one that measures the gold, so
# one environment variable made every promise in the contract read green.
#
# The correction, in §12's own words: "the flag may disable reporting gates, but never the
# measurement the build is graded on, and closure is REFUSED while the flag is off."
#
# Before this step NOTHING read the flag — measured over all nine v0.32 checks, zero references
# except two comments saying it is deliberately not read. A kill switch that no code consults is a
# paragraph, and so is the promise about what it cannot do. Both halves are now real:
#   · closure is refused while it is off (here), and
#   · smoke asserts NO v0.32 measurement reads it, which is what makes "it cannot silence the
#     measurement" a fact about the code rather than an intention.
_v32_strict_off() {
  case "${COMPASS_V32_STRICT:-1}" in 0|off|OFF|false|FALSE|no|NO) return 0 ;; esac
  return 1
}
cmd_close() { # <build-dir> <slug> [--abandon]
  local dir="$1" slug="$2" mode="${3:-}"
  if [ "$mode" = "--abandon" ]; then
    set_index_status "$slug" ROLLED-BACK
    ( cmd_dora_record "$dir" ROLLED-BACK ) >/dev/null 2>&1 || true   # v0.23: DORA record, additive — subshell so an internal die can't abort the close
    if _v32_strict_off; then
      ok "build '$slug' ABANDONED → status ROLLED-BACK (lifecycle-audit skipped); clearing state. NOTE: COMPASS_V32_STRICT was OFF for this session (v32-strict=off) — abandoning claims nothing about the build, which is why it is allowed while closing is not."
    else
      ok "build '$slug' ABANDONED → status ROLLED-BACK (lifecycle-audit skipped); clearing state."
    fi
  else
    # §12: closure is REFUSED while the kill switch is off. A build closed with the strict checks
    # disabled would carry a CLOSED status earned under weaker rules than the ones it is recorded
    # against — which is the "one environment variable makes every promise read green" failure the
    # section exists to stop. `--abandon` is deliberately still allowed above: cancelling a build
    # claims nothing about it, and blocking the cancel would only strand it.
    if _v32_strict_off; then
      die "close: COMPASS_V32_STRICT is off, so this build's strict checks are disabled and closure is REFUSED (contract §12). Stamp 'v32-strict=off' on the receipt if this session genuinely ran with it off, then re-run with the flag ON — a CLOSED status must be earned under the rules it is recorded against. To cancel instead: compass.sh close '$dir' '$slug' --abandon"
    fi
    # Terminal-status guard (v0.7.0): a normal close must pass the CLOSED lifecycle audit.
    cmd_lifecycle_audit "$dir" CLOSED >/dev/null 2>&1 || die "close: lifecycle-audit CLOSED failed — refusing to close an incomplete build. Inspect: compass.sh lifecycle-audit '$dir' CLOSED   (or cancel it: compass.sh close '$dir' '$slug' --abandon)."
    set_index_status "$slug" CLOSED
    ( cmd_dora_record "$dir" CLOSED ) >/dev/null 2>&1 || true        # v0.23: DORA record, additive (subshell + >/dev/null: never fails/leaks into the close)
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
    status="$(status_line "$sr/$slug/progress.md" --token)"   # v0.32 S24 (path stays inline: RB-02, never state_root)
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
  # v0.32.0 S24: the LAST status line, not the first. `lifecycle-migration-gates-v0-7`
  # stacks SIX of them (an append log, oldest first), so `head -1` made `compass.sh status`
  # report a SHIPPED build as "Contract LOCKED" — reproduced live before this change.
  # Every other caller already read the last one; now the display agrees with the decisions.
  status="$(status_line "$p" --raw)"
  stage="$(sed -nE 's/^\*\*Stage:\*\*[[:space:]]*(.*)/\1/p' "$p" 2>/dev/null | head -1)"
  next="$(sed -nE 's/^\*\*Next:\*\*[[:space:]]*(.*)/\1/p' "$p" 2>/dev/null | head -1)"
  # v0.24.0 (review-plan MAJOR-2): count ANY checkbox, not only '**S…' — numbered/**W-A1 plans
  # (v0.22/v0.23/this build) previously read 0/0. head -1 defends the grep-c "0\n0" tail.
  total="$(grep -cE '^[[:space:]]*- \[[ x~]\] ' "$dir/plan.md" 2>/dev/null || true)"; total="${total:-0}"
  done_="$(grep -cE '^[[:space:]]*- \[x\] ' "$dir/plan.md" 2>/dev/null || true)"; done_="${done_:-0}"
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

# ── v0.24.0: the pushed COCKPIT — the always-on "where it stands" clarity surface ────────────
# Pure bash (INV-ASCII-CHEAP: no render.sh/gen.mjs/chrome/headless). Prints the BUILD strip (the
# 7-stage pipeline with ✓/◉/○ + step k/n + next) and, when the build's contract names a `program:`
# AND PROGRAM.md exists, a two-altitude PROGRAM strip (phase K/N + per-phase contract child-rows).
# The program strip is sourced from the GIT-FREE readers (_program_rows/_program_contract_rows/
# _program_first_unshipped) — NEVER cmd_program_ledger (which spawns git per row → INV-PERF-ASCII).
# All reads guard-first + set-e-safe.
_program_contract_rows() { # <file> <phase-K>  → the indented 'contract:' child rows under phase K (git-free)
  [ -f "${1:-}" ] || return 0
  awk -v k="${2:-}" '
    /^phase [0-9]+\/[0-9]+ · /{ cur=$2; sub(/\/.*/,"",cur); inphase=(cur==k) }
    /^[[:space:]]+contract: /{ if (inphase) print }
  ' "$1" 2>/dev/null || true
}
_crow_slug()   { printf '%s' "$1" | sed -E 's/^[[:space:]]+contract:[[:space:]]*([^ ·]+).*/\1/'; }
_crow_status() { printf '%s' "$1" | sed -nE 's/.*· status=([a-z-]+).*/\1/p'; }
_cockpit_glyph() { case "${1:-}" in shipped) printf '✓' ;; in-flight|in-review*) printf '◉' ;; *) printf '○' ;; esac; }

# v0.32.0 S15 — INV-PLAIN-TERMINAL's own check. The invariant said the stage-end block carries four
# elements and NOTHING asserted it; the options element was missing on every build in every mode.
# A rule with no check is a sentence.
# v0.32.0 S12 + S13 — the stage-end contract, checked instead of hoped for.
#
# Contract §7 says two things about the end of every stage: the COCKPIT prints (in every mode, no
# exception), and the next step is ASKED via AskUserQuestion — unless the mode is auto, in which
# case the receipt carries `asked=no · reason=auto-mode` so every un-asked stage stays visible
# forever. Neither had a check. Measured before this: 5 of 30 receipt files carry any `asked=` at
# all, and all five are the mode choice at lock time, not a stage end.
#
# GUARD-FIRST, and the honest shape of it. Receipts are written by the SKILLS, not by this script,
# so no existing receipt can carry a stamp that did not exist when it was written. Enforcing
# retroactively would refuse all 30 builds — the v0.28 defect. So this gate checks every block that
# CARRIES a `stage-end:` line and REPORTS, in words and with a count, every block that does not.
# An unstated N/A is a rule quietly retired; a stated one is a migration in progress.
cmd_stage_end_gate() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh stage-end-gate <build-dir>"
  local r="$dir/receipts.md"
  [ -f "$r" ] || { ok "stage-end-gate: N/A — no receipts.md in '$(basename "$dir")' yet."; return 0; }
  local blocks=0 stamped=0 legacy=0 bad=""
  local hdr="" body="" line stage
  # walk the file block by block: a header line starts a new receipt.
  while IFS= read -r line; do
    case "$line" in
      '## RECEIPT — '*)
        if [ -n "$hdr" ]; then _stage_end_block "$hdr" "$body" || bad="$bad
    $_SE_WHY"; case "$_SE_KIND" in stamped) stamped=$((stamped+1)) ;; legacy) legacy=$((legacy+1)) ;; esac; fi
        hdr="$line"; body=""; blocks=$((blocks+1)) ;;
      *) body="$body
$line" ;;
    esac
  done < "$r"
  if [ -n "$hdr" ]; then _stage_end_block "$hdr" "$body" || bad="$bad
    $_SE_WHY"; case "$_SE_KIND" in stamped) stamped=$((stamped+1)) ;; legacy) legacy=$((legacy+1)) ;; esac; fi

  if [ -n "$bad" ]; then
    echo "refuse: stage-end" >&2
    die "stage-end-gate: $(printf '%s' "$bad" | grep -c .) receipt block(s) carry a stage-end stamp that does not hold:$bad
  Contract §7 — at every stage end the cockpit prints, and the next step is ASKED unless the mode is
  auto, in which case the receipt says so."
  fi
  if [ "$legacy" -gt 0 ]; then
    ok "stage-end-gate: $stamped of $blocks blocks carry a stage-end stamp and all hold. $legacy predate the stamp and are NOT checked — stated, not passed silently."
  else
    ok "stage-end-gate: all $stamped of $blocks receipt blocks carry a stage-end stamp and every one holds."
  fi
}

# Returns 0 when the block is acceptable. Sets _SE_KIND=stamped|legacy and, on failure, _SE_WHY.
_stage_end_block() { # <header> <body>
  local h="${1:-}" b="${2:-}"
  _SE_KIND=legacy; _SE_WHY=""
  local se; se="$(printf '%s' "$b" | LC_ALL=C grep -m1 -E '^[-* ]*\[?[x ]?\]?[[:space:]]*stage-end:' || true)"
  [ -n "$se" ] || return 0                      # no stamp: legacy, reported by the caller
  _SE_KIND=stamped
  local name; name="$(printf '%s' "$h" | sed -E 's/^## RECEIPT — ([^ ·]+).*/\1/')"
  # 1. the COCKPIT printed — in EVERY mode, no exception (contract §7).
  case "$se" in *cockpit=printed*) : ;; *)
    _SE_WHY="$name: the stamp does not say cockpit=printed. The cockpit prints at every stage end in every mode."; return 1 ;;
  esac
  # 2. the ASK. Either it was asked, or the mode was auto AND the stamp says so.
  case "$se" in
    *asked=yes*) : ;;
    *asked=no*)
      case "$se" in *reason=auto-mode*) : ;; *)
        _SE_WHY="$name: asked=no with no 'reason=auto-mode'. An un-asked stage end must say WHY, or it is just an un-asked stage end."; return 1 ;;
      esac ;;
    *) _SE_WHY="$name: the stamp records no 'asked=' at all."; return 1 ;;
  esac
  return 0
}

cmd_cockpit_gate() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh cockpit-gate <build-dir>"
  # GUARD-FIRST, and found by §12's own canary rather than by reading. A build with NO lifecycle
  # state — no progress.md and no receipts.md — has no stage end to describe, so demanding the four
  # elements of one is demanding a description of something that has not happened. `gate-soundness-v0-32`
  # in this repo is exactly that: a parked contract carrying only a carry-forward note and an orient
  # log. §12 makes any historical build a NEW gate would newly refuse a RELEASE BLOCKER, not a
  # fixture to delete — and that build is a no-touch zone, so the gate was the thing that had to change.
  # v0.33 S4 — the guard widened by ONE case, and measured before it was widened. A dir with a
  # receipts.md but NO progress.md also has no stage end to describe: the cockpit reads "what is
  # next" out of progress.md, so without it the block cannot state three of its four elements. The
  # old guard required BOTH files to be absent, so such a dir was refused for lacking something it
  # had no way to have.
  #
  # BLAST RADIUS, measured over every build folder on this machine before the change:
  #   both files = 31 · receipts-only = 0 · progress-only = 0 · neither = 1
  # ZERO real builds are receipts-only, so this widening refuses nothing that was passing and
  # excuses no build that could have complied. What it does cover is the suites' own minimal
  # fixtures — a two-line receipts.md — which is precisely the legacy/minimal case guard-first
  # exists for, and which this gate refused when it was first wired onto the cmd_gate seam
  # (968 passed / 4 FAILED).
  if [ ! -f "$dir/progress.md" ]; then
    ok "cockpit-gate '$(basename "$dir")': N/A — no progress.md, so there is no 'what is next' to state and no stage end to describe. NOT a statement that a stage end was well-formed."
    return 0
  fi
  if [ ! -f "$dir/progress.md" ] && [ ! -f "$dir/receipts.md" ]; then
    ok "cockpit-gate '$(basename "$dir")': N/A — no progress.md and no receipts.md, so this build has no stage end to describe. NOT a statement that a cockpit was printed."
    return 0
  fi
  local out; out="$(cmd_cockpit "$dir" 2>&1)" || true
  local missing=""
  # 1. WHAT HAPPENED — the stage strip, with a glyph per stage.
  printf '%s' "$out" | grep -q '^BUILD · ' || missing="$missing what-happened(the-stage-strip)"
  # 2. WHERE YOU ARE — the ▲ marker.
  printf '%s' "$out" | grep -q '▲ ' || missing="$missing where-you-are"
  # 3. WHAT IS NEXT.
  printf '%s' "$out" | grep -qE 'next:|all stages ✓' || missing="$missing what-is-next"
  # 4. THE OPTIONS — and each must name a real command, not a category.
  if printf '%s' "$out" | grep -q '▸ you can:'; then
    printf '%s' "$out" | grep -q '/compass:go' || missing="$missing options(names-no-command)"
  else
    missing="$missing the-options"
  fi
  [ -z "$missing" ] || { echo "refuse: cockpit-element" >&2
    die "cockpit-gate: the stage-end block is missing:$missing
  Contract §7 — a stage-end block states what happened, where you are, what is next, and the options."; }
  # The PLAIN-WORDS half needs the walkthrough skill to define a term where it is used. When that
  # skill is absent the check N/A-passes AND SAYS SO — an unstated N/A is how a rule stops being
  # enforced without anyone deciding to stop enforcing it.
  # BOTH locations. `feynman-walkthrough` is a USER-level skill, not bundled in this plugin, so
  # looking only inside the plugin would report N/A on every machine that HAS it — a permanent N/A
  # is a rule quietly retired, which is the shape this build exists to catch.
  local fey_p fey_u
  fey_p="$(dirname "${BASH_SOURCE[0]}")/../skills/feynman-walkthrough"
  fey_u="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/feynman-walkthrough"
  if [ ! -d "$fey_p" ] && [ ! -d "$fey_u" ]; then
    ok "cockpit-gate: all four elements present. Plain-words half N/A — /feynman-walkthrough is not installed on this tree, so no term-definition check ran. Stated, not skipped silently."
    return 0
  fi
  ok "cockpit-gate: all four elements present (what happened · where you are · what is next · the options)."
}

cmd_cockpit() { # <build-dir>  — the pushed clarity surface (INV-COCKPIT/PUSH-STAGE/PUSH-RESUME)
  local dir="${1:-}"; [ -n "$dir" ] || die "usage: compass.sh cockpit <build-dir>"
  [ -d "$dir" ] || die "no such build dir: $dir"
  local slug; slug="$(basename "$dir")"
  local c="$dir/contract.md" p="$dir/progress.md" r="$dir/receipts.md"
  echo "── Compass cockpit: $slug ───────────────────────────"

  # ── PROGRAM strip (two altitudes) — suppressed unless the contract names a real program ──
  local pname=""
  if [ -f "$c" ]; then
    pname="$(sed -nE 's/^[-* ]*\**program:\**[[:space:]]*//Ip' "$c" 2>/dev/null | head -1 | sed -E 's/[[:space:]]*(\(.*)?$//')"
  fi
  case "$(printf '%s' "${pname:-}" | tr 'A-Z' 'a-z')" in ''|none|'n/a'|'n/a — '*|na) pname="" ;; esac
  # git-free: the ledger sits at <state-root>/PROGRAM.md == the build dir's parent (never state_root,
  # which needs git → INV-PERF-ASCII + fixture-testable off a git repo).
  local pf; pf="$(dirname "$dir")/PROGRAM.md"
  if [ -n "$pname" ] && [ -f "$pf" ]; then
    local ptot="?" curslug row rk rn rslug rst rtag crow cslug cst
    curslug="$(_program_first_unshipped "$pf" 2>/dev/null || true)"
    [ -z "$curslug" ] && curslug="COMPLETE"
    while IFS= read -r row; do [ -n "$row" ] || continue
      rn="$(printf '%s' "$row" | sed -E 's#^phase [0-9]+/([0-9]+) · .*#\1#')"; ptot="$rn"; break
    done < <(_program_rows "$pf" 2>/dev/null || true)
    echo "PROGRAM · $pname   Phase(s)/$ptot · here: $curslug"
    while IFS= read -r row; do [ -n "$row" ] || continue
      rk="$(printf '%s' "$row" | sed -E 's#^phase ([0-9]+)/[0-9]+ · .*#\1#')"
      rslug="$(_row_slug "$row")"; rst="$(_row_status "$row")"; rtag="$(_row_tag "$row")"
      local here=""; [ "$rslug" = "$curslug" ] && here=" ◀ here"
      printf '  P%s %s %s%s%s\n' "$rk" "$(_cockpit_glyph "$rst")" "$rslug" "${rtag:+ ($rtag)}" "$here"
      # per-phase contract child rows (contracts-per-phase — the core pain)
      while IFS= read -r crow; do [ -n "$crow" ] || continue
        cslug="$(_crow_slug "$crow")"; cst="$(_crow_status "$crow")"
        printf '        · %s %s\n' "$(_cockpit_glyph "$cst")" "$cslug"
      done < <(_program_contract_rows "$pf" "$rk" 2>/dev/null || true)
    done < <(_program_rows "$pf" 2>/dev/null || true)
    echo "────────────────────────────────────────────────────"
  fi

  # ── BUILD strip (the 7-stage pipeline) ──
  # Use the canonical `stage_pass` helper (parses `## RECEIPT — <stage> · … · PASS`, exact-stage,
  # SUPERSEDED-aware, unchecked-box-aware) — NOT a hand-rolled receipt grep. (review-build R1
  # CRITICAL: an ad-hoc ` <stage> —` grep never matches the real receipt format and only tripped on
  # prose accidents, so the strip was wrong on every real build.)
  local stage cur="" line="" done_stage
  for stage in $LIFECYCLE; do
    if stage_pass "$dir" "$stage"; then :; else cur="$stage"; break; fi
  done
  for stage in $LIFECYCLE; do
    if stage_pass "$dir" "$stage"; then done_stage="✓";
    elif [ "$stage" = "$cur" ]; then done_stage="◉"; else done_stage="○"; fi
    line="$line$stage $done_stage  "
  done
  echo "BUILD · $slug"
  echo "  $line"
  # step k/n + next (git-free; fixed checkbox regex)
  local total done_ next
  total="$(grep -cE '^[[:space:]]*- \[[ x~]\] ' "$dir/plan.md" 2>/dev/null || true)"; total="${total:-0}"
  done_="$(grep -cE '^[[:space:]]*- \[x\] ' "$dir/plan.md" 2>/dev/null || true)"; done_="${done_:-0}"
  next="$(sed -nE 's/^\*\*Next:\*\*[[:space:]]*(.*)/\1/p' "$p" 2>/dev/null | head -1)"
  printf '  ▲ %s' "${cur:-done — all stages ✓}"
  [ "${total:-0}" -gt 0 ] 2>/dev/null && printf ' · step %s/%s' "${done_:-0}" "$total"
  [ -n "${next:-}" ] && printf ' · next: %s' "$next"
  printf '\n'
  # ── v0.32.0 S15 (INV-PLAIN-TERMINAL) — THE FOURTH ELEMENT ──────────────────────────────────
  # Contract §7: a stage-end block states what happened, WHERE YOU ARE, what is next, AND THE
  # OPTIONS. Three of the four were here. The options were not, on any build, in any mode — so the
  # surface that exists to tell a person what they can do never told them.
  # Concrete commands, not a category: "your options" that names no command is the same defect one
  # level up.
  local _optslug="$slug"
  printf '  ▸ you can:  '
  printf 'continue → /compass:go'
  printf '  ·  see where this stands → compass.sh status %s' "$dir"
  printf '  ·  pick it up later → /compass:resume %s' "$_optslug"
  printf '  ·  stop here — nothing is lost, the state is on disk\n'
  echo "────────────────────────────────────────────────────"
}

# ── v0.24.0: milestone artifact gate (INV-ARTIFACT-MILESTONES) ───────────────────────────────
# For milestones with NO forward lifecycle gate (ship = terminal; phase-boundary = not an edge):
# a reached milestone MUST have produced its HTML body. The contract-lock + plan-lock milestones
# are enforced for FREE by the frozen cmd_gate (it refuses to advance on any unchecked `- [ ]`
# MILESTONE receipt line). This standalone gate is the ship/phase seam. HTML is mandatory; the PNG
# may degrade to `png=N/A — no renderer` and still pass (never blocks a Chrome-less machine).
# ── v0.26.0: real render command — headless-Chrome screenshot of an HTML file to a PNG,
# watchdog-bounded, FAIL-CLOSED. So a `png=N/A` can only be written AFTER a genuine failed attempt.
# exit 0 = a non-empty PNG produced · exit 1 = a browser ran but produced no PNG · exit 3 = no browser / opted out.
cmd_render() { # <html> <png>
  local html="${1:-}" png="${2:-}"
  [ -n "$html" ] && [ -n "$png" ] || die "usage: compass.sh render <html> <png>"
  [ -f "$html" ] || die "render: html '$html' not found"
  if [ "${COMPASS_NO_BROWSER:-0}" = "1" ]; then echo "render: N/A — COMPASS_NO_BROWSER=1 (opted out)" >&2; return 3; fi
  local chrome=""
  for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" google-chrome-stable google-chrome chromium chromium-browser; do
    if [ -x "$c" ]; then chrome="$c"; break; fi
    command -v "$c" >/dev/null 2>&1 && { chrome="$(command -v "$c")"; break; }
  done
  [ -n "$chrome" ] || { echo "render: N/A — no headless browser found (install Chrome/Chromium)" >&2; return 3; }
  case "$html" in /*) : ;; *) html="$PWD/$html" ;; esac
  # v0.30: artefacts are BODY FRAGMENTS, which carry no <meta charset>. Chrome screenshotting a
  # file:// URL with no charset declaration falls back to the browser default, not UTF-8 — and a
  # generated brief carries 14 non-ASCII lines (— · ✓ → ≥). Every PNG would ship mojibake,
  # INCLUDING the image the cold-read gate is scored on, so the acceptance test would have been
  # grading garbled text. Wrap CONDITIONALLY: a complete document is passed through untouched,
  # because `render` is a public subcommand also used on full pages.
  local _wrapped=""
  if ! head -c 200 "$html" 2>/dev/null | grep -qiE '<!doctype|<html'; then
    _wrapped="$(mktemp -t compass-render).html"
    { printf '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">\n'
      cat "$html"; } > "$_wrapped"
    html="$_wrapped"
  fi
  rm -f "$png" 2>/dev/null || true
  ( "$chrome" --headless=new --disable-gpu --no-sandbox --hide-scrollbars --force-device-scale-factor=2 \
      --window-size=980,1500 --screenshot="$png" "file://$html" >/dev/null 2>&1 ) &
  local cpid=$!
  ( sleep 30 && kill -9 "$cpid" 2>/dev/null ) & local wpid=$!
  wait "$cpid" 2>/dev/null || true; kill -9 "$wpid" 2>/dev/null || true
  [ -n "$_wrapped" ] && rm -f "$_wrapped" 2>/dev/null
  { [ -f "$png" ] && [ -s "$png" ]; } || { echo "render: FAILED — no non-empty PNG produced" >&2; return 1; }
  ok "render: $png produced."
}

# ── v0.24.0 milestone gate + v0.26.0 delivery enforcement (INV-MILESTONE-DELIVERY) ─────────────
# HTML is mandatory. GUARD-FIRST: a receipt line with NO `artifact=` token is LEGACY (pre-v0.26) →
# HTML-only pass, REGARDLESS of any `png=` (legacy receipts carry `png=N/A — no renderer`; png= must
# NOT trigger strict). A line WITH `artifact=` is held to the strict grammar: png=<exists|N/A — reason>,
# artifact=<https URL|N/A — reason>; a bare `N/A` (no reason) fails closed. render= stays space-delimited.
_reasoned_na() { [[ "$1" =~ ^N/A[[:space:]]+[—-][[:space:]]+.*[^[:space:]] ]]; }
cmd_milestone_gate() { # <build-dir> <milestone-name>
  local dir="${1:-}" name="${2:-}"
  [ -n "$dir" ] && [ -n "$name" ] || die "usage: compass.sh milestone-gate <build-dir> <milestone>"
  local r="$dir/receipts.md"
  [ -f "$r" ] || die "milestone-gate: no receipts.md in $dir"
  local ln; ln="$(grep -E "MILESTONE: ${name} render=" "$r" 2>/dev/null | tail -1 || true)"
  [ -n "$ln" ] || die "milestone-gate: milestone '$name' has no 'MILESTONE: $name render=<path>' receipt line (HTML artifact not produced)."
  local path; path="$(printf '%s' "$ln" | sed -nE 's/.*render=([^ ]+).*/\1/p')"   # render= is a path (no spaces)
  [ -n "$path" ] || die "milestone-gate: milestone '$name' receipt has no render=<path> (HTML mandatory)."
  local abs="$path"; case "$abs" in /*) : ;; *) abs="$dir/$abs" ;; esac
  { [ -f "$abs" ] && [ -s "$abs" ]; } || die "milestone-gate: milestone '$name' HTML artifact '$abs' missing/empty (HTML mandatory)."
  # guard-first: no artifact= token → LEGACY → HTML-only pass
  case "$ln" in
    *' artifact='*) : ;;
    *) ok "milestone-gate: '$name' HTML artifact present ($abs) [legacy receipt — no delivery tokens]."; return 0 ;;
  esac
  # strict: capture png= / artifact= FULL values (to the next key or EOL) — em-dash reason preserved
  local pngv artv
  pngv="$(printf '%s' "$ln" | sed -nE 's/.*[[:space:]]png=(.*)$/\1/p' | sed -E 's/[[:space:]]+(artifact|bytes)=.*//')"
  artv="$(printf '%s' "$ln" | sed -nE 's/.*[[:space:]]artifact=(.*)$/\1/p' | sed -E 's/[[:space:]]+(png|bytes)=.*//')"
  # png: a path that exists, OR a reasoned N/A
  if _reasoned_na "$pngv"; then :
  elif [ -n "$pngv" ] && [[ "$pngv" != N/A* ]]; then
    local pabs="$pngv"; case "$pabs" in /*) : ;; *) pabs="$dir/$pabs" ;; esac
    { [ -f "$pabs" ] && [ -s "$pabs" ]; } || die "milestone-gate: '$name' png '$pabs' missing/empty."
  else die "milestone-gate: '$name' png=N/A needs a reason ('N/A — <reason>'); a bare N/A fails closed."
  fi
  # artifact: an https URL, OR a reasoned N/A
  if [[ "$artv" =~ ^https:// ]]; then :
  elif _reasoned_na "$artv"; then :
  else die "milestone-gate: '$name' artifact must be an https URL or 'N/A — <reason>' (got '${artv:-<empty>}'); a bare N/A fails closed."
  fi
  ok "milestone-gate: '$name' delivered — render=$path, png ok, artifact ok."
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
  if [ -f "$p" ] && grep -qE '^[[:space:]]*\*\*Status:\*\*' "$p"; then   # v0.32 S24: same shape status_line reads
    tmp="$(mktemp "${p}.XXXXXX")"; sed -E "s|^[[:space:]]*\*\*Status:\*\*.*|${banner}|" "$p" > "$tmp"; mv -f "$tmp" "$p"
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
  if [ -f "$p" ] && grep -qE '^[[:space:]]*\*\*Status:\*\*' "$p"; then   # v0.32 S24: same shape status_line reads
    tmp="$(mktemp "${p}.XXXXXX")"; sed -E "s|^[[:space:]]*\*\*Status:\*\*.*|${banner}|" "$p" > "$tmp"; mv -f "$tmp" "$p"
  else printf '\n%s\n' "$banner" >> "$p"; fi
  _chain_append "$dir" "-" "gate-wait-G1"
  return 1
}

# v0.11.0 S3 — gate-clear: release the gate-lock on human approval (G1 or G2) so the lifecycle (and,
# in auto, the self-spawn) may continue. Appends a `gate-cleared` event. Idempotent.
cmd_gate_clear() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh gate-clear <build-dir>"
  local slug ld; slug="$(basename "$dir")"; ld="$(locks_dir)"
  # slug is passed as a POSITIONAL arg ($2), never spliced into the sh -c string — a build dir whose
  # basename contains shell metacharacters must not become code execution.
  with_lock "gate-$slug" sh -c 'rmdir "$1/$2.gate-lock" 2>/dev/null || true' _ "$ld" "$slug"
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
  local status; status="$(status_line "$dir/progress.md")"   # v0.32 S24 — whole rest: the post-ship glob needs it
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
  ok "auto-start: '$(basename "$dir")' is now AUTONOMOUS (--auto). Budget set, .auto-mode written. Run /compass:go (it will auto-advance, stopping only at G1/G2)."
}

# S5 helper: attempt an autonomous cross-session spawn. Emits ZERO stdout (RP-04). Returns 0 if it
# spawned, 1 otherwise. Caller (stop-guard) handles the JSON. Refuses at gate-lock / foreign owner /
# cap, and is idempotent vs a recent spawn (RP-12). Increments spent_sessions BEFORE spawn (RP-02/07).
_auto_spawn_maybe() { # <dir> <slug> <sid> <locks-dir>
  local dir="$1" slug="$2" sid="$3" ld="$4"
  [ -f "$dir/.auto-mode" ] || return 1
  # SECURITY (R3): validate the slug BEFORE it is used in any lock name or `sh -c` command — a
  # build-dir basename with shell metacharacters would otherwise be code execution. Legit slugs are
  # [A-Za-z0-9._-]+; anything else refuses fail-closed, recorded honestly as spawn-failed.
  case "$slug" in *[!A-Za-z0-9._-]*) _chain_append "$dir" "-" "spawn-failed"; echo "compass: auto-spawn refused — unsafe slug '$slug'." >&2; return 1 ;; esac
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
  local status; status="$(status_line "$dir/progress.md" --raw --token)"   # v0.32 S24
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
  # ── v0.33.3 — DRIFT IS NOW WATCHED, AND REPORTED RATHER THAN ENFORCED ───────────────────────
  # drift-check re-runs a shipped build's recorded observation command. It existed since v0.23 and
  # NOTHING invoked it — no skill, no hook, no loop — so nothing detected drift after any release.
  # It was carried as KNOWN-OPEN through v0.33.2. This is where it belongs: the post-ship loop is
  # the only thing that runs after a release, per round, per build.
  #
  # REPORTED, NEVER ENFORCED, and the measurement decided that. Over the 14 build folders that
  # actually carry a post-ship loop, drift-check refuses at least 4 — and the refusals are exit 127,
  # a recorded command that no longer resolves. That is environment rot in a historical build, not a
  # product regression, and hard-failing a post-ship round on it would break the loop for most of
  # the builds that have one. Telling rot from regression is reading the command, which is judgment.
  #
  # So the round RUNS it, PRINTS its verdict, and carries on. A drift that matters is now visible
  # every round instead of invisible forever; a drift that is only a stale path costs a line of
  # output. Run in a subshell so a die() inside it cannot escape and end the round (VZ-4).
  if type cmd_drift_check >/dev/null 2>&1; then
    _dc="$( ( cmd_drift_check "$dir" ) 2>&1 | head -3 || true )"
    case "$_dc" in
      *DRIFT*) printf 'loop-round: drift watch — %s\n' "$(printf '%s' "$_dc" | head -1)" >&2 ;;
      *)       : ;;
    esac
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
    # Enforce the PINNED grammar at runtime (not just in smoke): 'ship-as-is — <PS ids> · <ts>'.
    printf '%s\n' "user-accepted: $ua" | user_accepted_match || { echo "refuse: accepted-void" >&2; die "loop-converged: user-accepted line is not the pinned 'ship-as-is — <PS ids> · <ts>' form."; }
    local missing="" accepted_ids idseg
    # Parse ONLY the <PS ids> SEGMENT (between the first ' — ' and the LAST ' · '), so an id merely
    # MENTIONED in the trailing annotation/timestamp can never count as accepted (R3 round-2 fix).
    idseg="${ua#*— }"; idseg="${idseg% · *}"
    accepted_ids="$(printf '%s' "$idseg" | grep -oE 'PS-[0-9]+-[0-9]+' || true)"
    [ -n "$accepted_ids" ] || { echo "refuse: accepted-void" >&2; die "loop-converged: user-accepted names no valid PS id (empty or placeholder <PS ids> segment)."; }
    if [ -f "$ledger" ]; then
      local id found tok
      while IFS= read -r id; do
        [ -n "$id" ] || continue
        found=0
        while IFS= read -r tok; do [ "$tok" = "$id" ] && { found=1; break; }; done <<ACC
$accepted_ids
ACC
        [ "$found" = 1 ] || missing="$missing $id"
      done <<EOF
$(awk -F'|' 'function trim(x){gsub(/^[ \t\r]+|[ \t\r]+$/,"",x);return x}
   /^[[:space:]]*\|/ {
     if ($0 ~ /^[[:space:]]*\|[-: |]+$/) next
     id=trim($2); if (id !~ /^PS-[0-9]+-[0-9]+$/) next
     sev=toupper(trim($4)); if (sev!="CRITICAL" && sev!="MAJOR") next
     st=toupper(trim($(NF-1)))
     exo=0; for(i=1;i<=NF;i++){ c=toupper(trim($i)); if(c ~ /^(OPEN|REOPENED)([ \t]*[(:—-]|$)/) exo=1 }
     if (exo || st !~ /^(CLOSED|FIXED|RESOLVED|N\/A)([^A-Z0-9]|$)/) print id }' "$ledger")
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
  # v0.30 INV-1: a dir carrying the script-written `.compass-format` stamp is a NEW-FORMAT build.
  # For those the gate arms REGARDLESS of facet, and neither of the two model-authored escapes
  # below is honoured — `cold-critic:` is a header the checked party writes, so leaving it off or
  # setting it to `off` let the subject switch its own gate off. The contract's own words:
  # "the gates are not switchable; a switchable gate is not a gate." A waiver now needs a
  # user-signed receipt line (`gate-cleared`/`fire-g2` shape), not a contract header.
  # Legacy dirs (no stamp) keep the byte-identical pre-v0.30 behaviour below — arming on absence
  # is what failed 25 of 26 existing builds when mode-gate first shipped.
  local _stamped=0; [ -f "$dir/.compass-format" ] && _stamped=1
  if [ "$_stamped" = 1 ]; then
    case "$cc" in
      off*)
        if grep -qE '^- \[x\] cold-critic-waiver: user-signed' "$r" 2>/dev/null; then
          ok "coldgo-gate: waived — user-signed waiver recorded in receipts."; return 0
        fi
        echo "refuse: header-waiver" >&2
        die "coldgo-gate: 'cold-critic: off' is a model-authored header and no longer waives this gate.
  A waiver requires a user-signed receipt line:
  - [x] cold-critic-waiver: user-signed · <reason>" ;;
    esac
  else
    case "$facets" in *web*) : ;; *) ok "coldgo-gate: N/A — not a web-facet build."; return 0 ;; esac
    case "$cc" in
      "")    ok "coldgo-gate: N/A — legacy web build (no cold-critic header, pre-v0.12)."; return 0 ;;
      off*)  ok "coldgo-gate: waived — ${cc#off}"; return 0 ;;
      on*)   : ;;
      *)     die "coldgo-gate: unparseable cold-critic header value '${cc}'." ;;
    esac
  fi
  [ -f "$r" ] || { echo "refuse: streak" >&2; die "coldgo-gate: no receipts.md — no cold-critic runs recorded."; }
  # Grammar tripwire (R3 round-2): any cold-critic header that matches none of the three pinned
  # forms is a FAIL-CLOSED parse error — a malformed header must never shift the block window.
  local bad; bad="$(grep -E '^## RECEIPT — cold-critic' "$r" | grep -vE '^## RECEIPT — cold-critic · (GO · tree=[a-z0-9]+|NO-GO · tree=[a-z0-9]+|HUMAN-GO · "[^"]*" · tree=[a-z0-9]+)$' || true)"
  [ -z "$bad" ] || { echo "refuse: unparseable" >&2; die "coldgo-gate: unparseable cold-critic receipt header (grammar drift): $bad"; }
  local head12; head12="$(git rev-parse --short=12 HEAD 2>/dev/null || printf nogit)"
  # HUMAN-GO path first (one suffices; gated-only; fallback must be declared)
  local hg; hg="$(grep -E '^## RECEIPT — cold-critic · HUMAN-GO · "[^"]*[^" ][^"]*" · tree=[a-z0-9]+' "$r" | tail -1 || true)"
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
  local last2; last2="$(grep -E '^## RECEIPT — cold-critic · (GO|NO-GO) · tree=' "$r" | tail -2 || true)"
  local n; n="$(printf '%s\n' "$last2" | grep -c 'cold-critic' || true)"
  [ "$n" = "2" ] || { echo "refuse: streak" >&2; die "coldgo-gate: need 2 consecutive cold GO receipts (have $n runs recorded)."; }
  printf '%s\n' "$last2" | grep -q 'NO-GO' && { echo "refuse: streak" >&2; die "coldgo-gate: a NO-GO sits in the last 2 runs — streak reset."; }
  local s1 s2
  s1="$(printf '%s\n' "$last2" | sed -n '1p' | sed -nE 's/.*tree=([a-z0-9]+).*/\1/p')"
  s2="$(printf '%s\n' "$last2" | sed -n '2p' | sed -nE 's/.*tree=([a-z0-9]+).*/\1/p')"
  [ "$s1" = "$s2" ] || { echo "refuse: streak" >&2; die "coldgo-gate: the 2 GOs carry different tree shas ($s1 vs $s2) — a commit between GOs resets the streak."; }
  # EACH of the last two cold-critic blocks needs its OWN checked clean-tree box (R3 round-1
  # fix: an aggregated count let a duplicated box in block 1 stand in for a missing one in
  # block 2 — the sha would no longer pin the pixels for that GO).
  local which nbox
  for which in 1 2; do
    nbox="$(awk -v w="$which" '
      /^## RECEIPT — cold-critic · (GO|NO-GO) · tree=/ { cnt++; cur=cnt; blk[cur]="" ; inb=1; next }
      inb && /^## / { inb=0 }
      inb { blk[cur]=blk[cur] $0 ORS }
      END { t=blk[cnt-(w-1)]; n=0; nl=split(t,L,ORS)
            for(i=1;i<=nl;i++) if (L[i] ~ /^\- \[x\] clean-tree: .*porcelain.*empty/) n++
            print n }' "$r")"
    [ "${nbox:-0}" -ge 1 ] || { echo "refuse: dirty-tree" >&2; die "coldgo-gate: the $([ "$which" = 1 ] && echo last || echo second-to-last) GO receipt lacks its own checked 'clean-tree: git status --porcelain empty' box (the sha must pin the pixels — per block, not in aggregate)."; }
  done
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

# ── v0.13.0 S10: intake-gate — the co-construction interview's teeth (contract F-INTAKEGATE) ──
# Trigger (RC-6, pinned): the gate applies iff the contract declares `intake: co-construct-v1`
# OR intake.md exists; `intake: classic` explicitly BYPASSES (the pre-v0.13 interview ran).
# Checks are EVIDENTIAL (G-I6 reads recorded interview evidence, never the transient .auto-mode
# marker — re-gating an --auto build that legitimately interviewed earlier stays clean).
# Codes: mode · phase-order · generators · rejection · budget · ladder · answers.
cmd_intake_gate() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh intake-gate <build-dir>"
  local c="$dir/contract.md" im="$dir/intake.md"
  local decl; decl="$(hdr_get "$c" intake 2>/dev/null || true)"
  case "$decl" in
    classic*) ok "intake-gate: N/A — 'intake: classic' (pre-v0.13 interview path)."; return 0 ;;
  esac
  if [ "$decl" != "co-construct-v1" ] && [ ! -f "$im" ]; then
    ok "intake-gate: N/A — no co-construct declaration and no intake.md (legacy)."; return 0
  fi
  [ -f "$im" ] || { echo "refuse: mode" >&2; die "intake-gate: 'intake: co-construct-v1' declared but intake.md is missing."; }
  # G-I1: MODE line + ordered PHASE markers (FULL: 0 1 2 3 4 5 · LIGHT: 0 1 3 4 5)
  local mode; mode="$(sed -nE 's/^MODE: (FULL|LIGHT).*/\1/p' "$im" | head -1)"
  [ -n "$mode" ] || { echo "refuse: mode" >&2; die "intake-gate: no MODE: FULL|LIGHT line (G-I1)."; }
  local want got
  if [ "$mode" = "FULL" ]; then want="0 1 2 3 4 5"; else want="0 1 3 4 5"; fi
  got="$(sed -nE 's/^PHASE ([0-9]+) DONE.*/\1/p' "$im" | tr '\n' ' ' | sed 's/ $//')"
  [ "$got" = "$want" ] || { echo "refuse: phase-order" >&2; die "intake-gate: PHASE markers '$got' != required '$want' for $mode (G-I1)."; }
  # G-I2 (FULL): 4 generators × ≥2 OPT lines, every OPT terminating in NOW|LATER|NEVER
  if [ "$mode" = "FULL" ]; then
    local g n
    for g in premortem relax 10x adjacent; do
      n="$(grep -cE "^GEN $g: OPT .+ → (NOW|LATER|NEVER)$" "$im" || true)"
      [ "$n" -ge 2 ] || { echo "refuse: generators" >&2; die "intake-gate: generator '$g' has $n disposed OPT lines (need ≥2) (G-I2)."; }
    done
    grep -qE '^GEN [a-z0-9]+: OPT .+ → ' "$im" && grep -E '^GEN [a-z0-9]+: OPT ' "$im" | grep -vqE '→ (NOW|LATER|NEVER)$' \
      && { echo "refuse: generators" >&2; die "intake-gate: an OPT line lacks a terminal NOW|LATER|NEVER disposition (G-I2 — nothing raised may be silently dropped)."; }
  fi
  # G-I3 (HARD, decision 5): expansion was real — ≥1 LATER or NEVER disposition somewhere
  grep -qE '(→ (LATER|NEVER)$|^SCOPE (LATER|NEVER): )' "$im" \
    || { echo "refuse: rejection" >&2; die "intake-gate: zero LATER/NEVER dispositions — an all-NOW ledger is sycophancy or scope balloon (G-I3, HARD)."; }
  # G-I4: Phase-4 question budget (Q: lines after the PHASE 3 marker): ≤4 FULL / ≤2 LIGHT
  local cap q4; [ "$mode" = "FULL" ] && cap=4 || cap=2
  q4="$(awk '/^PHASE 3 DONE/{p=1;next} p && /^Q: /{n++} END{print n+0}' "$im")"
  [ "$q4" -le "$cap" ] || { echo "refuse: budget" >&2; die "intake-gate: $q4 Phase-4 questions exceed the $mode cap $cap (G-I4 — the fatigue budget is enforced, not advisory)."; }
  # G-I5: ladder count sync (COUNT equality only — no substring matching, the G13 lesson)
  local b ic cc
  for b in NOW LATER NEVER; do
    ic="$(grep -cE "^SCOPE $b: " "$im" || true)"
    cc="$(awk -v b="$b" '/^## Scope ladder/{p=1;next} p&&/^## /{p=0} p{ line=$0; gsub(/\*/,"",line); if (line ~ ("^[- ]*" b ": ")) n++ } END{print n+0}' "$c")"
    [ "$ic" = "$cc" ] || { echo "refuse: ladder" >&2; die "intake-gate: $b count mismatch — intake.md has $ic, contract '## Scope ladder' has $cc (G-I5)."; }
  done
  # G-I6 (EVIDENTIAL): ≥1 real human answer recorded
  grep -qE '^Q: .+ → A: .+' "$im" || { echo "refuse: answers" >&2; die "intake-gate: zero recorded 'Q: … → A: …' answers — a headless session cannot fake the interview (G-I6)."; }
  ok "intake-gate: co-construct interview complete ($mode; phases $got; expansion real; budget kept; ladder synced)."
}
# intake-phase <dir>: the deterministic resume pointer — prints the highest completed phase.
cmd_intake_phase() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh intake-phase <build-dir>"
  [ -f "$dir/intake.md" ] || { echo "none"; return 0; }
  sed -nE 's/^PHASE ([0-9]+) DONE.*/\1/p' "$dir/intake.md" | tail -1 | { read -r p || p=none; echo "${p:-none}"; }
}

# ── v0.13.0 S11: sketch-gate — render-while-contracting teeth (contract F-SKETCHGATE) ──
# Applicability (RC-5, widened RD-9): applies iff sketch/LEDGER exists OR a `sketch:`/`mockup:`
# header is present OR `intake: co-construct-v1` is declared (ANY facet — web takes the
# mockup/design-standard branch, non-web the Logic Map branch). Escape: `sketch: out-of-scope —
# <reason>` → N/A(0). Legacy builds (none of the triggers) → N/A(0).
# Leak tracer (RC-4, first-line-anchored so Compass's own source can never self-trip): FAIL iff
# any TRACKED file outside the state root has LINE 1 matching `^<!-- COMPASS-MOCK slug=`.
# Codes: ledger · mockup · logicmap · leak.
cmd_sketch_gate() { # <build-dir>   (run from within the target repo for the tracer)
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh sketch-gate <build-dir>"
  local c="$dir/contract.md"
  # No contract at all → nothing declared, nothing to check (legacy/minimal fixtures — INV-BC;
  # the seam must be byte-inert for builds that never opted in).
  [ -f "$c" ] || { ok "sketch-gate: N/A — no contract.md (legacy)."; return 0; }
  local skl; skl="$(hdr_get "$c" sketch 2>/dev/null || true)"
  case "$skl" in out-of-scope*) ok "sketch-gate: N/A — ${skl}."; return 0 ;; esac
  local mock decl facets
  mock="$(hdr_get "$c" mockup 2>/dev/null || true)"
  decl="$(hdr_get "$c" intake 2>/dev/null || true)"
  facets="$(hdr_get "$c" Facets 2>/dev/null || true)"
  if [ ! -f "$dir/sketch/LEDGER" ] && [ -z "$skl" ] && [ -z "$mock" ] && [ "$decl" != "co-construct-v1" ]; then
    ok "sketch-gate: N/A — no sketch artifacts or declarations (legacy)."; return 0
  fi
  # LEDGER: ≥1 render line
  grep -qE '^v[0-9]+ · ' "$dir/sketch/LEDGER" 2>/dev/null \
    || { echo "refuse: ledger" >&2; die "sketch-gate: sketch/LEDGER missing or has no 'v<N> · …' render line."; }

  # ── v0.32.0 S21 (§17-3): every artefact the LEDGER NAMES must actually be there ──
  # Before this, a mockup was checked only when the contract carried a `mockup:` header,
  # and on the web arm a bare `design-standard:` line satisfied the gate on its own. So a
  # build that rendered a mock, recorded it in its LEDGER and then DELETED the file still
  # PASSED, exit 0 — reproduced on a copy of this build before the change. Keying on the
  # LEDGER's own `file=` rather than on a contract header is what makes it unwaivable.
  # Two shapes, because the corpus holds both: a real path must exist on disk, and a
  # `doc#anchor` reference must resolve to a heading in that doc. 9 of the 14 render lines
  # across the 30 build folders are `contract.md#logic-map`; treating those as paths would
  # newly refuse 9 historical builds, which contract §12's canary forbids.
  # v0.32.0 S21c — REWRITTEN after an INDEPENDENT reviewer defeated the first version seven ways,
  # every one reproduced here before the rewrite: a render line with NO `file=` skipped the check
  # entirely (so "unwaivable" was false); a LEDGER with no trailing newline dropped its last line;
  # `.HTML` skipped the marker and banner because the extension match was case-sensitive; `../`
  # escaped the build dir, so one mock anywhere satisfied every build; a greedy `.*` read only the
  # LAST `file=`, so appending a valid anchor laundered a missing mock; an anchor matched by PREFIX;
  # and a heading inside a code fence counted as a heading. It also forked one `sed` PER LINE —
  # 59.67s on a 20,000-line ledger, over this build's own deterministic perf budget.
  # ONE awk pass now extracts every token; the loop forks nothing per line.
  local _lkind _lf _ldoc _lanc _lhead _lfl
  # No `|| [ -n "$_lkind" ]` guard here, deliberately: this loop reads AWK's output, and awk always
  # terminates what it prints. The missing-trailing-newline defect lived in reading the LEDGER
  # directly, and awk is what fixes it — a guard here would imply a protection it does not provide.
  # Mutation-checked: removing such a guard changed nothing, which is how it was found to be dead.
  while read -r _lkind _lf; do
    [ -n "$_lkind" ] || continue
    if [ "$_lkind" = "NOFILE" ]; then
      echo "refuse: ledger-artefact" >&2
      die "sketch-gate: sketch/LEDGER render line $_lf names no artefact (no 'file=' field). A render line recording no artefact is not evidence that one was ever made."
    fi
    # Stay inside the build's own state root. Otherwise a single mock anywhere on disk satisfies
    # every build that points at it, which is the same defect as no check at all.
    case "$_lf" in
      /*|../*|*/../*|*/..) echo "refuse: ledger-artefact" >&2
        die "sketch-gate: LEDGER names '$_lf', which leaves the build directory. Sketch artefacts live under the build's own state root." ;;
    esac
    case "$_lf" in
      *"#"*)
        _ldoc="${_lf%%#*}"; _lanc="${_lf#*#}"
        [ -f "$dir/$_ldoc" ] || { echo "refuse: ledger-artefact" >&2; die "sketch-gate: LEDGER names '$_lf' but '$_ldoc' does not exist."; }
        # the anchor is stripped to [A-Za-z0-9 _] BEFORE it reaches a pattern — an unescaped
        # variable inside a regex is a recurring defect class in this file's own gates.
        _lhead="$(printf '%s' "$_lanc" | tr '-' ' ' | tr -cd 'A-Za-z0-9 _')"
        [ -n "$_lhead" ] || { echo "refuse: ledger-artefact" >&2; die "sketch-gate: LEDGER names '$_lf' but '#$_lanc' is not a usable heading anchor."; }
        # EXACT heading, and never one inside a code fence. Prefix matching let `#l` resolve to
        # `## Logic Map`, and a fenced example heading counted as the real thing.
        awk -v h="$_lhead" '
          /^```/ { f = !f; next }
          !f && tolower($0) ~ "^#+[ \t]+" tolower(h) "[ \t]*$" { found = 1 }
          END { exit found ? 0 : 1 }' "$dir/$_ldoc" 2>/dev/null \
          || { echo "refuse: ledger-artefact" >&2; die "sketch-gate: LEDGER names '$_lf' but '$_ldoc' carries no heading '#$_lanc' outside a code fence."; }
        ;;
      *)
        [ -f "$dir/$_lf" ] || { echo "refuse: ledger-artefact" >&2; die "sketch-gate: LEDGER names artefact '$_lf' but the file is missing — a recorded sketch that is not on disk is not evidence."; }
        _lfl="$(printf '%s' "$_lf" | tr 'A-Z' 'a-z')"
        case "$_lfl" in
          *.html|*.htm)
            head -1 "$dir/$_lf" 2>/dev/null | grep -q '^<!-- COMPASS-MOCK slug=' \
              || { echo "refuse: mockup" >&2; die "sketch-gate: LEDGER artefact '$_lf' lacks the line-1 COMPASS-MOCK marker."; }
            grep -q 'THROWAWAY WIREFRAME' "$dir/$_lf" 2>/dev/null \
              || { echo "refuse: mockup" >&2; die "sketch-gate: LEDGER artefact '$_lf' lacks the visible THROWAWAY banner."; }
            ;;
          *)
            # a non-HTML artefact has no marker convention, so the only honest check is that it
            # holds something. A zero-byte file is a recorded sketch that was never made.
            [ -s "$dir/$_lf" ] || { echo "refuse: ledger-artefact" >&2; die "sketch-gate: LEDGER artefact '$_lf' is EMPTY. A zero-byte artefact is not a sketch."; }
            ;;
        esac
        ;;
    esac
  done <<EOF
$(awk '
  /^v[0-9]+/ && index($0, "·") > 0 {
    n = 0
    for (i = 1; i <= NF; i++) if ($i ~ /^file=/) { t = substr($i, 6); if (substr(t, length(t)-1) == "·") t = substr(t, 1, length(t)-2); if (t != "") { print "FILE " t; n++ } }
    if (n == 0) print "NOFILE " NR
  }' "$dir/sketch/LEDGER" 2>/dev/null)
EOF
  case "$facets" in
    *web*)
      local ok_spec=""
      if [ -n "$mock" ]; then
        local mp; mp="$dir/$(printf '%s' "$mock" | sed -E 's/ \(ACCEPTED.*//')"
        [ -f "$mp" ] || { echo "refuse: mockup" >&2; die "sketch-gate: contract names mockup '$mock' but the file is missing."; }
        head -1 "$mp" | grep -q '^<!-- COMPASS-MOCK slug=' || { echo "refuse: mockup" >&2; die "sketch-gate: mockup lacks the line-1 COMPASS-MOCK marker."; }
        grep -q 'THROWAWAY WIREFRAME' "$mp" || { echo "refuse: mockup" >&2; die "sketch-gate: mockup lacks the visible THROWAWAY banner."; }
        ok_spec=1
      fi
      [ -z "$ok_spec" ] && hdr_get "$c" design-standard >/dev/null 2>&1 && ok_spec=1   # decision 6: both paths valid
      [ -n "$ok_spec" ] || { echo "refuse: mockup" >&2; die "sketch-gate: web build needs an ACCEPTED mockup (marker+banner) OR a 'design-standard:' line (decision 6)."; }
      ;;
  esac
  # ── v0.32.0 S21 (§17-4): the Logic Map check ran in the `*)` arm of the case above, so
  # ANY build whose Facets line merely CONTAINED the string "web" skipped it entirely —
  # including three that say "no web surface", because the match is a substring over free
  # prose. It now runs for both arms. Blast radius measured BEFORE the change: 14 of 30
  # build folders reach this point and all 14 already carry a Logic Map with at least one
  # edge, so this refuses none of them (contract §12's canary).
  awk '/^## Logic Map/{p=1;next} p&&/^## /{p=0} p' "$c" | awk '/^```mermaid/{m=1;next} m&&/^```/{m=0} m' | grep -q -- '-->' \
    || { echo "refuse: logicmap" >&2; die "sketch-gate: a co-construct build needs a '## Logic Map' mermaid fence with >=1 edge (RD-9 — a build cannot silently skip its logic map)."; }
  # leak tracer — tracked files only, line-1 anchored, state root excluded
  local hits=""
  if git rev-parse --git-dir >/dev/null 2>&1; then
    local f
    while IFS= read -r f; do
      case "$f" in .claude/builds/*) continue ;; esac
      [ -f "$f" ] || continue
      head -1 "$f" 2>/dev/null | grep -q '^<!-- COMPASS-MOCK slug=' && hits="$hits $f"
    done <<EOF
$(git ls-files)
EOF
  fi
  [ -z "$hits" ] || { echo "refuse: leak" >&2; die "sketch-gate: THROWAWAY mockup leaked into tracked product source:$hits (the marker is the tracer — mockups live only under the state root)."; }
  ok "sketch-gate: sketch artifacts sound; no tracked line-1 COMPASS-MOCK leak."
}

# ── v0.13.0 S14: *_match helpers — each SKILL-pinned template's acceptance rule lives HERE, ──
# used by the gates' parsing and driven directly by smoke via `__match` with map-instantiated
# templates (INV-TEMPLATES): the pinned template text and the parser physically cannot drift.
round_receipt_match() { # stdin: one round-receipt block
  local b; b="$(cat)"
  printf '%s\n' "$b" | head -1 | grep -qE '^## RECEIPT — post-ship-critique · round [0-9]+ · (CLEAN|MATERIAL)$' || return 1
  printf '%s\n' "$b" | grep -qE '^- \[x\] LIVE-TARGET: .+' || return 1
  printf '%s\n' "$b" | grep -qE '^\- \[x\].*`.*`.*→' || return 1
}
user_accepted_match() { # stdin: one line
  local l; l="$(cat)"; l="$(norm_line "$l")"
  printf '%s' "$l" | grep -qE '^[- ]*user-accepted: ship-as-is — .+ · .+$'
}
coldcritic_receipt_match() { # stdin: one cold-critic block
  local b; b="$(cat)"
  printf '%s\n' "$b" | head -1 | grep -qE '^## RECEIPT — cold-critic · (GO|NO-GO|HUMAN-GO · ".+") · tree=[a-z0-9]+$' || return 1
  printf '%s\n' "$b" | grep -qE '^- \[x\] clean-tree: git status --porcelain empty$' || return 1
}
postship_box_match() { # stdin: one receipt box line
  local l; l="$(cat)"; l="$(norm_line "$l")"
  printf '%s' "$l" | grep -qE '^[- ]*\[x\] post-ship-loop: (on \(clean [0-9]+ / cap [0-9]+\)|off — .+)$'
}
intake_box_match() { # stdin
  local l; l="$(cat)"; l="$(norm_line "$l")"
  printf '%s' "$l" | grep -qE '^[- ]*\[x\] intake-gate: compass.sh intake-gate .+ → 0$'
}
observation_box_match() { # stdin: the ship receipt's observation box line
  local l; l="$(cat)"; l="$(norm_line "$l")"
  printf '%s' "$l" | grep -qE '^[- ]*\[x\] observation (web|pipeline|library): `.+` → evidence/round-1/.+$'
}
sketch_box_match() { # stdin
  local l; l="$(cat)"; l="$(norm_line "$l")"
  printf '%s' "$l" | grep -qE '^[- ]*\[x\] sketch-gate: compass.sh sketch-gate .+ → 0$'
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

# ── program-continuity ledger (v0.22.0 · contract 7a) ────────────────────────
# PROGRAM.md (gitignored, one per repo, hand-editable local state) grammar:
#   # Program — <name>
#   vision: <text>
#   current: <slug>
#   phase <K>/<N> · <slug> · status=<planned|in-flight|shipped>[ · <tag>]
# The "really shipped?" signal is a REAL release tag bound to the built version — NEVER the
# hand-editable status line (review-plan RP1-C1). All reads are guard-first + set-e-safe (INV-BC).
_program_file() { printf '%s/PROGRAM.md' "$(state_root)"; }
_program_name() { [ -f "${1:-}" ] && sed -n '1s/^# Program — //p' "$1" 2>/dev/null | sed 's/[[:space:]]*$//' || true; }
_program_rows() { [ -f "${1:-}" ] && grep -E '^phase [0-9]+/[0-9]+ · ' "$1" 2>/dev/null || true; }
_row_slug()   { printf '%s' "$1" | sed -E 's/^phase [0-9]+\/[0-9]+ · ([^ ·]+) · .*/\1/'; }
_row_status() { printf '%s' "$1" | sed -nE 's/.*· status=([a-z-]+).*/\1/p'; }
_row_tag()    { printf '%s' "$1" | sed -nE 's/.*· status=[a-z-]+ · (.+)$/\1/p'; }
_program_current() { [ -f "${1:-}" ] && sed -nE 's/^current:[[:space:]]*(.*)$/\1/p' "$1" 2>/dev/null | head -n1 | sed 's/[[:space:]]*$//' || true; }
_program_first_unshipped() { # <file>  → prints first non-shipped slug (empty if all shipped)
  local r st
  while IFS= read -r r; do [ -n "$r" ] || continue
    st="$(_row_status "$r")"; [ "$st" = shipped ] && continue
    _row_slug "$r"; return 0
  done < <(_program_rows "${1:-}"); return 0
}
# _tag_is_real_and_bound <tag>: exit 0 iff <tag> is a REAL tag (rejects HEAD/branch/SHA) whose
# committed plugin.json version == ${tag#v} (the tag→build binding). FAIL-CLOSED on any git error.
_tag_is_real_and_bound() { # <tag>
  local tag="${1:-}"; [ -n "$tag" ] || return 1
  git rev-parse --git-dir >/dev/null 2>&1 || return 1
  [ -n "$(git tag -l "$tag" 2>/dev/null)" ] || return 1
  git rev-parse --verify -q "refs/tags/${tag}^{commit}" >/dev/null 2>&1 || return 1
  local ver
  ver="$(git show "${tag}:plugins/compass/.claude-plugin/plugin.json" 2>/dev/null \
        | sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n1)"
  [ -n "$ver" ] && [ "$ver" = "${tag#v}" ]
}

cmd_program_init() { # <name>
  local name="${1:-}"; [ -n "$name" ] || die "program-init: usage: program-init <name>"
  local f; f="$(_program_file)"
  if [ -f "$f" ]; then
    local existing; existing="$(_program_name "$f")"
    [ "$existing" = "$name" ] || die "program-init: PROGRAM.md already exists for program '$existing' (one per repo)."
    ok "program-init: '$name' already initialized (idempotent no-op)."; return 0
  fi
  mkdir -p "$(dirname "$f")"
  with_lock program-ledger _program_write "$f" "$(printf '# Program — %s\nvision: (set the program vision)\ncurrent: \n' "$name")"
  ok "program-init: created $(_program_file) for program '$name'."
}
# _program_write <file> <content>  — the only writer; runs inside with_lock; RETURNs, never die()s (M12/BUG-3).
_program_write() { printf '%s\n' "$2" | atomic_write "$1"; return 0; }

cmd_program_next() { # <name>  → prints the first non-shipped slug (exit 0); "COMPLETE" if all shipped; die if no/mismatched ledger
  local name="${1:-}"; [ -n "$name" ] || die "program-next: usage: program-next <name>"
  local f; f="$(_program_file)"
  [ -f "$f" ] || die "program-next: no program ledger (run program-init)."
  local ename; ename="$(_program_name "$f")"
  [ "$ename" = "$name" ] || die "program-next: ledger is for '$ename', not '$name'."
  local nxt; nxt="$(_program_first_unshipped "$f")"
  if [ -n "$nxt" ]; then printf '%s\n' "$nxt"; else printf 'COMPLETE\n'; fi
  return 0
}

cmd_program_ledger() { # <name>  — render + cross-check (real-tag+binding staleness + structural invariants, M13). exit≠0 + WARN on any violation.
  local name="${1:-}"; [ -n "$name" ] || die "program-ledger: usage: program-ledger <name>"
  local f; f="$(_program_file)"
  [ -f "$f" ] || die "program-ledger: no program ledger (run program-init)."
  local ename; ename="$(_program_name "$f")"
  [ "$ename" = "$name" ] || die "program-ledger: ledger is for '$ename', not '$name'."
  git rev-parse --git-dir >/dev/null 2>&1 || { echo "COMPASS-LEDGER: FLAG — not in a git repo, cannot verify tags (fail-closed)." >&2; return 1; }
  local flags=0 seen_slugs="" seen_tags="" inflight=0 rows_n=0 row slug status tag kn k expn=""
  # render header
  sed -n '1,3p' "$f"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    rows_n=$((rows_n+1))
    slug="$(_row_slug "$row")"; status="$(_row_status "$row")"; tag="$(_row_tag "$row")"
    # R1-F1 fix: validate EVERY row's K and N, not just the last row's denominator — a hand-edited
    # ledger whose rows disagree on the total (or skip a phase) previously rendered clean.
    k="$(printf '%s' "$row" | sed -E 's#^phase ([0-9]+)/[0-9]+ · .*#\1#')"
    kn="$(printf '%s' "$row" | sed -E 's#^phase [0-9]+/([0-9]+) · .*#\1#')"
    [ "$rows_n" = 1 ] && expn="$kn"    # the FIRST row pins the program's declared total N
    [ "$kn" != "$expn" ] && { echo "COMPASS-LEDGER: FLAG — row '$slug' declares total /$kn but the program total is /$expn (rows disagree)." >&2; flags=$((flags+1)); }
    [ "$k" != "$rows_n" ] && { echo "COMPASS-LEDGER: FLAG — row '$slug' is phase $k but appears at position $rows_n (out of order / gap)." >&2; flags=$((flags+1)); }
    printf '  %s\n' "$row"
    # dup-slug (M13)
    printf '%s\n' "$seen_slugs" | grep -qxF "$slug" && { echo "COMPASS-LEDGER: FLAG — duplicate slug '$slug'." >&2; flags=$((flags+1)); }
    seen_slugs="$seen_slugs
$slug"
    case "$status" in
      shipped)
        if [ -z "$tag" ]; then echo "COMPASS-LEDGER: FLAG — shipped row '$slug' has no tag (fail-closed)." >&2; flags=$((flags+1));
        elif ! _tag_is_real_and_bound "$tag"; then echo "COMPASS-LEDGER: FLAG — shipped row '$slug' tag '$tag' is not a real bound release tag (forged/stale)." >&2; flags=$((flags+1));
        else
          printf '%s\n' "$seen_tags" | grep -qxF "$tag" && { echo "COMPASS-LEDGER: FLAG — tag '$tag' reused across shipped rows (borrowed tag)." >&2; flags=$((flags+1)); }
          seen_tags="$seen_tags
$tag"
        fi ;;
      in-flight) inflight=$((inflight+1)) ;;
    esac
  done < <(_program_rows "$f")
  # >1 in-flight (M13)
  [ "$inflight" -gt 1 ] && { echo "COMPASS-LEDGER: FLAG — $inflight rows are in-flight (expected ≤1)." >&2; flags=$((flags+1)); }
  # K/N total == actual row count (M13; R1-F1: uses the first-row-pinned total, and every row's N
  # was already checked equal to it above — so an inconsistent-denominator ledger can't pass).
  [ -n "$expn" ] && [ "$expn" != "$rows_n" ] && { echo "COMPASS-LEDGER: FLAG — declared phase total $expn ≠ actual row count $rows_n." >&2; flags=$((flags+1)); }
  # current: == first non-shipped (M13)
  local cur first; cur="$(_program_current "$f")"; first="$(_program_first_unshipped "$f")"
  [ "$cur" != "$first" ] && { echo "COMPASS-LEDGER: FLAG — current '$cur' ≠ first non-shipped '$first'." >&2; flags=$((flags+1)); }
  [ "$flags" -eq 0 ] || { echo "COMPASS-LEDGER: $flags FLAG(s) — ledger is not trustworthy." >&2; return 1; }
  ok "program-ledger: '$name' consistent ($rows_n rows, all shipped tags real+bound, structure valid)."
}

# program-advance <name> <slug> <tag> — mark <slug> shipped <tag> + advance current: to the next
# unshipped. GUARD + every die() run OUTSIDE with_lock (M12/BUG-3: a die inside the lock skips the
# RETURN-trap and leaks the mutex). Guard = (1)+(2) real tag bound to THIS build · (2b) tag not
# already on another shipped row · (3) dir-conditional lifecycle-audit. Ledger byte-unchanged unless
# the whole guard passes (guard precedes the only write). Idempotent: an already-shipped row = no-op.
cmd_program_advance() { # <name> <slug> <tag>
  local name="${1:-}" slug="${2:-}" tag="${3:-}"
  [ -n "$name" ] && [ -n "$slug" ] && [ -n "$tag" ] || die "program-advance: usage: program-advance <name> <slug> <tag>"
  local f; f="$(_program_file)"
  [ -f "$f" ] || die "program-advance: no program ledger (run program-init)."
  local ename; ename="$(_program_name "$f")"
  [ "$ename" = "$name" ] || die "program-advance: ledger is for '$ename', not '$name'."

  # locate the target row + its status; the slug MUST be a real row.
  local r cur_status="" found=0
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    [ "$(_row_slug "$r")" = "$slug" ] || continue
    found=1; cur_status="$(_row_status "$r")"; break
  done < <(_program_rows "$f")
  [ "$found" = 1 ] || die "program-advance: slug '$slug' is not a row in program '$name'."

  # IDEMPOTENT (M14): an already-shipped row is a no-op — a second advance leaves the ledger
  # byte-identical (cksum equal) and current: unmoved. Short-circuit BEFORE the guard.
  if [ "$cur_status" = shipped ]; then
    ok "program-advance: '$slug' already shipped (idempotent no-op)."; return 0
  fi

  # ── GUARD (all OUTSIDE with_lock; each failure die()s HERE, never inside the lock — M12/BUG-3) ──
  # (1)+(2) a REAL tag (rejects HEAD/branch/SHA) bound to THIS build (committed version == ${tag#v}).
  _tag_is_real_and_bound "$tag" \
    || die "program-advance: '$tag' is not a real release tag bound to this build (need a tag whose committed plugin.json version == \${tag#v})."
  # (2b) tag-uniqueness-per-shipped-row (RP2-M2): the tag must not already sit on ANOTHER shipped row.
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    [ "$(_row_status "$r")" = shipped ] || continue
    [ "$(_row_slug "$r")" = "$slug" ] && continue
    [ "$(_row_tag "$r")" = "$tag" ] \
      && die "program-advance: tag '$tag' is already recorded on shipped row '$(_row_slug "$r")' (borrowed/duplicate tag)."
  done < <(_program_rows "$f")
  # (3) dir-conditional AND: if THIS build's dir is present, its lifecycle-audit SHIPPED must pass too.
  #     A SUBSHELL catches lifecycle-audit's internal die() as a non-zero exit (never fatal to us).
  local dir; dir="$(state_root)/$slug"
  if [ -d "$dir" ]; then
    ( cmd_lifecycle_audit "$dir" SHIPPED >/dev/null 2>&1 ) \
      || die "program-advance: build dir '$slug' present but lifecycle-audit SHIPPED failed (chain/ship not complete)."
  fi

  # ── PASS → the ONLY write, under the lock; the locked helper RETURNs, never die()s (M12/BUG-3). ──
  with_lock program-ledger _program_advance_locked "$f" "$slug" "$tag" \
    || die "program-advance: ledger write failed (no change applied)."
  ok "program-advance: '$slug' → shipped $tag; current advanced to the next unshipped."
}

# _program_advance_locked <file> <slug> <tag> — pure read-modify-write, runs INSIDE with_lock;
# RETURNs non-zero on any internal error and NEVER die()s (a die here skips with_lock's RETURN-trap
# and leaks the mutex — BUG-3). Mirrors _budget_check_locked / _program_write.
_program_advance_locked() { # <file> <slug> <tag>
  local f="$1" slug="$2" tag="$3" tmp tmp2 nxt line rewrote=0 prefix
  tmp="$(mktemp "${f}.XXXXXX")" || return 1
  # R1-F2 fix: rewrite the target row by EXACT-slug STRING match — never a regex built from $slug
  # (a crafted slug like '.*' previously matched EVERY row via the sed pattern). $slug/$tag are only
  # ever compared or printed literally, never interpolated into a pattern or eval'd.
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$rewrote" = 0 ] && printf '%s' "$line" | grep -qE '^phase [0-9]+/[0-9]+ · ' && [ "$(_row_slug "$line")" = "$slug" ]; then
      prefix="${line%% · status=*}"                         # 'phase K/N · <slug>' — literal glob strip, no regex
      printf '%s · status=shipped · %s\n' "$prefix" "$tag" >> "$tmp"
      rewrote=1
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$f"
  [ "$rewrote" = 1 ] || { rm -f "$tmp"; return 1; }          # slug not a row (guard should have caught) — no write
  # recompute current: = first non-shipped AFTER the rewrite (empty when all shipped).
  nxt="$(_program_first_unshipped "$tmp")"
  tmp2="$(mktemp "${f}.XXXXXX")" || { rm -f "$tmp"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      current:*) printf 'current: %s\n' "$nxt" >> "$tmp2" ;;
      *)         printf '%s\n' "$line"        >> "$tmp2" ;;
    esac
  done < "$tmp"
  rm -f "$tmp"
  mv -f "$tmp2" "$f" || { rm -f "$tmp2"; return 1; }
  return 0
}

# mutation-check <build-dir> — RUN each `mutation:` recipe from the build's receipts.md and prove
# the gate it names actually BITES: red PASSES on a pristine copy (control) then FAILS after the
# break (mutant killed). Everything happens in an ephemeral system-temp sandbox cd'd away from the
# live tree; a live-file cksum backstop DETECTS (fail-closed die) any break that escaped the sandbox.
# guard-first N/A (INV-BC): no receipts.md / no `mutation:` recipes → exit 0, no output.
cmd_mutation_check() { # <build-dir>
  local dir="${1:-}"
  [ -n "$dir" ] || die "mutation-check: usage: mutation-check <build-dir>"
  [ -f "$dir/receipts.md" ] || return 0            # guard-first, BEFORE any read (set -e safe)
  local f="$dir/receipts.md" recipes
  recipes="$(grep '^mutation:' "$f" 2>/dev/null || true)"
  [ -n "$recipes" ] || return 0                    # no recipes → N/A-pass
  # RP2-M4: resolve main_root to an ABSOLUTE path NOW, while still in the git repo — NEVER call a
  # git-dependent helper after the cd into the (non-git) sandbox inside _mutation_recipe_body.
  local mainroot; mainroot="$(main_root)" || die "mutation-check: cannot resolve main_root."
  local rc_all=0 line code
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if ( _mutation_recipe_body "$mainroot" "$line" ); then code=0; else code=$?; fi   # per-recipe SUBSHELL → its EXIT trap cleans the sandbox (if/else = set -e exempt)
    case "$code" in
      0) : ;;
      2) die "mutation-check: fail-closed — malformed recipe / missing file / the LIVE tree was touched (see message above)." ;;
      *) rc_all=1 ;;
    esac
  done <<EOF
$recipes
EOF
  [ "$rc_all" = 0 ] || die "mutation-check: a recipe did NOT bite (broken-control or decorative red — see above)."
  ok "mutation-check: all recipes bite (control-green → mutant-red; live tree cksum-verified untouched)."
}

# _mutation_recipe_body <mainroot> <recipe-line> — MUST be called inside a ( ) subshell (the caller
# does), so cd + the sandbox-cleanup EXIT trap are isolated per recipe. Exit: 0=bites · 1=did-not-bite
# (broken-control / decorative) · 2=fail-closed fatal (malformed / missing file / LIVE tree touched).
_mutation_recipe_body() { # <mainroot> <recipe-line>
  local mainroot="$1" line="$2"
  local body inv="" file="" brk="" red="" fld
  body="$(printf '%s' "$line" | sed -E 's/^mutation:[[:space:]]*//')"
  # fields are separated by " · " (the unusual delimiter avoids collision with command text).
  # Split in bash via ANSI-C quoting (which DOES emit the real U+00B7 bytes) — NOT a sed \xHH
  # escape, which sed treats literally and would fail to match the middle dot.
  local DELIM; DELIM=$' \xc2\xb7 '
  while IFS= read -r fld; do
    case "$fld" in
      file=*)  file="${fld#file=}" ;;
      break=*) brk="${fld#break=}" ;;
      red=*)   red="${fld#red=}" ;;
      "")      : ;;
      *)       [ -z "$inv" ] && inv="$fld" || : ;;   # first non key=val field = the INV-id
    esac
  done <<< "${body//"$DELIM"/$'\n'}"
  [ -n "$inv" ] || inv="?"
  { [ -n "$file" ] && [ -n "$brk" ] && [ -n "$red" ]; } \
    || { echo "mutation-check: malformed recipe (need file= break= red=): $line" >&2; exit 2; }
  local src="$mainroot/$file"
  [ -f "$src" ] || { echo "mutation-check: recipe file not found: $src" >&2; exit 2; }
  local sandbox; sandbox="$(mktemp -d)" || { echo "mutation-check: mktemp failed" >&2; exit 2; }
  trap 'rm -rf "$sandbox"' EXIT
  local dst="$sandbox/$file"
  mkdir -p "$(dirname "$dst")"; cp "$src" "$dst" || { echo "mutation-check: copy failed" >&2; exit 2; }
  local live_ck; live_ck="$(cksum "$src")"
  local qdst; qdst="$(printf '%q' "$dst")"   # shell-quote the {} substitution (sandbox is space-free system temp)
  local brk_cmd red_cmd                       # replace every literal {} with the quoted copy path (bash expansion — no sed-delimiter clash with command text)
  brk_cmd="${brk//\{\}/$qdst}"
  red_cmd="${red//\{\}/$qdst}"
  cd "$sandbox" || { echo "mutation-check: cannot cd sandbox" >&2; exit 2; }
  local control_rc mutant_rc
  # if/then/else captures the exit code WITHOUT tripping set -e (the mutant red is EXPECTED to fail).
  if eval "$red_cmd" >/dev/null 2>&1; then control_rc=0; else control_rc=$?; fi   # (control) red on the PRISTINE copy
  eval "$brk_cmd" >/dev/null 2>&1 || true                                        # apply the break to the copy
  if eval "$red_cmd" >/dev/null 2>&1; then mutant_rc=0; else mutant_rc=$?; fi     # (mutant) red after the break
  # (backstop) ALWAYS re-cksum the LIVE file — a break that escaped the sandbox is DETECTED and dies
  # fail-closed, TAKING PRECEDENCE over the bite verdict (RP2-M3 / N3: detect-and-die, not restore).
  if [ "$(cksum "$src")" != "$live_ck" ]; then
    echo "mutation-check: [$inv] the LIVE tree file changed during the recipe ($src) — break escaped the sandbox (fail-closed detection)." >&2
    exit 2
  fi
  [ "$control_rc" = 0 ] || { echo "mutation-check: [$inv] red FAILS on the PRISTINE copy (broken/decorative control) — $file" >&2; exit 1; }
  [ "$mutant_rc" != 0 ] || { echo "mutation-check: [$inv] red still PASSES after the break (decorative — mutant not killed) — $file" >&2; exit 1; }
  echo "mutation-check: [$inv] bites (control-green → mutant-red; live tree cksum-verified untouched) — $file"
  exit 0
}

# redgreen-check <build-dir> — honor-level RED-first-evidence gate (INV-REDGREEN). A build that adds
# a test (adds-test: yes) must carry a REAL red-green: attestation (the failing test + why it failed
# before the fix). Guard-first N/A (INV-BC): no receipts.md → exit 0, no output. adds-test absent/no →
# N/A. Per the free-text-gate lesson [[gate-freetext-softpass-lesson]]: the INV name is DECOUPLED from
# the grepped literal, real vocabulary is ACCEPTED, only empty/placeholder is rejected (_attest_real),
# and the SUBSTANCE is re-challenged at the review stage (W-D5) — not soft-passed here, not ground on.
cmd_redgreen_check() { # <build-dir>
  local dir="${1:-}"
  [ -n "$dir" ] || die "redgreen-check: usage: redgreen-check <build-dir>"
  [ -f "$dir/receipts.md" ] || return 0            # guard-first, BEFORE any read (set -e safe)
  local f="$dir/receipts.md"
  # adds-test: fail-SAFE union — a new-test build is one where ANY anchored adds-test line reads yes
  # (a stale `no` stub above a real `yes` cannot hide it). absent / all-no → N/A-pass (byte-inert).
  local at_vals adds=no
  # anchor tolerates an optional list marker + a receipt checkbox: matches `adds-test: yes`,
  # `- adds-test: yes`, AND the receipt-box form `- [x] adds-test: yes`.
  # R1-F3 fix: guard the read (an unreadable receipts.md must not crash under set -e + pipefail — mirror mutation-check).
  at_vals="$( { sed -nE 's/^[[:space:]]*[-*]?[[:space:]]*(\[[ xX]\])?[[:space:]]*adds-test:[[:space:]]*([A-Za-z]+).*/\2/p' "$f" 2>/dev/null || true; } | tr 'A-Z' 'a-z')"
  printf '%s\n' "$at_vals" | grep -qx yes && adds=yes
  [ "$adds" = yes ] || return 0
  # adds-test: yes → at least ONE red-green line must carry a REAL (non-empty, non-placeholder) value.
  local found=0 rgline
  while IFS= read -r rgline; do
    [ -n "$rgline" ] || continue
    if _attest_real "$rgline"; then found=1; break; fi
  done <<EOF
$( { sed -nE 's/^[[:space:]]*[-*]?[[:space:]]*(\[[ xX]\])?[[:space:]]*red-green:[[:space:]]*(.*)$/\2/p' "$f" 2>/dev/null || true; } )
EOF
  [ "$found" = 1 ] || die "redgreen-check: adds-test: yes but no real red-green: evidence — record the RED-first proof (the failing test + why it failed before the fix; empty / 'N/A' / 'TODO' is not evidence). HARD STOP — never a soft pass. (The review stage re-challenges the substance.)"
  ok "redgreen-check: adds-test: yes with a real red-green: attestation present (substance re-challenged at review)."
}

# ── v0.23.0 DORA operability ledger (append-only, gitignored) ────────────────────────────────
_dora_file() { printf '%s/DORA.md' "$(state_root)"; }

# dora-record <build-dir> <outcome> — append ONE metadata row per terminal exit. ADDITIVE (never
# changes an existing flow's exit/stdout) + never blocks a terminal exit. Guard+die OUTSIDE the lock;
# the locked helper does the (slug,outcome,sig) dup-check INSIDE the lock and only RETURNs (BUG-3).
cmd_dora_record() { # <build-dir> <outcome>
  local dir="${1:-}" outcome="${2:-}"
  [ -n "$dir" ] || die "dora-record: usage: dora-record <build-dir> <outcome>"
  case "$outcome" in SHIPPED|CLOSED|ROLLED-BACK) : ;; *) die "dora-record: outcome must be SHIPPED|CLOSED|ROLLED-BACK (got '$outcome')." ;; esac
  local slug; slug="$(basename "$dir")"
  local f; f="$(_dora_file)"
  local be="$dir/budget.env" rc="$dir/receipts.md" scl="$dir/session-chain.log"
  local stages="NA" rounds="NA" cyc="NA" sig ts sg r first
  [ -r "$be" ] && { sg="$(_be_get "$be" spent_stages 2>/dev/null || true)"; _is_num "$sg" && stages="$sg"; }
  [ -r "$rc" ] && { r="$(grep -c 'review-build.*round' "$rc" 2>/dev/null || true)"; _is_num "$r" && rounds="$r"; }
  ts="$(_now_epoch)"
  if [ -r "$scl" ]; then first="$(sed -n '1s/^\([0-9][0-9]*\)|.*/\1/p' "$scl" 2>/dev/null || true)"; if _is_num "$first"; then first=$((10#$first)); if [ "$first" -gt 0 ] && [ "$ts" -ge "$first" ]; then cyc=$(( ts - first )); fi; fi; fi   # base-10 (m2: no octal on 08/09) + no negative cycle on clock skew (m3)
  sig="$(git rev-parse --short=12 HEAD 2>/dev/null || printf 'nogit')"; [ -n "$sig" ] || sig="nogit"
  local row="dora: $slug · outcome=$outcome · stages=$stages · rounds=$rounds · cycle=$cyc · sig=$sig · ts=$ts"
  # dora-record must NEVER stall a terminal exit (review-build M1): a BOUNDED, self-reaping best-effort
  # lock instead of the 30s-blocking with_lock. A real DORA append is instant, so a lock still held
  # after ~2s is dead → reap it once; still contended → SKIP (additive, best-effort). Caps close at ~2s.
  local lock; lock="$(locks_dir)/.dora.lock"; mkdir -p "$(dirname "$lock")" 2>/dev/null || true
  local got=0 tries=0
  while [ "$tries" -lt 60 ]; do
    if mkdir "$lock" 2>/dev/null; then got=1; break; fi
    # reap ONLY a genuinely-stale lock (age ≥ 5s): a real append is instant, so a >5s-held lock is dead;
    # a racing winner's FRESH lock is NOT reaped, so mutual exclusion holds (RB-R2 — blind rmdir raced 2 writers in).
    if [ -d "$lock" ] && [ "$(( $(_now_epoch) - $(_lock_mtime "$lock") ))" -ge 5 ]; then rmdir "$lock" 2>/dev/null || true; fi
    tries=$((tries+1)); sleep 0.05
  done
  [ "$got" = 1 ] || { ok "dora-record: skipped ($slug outcome=$outcome — ledger contended; best-effort, no terminal-exit stall)."; return 0; }
  # shellcheck disable=SC2064
  trap "rmdir '$lock' 2>/dev/null || true" RETURN
  _dora_record_locked "$f" "$slug" "$outcome" "$sig" "$row" || { rmdir "$lock" 2>/dev/null || true; trap - RETURN; die "dora-record: ledger write failed."; }
  rmdir "$lock" 2>/dev/null || true; trap - RETURN
  ok "dora-record: $slug outcome=$outcome (cycle=$cyc sig=$sig)."
}
# _dora_record_locked <file> <slug> <outcome> <sig> <row> — INSIDE with_lock; dup-check per
# (slug,outcome,sig) then append; RETURNs only, never die()s (BUG-3). A DORA append is NOT
# idempotent-by-construction, so the dup-check MUST be under the lock (review-plan M4).
_dora_record_locked() { # <file> <slug> <outcome> <sig> <row>
  local f="$1" slug="$2" outcome="$3" sig="$4" row="$5"
  [ -f "$f" ] || printf '# DORA — compass\n' > "$f" || return 1
  if grep -F "dora: $slug · outcome=$outcome · " "$f" 2>/dev/null | grep -qF "· sig=$sig · "; then
    return 0    # exact (slug,outcome,sig) already recorded → idempotent no-op
  fi
  printf '%s\n' "$row" >> "$f" || return 1
  return 0
}

# dora-ledger — render + aggregates (count, ship-rate). Guard-first N/A (no/unreadable DORA.md →
# exit 0, no output). A malformed row → FLAG (fail-closed). 0 rows → ship-rate NA (no div-by-zero).
cmd_dora_ledger() {
  local f; f="$(_dora_file)"
  { [ -f "$f" ] && [ -r "$f" ]; } || return 0    # a regular, readable file only — a directory/unreadable DORA.md → N/A (review-build agent2 MINOR)
  local total=0 shipped=0 malformed=0 line seen="" key
  sed -n '1p' "$f"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "dora: "*) : ;; *) continue ;; esac
    case "$line" in
      *"· outcome="*" · stages="*" · rounds="*" · cycle="*" · sig="*" · ts="*) : ;;
      *) malformed=1 ;;
    esac
    printf '  %s\n' "$line"
    # DEDUP-ON-READ by (slug,outcome,sig) — a best-effort append ledger can carry a rare duplicate
    # under a lock-reap race (RB-R2); deduping at READ keeps count/ship-rate correct regardless of
    # duplicate appends (a single-line append is atomic, so a dup is benign — never corruption).
    key="$(printf '%s' "$line" | sed -nE 's/^dora: ([^ ]+) · outcome=([^ ]+) .* · sig=([^ ]+) · ts=.*/\1|\2|\3/p')"
    if [ -n "$key" ] && printf '%s\n' "$seen" | grep -qxF "$key"; then continue; fi   # duplicate → do not double-count
    [ -n "$key" ] && seen="$seen
$key"
    total=$((total+1))
    case "$line" in *"· outcome=SHIPPED · "*) shipped=$((shipped+1)) ;; esac
  done < "$f"
  [ "$malformed" = 0 ] || { echo "COMPASS-DORA: FLAG — malformed row(s) present (fail-closed)." >&2; return 1; }
  local rate
  if [ "$total" -eq 0 ]; then rate="NA"; else rate="$(( 100 * shipped / total ))%"; fi
  ok "dora-ledger: $total records, $shipped shipped, ship-rate: $rate."
}

# drift-check <build-dir> — opt-in, on-demand (NO autonomous loop). A shipped build was GREEN by
# construction; re-run its recorded verification command and FLAG iff it is no longer green.
# Baseline command: ship-receipt `RECON-CMD:` (verbatim) primary; contract `observation-channel:`
# (strip the `<facet> = ` prefix) fallback. cd main_root first (recorded cmds are repo-root-relative).
cmd_drift_check() { # <build-dir>
  local dir="${1:-}"
  [ -n "$dir" ] || die "drift-check: usage: drift-check <build-dir>"
  [ -r "$dir/receipts.md" ] || return 0     # guard-first N/A (no/unreadable receipts.md → exit 0, no output)
  local rc="$dir/receipts.md" contract="$dir/contract.md" cmd=""
  cmd="$(grep -E '^RECON-CMD:' "$rc" 2>/dev/null | tail -1 | sed -E 's/^RECON-CMD:[[:space:]]*//' || true)"
  if [ -z "$cmd" ]; then
    local decl; decl="$(hdr_get "$contract" observation-channel 2>/dev/null || true)"
    case "$decl" in *" = "*) cmd="${decl#* = }" ;; *) cmd="" ;; esac   # grammar `<facet> = <cmd>`: strip prefix; a MALFORMED decl (no ` = `) → no baseline → N/A, never a false FLAG (review-build m4)
  fi
  [ -n "$cmd" ] || return 0                  # no baseline (not built/shipped, no observation-channel) → N/A-pass
  local mr; mr="$(main_root)" || die "drift-check: cannot resolve main_root."
  local rc2
  if ( cd "$mr" && eval "$cmd" >/dev/null 2>&1 ); then rc2=0; else rc2=$?; fi
  if [ "$rc2" = 0 ]; then
    ok "drift-check: '$(basename "$dir")' still green (re-ran the recorded baseline: $cmd)."
  else
    echo "COMPASS-DRIFT: FLAG — '$(basename "$dir")' DRIFTED — the recorded baseline command no longer passes (exit $rc2): $cmd" >&2
    return 1
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
# v0.28.0 "always clarity" — orientation block + progress card.
# The user must ALWAYS know what is planned and how far along it is. These are
# SCRIPT-rendered and RECEIPT-recorded, never prose instructions: the v0.15
# welcome sat in go.md for 12 versions and printed 0 times in 30 real
# /compass:go runs, because its only tests grepped the file for the words.
# Determinism is load-bearing — no timestamp, no absolute path, no locale-
# dependent formatting inside a rendered block, so fixtures can be byte-compared.
# ══════════════════════════════════════════════════════════════════════════════

COMPASS_ORIENT_LOG_CAP="${COMPASS_ORIENT_LOG_CAP:-500}"

# Strip terminal control characters — a plan.md step title is untrusted input
# (contract STRIDE-lite: Tampering). Keeps \t and \n, drops the escape family.
_orient_strip() { tr -d '\000-\010\013\014\016-\037'; }

# Append one observability line, then cap the file. Never fails the caller.
_orient_log() { # <logfile> <command> <mode> <bytes-out>
  local lf="${1:-}" cmd="${2:-}" mode="${3:-}" bytes="${4:-0}"
  [ -n "$lf" ] || return 0
  mkdir -p "$(dirname "$lf")" 2>/dev/null || return 0
  printf '%s · %s · %s · %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$cmd" "$mode" "$bytes" >> "$lf" 2>/dev/null || return 0
  local n; n="$(wc -l < "$lf" 2>/dev/null | tr -d ' ')"; n="${n:-0}"
  if [ "$n" -gt "$COMPASS_ORIENT_LOG_CAP" ] 2>/dev/null; then
    tail -n "$COMPASS_ORIENT_LOG_CAP" "$lf" > "$lf.tmp" 2>/dev/null && mv "$lf.tmp" "$lf" 2>/dev/null
  fi
  return 0
}

# List ONLY real in-flight build rows from cmd_active_builds. That command prints
# a human "COMPASS-GATE: PASS — 0 active builds." line when there are none, and a
# naive ^[a-zA-Z0-9] match counted THAT as a build — so with nothing in flight the
# renderer tried `--where <state-root>/COMPASS-GATE:` and emitted nothing at all.
# The new-user path (no builds yet) is the single most important case for the
# NEW-BUILD block, and it was the one that broke. Found by the post-ship loop.
_orient_active_rows() { # <state-root>
  cmd_active_builds "${1:-}" 2>/dev/null | grep -E '^[A-Za-z0-9][A-Za-z0-9_.-]* \(' || true
}

# The NEW-BUILD block — shown when nothing is in flight. Deliberately short:
# it teaches the model, it does not recite the manual.
_orient_new_block() {
  cat <<'COMPASS_ORIENT_NEW'
── Compass ─────────────────────────────────────────────
  Build true to a spec you lock first — zero drift.

  1  Contract   we write what "done" means. You lock it.
  2  Gates      contract→review→plan→review→build→review→ship.
                Between each, a real script check refuses to
                advance until the work still matches the contract.
  3  Never lost Stop any time. /compass:go picks you up here.

  Three doors:  /compass:go  ·  /compass:status  ·  /compass:resume
────────────────────────────────────────────────────────
COMPASS_ORIENT_NEW
}

# Read the declared run-mode. INV-MODE-VISIBLE: the user must always be able to
# see whether Compass will stop for them, not just have it recorded on disk.
_orient_mode() { # <build-dir>
  local m; m="$(sed -nE 's/^mode:[[:space:]]*([A-Za-z-]+).*/\1/p' "${1:-}/progress.md" 2>/dev/null | head -1)"
  case "$(printf '%s' "${m:-}" | tr 'A-Z' 'a-z')" in
    autonomous|auto) printf 'Autonomous' ;;
    human-gated|gated|human) printf 'Human-gated' ;;
    *) printf 'not set' ;;
  esac
}

# The MID-BUILD block — shown when something IS in flight. Never contains the
# NEW-BUILD intro (INV-ORIENT-NOREPEAT): six /compass:go calls in one session is
# normal, and six full intros would be rage-inducing.
_orient_where_block() { # <build-dir>
  local dir="$1" slug; slug="$(basename "$dir")"
  local stage cur="" strip="" label
  for stage in $LIFECYCLE; do
    if stage_pass "$dir" "$stage"; then :; else cur="$stage"; break; fi
  done
  for stage in $LIFECYCLE; do
    case "$stage" in review-*) label="review" ;; *) label="$stage" ;; esac
    if stage_pass "$dir" "$stage"; then strip="$strip$label ✓  "
    elif [ "$stage" = "$cur" ]; then strip="$strip$label ◉  "
    else strip="$strip$label ○  "; fi
  done
  local total done_ next goal
  total="$(grep -cE '^[[:space:]]*- \[[ x~]\] ' "$dir/plan.md" 2>/dev/null || true)"; total="${total:-0}"
  done_="$(grep -cE '^[[:space:]]*- \[x\] ' "$dir/plan.md" 2>/dev/null || true)"; done_="${done_:-0}"
  next="$(sed -nE 's/^\*\*Next:\*\*[[:space:]]*(.*)/\1/p' "$dir/progress.md" 2>/dev/null | head -1)"
  goal="$(LC_ALL=C grep -F "$slug · " "$(dirname "$dir")/INDEX" 2>/dev/null | head -1 | LC_ALL=C sed -E 's/^[^·]+· ([^·]+) ·.*/\1/')"
  # Trim trailing spaces with bash expansion, NOT sed: `[[:space:]]` is
  # locale-dependent, and these strings carry multibyte glyphs (✓ ◉ ○), so a
  # sed trim renders differently under LC_ALL=C vs a UTF-8 locale — which the
  # determinism clause forbids and the TZ/locale fixture check catches.
  goal="${goal%"${goal##*[! ]}"}"
  strip="${strip%"${strip##*[! ]}"}"
  printf '── Compass · %s ────────────────────────────────────\n' "$slug"
  printf '  %s\n' "$strip"
  printf '  ▲ %s' "${cur:-done — all stages ✓}"
  [ "${total:-0}" -gt 0 ] 2>/dev/null && printf ' · step %s/%s' "${done_:-0}" "$total"
  [ -n "${next:-}" ] && printf ' · next: %s' "$next"
  printf '\n'
  [ -n "${goal:-}" ] && printf '  Goal: %s\n' "$goal"
  printf '  mode: %s\n' "$(_orient_mode "$dir")"
  printf '────────────────────────────────────────────────────────\n'
}

# N>1 in flight. CURRENT cannot disambiguate parallel builds, so it is shown as
# a hint, never as the answer.
_orient_multi_block() { # <state-root>
  local sr="$1" slug cur line
  cur="$(cat "$sr/CURRENT" 2>/dev/null | tr -d '[:space:]')"
  printf '── Compass · %s builds in flight ───────────────────\n' "$(_orient_active_rows "$sr" | grep -c . | tr -d ' ')"
  while IFS= read -r line; do
    slug="$(printf '%s' "$line" | awk '{print $1}')"
    [ -n "$slug" ] || continue
    local st tot dn; st=""
    for s in $LIFECYCLE; do if stage_pass "$sr/$slug" "$s"; then :; else st="$s"; break; fi; done
    tot="$(grep -cE '^[[:space:]]*- \[[ x~]\] ' "$sr/$slug/plan.md" 2>/dev/null || true)"; tot="${tot:-0}"
    dn="$(grep -cE '^[[:space:]]*- \[x\] ' "$sr/$slug/plan.md" 2>/dev/null || true)"; dn="${dn:-0}"
    printf '  · %s — %s · step %s/%s\n' "$slug" "${st:-done}" "$dn" "$tot"
  done < <(_orient_active_rows "$sr")
  printf '────────────────────────────────────────────────────────\n'
  if [ -n "$cur" ] && [ -d "$sr/$cur" ]; then
    _orient_where_block "$sr/$cur"
    printf '  ◀ hint — CURRENT is a hint only and cannot disambiguate parallel builds.\n'
  fi
}

# The itemised planned-vs-done card, rendered at EVERY build step.
# Honesty rule (INV-CARD-HONEST): a step counts as verified only when its
# IN-PROGRESS receipt exists. A ticked box with no receipt renders "box-only" —
# a progress bar you cannot trust is worse than none.
cmd_progress_card() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh progress-card <build-dir>"
  [ -n "${COMPASS_QUIET:-}" ] && return 0
  local slug; slug="$(basename "$dir")"
  local plan="$dir/plan.md" rcp="$dir/receipts.md"
  [ -f "$plan" ] || { printf '── Plan · %s ───────────────────────────────────\n  (no plan.md yet — nothing planned to show)\n────────────────────────────────────────────────────────\n' "$slug"; return 0; }
  local -a titles=() states=()
  local n=0 line box title cur=0 donec=0
  while IFS= read -r line; do
    case "$line" in
      *'- [x] '*) box=x ;;
      *'- [ ] '*) box=' ' ;;
      *) continue ;;
    esac
    n=$((n+1))
    title="${line#*] }"
    # Strip markdown emphasis, the redundant "N · " prefix (the number already
    # has its own column), and any terminal control characters (untrusted input).
    title="$(printf '%s' "$title" | _orient_strip | LC_ALL=C sed -E 's/\*\*//g; s/`//g; s/^[0-9]+ · //')"
    title="$(printf '%s' "$title" | cut -c1-44)"
    titles[$n]="$title"
    # Verified ONLY if this step number has an IN-PROGRESS receipt.
    if [ "$box" = "x" ]; then
      if LC_ALL=C grep -qE "IN-PROGRESS · step $n/" "$rcp" 2>/dev/null; then states[$n]="verified"; donec=$((donec+1))
      else states[$n]="box-only"; fi
    else
      if [ "$cur" = "0" ]; then states[$n]="running"; cur=$n; else states[$n]="pending"; fi
    fi
  done < <(LC_ALL=C grep -E '^[[:space:]]*- \[[ x~]\] ' "$plan" 2>/dev/null)
  [ "$n" -gt 0 ] || { printf '── Plan · %s ───────────────────────────────────\n  (plan.md has no steps yet)\n────────────────────────────────────────────────────────\n' "$slug"; return 0; }
  local shown_cur="${cur:-$n}"; [ "$shown_cur" = "0" ] && shown_cur="$n"
  printf '── Plan · %s · step %s of %s ─────────────────────\n' "$slug" "$shown_cur" "$n"
  # INV-CARD-CAP: a long plan must not become a wall. Over 12 steps, collapse
  # the finished ones to a count and window 3 before / 3 after the current step.
  local lo=1 hi="$n" collapsed=0
  if [ "$n" -gt 12 ]; then
    lo=$((shown_cur-3)); [ "$lo" -lt 1 ] && lo=1
    hi=$((shown_cur+3)); [ "$hi" -gt "$n" ] && hi="$n"
    collapsed=$((lo-1))
    [ "$collapsed" -gt 0 ] && printf '  … %s earlier step(s) done\n' "$collapsed"
  fi
  local i g suffix
  for i in $(seq "$lo" "$hi"); do
    case "${states[$i]}" in
      verified) g='✓'; suffix='verified' ;;
      'box-only') g='!'; suffix='box-only — no verify recorded' ;;
      running)  g='▶'; suffix='← now' ;;
      *)        g='·'; suffix='' ;;
    esac
    if [ -n "$suffix" ]; then printf '  %s %-2s %-46s %s\n' "$g" "$i" "${titles[$i]}" "$suffix"
    else printf '  %s %-2s %s\n' "$g" "$i" "${titles[$i]}"; fi
  done
  [ "$hi" -lt "$n" ] && printf '  … %s later step(s) to go\n' "$((n-hi))"
  printf '  ──────────────────────────────────────────────────────\n'
  printf '  %s done · %s running · %s to go\n' "$donec" "$([ "$cur" != "0" ] && echo 1 || echo 0)" "$((n-donec-$([ "$cur" != "0" ] && echo 1 || echo 0)))"
  printf '────────────────────────────────────────────────────────\n'
  _orient_log "$dir/orient.log" "progress-card" "step $shown_cur/$n" "$n"
  return 0
}

# Install the Claude Code status line — EXPLICIT, OPT-IN, NEVER automatic.
# The public release must not touch any installer's global settings; a plugin
# silently rewriting a stranger's ~/.claude/settings.json is out of bounds. This
# runs only when a human types it, and only after a timestamped backup.
cmd_statusline_install() { # [--dry-run]
  local dry="${1:-}" cfg="$HOME/.claude/settings.json"
  local cmdline; cmdline="bash \"$(main_root)/plugins/compass/scripts/compass.sh\" statusline"
  [ -f "$cfg" ] || die "statusline-install: no $cfg to edit."
  if [ "$dry" = "--dry-run" ]; then
    echo "would back up: $cfg"; echo "would set statusLine.command: $cmdline"; return 0
  fi
  local bak; bak="$cfg.compass-backup-$(date -u +%Y%m%dT%H%M%SZ)"
  cp "$cfg" "$bak" || die "statusline-install: backup failed."
  python3 - "$cfg" "$cmdline" <<'PY' || die "statusline-install: edit failed (backup kept)."
import json,sys
cfg,cmd=sys.argv[1],sys.argv[2]
d=json.load(open(cfg))
d["statusLine"]={"type":"command","command":cmd}
json.dump(d,open(cfg,"w"),indent=2)
PY
  python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$cfg" || die "statusline-install: result is not valid JSON (restore from $bak)."
  ok "statusline-install: installed. Backup: $bak  ·  undo: cp \"$bak\" \"$cfg\""
}

# ── v0.29.0 artefact gate / delivery / audit ──────────────────────────────────
# The structural gate lives in node (it reads HTML), so this is a thin, honest wrapper.
cmd_artefact_gate() { # <html> [--source <md>] [--steps N] [--bands]
  local f="${1:-}"; [ -n "$f" ] || die "usage: compass.sh artefact-gate <html> [--source <md>] [--steps N] [--bands]"
  shift || true
  node "$(dirname "$0")/artefact-gate.mjs" "$f" "$@"
}

# ── v0.30 INV-5 PORTABLE: delivery is a URL, or an honest statement that there is none ────────
# WHAT WAS HERE, AND WHY IT WENT — described, never spelled, because writing the paths out is
# how they keep coming back (this comment tripped the portability check twice before this
# wording; the same thing happened to the note explaining the removal of the typed lock phrase):
#   · a hardcoded personal downloads folder, assumed to exist — not a given off macOS
#   · a macOS-only file opener that silently did nothing elsewhere and STILL reported success,
#     because its exit code was captured into a string and never checked
#   · a peer-to-peer file sender behind a hardcoded Apple-Silicon package path, used to push the
#     UNREDACTED brief to whichever machine a fragile awk over its status output picked first.
#     One person's convenience, shipped to every installer as a product feature, carrying their
#     reconciliation gold to a host chosen by a text-parsing accident.
# The replacement records where the artefact went. Publishing itself is done by the caller (the
# Artifact tool lives in the agent, not in bash), so this owns the STATE: one URL per artefact,
# stored and reused, or an honest local-path fallback naming why there is no link.
# ── v0.30: the RAIL — the terminal surface that carries the artefact link ─────────────────────
# LEFT BORDER ONLY. A closed four-sided box needs >=74 columns to hold a 68-character artefact
# URL, and shatters below that; with no right border there is nothing to align to, so it cannot
# misalign and only the URL line wraps on a narrow terminal.
# It is printed in the model's RESPONSE, not by a hook: proven this session that every hook
# prefixes EVERY line of a systemMessage with "<HookName> says: ", which destroys box art. The
# one-line hook backstop ships with v0.31, where it can be one line.
cmd_rail() { # <build-dir> [--artefact <view>] [--url <url>] [--local <path>]
  local dir="${1:-}"; shift || true
  [ -n "$dir" ] || die "usage: compass.sh rail <build-dir> [--artefact <view>] [--url <url>] [--local <path>]"
  local view="" url="" local_path=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --artefact) view="${2:-}"; shift 2 ;;
      --url) url="${2:-}"; shift 2 ;;
      --local) local_path="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  # An empty or absent build dir prints NOTHING — an empty frame is worse than silence.
  [ -d "$dir" ] || return 0
  [ -f "$dir/contract.md" ] || return 0
  local slug; slug="$(basename "$dir")"
  local stage; stage="$(sed -nE 's/^\*\*Stage:\*\*[[:space:]]*(.*)/\1/p' "$dir/progress.md" 2>/dev/null | head -1)"
  [ -n "$stage" ] || stage="contract"
  # Step k/n ONLY when plan.md exists. Printing 0/0 for a build with no plan states a falsehood.
  local seg=""
  if [ -f "$dir/plan.md" ]; then
    local tot done_
    tot="$(LC_ALL=C grep -cE '^[[:space:]]*- \[[ x~]\] ' "$dir/plan.md" 2>/dev/null | head -1)"; tot="${tot:-0}"
    done_="$(LC_ALL=C grep -cE '^[[:space:]]*- \[x\] ' "$dir/plan.md" 2>/dev/null | head -1)"; done_="${done_:-0}"
    [ "${tot:-0}" -gt 0 ] 2>/dev/null && seg=" · step ${done_}/${tot}"
  fi
  # Resolve the BODY before printing anything. The frame used to print with nothing inside it
  # whenever no link was passed — and this function's own comment says an empty frame is worse than
  # silence. Found by dogfooding: the first rail v0.31 printed was four empty lines.
  # If a view was named and its file is on disk, that IS the local fallback; nobody should have to
  # pass a path the build already knows.
  if [ -z "$url" ] && [ -z "$local_path" ] && [ -n "$view" ] && [ -f "$dir/$view.html" ]; then
    local_path="$dir/$view.html"
  fi
  [ -n "$url" ] || [ -n "$local_path" ] || return 0
  local title; title="$(printf '%s' "${view:-BUILD}" | tr 'a-z-' 'A-Z ')"
  printf '\xe2\x95\xad\xe2\x94\x80 %s \xc2\xb7 %s%s\n' "$title" "$stage" "$seg"
  printf '\xe2\x94\x82\n'
  if [ -n "$url" ]; then
    printf '\xe2\x94\x82   \xe2\x96\xb8  %s\n' "$url"
    printf '\xe2\x94\x82\n'
    printf '\xe2\x94\x82   That page is the decision. Everything here is a pointer to it.\n'
  elif [ -n "$local_path" ]; then
    printf '\xe2\x94\x82   \xe2\x96\xb8  %s\n' "$local_path"
    printf '\xe2\x94\x82\n'
    printf '\xe2\x94\x82   No link this time \xe2\x80\x94 nothing here could publish it.\n'
    printf '\xe2\x94\x82   Open the file above in a browser.\n'
  fi
  printf '\xe2\x94\x82\n'
  printf '\xe2\x95\xb0\xe2\x94\x80 %s\n' "$slug"
}

cmd_artefact_publish() { # <html> [--url <artifact-url>] [--dir <build-dir>]
  local f="${1:-}"; shift || true
  [ -n "$f" ] && [ -f "$f" ] || die "usage: compass.sh artefact-publish <html-file> [--url <url>] [--dir <build-dir>]"
  local url="" dir=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --url) url="${2:-}"; shift 2 ;;
      --dir) dir="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -n "$dir" ] || dir="$(dirname "$f")"
  local view; view="$(basename "$f" .html)"
  local store="$dir/artifact-urls"
  local prior=""; [ -f "$store" ] && prior="$(LC_ALL=C grep -E "^${view}=" "$store" 2>/dev/null | head -1 | cut -d= -f2- || true)"

  if [ -z "$url" ] && [ -n "$prior" ]; then
    # INV-7: republishing must UPDATE the same artefact, never create a second one. Hand the
    # caller the stored URL so it republishes in place. Before this, every regeneration made a
    # new artefact — the user's gallery already carries duplicate Briefs from that.
    ok "artefact-publish: reuse this URL for '$view' (INV-7, republish in place): $prior"
    return 0
  fi

  if [ -z "$url" ]; then
    # No URL and none stored: the caller could not publish. Say so, name the local file, and
    # exit NON-ZERO. The old path always exited 0 — a `cp` was the only thing that could fail —
    # so "delivered" was unfalsifiable.
    echo "artefact-publish: NO PUBLISH PATH — no URL supplied and none stored for '$view'." >&2
    echo "  The artefact is on disk at: $f" >&2
    echo "  Open that file, or re-run where the Artifact tool is available." >&2
    return 3
  fi

  case "$url" in https://*) : ;; *) die "artefact-publish: '$url' is not an https URL." ;; esac
  local tmp; tmp="$(mktemp)"
  [ -f "$store" ] && LC_ALL=C grep -vE "^${view}=" "$store" > "$tmp" 2>/dev/null
  printf '%s=%s\n' "$view" "$url" >> "$tmp"
  mv "$tmp" "$store"
  # Observability: a delivery with no line did not happen.
  printf 'artefact=%s url=%s gate=PASS\n' "$view" "$url" >> "$dir/../orient.log" 2>/dev/null || true
  if [ -n "$prior" ] && [ "$prior" != "$url" ]; then
    ok "artefact-publish: '$view' URL REPLACED (the stored one no longer resolved): $url"
  else
    ok "artefact-publish: '$view' → $url (stored; republish reuses it)"
  fi
}

# The observation channel: re-run the gate over the last rendered outputs and show the log.
cmd_artefact_audit() { # <build-dir>
  local d="${1:-}"; [ -n "$d" ] && [ -d "$d" ] || die "usage: compass.sh artefact-audit <build-dir>"
  local any=0 f bad=0 src out rc
  # v0.30: program-cockpit deleted; review added. Kept `[ -f ]`-guarded so a build with only
  # some of these still audits cleanly.
  #
  # Round 3 M1: this called artefact-gate with NO `--source` and NO `--copy`, so `fresh`,
  # `claimed-count-matches` and every copy check were structurally unreachable here — the audit
  # could not fail on a stale artefact stating a wrong count, which is exactly what it found when
  # run by hand. `tail -1` then collapsed however many problems there were into one line, and the
  # function returned 0 regardless. Three separate ways for a defect to pass through a check.
  for f in "$d"/brief.html "$d"/plan-map.html "$d"/release-card.html "$d"/review.html; do
    [ -f "$f" ] || continue
    any=1
    # Each view is checked against the file it is actually generated from. A view with no obvious
    # source is still checked structurally rather than skipped.
    # A page that renders steps must be told how many to expect, or `counts-match` reports "could not
    # be checked" and passes — a check that cannot fail. The count comes from the same awk the gold
    # uses: `- [ ]`/`- [x]` in plan.md, outside code fences.
    local extra=""
    case "$(basename "$f")" in
      plan-map.html) src="$d/plan.md"
                     extra="--bands"
                     [ -f "$d/plan.md" ] && extra="$extra --steps $(awk '/^[[:space:]]*```/ { f = !f; next } !f && /^[[:space:]]*- \[[ xX~]\]/ { n++ } END { print n+0 }' "$d/plan.md")" ;;
      # NOT --steps: the review page renders FINDINGS, not plan steps, so handing it the plan's count
      # asserts the wrong thing (it reported "body renders 43, --steps was given as 16"). Mine, from
      # copying the plan-map's invocation without checking what the page counts.
      review.html)   src="$d/review-ledger.md" ;;
      *)             src="$d/contract.md" ;;
    esac
    printf '  %-22s\n' "$(basename "$f")"
    # `out="$(cmd)"; rc=$?` aborts the whole function under `set -e` the moment cmd fails — the
    # assignment IS the failing command, so `rc=$?` never runs and the audit dies silently with the
    # findings still in `$out`. Same bug I put in `gold-numbers-gate` and had to be shown twice.
    if [ -f "$src" ]; then
      if out="$(node "$(dirname "$0")/artefact-gate.mjs" "$f" --copy --source "$src" $extra 2>&1)"; then rc=0; else rc=$?; fi
    else
      if out="$(node "$(dirname "$0")/artefact-gate.mjs" "$f" --copy $extra 2>&1)"; then rc=0; else rc=$?; fi
    fi
    printf '%s\n' "$out" | sed 's/^/    /'
    [ "$rc" -eq 0 ] || bad=$((bad+1))
  done
  [ "$any" = 1 ] || echo "  (no artefacts rendered in $d yet)"
  [ -f "$d/artefacts.log" ] && { echo "  ── artefacts.log (last 5) ──"; tail -5 "$d/artefacts.log" | sed 's/^/  /'; } || true
  [ "$bad" -eq 0 ] || { echo "  artefact-audit: $bad artefact(s) FAILED their gate."; return 1; }
  return 0
}

# INV-MODE-ASKED — the run-mode must be ASKED, never inferred.
# Born from a real failure in this build's own session: the mode question that
# INV-MODE-AT-LOCK requires was never asked, and `Human-gated` was inferred from
# an unrelated earlier answer, then written to the receipt as if the user had
# chosen it. `fixtures/mode/inferred` holds that exact string, so the regression
# is the test.
#
# GUARD-FIRST N/A-PASS: a contract receipt with no `mode choice:` line at all is
# LEGACY and passes byte-identically. Every build predating this format — all of
# them, in every installed repo — keeps working. Only a mode line that is
# PRESENT but not marked `asked=yes` fails. New builds are forced instead by the
# receipt template's checkbox, which scan-receipt already enforces.
cmd_mode_gate() { # <build-dir>
  local dir="${1:-}"
  [ -n "$dir" ] || die "usage: compass.sh mode-gate <build-dir>"
  # Contract-header-driven, exactly like schema-pin-gate / perf-budget-gate /
  # pii-gate. A legacy contract has no `mode-asked:` header, so the gate is
  # inert for it — which is the ONLY way to tell "written before this format
  # existed" from "inferred just now". Both look identical in the receipt, so
  # keying off the receipt alone failed 25 of 26 existing builds, and after that
  # was fixed it still failed 3 real builds that had recorded a genuine explicit
  # choice in the old wording.
  local c="$dir/contract.md"
  if [ ! -f "$c" ]; then
    [ -f "$dir/.compass-format" ] && die "mode-gate: no contract.md in a v0.30 build dir."
    return 0
  fi
  local hdr; hdr="$(LC_ALL=C sed -nE 's/^mode-asked:[[:space:]]*([A-Za-z-]+).*/\1/p' "$c" 2>/dev/null | head -1 || true)"
  # v0.30 INV-3: arm on the UNION — the script-written stamp OR the legacy header. A union is a
  # strict superset, so v0.29 builds that declared `mode-asked: required` keep their gate, while a
  # v0.30 dir is armed by something the contract stage cannot author. Never a REPLACEMENT: keying
  # only on the stamp would silently un-arm every v0.29 build that had opted in.
  local _armed=0 _stamped_dir=0
  [ -f "$dir/.compass-format" ] && { _armed=1; _stamped_dir=1; }
  case "$(printf '%s' "${hdr:-}" | tr 'A-Z' 'a-z')" in required) _armed=1 ;; esac
  [ "$_armed" = 1 ] || return 0                 # legacy / not declared → N/A-pass
  local f="$dir/receipts.md"
  # v0.30: on a STAMPED dir these three early returns must DIE, not pass. Review (V4/R3-4) found a
  # stamped dir still N/A-passed all of them — a missing receipts.md, or an empty contract block,
  # silently satisfied the gate that exists to prove the question was asked. On a legacy dir they
  # keep returning 0, byte-identically.
  if [ ! -f "$f" ]; then
    [ "$_stamped_dir" = 1 ] && die "mode-gate: no receipts.md in a v0.30 build dir — the mode question cannot have been recorded."
    return 0
  fi
  local blk; blk="$(last_block "$f" contract 2>/dev/null)"
  if [ -z "$blk" ]; then
    [ "$_stamped_dir" = 1 ] && die "mode-gate: no contract receipt block in a v0.30 build dir — the mode question cannot have been recorded."
    return 0
  fi
  # `|| true` is load-bearing: compass.sh runs `set -euo pipefail`, so a grep
  # with NO match returns 1, pipefail propagates it, and set -e kills the
  # function *silently* — which killed the legacy N/A-pass below and failed 25
  # of 26 existing builds on the first run of this gate. Guard-first only works
  # if the guard is allowed to run.
  local line; line="$(printf '%s' "$blk" | LC_ALL=C grep -E 'mode choice:' | head -1 || true)"
  # The contract DECLARED that the mode must be asked, so omitting the line is
  # not an escape hatch — silence is exactly how the original failure happened.
  [ -n "$line" ] || die "mode-gate: contract declares 'mode-asked: required' but the contract receipt records no mode choice at all.
  Ask the user Human-gated or Autonomous, then record:
  mode choice: asked=yes · answer=<Human-gated|Autonomous> · source=<question|typed-flag>"
  printf '%s' "$line" | LC_ALL=C grep -q 'asked=yes' \
    || die "mode-gate: the run-mode was recorded but not marked as ASKED.
  found: $(printf '%s' "$line" | LC_ALL=C sed -E 's/^[[:space:]]*-?[[:space:]]*\[.\][[:space:]]*//')
  The user must be ASKED whether the lifecycle runs Human-gated or Autonomous —
  it may never be inferred from another answer or assumed from a default.
  Record it as: mode choice: asked=yes · answer=<Human-gated|Autonomous> · source=<question|typed-flag>"
  printf '%s' "$line" | LC_ALL=C grep -qE 'answer=(Human-gated|Autonomous)' \
    || die "mode-gate: mode line carries asked=yes but no valid answer= (want Human-gated or Autonomous)."
  ok "mode-gate: run-mode was explicitly asked and recorded."
}

# One line for the Claude Code status line: always on screen, zero output cost.
# Prints NOTHING when no build is in flight — a permanent empty line would be
# worse than no status line at all.
# ── v0.30 INV-3: the build-dir creation seam ────────────────────────────────────────────────
# WHY THIS EXISTS: INV-3 says mode-gate must not be disarmable by the party it checks. The first
# design armed it on a `compass-format:` HEADER — but the model writes contract.md, so the model
# wrote the stamp, and omitting one line disarmed the gate. Review found `compass-format` appeared
# ZERO times in this script, there was no build-dir-creating command at all, and the v0.30 build's
# own directory had been made with `mkdir -p`. The stamp has to be written by something the
# contract stage cannot author: a dotfile, written here.
# ── v0.30 INV-10: a non-reproducible gold HARD-STOPS. It does not get substituted. ────────────
# WHY: this happened. A pinned reconciliation gold turned out to be analyst-coded and not
# reproducible, and the agent replaced it with "cross-path parity" — two of its own code paths
# compared against each other — then presented that as the gate. Two paths can agree and both be
# wrong. contract/SKILL.md already says the gold "may NOT be computed by the reproducing query
# (a query agreeing with itself proves nothing)" and review-contract grades a self-computed gold
# CRITICAL, but nothing executed either sentence. This does.
# ── v0.30 INV-9: no internal code on a reader-facing surface ──────────────────────────────────
# SCOPED to the model-authored reader-copy block ONLY. It never inspects quoted contract text, the
# invariant table (where the codes ARE the subject), or code shown as code — an earlier draft that
# scanned the whole page would have fired on every correct Brief, and a gate that fires on correct
# work gets disabled within a week.
# ── v0.30 INV-0: the gate that governs the other gates ────────────────────────────────────────
# Every INVARIANT must have been run against the PRE-CHANGE tree and observed to FAIL before it
# counts. An assertion that has never failed is not an assertion, and three review rounds were
# defeated by exactly that. This reads the generated evidence and refuses if any row is missing
# its RED — including its own.
cmd_redfirst_check() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh redfirst-check <build-dir>"
  local f="$dir/red-first-evidence.md"
  [ -f "$f" ] || die "redfirst-check: no red-first-evidence.md in '$dir'.
  Generate it: assert-invariants.sh <repo-root> > $f
  An INVARIANT with no recorded pre-change FAIL has not been proven able to fail."
  [ -s "$f" ] || die "redfirst-check: red-first-evidence.md is EMPTY — an empty record is not a record."
  # Which INVARIANTs does the contract declare? Count EVERY form. The bullet-only regex reported
  # "N/A — declares no INVARIANTs" for a contract that declared them in a markdown table, which is
  # an ordinary way to write one: the gate answered "nothing to check" to a contract full of checks.
  local c="$dir/contract.md" declared="" tokens=""
  if [ -f "$c" ]; then
    declared="$(LC_ALL=C grep -oE '(^| |\||\*)\*\*INV-[0-9A-Za-z]+' "$c" 2>/dev/null | grep -oE 'INV-[0-9A-Za-z]+' | sort -u || true)"
    tokens="$(LC_ALL=C grep -oE 'INV-[0-9A-Za-z]+' "$c" 2>/dev/null | sort -u || true)"
  fi
  if [ -z "$declared" ] && [ -n "$tokens" ]; then
    die "redfirst-check: the contract mentions INVARIANT ids ($(printf '%s' "$tokens" | tr '\n' ' ')) but none match the
  declaration form this gate can read. Refusing to report 'no INVARIANTs' for a contract full of them.
  Declare each as '- **INV-x:** …' or '| **INV-x** |' so the check can find it."
  fi
  [ -n "$declared" ] || { ok "redfirst-check: N/A — contract declares no INVARIANTs."; return 0; }

  # ── A row is evidence only if the RUNNER produced it. ───────────────────────────────────────
  # Round 2 defeated the prose version in one line: `INV-1 INV-2 INV-5 INV-9 INV-11  value=9
  # target=0  RED` — never executed, five invariants on one line — and the gate reported
  # "machine=5 hand=0", with a die message that had literally dictated the string to write. The
  # lesson is not "add more phrases to the blocklist": a literal list cannot win a paraphrase race
  # against the thing it is trying to read. So the format is what is trusted, not the words.
  #
  # A machine row must be EXACTLY what assert-invariants.sh prints: one invariant, its value, its
  # target, its verdict — nothing else before it on the line. And the file must carry the runner's
  # provenance header naming a tree that actually exists in this repo's history, which a person
  # writing prose has no way to forge without running the thing.
  local hdr_sha=""
  hdr_sha="$(LC_ALL=C grep -oE '^ASSERT-INVARIANTS-RUN .*tree=[0-9a-f]{7,40}' "$f" 2>/dev/null | grep -oE '[0-9a-f]{7,40}$' | head -1 || true)"
  if [ -z "$hdr_sha" ]; then
    die "redfirst-check: $f carries no assert-invariants provenance header.
  Every machine-measured record starts with a line the runner writes:
      ASSERT-INVARIANTS-RUN root=<repo> tree=<git sha>
  Produce it by RUNNING the checks against the pre-change tree:
      scripts/assert-invariants.sh <repo-root> >> $f
  A file of hand-written rows is the author grading their own work — round 2 got five fake
  machine rows past this gate with a single typed line."
  fi
  # Verify the named tree really exists. git searches upward from the build dir itself, so this
  # works wherever the build lives inside the repo. Where there is no repo the claim CANNOT be
  # checked — and the pass line says so rather than implying it was verified. Honest degradation
  # is the whole point: a check that quietly stops checking is the defect this build is about.
  local sha_state="unverified (no git repo here)"
  if command -v git >/dev/null 2>&1 && git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$dir" rev-parse --verify --quiet "${hdr_sha}^{commit}" >/dev/null 2>&1 \
      || die "redfirst-check: the evidence header names tree $hdr_sha, which is not a commit in this repo.
  The pre-change measurement must have been taken against a real tree."
    sha_state="tree ${hdr_sha%%"${hdr_sha#???????}"} verified"
  fi
  # Phrases that record the OPPOSITE of a pre-change FAIL while still containing the token RED.
  # A literal list cannot win a paraphrase race — the header and shape requirements above are what
  # actually carry this gate — but it is free and it catches the careless case.
  local antired='never[[:space:]]+went[[:space:]]+RED|GREEN[[:space:]]+from[[:space:]]+the[[:space:]]+start|already[[:space:]]+green|did[[:space:]]+not[[:space:]]+fail|was[[:space:]]+not[[:space:]]+RED|no[[:space:]]+RED[[:space:]]+observed|passed[[:space:]]+cleanly[[:space:]]+before|green[[:space:]]+the[[:space:]]+whole[[:space:]]+time|to[[:space:]]+satisfy[[:space:]]+the[[:space:]]+gate|this[[:space:]]+row[[:space:]]+is[[:space:]]+decoration'
  local missing="" faked="" deferred="" machine=0 hand=0 i row mrow
  for i in $declared; do
    # THE machine row: the runner's exact shape, this invariant and no other on the line.
    # `PASS` must NOT be in this alternation. Five rows ending in the literal word PASS were
    # accepted as "a recorded pre-change RED" — the gate read the shape and ignored the verdict.
    mrow="$(LC_ALL=C grep -E "^[[:space:]]*${i}[[:space:]]+value=[^[:space:]]+[[:space:]]+target=[^[:space:]]+[[:space:]]+RED" "$f" 2>/dev/null | head -1 || true)"
    if [ -n "$mrow" ]; then
      # An ERR row measured NOTHING. `value=ERR-no-pattern-file … RED` is the runner saying its
      # precondition was broken, and it is exactly what the documented workflow produces when the
      # pre-change tree predates the fixtures — so the normal path was recording five ERRs and
      # this gate was calling them five machine-measured REDs, with the tree sha verified. The
      # runner's own --assert-red refuses those; so must this.
      if printf '%s' "$mrow" | LC_ALL=C grep -q 'value=ERR'; then faked="$faked $i(ERR-not-a-measurement)"; continue; fi
      # A runner-shaped row with a confession bolted on is still a confession. This list cannot win
      # a paraphrase race on its own — the header + shape requirements above are what actually
      # carry the check — but it costs nothing and catches the careless case.
      if printf '%s' "$mrow" | LC_ALL=C grep -qiE "$antired"; then faked="$faked $i(anti-evidence)"; continue; fi
      local v t
      v="$(printf '%s' "$mrow" | LC_ALL=C grep -oE 'value=[^[:space:]]+' | head -1 | cut -d= -f2)"
      t="$(printf '%s' "$mrow" | LC_ALL=C grep -oE 'target=[^[:space:]]+' | head -1 | cut -d= -f2)"
      if [ "$v" = "$t" ]; then faked="$faked $i(value=target)"; continue; fi
      machine=$((machine+1)); continue
    fi
    row="$(LC_ALL=C grep -E "(^|[^A-Za-z0-9-])${i}([^A-Za-z0-9-]|$)" "$f" 2>/dev/null | head -4 || true)"
    if [ -z "$row" ]; then missing="$missing $i"; continue; fi
    if printf '%s' "$row" | LC_ALL=C grep -qE 'value=[^[:space:]]+[[:space:]]+target='; then
      # It LOOKS like a machine row but is not shaped like one — several invariants sharing a line,
      # or text before the id. That is the round-2 forgery exactly; refuse it by name.
      faked="$faked $i(not-runner-shaped)"; continue
    fi
    if printf '%s' "$row" | LC_ALL=C grep -qE 'DEFERRED|Deferred'; then
      printf '%s' "$row" | LC_ALL=C grep -qE '(DEFERRED|Deferred).*(—|--|:)[[:space:]]*[A-Za-z][A-Za-z]' \
        || { faked="$faked $i(bare-DEFERRED)"; continue; }
      deferred="$deferred $i"; continue
    fi
    if printf '%s' "$row" | LC_ALL=C grep -q 'RED'; then hand=$((hand+1)); continue; fi
    missing="$missing $i"
  done
  # Deferrals must each say something DIFFERENT. Four identical "DEFERRED — we will do it later"
  # rows passed round 2; a reason copy-pasted across every row is not a reason, it is the same
  # non-answer repeated until the count is satisfied.
  if [ -n "$deferred" ]; then
    local reasons dupes
    # `tr -s '[:space:]' ' '` COLLAPSES THE TRAILING NEWLINE INTO A SPACE, so every reason ran into
    # the next one and `sort | uniq -d` saw a single long line — the check could not fire for any
    # input at all, including the four-identical-reasons defeat quoted in the comment above it.
    # A guard whose own recorded defeat still passes is not a guard. Normalise WITHOUT eating the
    # line ending, and emit exactly one line per reason.
    reasons="$(for i in $deferred; do
      LC_ALL=C grep -m1 -E "(^|[^A-Za-z0-9-])${i}([^A-Za-z0-9-]|$)" "$f" 2>/dev/null \
        | sed -E 's/.*(DEFERRED|Deferred)[^A-Za-z]*//; s/[[:space:]]+/ /g; s/^ //; s/ $//'
    done)"
    dupes="$(printf '%s\n' "$reasons" | grep -v '^$' | sort | uniq -d | head -1 || true)"
    [ -z "$dupes" ] || die "redfirst-check: two or more INVARIANTs are deferred with the SAME reason:
    \"$dupes\"
  If the reason is genuinely identical they are one deferral, not several. State what each one
  is waiting on, or stop deferring it."
  fi
  [ -z "$faked" ] || die "redfirst-check: these rows claim evidence but record the opposite of a pre-change FAIL:$faked
  A row that says the check was green from the start, or whose measured value equals its target,
  is a record that the check CANNOT fail — the exact thing INV-0 exists to catch."
  [ -z "$missing" ] || die "redfirst-check: no recorded pre-change RED for:$missing
  Each INVARIANT must be run against the pre-change tree and observed to FAIL before it counts.
  A command that is green before the work begins is decoration, not a check."
  # Visible degradation: a caller must be able to see how much of this was measured by a runner and
  # how much is hand-written prose. A silent blend reads as "all machine-verified".
  local total=$((machine+hand)); local dn=0
  [ -n "$deferred" ] && dn="$(printf '%s' "$deferred" | wc -w | tr -d ' ')"
  [ "$machine" -gt 0 ] || die "redfirst-check: not one row was produced by assert-invariants.sh (machine=0).
  Hand-written RED prose alone is the author grading their own work. Run:
  scripts/assert-invariants.sh <repo-root> >> $f"
  [ "$total" -gt 0 ] || die "redfirst-check: every declared INVARIANT is DEFERRED — nothing is proven."
  ok "redfirst-check: every declared INVARIANT has a recorded pre-change RED (machine=$machine hand=$hand deferred=$dn; $sha_state)."
}

cmd_copy_gate() { # <file> [--block <fence-name>]
  local f="${1:-}"; [ -n "$f" ] && [ -f "$f" ] || die "usage: compass.sh copy-gate <file>"
  local fx; fx="$(dirname "${BASH_SOURCE[0]}")/fixtures/copy"
  local pat="$fx/jargon.txt" ctl="$fx/positive-control.txt"
  [ -f "$pat" ] || die "copy-gate: pattern file missing at $pat"
  [ -s "$pat" ] || die "copy-gate: pattern file is EMPTY at $pat"
  # INV-0b: if the pattern stops catching the known jargon, refuse to report a verdict.
  # PER-LINE coverage plus a pinned count — the same rule INV-5's control uses. `-ge 6` against a
  # 7-line control meant one pattern could be deleted outright and the total still cleared the bar,
  # so `guard-first` stopped being policed while this gate kept printing PASS.
  local _cl _cmiss=""
  while IFS= read -r _cl; do
    case "$_cl" in ''|'#'*) continue ;; esac
    grep -qE -- "$_cl" "$ctl" 2>/dev/null || _cmiss="$_cmiss
    $_cl"
  done < "$pat"
  [ -z "$_cmiss" ] || die "copy-gate: PATTERN BROKEN — these lines no longer match the positive control:$_cmiss
  Refusing to report a verdict."
  local _cw _ch
  _cw="$(sed -n 's/^# expects:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$ctl" | head -1)"
  _ch="$(grep -cE '^[^#[:space:]]' "$pat" 2>/dev/null || echo 0)"
  if [ -n "$_cw" ] && [ "${_ch:-0}" != "$_cw" ]; then
    die "copy-gate: PATTERN COUNT CHANGED — $_ch lines, the control expects $_cw. Bump the pin deliberately or restore the line."
  fi
  # Extract the reader-copy block with THE extractor — the same code gen.mjs lays the page out
  # from, so the gate and the renderer can never disagree about what the block is. They did: this
  # was a prefix-matching awk while gen.mjs required an exact fence, and one trailing space on the
  # fence line made gen.mjs render copy that the gate reported as absent. Silent in both directions.
  local rc_ex; rc_ex="$(dirname "${BASH_SOURCE[0]}")/reader-copy.mjs"
  [ -f "$rc_ex" ] || die "copy-gate: the shared extractor is missing at $rc_ex"
  command -v node >/dev/null 2>&1 || die "copy-gate: node is required to read the reader-copy block."
  # set -e: a bare \`body="$(node …)"\` whose substitution exits 3 aborts the whole script BEFORE the
  # N/A branch below can run — the unguarded-read-under-set-e class. Assign inside an if-condition.
  local body rcx
  if body="$(node "$rc_ex" --extract "$f" 2>/dev/null)"; then rcx=0; else rcx=$?; fi
  case "$rcx" in
    0) : ;;
    3) # v0.32.0 S14 (§17 / contract §7). An ABSENT reader-copy block was an N/A-PASS, so on 27 of
       # 30 contracts this gate printed a pass for a file it had not read one word of. "No block"
       # is not "the copy is fine"; it is "there is no copy", and the rule exists because a reader
       # met six words of insider shorthand in a row on a page nothing was checking.
       #
       # GUARD-FIRST, which is the v0.28 lesson: a gate that refuses 25 of 26 existing builds is a
       # defect, not a standard. A contract that PREDATES this format N/A-passes AND SAYS SO. The
       # marker is the `compass-format:` line `compass.sh new-build` writes. Measured over all 30
       # build folders before the change: the three carrying that line are EXACTLY the three
       # carrying a block, so this refuses none of them.
       if grep -qE '^compass-format:' "$f" 2>/dev/null; then
         echo "refuse: reader-copy" >&2
         die "copy-gate: '$(basename "$f")' declares a compass-format but carries NO compass-reader-copy block.
  A contract written to this format states its own reader copy; without it there is nothing to check
  and this gate would be reporting a pass on an unread file."
       fi
       ok "copy-gate: N/A — '$(basename "$f")' predates the reader-copy format (it carries no 'compass-format:' line), so there is no block to check. Stated rather than passed silently."
       return 0 ;;
    *) # malformed: a fence the author wrote that the parser cannot read. Reporting N/A here is how
       # an indented or 4-backtick block went unpoliced while the gate printed a pass.
       die "copy-gate: $(basename "$f") has a compass-reader-copy block that cannot be parsed:
$(node "$rc_ex" --extract "$f" 2>&1 >/dev/null | sed 's/^/    /')
  A block this gate cannot read is a block it did not check. Fix the fence — do not ship it unchecked." ;;
  esac
  [ -n "$body" ] || die "copy-gate: the compass-reader-copy block in $(basename "$f") is empty."
  # Case-INSENSITIVE, and dashes normalised. Reader copy is sentences, so the terms appear
  # capitalised at the start of one — `Self-computed`, `Guard-first`, `Byte-inert` all passed a
  # case-sensitive match while their lowercase forms failed. gold-gate already normalises the
  # typographic dash family; this gate did not, so a U+2011 hyphen also walked through.
  local _nbody; _nbody="$(printf '%s\n' "$body" | sed $'s/[‐‑‒–—―]/-/g; s/[  ]/ /g')"
  local hits; hits="$(printf '%s\n' "$_nbody" | grep -niEo -f "$pat" 2>/dev/null | head -5 || true)"
  if [ -n "$hits" ]; then
    echo "refuse: reader-jargon" >&2
    die "copy-gate: internal code reached reader-facing copy in $(basename "$f"):
$(printf '%s' "$hits" | sed 's/^/    /')
  Reader copy names things in plain words and introduces a term before using it.
  See shared/feynman.md. The contract may be as precise as it likes — the artefact is
  where a person decides."
  fi
  ok "copy-gate: reader copy carries no internal codes."
}

cmd_gold_gate() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh gold-gate <build-dir>"
  local c="$dir/contract.md"; [ -f "$c" ] || return 0
  local fx; fx="$(dirname "${BASH_SOURCE[0]}")/fixtures/gold"
  local pat="$fx/self-referential.txt" ctl="$fx/positive-control.txt"
  [ -f "$pat" ] || die "gold-gate: pattern file missing at $pat"
  # PER-LINE coverage, not a total. `-ge 4` against an 11-line pattern meant 7 lines could be
  # deleted outright and the control still reported 4/4 — silent pattern rot, the same defect the
  # INV-5 control was fixed for two hundred lines away in the other file. Every pattern line must
  # prove itself, and the count is pinned so a DELETED line cannot pass unnoticed either.
  local _pl _missing=""
  while IFS= read -r _pl; do
    case "$_pl" in ''|'#'*) continue ;; esac
    grep -qiF -- "$_pl" "$ctl" 2>/dev/null || _missing="$_missing
    $_pl"
  done < "$pat"
  [ -z "$_missing" ] || die "gold-gate: PATTERN BROKEN — these lines no longer match the positive control:$_missing
  Refusing to report a verdict."
  local _want _have
  _want="$(sed -n 's/^# expects:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$ctl" | head -1)"
  _have="$(grep -cE '^[^#[:space:]]' "$pat" 2>/dev/null || echo 0)"
  if [ -n "$_want" ] && [ "${_have:-0}" != "$_want" ]; then
    die "gold-gate: PATTERN COUNT CHANGED — $_have lines, the control expects $_want.
  A deleted pattern line stops a whole class being checked; bump the pin deliberately or restore it."
  fi

  # Heading: ANY prefix, any level. `## 7. Reconciliation` fell straight through "no section" and
  # PASSed a contract whose very next line was the fixture's own positive-control sentence.
  # End the section on a heading at the SAME OR SHALLOWER level — never on its own sub-heading.
  # `## Reconciliation` followed by `### Gold figure` used to terminate the section at the
  # sub-heading, handing the hardened blocklist an empty string and printing "N/A — no
  # Reconciliation section" over a body holding three verbatim positive-control lines. A bold
  # pseudo-heading (`**Reconciliation**`) opened nothing at all.
  local sec; sec="$(awk '
    function lvl(s){n=0; while(substr(s,n+1,1)=="#") n++; return n}
    tolower($0) ~ /^[[:space:]]{0,3}#+.*reconcil/  { f=1; d=lvl($0); next }
    tolower($0) ~ /^[[:space:]]*\*\*reconcil[a-z]*:?\*\*[[:space:]]*:?[[:space:]]*$/ { f=1; d=99; next }
    f && d==99 && /^[[:space:]]*\*\*[A-Za-z][A-Za-z ]*:?\*\*[[:space:]]*:?[[:space:]]*$/ { f=0 }
    f && /^[[:space:]]{0,3}#+[[:space:]]/ { if (d==99 || lvl($0) <= d) { f=0 } }
    f' "$c" 2>/dev/null)"
  [ -n "$sec" ] || { ok "gold-gate: N/A — no Reconciliation section."; return 0; }

  # Normalise before matching. Typographic hyphens and non-breaking spaces are ordinary in
  # model-authored prose and defeated a fixed-string search: `cross‑path parity` with U+2011 read
  # as clean. Map the dash and space families to ASCII first.
  local nsec; nsec="$(printf '%s' "$sec" | sed $'s/[‐‑‒–—―]/-/g; s/[              ]/ /g')"

  # ── The blocklist runs over the WHOLE section, ALWAYS. ──────────────────────────────────────
  # Every previous defeat was an N/A arm switching this off: a section with no line containing the
  # word "gold"; a units column reading "(units N/A)"; a numbered heading. Whether a gold is
  # *declared* decides whether PROVENANCE is required — it must never decide whether a
  # self-referential check is allowed to ship. Those are different questions and conflating them
  # is what made three one-line escapes work.
  local negform bad still phrases
  phrases="$(sed 's/[][\.*^$(){}?+|/]/\\&/g' "$pat" | paste -sd'|' - )"
  # Disclaimer forms, before the phrase. Two hand-written CORRECT sentences were refused in round 3
  # — "Cross-path parity is explicitly rejected as a gold" and "We refuse any figure that is
  # self-computed" — because only `refuses? to` was listed and the negation had to sit within two
  # words. A gate that refuses a contract for saying it does the right thing gets switched off.
  negform="(not|never|no|is not|are not|was not|were not|rather than|instead of|may not be|must not be|cannot be|can not be|forbidden|forbids?|refuses?|refused|rejects?|rejected|bans?|banned|disallows?|prohibits?|avoids?|excludes?|never[[:space:]]+use)([[:space:]]+[A-Za-z]+){0,5}[[:space:]]+($phrases)"
  # A negation can sit on EITHER side of the phrase. Two shipped contracts write "A gate agreeing
  # with itself proves nothing — so each INVARIANT pins the real failure shape", which is the gate's
  # own doctrine stated correctly, and a before-only filter flagged both. A guard that fires on
  # correct work gets switched off within a week, so the after-form counts too.
  local postneg
  postneg="($phrases)([[:space:]]+[A-Za-z]+){0,5}[[:space:]]+(proves?[[:space:]]+nothing|is[[:space:]]+not[[:space:]]+evidence|means?[[:space:]]+nothing|is[[:space:]]+worthless|is[[:space:]]+(explicitly[[:space:]]+)?(refused|rejected|forbidden|banned|disallowed|prohibited|excluded|avoided|not[[:space:]]+allowed|not[[:space:]]+used)|does[[:space:]]+not[[:space:]]+count|would[[:space:]]+prove[[:space:]]+nothing)"
  # A negation only excuses the phrase if it GOVERNS it. "The board figure is not available so the
  # gold is self-computed by the reproducing query" put a negation five words away that negates
  # something else entirely — and the gate accepted the confession. Widening the window to catch
  # real disclaimers ("We refuse any figure that is self-computed") made that possible, so the
  # window stays wide and a CLAUSE BOUNDARY between the negation and the phrase cancels it.
  # ERE has no lookahead, so this is a second pattern subtracted rather than an inline exclusion.
  local connform
  connform="(not|never|no|is not|are not|was not|were not|forbidden|forbids?|refuses?|refused|rejects?|rejected|bans?|banned|disallows?|prohibits?|avoids?|excludes?)([[:space:]]+[A-Za-z]+){0,5}[[:space:]]+(so|because|therefore|thus|hence|since|but|although|however|yet)([[:space:]]+[A-Za-z]+){0,5}[[:space:]]+($phrases)"
  local _cand _keep=""
  _cand="$(printf '%s' "$nsec" | grep -inFf "$pat" 2>/dev/null || true)"
  while IFS= read -r _cand_line; do
    [ -n "$_cand_line" ] || continue
    # excused only when a disclaimer governs it and no clause boundary intervenes
    if grep -qiE "$negform" <<<"$_cand_line" && ! grep -qiE "$connform" <<<"$_cand_line"; then continue; fi
    if grep -qiE "$postneg" <<<"$_cand_line"; then continue; fi
    _keep="$_keep$_cand_line
"
  done <<<"$_cand"
  bad="$(printf '%s' "$_keep" | grep -v '^$' | head -3 || true)"
  still="$(grep -iFf "$pat" "$ctl" 2>/dev/null | grep -ivE "$negform" | grep -ivcE "$postneg" || echo 0)"
  [ "${still:-0}" -ge 4 ] || die "gold-gate: NEGATION FILTER TOO BROAD — it now swallows $((4-still)) of the 4 positive-control lines. Refusing to report a verdict."
  if [ -n "$bad" ]; then
    echo "refuse: self-referential-gold" >&2
    die "gold-gate: the reconciliation gold is SELF-REFERENTIAL — a check the build runs against itself.
$(printf '%s' "$bad" | sed 's/^/    /')
  A query agreeing with itself proves nothing. If the pinned gold turned out not to be
  reproducible, that is a HARD STOP: say so and ask the user to choose (find another
  independent figure, accept a weaker gate explicitly, or re-cut the contract).
  Substituting a check the code can pass is exactly the failure this gate exists to stop."
  fi

  # ── Provenance, required of NEW builds that declare a gold. ─────────────────────────────────
  # N/A is a WHOLE-LINE / leading-token test now. Matching "N/A" anywhere let `gold: 4,182 loans
  # (units N/A)` read as "no gold declared".
  local goldlines realgold
  goldlines="$(printf '%s' "$nsec" | LC_ALL=C grep -i 'gold' || true)"
  realgold="$(printf '%s' "$goldlines" | LC_ALL=C grep -ivE '^[[:space:]]*[-*>]?[[:space:]]*(\*\*)?gold[^:]*:?(\*\*)?[[:space:]]*(is[[:space:]]+)?N/A\b' || true)"
  if [ -f "$dir/.compass-format" ] && [ -n "$realgold" ]; then
    local prov
    prov="$(printf '%s' "$nsec" | LC_ALL=C grep -iE 'provenance[^A-Za-z]*[:=-]' | head -1 || true)"
    [ -n "$prov" ] || die "gold-gate: this contract declares a numeric gold but names no provenance.
  Add a 'provenance:' line to the Reconciliation section naming the EXTERNAL artefact the figure
  comes from (an audited report, a board figure, a pre-change measurement of the old tree)."
    # A provenance that points back at the build is not provenance. "provenance: the query itself"
    # and "provenance: measured by the build itself" both satisfied a mere presence check, which
    # made the requirement decorative on exactly the contracts it was written to catch.
    local pval; pval="$(printf '%s' "$prov" | sed -E 's/.*[Pp]rovenance[^A-Za-z]*[:=-][[:space:]]*//')"
    if printf '%s' "$pval" | LC_ALL=C grep -qiE 'itself|self-comput|^[[:space:]]*(the[[:space:]]+)?(same[[:space:]]+)?(query|build|code|script|gate|check|tool|run|pipeline)[[:space:].]*$|measured[[:space:]]+by[[:space:]]+the[[:space:]]+(build|query|code|script)'; then
      echo "refuse: self-referential-provenance" >&2
      die "gold-gate: the provenance line points back at this build:
    $pval
  Provenance names something this build did NOT produce. If no such source exists, that is the
  HARD STOP — say so and ask the user, rather than citing the build as its own witness."
    fi
    printf '%s' "$pval" | LC_ALL=C grep -qE '[A-Za-z]{3}.*[A-Za-z]{3}' || die "gold-gate: the provenance line says nothing:
    $pval"
  fi
  ok "gold-gate: reconciliation gold is not self-referential."
}

# ── Human-typed utilities (v0.30, review-3) ───────────────────────────────────────────────────
# `orient-audit`, `artefact-audit`, `statusline-install`, `worktree-rm`, `cwd-slug` and
# `scripts/spawn-smoke.sh` are invoked by NO skill, hook or suite. That is deliberate for a
# forensic/CLI utility and a defect for anything meant to run automatically — the two look
# identical from the outside, which is how six gates in this plugin came to exist and never run.
# They are recorded here as the first kind. `spawn-smoke.sh` is asserted only to EXIST by the smoke
# suite, which is not coverage; it is a manual feasibility harness.
cmd_converge_waiver() { # <build-dir>  — may a NON-CONVERGED review-build hand on to ship?
  # Compass had two states for a review: PASS, or blocked. A third really happens — the review did
  # NOT converge and a human decided to ship anyway, knowing what is open. With no way to say that,
  # the only route forward was to tick a box that was false, which is the falsification this build
  # exists to prevent. So the state is sayable, and ONLY the user can say it.
  #
  # This deliberately does NOT live in `cmd_gate`: v0.28's INV-NO-LIFECYCLE-CHANGE freezes that
  # function's PASS/SUPERSEDED/unchecked-box semantics byte-for-byte, and it caught the attempt
  # immediately. A lifecycle change is high blast-radius and must not be made in passing — so the
  # gate stays frozen and the exception is an explicit, separate, loud step the ship stage takes.
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh converge-waiver <build-dir>"
  local f="$dir/receipts.md"; [ -f "$f" ] || die "converge-waiver: no receipts.md in '$dir'."
  local block; block="$(last_block "$f" review-build)"
  [ -n "$block" ] || die "converge-waiver: no review-build receipt in '$dir'."
  local header; header="$(printf '%s' "$block" | head -n1)"
  case "$header" in
    *"ACCEPTED WITH OPEN FINDINGS"*) : ;;
    *) die "converge-waiver: the review-build receipt is not 'ACCEPTED WITH OPEN FINDINGS' — use the normal gate." ;;
  esac
  printf '%s' "$block" | grep -qE '^- \[x\] converge-waiver: user-signed' \
    || die "converge-waiver: no user-signed waiver in the review-build receipt.
  A review that did not converge may only ship with a line the USER signs:
  - [x] converge-waiver: user-signed · <what is open, and who accepted it>
  A model-authored header does not count — that is how cold-critic became switchable."
  # Loud, every time, to stderr: nobody reads this build's state and misses it.
  printf 'COMPASS-GATE: WARN — this build SHIPS UN-CONVERGED under a user-signed waiver.\n' >&2
  printf '%s' "$block" | grep '^- \[ \]' | sed 's/^/    NOT ACHIEVED: /' >&2
  printf '%s' "$block" | grep -E '^- \[x\] converge-waiver: user-signed' | cut -c1-160 | sed 's/^/    SIGNED: /' >&2
  ok "converge-waiver: user-signed waiver present — ship may proceed, un-converged and recorded."
}

cmd_new_build() { # <slug> [--state-root <dir>]
  local slug="${1:-}"; [ -n "$slug" ] || die "usage: compass.sh new-build <slug>"
  case "$slug" in *[!a-zA-Z0-9._-]*) die "new-build: slug may only contain [A-Za-z0-9._-]: '$slug'" ;; esac
  local sr; sr="$(cmd_state_root 2>/dev/null)" || sr=".claude/builds"
  local dir="$sr/$slug"
  [ -d "$dir" ] && die "new-build: '$dir' already exists — refusing to overwrite a build directory."
  mkdir -p "$dir" || die "new-build: could not create '$dir'"
  printf 'compass-format: v0.30\ncreated: build-dir created by compass.sh new-build\n' > "$dir/.compass-format"
  ok "new-build: $dir (stamped .compass-format v0.30)"
}

# Guard-first refusal, with the DISCRIMINATOR review demanded: a legacy dir and a hand-made dir are
# byte-identical states, so a gate cannot refuse one and N/A-pass the other without a signal. The
# signal is "claims the new format but was not created by new-build" — a contract carrying a
# `compass-format:` header while the dotfile is absent. A legacy contract has neither and passes,
# so all 27 existing builds keep working (the rollback clause requires exactly that).
cmd_contract_gate() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh contract-gate <build-dir>"
  local c="$dir/contract.md"
  [ -f "$c" ] || return 0
  local hdr; hdr="$(hdr_get "$c" compass-format || true)"
  [ -n "$hdr" ] || { ok "contract-gate: N/A — legacy build dir (no compass-format header)."; return 0; }
  [ -f "$dir/.compass-format" ] || die "contract-gate: '$c' declares 'compass-format: $hdr' but $dir/.compass-format is absent.
  That header is model-written and proves nothing. Create build dirs with:
  compass.sh new-build <slug>"
  # A stamp is evidence only if it carries what new-build writes. `: > .compass-format` produced a
  # 0-byte file that passed as "created by new-build" — a stamp anyone can forge with one keystroke
  # is not a stamp.
  LC_ALL=C grep -q '^compass-format: v' "$dir/.compass-format" 2>/dev/null || die "contract-gate: $dir/.compass-format exists but is empty or malformed.
  Expected a line 'compass-format: v<version>' as written by 'compass.sh new-build'.
  A zero-byte stamp is not proof the dir was created by new-build."
  ok "contract-gate: build dir was created by new-build (stamp present and well-formed)."
}

cmd_statusline() { # [<build-dir>]
  local dir="${1:-}"
  if [ -z "$dir" ]; then
    local sr n first; sr="$(state_root 2>/dev/null)" || return 0
    n="$(_orient_active_rows "$sr" | grep -c . || true)"; n="${n:-0}"
    [ "$n" = "0" ] && return 0
    first="$(_orient_active_rows "$sr" | head -1 | awk '{print $1}')"
    dir="$sr/$first"
  fi
  [ -d "$dir" ] || return 0
  local slug cur="" total done_ next
  slug="$(basename "$dir")"
  for s in $LIFECYCLE; do if stage_pass "$dir" "$s"; then :; else cur="$s"; break; fi; done
  total="$(LC_ALL=C grep -cE '^[[:space:]]*- \[[ x~]\] ' "$dir/plan.md" 2>/dev/null || true)"; total="${total:-0}"
  done_="$(LC_ALL=C grep -cE '^[[:space:]]*- \[x\] ' "$dir/plan.md" 2>/dev/null || true)"; done_="${done_:-0}"
  next="$(LC_ALL=C sed -nE 's/^\*\*Next:\*\*[[:space:]]*(.*)/\1/p' "$dir/progress.md" 2>/dev/null | head -1 | cut -c1-40)"
  printf '%s · %s · step %s/%s · %s · %s\n' "$slug" "${cur:-done}" "$done_" "$total" "$(_orient_mode "$dir")" "${next:-—}"
}

# The teeth. A step cannot be marked done unless its card is ON the receipt.
# COMPASS_QUIET suppresses PRINTING, never RECORDING — so quiet mode does not
# deadlock the build loop.
cmd_progress_gate() { # <build-dir>
  local dir="${1:-}"; [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh progress-gate <build-dir>"
  local f="$dir/receipts.md"
  [ -f "$f" ] || return 0                       # guard-first: no receipts yet → N/A-pass (legacy/pre-build)
  # Bound the block at the NEXT '## ' header, not at EOF. Capturing to EOF meant
  # a card appearing in ANY later block — the final PASS receipt, say — satisfied
  # the gate for a step receipt that carried none. Found by the review-3
  # adversarial pass, which fed it exactly that shape.
  local blk; blk="$(LC_ALL=C awk '
    /^## RECEIPT .*IN-PROGRESS/ { buf=$0 "\n"; cap=1; next }
    cap && /^## / { last=buf; cap=0 }
    cap { buf=buf $0 "\n" }
    END { if (cap) last=buf; printf "%s", last }' "$f")"
  [ -n "$blk" ] || return 0                     # no IN-PROGRESS step receipt yet → N/A-pass
  printf '%s' "$blk" | LC_ALL=C grep -q '<!-- progress-card -->' \
    || die "progress-gate: the latest build step receipt carries no progress card. The user must always see what is planned and how far along it is — render it with 'compass.sh progress-card $dir' and fence it into the step receipt."
  # An empty fence is the byte-inert trap in miniature: the marker present, the
  # content absent. Require a real card body between the fences.
  local body; body="$(printf '%s' "$blk" | LC_ALL=C awk '/<!-- progress-card -->/{f=1;next} /<!-- \/progress-card -->/{f=0} f{print}' | LC_ALL=C grep -cE '[^[:space:]]' || true)"
  [ "${body:-0}" -ge 3 ] 2>/dev/null \
    || die "progress-gate: the progress-card fence is present but empty (or near-empty). A marker with no card is exactly the byte-inert failure this build exists to end."
  ok "progress-gate: latest step receipt carries a rendered progress card."
}

cmd_orient() { # [--new | --where <build-dir>]
  # Kill-switch: suppress USER-FACING output only. Recording is a separate
  # concern (see progress-gate) — a quiet mode that also stopped recording
  # would make INV-CARD-GATE hard-stop every build step.
  [ -n "${COMPASS_QUIET:-}" ] && return 0
  local mode="${1:-}" dir="${2:-}" out=""
  # No argument = auto-detect, so callers never have to decide which block is
  # right (INV-ONE-RENDERER: one renderer, three front doors).
  if [ -z "$mode" ]; then
    local sr n first; sr="$(state_root 2>/dev/null)"
    n="$(_orient_active_rows "$sr" | grep -c . || true)"; n="${n:-0}"
    if [ "$n" = "0" ]; then mode="--new"
    else
      first="$(_orient_active_rows "$sr" | head -1 | awk '{print $1}')"
      if [ "$n" = "1" ]; then mode="--where"; dir="$sr/$first"
      else
        # N>1: parallel builds are a keystone feature, and CURRENT is explicitly
        # a non-authoritative hint — so list them all, then show the hinted one
        # marked as a hint rather than pretending it is authoritative.
        out="$(_orient_multi_block "$sr")"
        printf '%s\n' "$out"
        _orient_log "$sr/orient.log" "orient" "multi" "${#out}"
        return 0
      fi
    fi
  fi
  case "$mode" in
    --new)
      out="$(_orient_new_block)"
      printf '%s\n' "$out"
      _orient_log "$(state_root 2>/dev/null)/orient.log" "orient" "new" "${#out}"
      return 0 ;;
    --where)
      [ -n "$dir" ] && [ -d "$dir" ] || die "usage: compass.sh orient --where <build-dir>"
      out="$(_orient_where_block "$dir")"
      printf '%s\n' "$out"
      _orient_log "$dir/orient.log" "orient" "where" "${#out}"
      return 0 ;;
    *) die "usage: compass.sh orient [--new | --where <build-dir>]" ;;
  esac
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
    cockpit)           cmd_cockpit "$@" ;;
    orient)            cmd_orient "$@" ;;
    progress-card)     cmd_progress_card "$@" ;;
    progress-gate)     cmd_progress_gate "$@" ;;
    redfirst-check)    cmd_redfirst_check "$@" ;;
    review-streams)   cmd_review_streams "$@" ;;
    engine-gate)      cmd_engine_gate "$@" ;;
    review-disclose-gate) cmd_review_disclose_gate "$@" ;;
    review-evidence-gate) cmd_review_evidence_gate "$@" ;;

    copy-gate)         cmd_copy_gate "$@" ;;
    gold-gate)         cmd_gold_gate "$@" ;;
    converge-waiver)   cmd_converge_waiver "$@" ;;
    new-build)         cmd_new_build "$@" ;;
    contract-gate)     cmd_contract_gate "$@" ;;
    statusline)        cmd_statusline "$@" ;;
    statusline-install) cmd_statusline_install "$@" ;;
    mode-gate)         cmd_mode_gate "$@" ;;
    artefact-gate)     cmd_artefact_gate "$@" ;;
    gold-numbers-gate) cmd_gold_numbers_gate "$@" ;;
    rail)              cmd_rail "$@" ;;
    artefact-publish)  cmd_artefact_publish "$@" ;;
    artefact-audit)    cmd_artefact_audit "$@" ;;
    orient-audit)      python3 "$(dirname "$0")/orient-audit.py" "$@" ;;
    milestone-gate)    cmd_milestone_gate "$@" ;;
    render)            cmd_render "$@" ;;
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
    intake-gate)       cmd_intake_gate "$@" ;;
    intake-phase)      cmd_intake_phase "$@" ;;
    sketch-gate)       cmd_sketch_gate "$@" ;;
    cockpit-gate)      cmd_cockpit_gate "$@" ;;
    stage-end-gate)    cmd_stage_end_gate "$@" ;;
    restore-point)     cmd_restore_point "$@" ;;
    config-parity)     cmd_config_parity "$@" ;;
    schema-pin-gate)   cmd_schema_pin_gate "$@" ;;
    perf-budget-gate)  cmd_perf_budget_gate "$@" ;;
    expand-contract-gate)    cmd_expand_contract_gate "$@" ;;
    backfill-recon-gate)     cmd_backfill_recon_gate "$@" ;;
    rollback-fwdcompat-gate) cmd_rollback_fwdcompat_gate "$@" ;;
    green-ci-gate)     cmd_green_ci_gate "$@" ;;
    pii-gate)          cmd_pii_gate "$@" ;;
    ship-prodsafety-receipt-match) cmd_ship_prodsafety_receipt_match "$@" ;;
    abort)             cmd_abort "$@" ;;
    abort-check)       cmd_abort_check "$@" ;;
    abort-clear)       cmd_abort_clear "$@" ;;
    bake-gate)         cmd_bake_gate "$@" ;;
    canary-analysis)   cmd_canary_analysis "$@" ;;
    watcher-check)     cmd_watcher_check "$@" ;;
    ship-cutover-receipt-match) cmd_ship_cutover_receipt_match "$@" ;;
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
    program-init)      cmd_program_init "$@" ;;
    program-ledger)    cmd_program_ledger "$@" ;;
    program-next)      cmd_program_next "$@" ;;
    program-advance)   cmd_program_advance "$@" ;;
    mutation-check)    cmd_mutation_check "$@" ;;
    redgreen-check)    cmd_redgreen_check "$@" ;;
    dora-record)       cmd_dora_record "$@" ;;
    dora-ledger)       cmd_dora_ledger "$@" ;;
    drift-check)       cmd_drift_check "$@" ;;
    *) echo "compass.sh: unknown subcommand '$sub'" >&2; exit 2 ;;
  esac
}
# v0.12.0 S2a: source-guard — `source compass.sh` loads the library without running main,
# so the suites can unit-drive internal helpers (hdr_get/ps_open_rows/*_match). CLI unchanged.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then main "$@"; fi
