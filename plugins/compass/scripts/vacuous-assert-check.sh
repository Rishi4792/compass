#!/usr/bin/env bash
# vacuous-assert-check — assertions that cannot fail. (v0.33, INV-NO-VACUOUS-ASSERTION)
#
# GUARD-FIRST, measured on this repo before a single rule was written, because a check that fires on
# correct work gets disabled within a week:
#
#   smoke.sh holds 680 assertions, selftest.sh 163.
#   * constant-vs-constant  : 12 in smoke, 0 in selftest. ALL TWELVE are deliberate N/A skip markers
#     in an else-branch, each labelled "N/A — <reason>". A naive rule would have failed 12 correct
#     lines on its first run.
#   * assert-over-the-live-build-path : 5 candidates, and ALL FIVE are correct — three are the N/A
#     markers above, one asserts zero bytes when there is deliberately no state, and one reads a
#     fixture the suite itself creates under its temp root.
#   * chk-inside-a-loop-that-can-be-empty : 12 candidates, 4 guarded, and 2 of the remainder are
#     JavaScript `for` loops inside a heredoc, not shell loops at all.
#
# SO THIS SCRIPT SPLITS WHAT IT CAN DECIDE FROM WHAT IT CANNOT, and says which is which:
#   MEASUREMENT (exit non-zero) — constant-vs-constant with no declared N/A. Zero false positives on
#     this tree, proven above.
#   REPORTING  (never fails)    — the loop and live-path candidates. A static line scan cannot tell a
#     vacuous one from a correct one here; that is a judgment, which is precisely the boundary this
#     whole build is about. Printing them with that caveat is honest. Failing on them would not be.
#
# Usage: vacuous-assert-check.sh <repo-root>   Exit 0 clean · 1 vacuous found · 2 usage.
set -uo pipefail
R="${1:-.}"
cd "$R" 2>/dev/null || { echo "vacuous-assert-check: cannot enter '$R'"; exit 2; }
[ -d plugins/compass ] || { echo "vacuous-assert-check: not a compass repo root: $R"; exit 2; }

SUITES="plugins/compass/scripts/compass.smoke.sh plugins/compass/scripts/compass.selftest.sh"
total=0; vacuous=0; na=0; cand_loop=0; cand_path=0; files=0

for f in $SUITES; do
  [ -f "$f" ] || continue
  files=$((files+1))
  n=$(LC_ALL=C grep -cE '^[[:space:]]*chk[[:space:]]' "$f" || true); total=$((total+${n:-0}))

  # ── MEASUREMENT: both sides literal, and the label does NOT declare an N/A with a reason ──────
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    ln="${line%%:*}"
    if printf '%s' "$line" | LC_ALL=C grep -qE 'N/A[[:space:]]*[—–-]'; then
      na=$((na+1)); continue
    fi
    printf '  VACUOUS %s:%s\n' "$f" "$ln"
    printf '          %s\n' "$(printf '%s' "${line#*:}" | cut -c1-110)"
    printf '          both sides are literals, so this assertion cannot fail. If it marks a skipped\n'
    printf '          branch, say so: label it "N/A — <reason>", the way the other %s do.\n' "$na"
    vacuous=$((vacuous+1))
  done <<EOF
$(LC_ALL=C grep -nE '^[[:space:]]*chk[[:space:]]+"[^"$]*"[[:space:]]+"[^"$]*"' "$f" || true)
EOF

  # ── REPORTING: candidates a line scan cannot decide ───────────────────────────────────────────
  c=$(LC_ALL=C awk '
        /^[[:space:]]*(for|while) .*(\*|\$\()/ && !/for[[:space:]]*\(/ {loop=NR}
        loop && /chk / {n++; loop=0}
        END{print n+0}' "$f")
  cand_loop=$((cand_loop+${c:-0}))
  c=$(LC_ALL=C grep -nE '^[[:space:]]*chk .*[^/$"]\.claude/builds' "$f" 2>/dev/null | grep -vc '\$[A-Za-z_]*/\.claude' || true)
  cand_path=$((cand_path+${c:-0}))
done

echo
# VACUITY GUARD — the check refusing to be vacuous about vacuity.
if [ "$files" -eq 0 ] || [ "$total" -eq 0 ]; then
  echo "vacuous-assert-check: ERR — $files suite file(s), $total assertions. A green over an empty set is not a signal."
  exit 1
fi
printf 'vacuous-assert-check: %s vacuous of %s assertions across %s suite file(s).\n' "$vacuous" "$total" "$files"
printf '  %s constant-vs-constant assertions declare "N/A — <reason>" and are counted as deliberate skips.\n' "$na"
printf '  REPORTED, NOT FAILED (a static scan cannot decide these — they need a person):\n'
printf '    %s assertion(s) inside a loop whose source can be empty — zero iterations is zero failures.\n' "$cand_loop"
printf '    %s assertion(s) reading the live build path, which is gitignored and empty on a clean clone.\n' "$cand_path"
[ "$vacuous" -eq 0 ] || exit 1
exit 0
