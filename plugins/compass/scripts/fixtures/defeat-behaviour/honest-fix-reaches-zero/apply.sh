#!/usr/bin/env bash
# NOT A CHEAT — the POSITIVE CONTROL, and deliberately a NO-OP.
#
# It used to SIMULATE an honest fix by appending a control per dropped unit at the end of the page.
# That stopped being valid the moment the check learned to tie a control to its ROW by position: a
# pile of controls at the page foot is an aggregation, not disclosure, and the check is right to
# refuse it. Simulating a fix that the rules correctly reject proves nothing.
#
# So this applies NOTHING and asserts the SHIPPED generator reaches zero on every path the check can
# bind. That is the real acceptance criterion, and running it here means the corpus notices the day
# the target stops being reachable — which is the v0.31 failure this entry exists to prevent.
set -euo pipefail
[ -n "${1:-}" ] || { echo "usage: apply.sh <work-root>"; exit 2; }
assert_noop=1   # nothing is patched, on purpose; the runner still checks the figure
echo "honest-fix-reaches-zero: no mutation applied — asserting the SHIPPED generator reaches zero." >&2
