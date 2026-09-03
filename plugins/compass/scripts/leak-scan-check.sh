#!/usr/bin/env bash
# suite-member: mechanical-suite — the suite's child list must NAME this check; removing it from
# CHILDREN while this line stands makes the suite ERR.
#
# leak-scan-check — the shipped tree carries no home path and no session id. (v0.34.1)
#
#   usage: leak-scan-check.sh [repo-root]
#
# WHY THIS EXISTS. An absolute home path shipped inside this PUBLIC plugin from v0.28.0 to v0.34.0 —
# six releases — in four fixture files. It was found by a person doing a release soak by hand, not by
# a check. `compass.sh secret-scan` returned PASS on the very commit that published it, and
# `INV-NO-LEAK` in smoke is implemented by calling that same function, so it inherited the blindness.
# There was no CI, no git hook, and no scan step in RELEASING.md. The class had no owner.
#
# This runs the scanner over the tree that actually ships, every time the suite runs, so the next one
# is caught by a script rather than by somebody remembering.
#
# exit 0  the shipped tree is clean
# exit 1  a home path or a session id reached a shipped file — named, with its line
# exit 2  usage / not a compass repo
set -uo pipefail
ROOT="${1:-.}"
case "$ROOT" in --help|-h) sed -n '5,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
cd "$ROOT" 2>/dev/null || { echo "leak-scan-check: cannot enter '$ROOT'" >&2; exit 2; }
[ -d plugins/compass ] || { echo "leak-scan-check: not a compass repo root" >&2; exit 2; }

out="$(bash plugins/compass/scripts/compass.sh secret-scan plugins 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
  echo "leak-scan-check: the SHIPPED tree carries something private:"
  printf '%s\n' "$out" | sed 's/^/    /' | head -12
  echo "  A home path or a session id in plugins/ becomes public on the next push."
  exit 1
fi
echo "leak-scan-check: the shipped tree carries no home path and no session id."
exit 0
