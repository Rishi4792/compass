#!/usr/bin/env bash
# v0.32.0 S35 — §12's CANARY: no historical build may be newly refused by a gate this build adds.
#
# WHY THIS EXISTS AS A SCRIPT AND NOT A SENTENCE. Compass has shipped this mistake before: v0.28's
# mode-gate armed on a MISSING header and refused 25 of 26 existing builds. §12 makes the pinned
# corpus the canary and says any historical build a new gate would newly refuse is a RELEASE
# BLOCKER, not a fixture to delete. A promise like that needs a run, and the run needs a record —
# so this prints one, and `--record <file>` writes it.
#
# WHAT IT RUNS: every gate v0.32 adds or changes, over every build folder on the tree, in every
# lifecycle stage the seam takes. It is read-only: no gate here writes to a build.
#
# Usage: canary-gates.sh [<repo-root>] [--record <file>]
# Exit: 0 nothing newly refused · 1 at least one refusal · 2 usage/no builds.
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
case "$ROOT" in --*) ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)" ;; *) shift 2>/dev/null || true ;; esac
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "canary-gates: cannot resolve root"; exit 2; }
REC=""; SAMPLE=0
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --record) REC="${2:-}"; shift 2 ;;
    # A SAMPLE, for the suite. The full run is 374 gate calls and 41.7 seconds — it pushed the smoke
    # suite from 39s to 59.1s, past the 50.2s ceiling the contract states. Coverage is MOVED, not
    # deleted: the suite runs a sample every time and the RELEASE runs all of it. A sample says so
    # in its own output, so nobody can read it as the complete canary.
    --sample) SAMPLE="${2:-6}"; shift 2 ;;
    *) shift ;;
  esac
done
case "$SAMPLE" in ''|*[!0-9]*) SAMPLE=0 ;; esac
SH="$ROOT/plugins/compass/scripts/compass.sh"
[ -f "$SH" ] || { echo "canary-gates: no compass.sh at $SH"; exit 2; }

# The gates v0.32 ADDS or CHANGES. Anything not in this list is untouched by this build and is not
# this canary's business — a canary that re-runs everything cannot tell a new refusal from an old one.
# Determined from `git show <v0.31 tag>:compass.sh` rather than from memory: these five functions
# did not exist before v0.32, and perf-budget-gate's rule changed in S22.
GATES="engine-gate review-disclose-gate cockpit-gate stage-end-gate perf-budget-gate"
# DELIBERATELY EXCLUDED, and said out loud rather than quietly dropped:
#   · progress-gate — it existed before v0.32 and this build did not change it. Its refusals on 9
#     legacy folders are pre-existing behaviour; a canary that cannot tell a NEW refusal from an old
#     one reports 41 problems and hides the one that matters.
#   · copy-gate — v0.32 changed it (S14), but it takes a FILE, not a build directory. It is
#     exercised over real files below instead of being fed a directory and refusing 30 times on a
#     usage error, which is what the first version of this script did.
EXCLUDED="progress-gate(pre-existing) copy-gate(takes-a-file,run-separately-below)"
STAGES="contract plan build review-contract review-plan review-build ship"

BUILDS="$ROOT/.claude/builds"
[ -d "$BUILDS" ] || { echo "canary-gates: no .claude/builds at $BUILDS — nothing to canary. That is an ERR, not a pass: this directory is gitignored, so an empty run on a clean clone would otherwise read as 'nothing newly refused'."; exit 2; }
n_b=0; for d in "$BUILDS"/*/; do [ -d "$d" ] && n_b=$((n_b+1)); done
[ "$n_b" -gt 0 ] || { echo "canary-gates: ERR - zero build folders. An empty canary proves nothing."; exit 2; }

out=""; refused=0; calls=0; seen=0
for d in "$BUILDS"/*/; do
  [ -d "$d" ] || continue
  seen=$((seen+1))
  [ "$SAMPLE" -gt 0 ] && [ "$seen" -gt "$SAMPLE" ] && continue
  slug="$(basename "$d")"
  for g in $GATES; do
    calls=$((calls+1))
    if msg="$(bash "$SH" "$g" "$d" 2>&1)"; then :; else
      refused=$((refused+1))
      out="$out
  REFUSED $slug · $g · $(printf '%s' "$msg" | head -1 | cut -c1-140)"
    fi
  done
  # ...and the SEAM, which is what a real lifecycle crosses. A gate can pass standalone and refuse
  # here, or never be reached at all — both were real defects in this build.
  for st in $STAGES; do
    calls=$((calls+1))
    msg="$(bash "$SH" gate "$d" "$st" 2>&1 || true)"
    case "$msg" in
      *"engine-gate FAILED"*|*"review-disclose-gate FAILED"*|*"review-evidence-gate FAILED"*|*"perf-budget-gate FAILED"*|*"no RUN SERIES behind them"*|*"records no 'engine:' line"*|*"say nothing about independence"*)
        refused=$((refused+1))
        out="$out
  REFUSED $slug · gate/$st · $(printf '%s' "$msg" | head -1 | cut -c1-140)" ;;
    esac
  done
done

# copy-gate over real FILES — the argument it actually takes. Every reader-copy block on the tree.
cg_n=0; cg_bad=0
for f in "$ROOT/plugins/compass/scripts/fixtures"/*/*.md "$ROOT/plugins/compass/skills"/*/SKILL.md; do
  [ -f "$f" ] || continue
  grep -q 'compass-format\|reader-copy\|## Reader copy' "$f" 2>/dev/null || continue
  cg_n=$((cg_n+1)); calls=$((calls+1))
  if ! msg="$(bash "$SH" copy-gate "$f" 2>&1)"; then
    cg_bad=$((cg_bad+1)); refused=$((refused+1))
    out="$out
  REFUSED $(basename "$(dirname "$f")")/$(basename "$f") · copy-gate · $(printf '%s' "$msg" | head -1 | cut -c1-140)"
  fi
done

_scope="all $n_b build folders"
if [ "$SAMPLE" -gt 0 ] && [ "$SAMPLE" -lt "$n_b" ]; then
  _scope="a SAMPLE of $SAMPLE of $n_b build folders — this is NOT the full canary; the release must run it without --sample"
fi
report="canary-gates: $calls gate calls over $_scope · $refused newly refused
  gates run  : $GATES
  excluded   : $EXCLUDED
  copy-gate  : $cg_n file(s) carrying a reader-copy block, $cg_bad refused"
[ -n "$out" ] && report="$report$out"
printf '%s\n' "$report"
if [ -n "$REC" ]; then
  { printf '# canary-gates run\n\n'; printf 'gates: %s\n' "$GATES"; printf 'stages: %s\n\n' "$STAGES"; printf '%s\n' "$report"; } > "$REC" 2>/dev/null \
    && printf 'canary-gates: recorded to %s\n' "$REC"
fi
[ "$refused" -eq 0 ] || exit 1
exit 0
