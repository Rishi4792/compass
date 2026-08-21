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
# v0.32 S4b, C-4: a page that FAILED TO RENDER is not a page with nothing unreachable on it.
# An independent reviewer appended `throw new Error("boom")` to gen.mjs and got
# `0 pages rendered, 24 failed` -> `COMPASS-GATE: PASS`, rc=0. The empty-CORPUS case was guarded;
# the zero-PAGES case was not, and they fail the same way — a confident zero from a measurement
# that never happened.
_pr="$(printf '%s' "$out" | sed -nE 's/^reachable-argument: ([0-9]+) pages rendered, ([0-9]+) failed.*/\1 \2/p' | head -1)"
_rendered="${_pr%% *}"; _failed="${_pr##* }"
if [ -z "$_pr" ] || [ "${_rendered:-0}" -eq 0 ]; then
  echo "COMPASS-GATE: ERR — reachable-argument: ZERO pages rendered. Nothing was measured, and a zero from an unmeasured corpus is not a clean result."; exit 3
fi
if [ "${_failed:-0}" -gt 0 ]; then
  echo "COMPASS-GATE: ERR — reachable-argument: $_failed page(s) failed to render, so their rows were never checked. A partial measurement is not a pass."; exit 3
fi
# The verdict is read from the PRINTED figure, never from the exit code alone — SELF-4, the day a
# missing `timeout` binary exited 0 with the suite never run.
n="$(printf '%s' "$out" | sed -nE 's/^[[:space:]]*UNREACHABLE[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)"
if [ -z "$n" ]; then
  echo "COMPASS-GATE: ERR — reachable-argument printed no UNREACHABLE figure. Silence is not a pass."; exit 3
fi
# ── WHAT THIS GATE CANNOT SEE, printed on EVERY run — passing, failing, either way ───────────
# Rishi's call, 2026-08-21: ship v0.32 with C-1 named rather than deleted or ground on further.
# A verdict given without saying what the check is blind to is the exact thing this build exists to
# stop, so the blindness prints beside the verdict — not in a comment, not in a CHANGELOG only.
# Above BOTH branches on purpose: a FAIL is just as incomplete a statement as a PASS.
_bopen="$(grep -c '^open=' "$(dirname "$0")/fixtures/defeat-behaviour"/*/EXPECTED 2>/dev/null | awk -F: '{t+=$2} END{print t+0}')"
if [ "${_bopen:-0}" -gt 0 ]; then
  echo "  KNOWN OPEN           : $_bopen cheat(s) in the behaviour corpus are NOT defeated by this"
  echo "                         check. A generator that lies about its own trace cannot be caught"
  echo "                         from inside the generator's process. Run behaviour-corpus-check.sh"
  echo "                         for the named list. This verdict is sound only against the cheats"
  echo "                         the corpus proves it defeats."
fi
if [ "$n" -eq 0 ]; then
echo "COMPASS-GATE: PASS — reachable-argument: every dropped unit is reachable on its own page."; exit 0
fi
echo "COMPASS-GATE: FAIL — reachable-argument: $n dropped units cannot be reached by a reader."
exit 1
