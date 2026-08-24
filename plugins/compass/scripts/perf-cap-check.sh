#!/usr/bin/env bash
# perf-cap-check — the speed cap, MEASURED rather than merely written. (v0.33, INV-PERF-CAP-MEASURED)
#
# WHY IT EXISTS. `perf-budget-gate` proves a budget was WRITTEN — axes named, literals present, an
# SLO range stated. It never runs anything. So a contract can state a baseline that was never taken
# and the gate goes green, which is exactly what happened here: v1-v6 of this build's contract
# claimed a baseline "MEASURED in a clean clone", and those three numbers were copied from a
# previous release's measurement of a DIFFERENT commit. The gate passed all six versions.
#
# THREE RULES IT FOLLOWS, each from a defect this build hit:
#   1. It asserts a CEILING, never an equality. A wall clock never repeats, so equality is a test
#      that fails at random, and a speed gate that goes spuriously red is a speed gate somebody
#      switches off.
#   2. It takes the MEDIAN of three runs, the way the contract's own baseline is measured, so one
#      slow scheduling moment does not decide the verdict.
#   3. It PRINTS the figure it judged. A verdict without its number cannot be argued with, and this
#      build has now corrected five figures that nobody could see.
#
# Usage: perf-cap-check.sh <repo-root> [--ceiling N] [--runs N]
#        Exit 0 inside the ceiling · 1 over it · 2 usage.
set -uo pipefail
R="${1:-.}"; shift 2>/dev/null || true
CEIL=""; RUNS=3
while [ $# -gt 0 ]; do
  case "$1" in
    --ceiling) CEIL="${2:-}"; shift 2 ;;
    --runs)    RUNS="${2:-3}"; shift 2 ;;
    *) shift ;;
  esac
done
cd "$R" 2>/dev/null || { echo "perf-cap-check: cannot enter '$R'"; exit 2; }
SUITE=plugins/compass/scripts/compass.smoke.sh
[ -f "$SUITE" ] || { echo "perf-cap-check: no suite at $SUITE"; exit 2; }

# The ceiling comes from ONE place — the contract — so it cannot drift from the number the contract
# states. Review-2 round 4 found this build stating two different ceilings at once after a fix
# landed in the header and not in the invariant.
if [ -z "$CEIL" ]; then
  C="$(cat .claude/builds/CURRENT 2>/dev/null | head -1)"
  [ -n "$C" ] && CEIL="$(LC_ALL=C sed -n 's/.*p95 ceiling on the whole suite is \([0-9][0-9.]*\)s.*/\1/p' ".claude/builds/$C/contract.md" 2>/dev/null | head -1)"
fi
[ -n "$CEIL" ] || { echo "perf-cap-check: ERR — no ceiling found in the contract and none given. Refusing to invent one."; exit 2; }

case "${RUNS:-0}" in ''|*[!0-9]*|0) echo "perf-cap-check: ERR — runs must be a positive integer."; exit 2 ;; esac

times=""
i=1
while [ "$i" -le "$RUNS" ]; do
  s=$(date +%s); bash "$SUITE" >/dev/null 2>&1; e=$(date +%s)
  times="$times $((e-s))"
  i=$((i+1))
done
med="$(printf '%s\n' $times | LC_ALL=C sort -n | awk -v n="$RUNS" 'NR==int((n+1)/2){print}')"

# STATE THE SET. The same suite runs ~38s in a fresh clone and ~48s on a tree carrying build
# folders, because several checks iterate them. Reporting a duration without saying which set it
# was taken over is how this build published a baseline nobody could reproduce — twice.
_bs="absent (clean-clone conditions, the set an installer has)"
[ -d .claude/builds ] && _bs="PRESENT ($(ls -d .claude/builds/*/ 2>/dev/null | grep -c . || echo 0) folders — this run is SLOWER than an installer's by ~10s)"
printf 'perf-cap-check: median %ss of %s run(s) [%s ] against a %ss ceiling.\n' "$med" "$RUNS" "$times" "$CEIL"
printf '  build state: %s\n' "$_bs"
printf '  Asserting a CEILING, never an equality — a wall clock never repeats, and a speed gate that\n'
printf '  goes spuriously red is one somebody switches off. The ceiling is read from the contract,\n'
printf '  from one place, so it cannot drift from the number the contract states.\n'
# Integer comparison against a possibly-decimal ceiling: compare in tenths, no bc dependency.
ct=$(printf '%s' "$CEIL" | awk '{printf "%d", ($1*10)+0.5}')
mt=$((med*10))
if [ "$mt" -le "$ct" ]; then
  printf '  INSIDE the ceiling by %ss.\n' "$(awk -v a="$ct" -v b="$mt" 'BEGIN{printf "%.1f",(a-b)/10}')"
  exit 0
fi
printf '  OVER the ceiling by %ss. This is a release blocker, not a note.\n' "$(awk -v a="$ct" -v b="$mt" 'BEGIN{printf "%.1f",(b-a)/10}')"
exit 1
