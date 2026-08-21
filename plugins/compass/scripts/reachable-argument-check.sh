#!/usr/bin/env bash
# v0.32 S4 — THE GOLD'S CHECK. How many dropped units can a reader still get to?
#
# This is the named entry point contract section 9 and plan step S4 refer to. The measurement lives
# in `reachable-argument.mjs` beside it; this wrapper exists so the check has one stable name, one
# stable exit contract, and so the ERR case cannot be mistaken for a pass by a caller reading only
# an exit code.
#
# Exit: 0 every dropped unit is reachable · 1 some are not · 2 usage · 3 ERR, the corpus is empty.
#
# COMPASS_V32_STRICT is NOT read here and must never be. Contract section 12: the kill switch may
# silence a REPORTING gate; it may never silence the MEASUREMENT. A flag that can turn a measurement
# off produces a zero that is indistinguishable from a fix.
set -uo pipefail
ROOT="${1:-.}"; shift || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MJS="$HERE/reachable-argument.mjs"
[ -f "$MJS" ] || { echo "reachable-argument-check: ERR - no measurement at $MJS"; exit 3; }
command -v node >/dev/null 2>&1 || { echo "reachable-argument-check: ERR - node is not on PATH, so nothing was measured. This is an ERR, never a pass."; exit 3; }

out="$(node "$MJS" "$ROOT" "$@" 2>&1)"; rc=$?
printf '%s\n' "$out"
case "$rc" in
  3) echo "COMPASS-GATE: ERR — reachable-argument: nothing was measured. A corpus with no pages is not a clean result."; exit 3 ;;
  2) echo "COMPASS-GATE: ERR — reachable-argument: usage."; exit 2 ;;
esac
# The verdict is read from the PRINTED figure, never from the exit code alone — SELF-4, the day a
# missing `timeout` binary exited 0 with the suite never run.
n="$(printf '%s' "$out" | sed -nE 's/^[[:space:]]*UNREACHABLE[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)"
if [ -z "$n" ]; then
  echo "COMPASS-GATE: ERR — reachable-argument printed no UNREACHABLE figure. Silence is not a pass."; exit 3
fi
if [ "$n" -eq 0 ]; then
  echo "COMPASS-GATE: PASS — reachable-argument: every dropped unit is reachable on its own page."; exit 0
fi
echo "COMPASS-GATE: FAIL — reachable-argument: $n dropped units cannot be reached by a reader."
exit 1
