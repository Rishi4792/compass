#!/usr/bin/env bash
# suite-member: mechanical-suite — the suite's child list must NAME this check; removing it from
# CHILDREN while this line stands makes the suite ERR.
#
# leak-scan-check — the shipped tree carries no home path and no session id. (v0.34.1)
#
#   usage: leak-scan-check.sh [repo-root]
#
# WHY THIS EXISTS. An absolute home path shipped inside this PUBLIC plugin in four fixture files
# across FIFTEEN tagged releases, v0.28.0 through v0.33.5. It was found by a person doing a release
# soak by hand, not by a check. `compass.sh secret-scan` returned PASS on the very commit that
# published it, and `INV-NO-LEAK` in smoke is implemented by calling that same function, so it
# inherited the blindness. There was no CI, no git hook, and no scan step in RELEASING.md. The class
# had no owner.
#
# WHAT "THE SHIPPED TREE" MEANS. The first version of this check scanned `plugins/` only. An
# independent reviewer planted a home path in README.md, CHANGELOG.md and docs/index.html — all
# public on GitHub — and this check reported clean. The population that ships is the set git TRACKS,
# so that is what is scanned: `secret-scan --tracked`. No hand-written exclude list survives.
#
# exit 0  the shipped tree is clean
# exit 1  a home path or a session id reached a shipped file — named, with its line
# exit 2  usage / not a compass repo
set -uo pipefail
ROOT="${1:-.}"
case "$ROOT" in --help|-h) sed -n '5,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
cd "$ROOT" 2>/dev/null || { echo "leak-scan-check: cannot enter '$ROOT'" >&2; exit 2; }
[ -d plugins/compass ] || { echo "leak-scan-check: not a compass repo root" >&2; exit 2; }

out="$(bash plugins/compass/scripts/compass.sh secret-scan --tracked 2>&1)"; rc=$?
n="$(git ls-files 2>/dev/null | grep -c . || true)"; n="${n:-0}"
if [ "$rc" -ne 0 ]; then
  hits="$(printf '%s\n' "$out" | grep -cE '^[^ ].*:[0-9]+:' || true)"; hits="${hits:-0}"
  # Every line of the detail starts with this check's own name. mechanical-suite.sh keeps only the
  # lines that do, and an independent reviewer proved the indented hit list was thrown away — the
  # suite printed a headline with nothing under it. Prefixing each line keeps the detail through
  # BOTH paths, and the suite now prints a failing child's full output as well.
  printf 'leak-scan-check: the SHIPPED tree carries something private — %s hit(s) in %s tracked files.\n' "$hits" "$n"
  printf '%s\n' "$out" | sed 's/^/leak-scan-check:     /' | head -14
  if [ "$hits" -gt 12 ]; then printf 'leak-scan-check:     … %s more not shown.\n' "$((hits-12))"; fi
  printf 'leak-scan-check:   Anything tracked becomes public on the next push.\n'
  exit 1
fi
printf 'leak-scan-check: %s tracked files carry no home path and no session id.\n' "$n"
exit 0
