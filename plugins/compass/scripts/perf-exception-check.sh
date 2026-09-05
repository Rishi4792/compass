#!/usr/bin/env bash
# perf-exception-check — decide whether a measured overage is covered by a SIGNED, BOUNDED exception.
#
# WHY THIS IS ITS OWN SCRIPT. The decision lives here, apart from `perf-cap-check`, for exactly one
# reason: `perf-cap-check` runs the whole test suite before it can decide anything, so any test of
# the decision would cost a full suite run per case and nobody would write one. An exception
# mechanism with no test that can fail is the precise defect this release has spent six review
# streams removing — a rule stated in prose, believed by everyone, and never once exercised. Split
# out, the decision takes a number on the command line and every branch is testable in milliseconds.
#
# WHAT IT IS FOR. "Raise the ceiling until it passes" and "one named release ships over a measured
# bound, on the owner's signature" are different acts, and only the second is honest. The first is
# forbidden here and stays forbidden. Nothing in this script writes to perf-ceiling.txt or to any
# contract, and with no exception file present it refuses, which is the default every release has.
#
# THREE BOUNDS, each of which independently restores the block:
#   VERSION   — the exception names one release. Bump plugin.json and it is spent, with no edit and
#               no reminder needed.
#   MAGNITUDE — it names the figure it covers. Grow past that and it fails again, so an exception
#               cannot become cover for a suite that keeps getting slower.
#   SIGNATURE — a person is named and dated in the file. An unsigned or half-written exception is
#               not a decision anybody made, and is refused rather than read generously.
#
# Usage: perf-exception-check.sh <measured-seconds> <ceiling-seconds> [repo-root]
# Exit:  0 covered by a valid, signed, in-date exception · 1 not covered (blocker) · 2 usage.
set -uo pipefail

MEAS="${1:-}"; CEIL="${2:-}"; ROOT="${3:-.}"
case "$MEAS" in ''|*[!0-9.]*) echo "perf-exception-check: usage: perf-exception-check.sh <measured-seconds> <ceiling-seconds> [repo-root]" >&2; exit 2 ;; esac
case "$CEIL" in ''|*[!0-9.]*) echo "perf-exception-check: usage: perf-exception-check.sh <measured-seconds> <ceiling-seconds> [repo-root]" >&2; exit 2 ;; esac

EXC="$ROOT/plugins/compass/scripts/perf-exception.txt"
PJ="$ROOT/plugins/compass/.claude-plugin/plugin.json"

if [ ! -f "$EXC" ]; then
  printf '  No exception on record. This is a release blocker, not a note.\n'
  exit 1
fi

_ev="$(LC_ALL=C sed -n 's/^exception-version:[[:space:]]*\(.*\)$/\1/p' "$EXC" 2>/dev/null | head -1 | tr -d ' \r')"
_ec="$(LC_ALL=C sed -n 's/^exception-ceiling-seconds:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' "$EXC" 2>/dev/null | head -1)"
_es="$(LC_ALL=C sed -n 's/^exception-signed-by:[[:space:]]*\(.*\)$/\1/p' "$EXC" 2>/dev/null | head -1 | sed 's/[[:space:]]*$//')"
_ed="$(LC_ALL=C sed -n 's/^exception-signed-date:[[:space:]]*\(.*\)$/\1/p' "$EXC" 2>/dev/null | head -1 | tr -d ' \r')"
_pv="$(LC_ALL=C sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PJ" 2>/dev/null | head -1)"

if [ -z "$_ev" ] || [ -z "$_ec" ] || [ -z "$_es" ] || [ -z "$_ed" ]; then
  printf '  An exception file exists but is INCOMPLETE — it needs a version, a figure, a signer and a\n'
  printf '  date, and it is missing:%s%s%s%s. A partial exception is not a decision anybody made.\n' \
    "$( [ -z "$_ev" ] && printf ' version')" "$( [ -z "$_ec" ] && printf ' figure')" \
    "$( [ -z "$_es" ] && printf ' signer')" "$( [ -z "$_ed" ] && printf ' date')"
  printf '  Release blocker.\n'
  exit 1
fi

if [ -z "$_pv" ] || [ "$_ev" != "$_pv" ]; then
  printf '  The exception was signed for version %s and this tree is version %s, so it is SPENT.\n' "$_ev" "${_pv:-unknown}"
  printf '  An exception covers one release and expires by itself. Release blocker.\n'
  exit 1
fi

_mt=$(printf '%s' "$MEAS" | awk '{printf "%d", ($1*10)+0.5}')
_et=$(printf '%s' "$_ec"  | awk '{printf "%d", ($1*10)+0.5}')
if [ "$_mt" -gt "$_et" ]; then
  printf '  OVER EVEN THE SIGNED EXCEPTION by %ss (it covers %ss for v%s).\n' \
    "$(awk -v a="$_et" -v b="$_mt" 'BEGIN{printf "%.1f",(b-a)/10}')" "$_ec" "$_ev"
  printf '  The exception bounds the overage it was signed for; it does not license more.\n'
  printf '  Release blocker.\n'
  exit 1
fi

printf '  COVERED by a signed exception for v%s: up to %ss, signed by %s on %s.\n' "$_ev" "$_ec" "$_es" "$_ed"
printf '  The %ss CEILING IS UNCHANGED and still binds every other release. This exception is spent\n' "$CEIL"
printf '  the moment the version changes. Reason on record in perf-exception.txt.\n'
exit 0
