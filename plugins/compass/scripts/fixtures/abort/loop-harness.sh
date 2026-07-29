#!/usr/bin/env bash
# INV-ABORT loop-harness — proves `compass.sh abort-check` halts a step-loop BEFORE the next mutating
# op (not merely that a SKILL line exists). A build sets abort after op 2; op 3's pre-check must halt,
# so ops 3-5 never run. Prints HALTED-before-op-3 ran=2 and exits 0; a no-halt run exits 1.
SH="${1:?usage: loop-harness.sh <path-to-compass.sh>}"
D="$(mktemp -d)"; printf '# harness build dir\n' > "$D/contract.md"
trap 'rm -rf "$D"' EXIT
ran=0
for k in 1 2 3 4 5; do
  bash "$SH" abort-check "$D" >/dev/null || { echo "HALTED-before-op-$k ran=$ran"; exit 0; }
  ran=$k                                        # the "mutating op" for step k
  [ "$k" = 2 ] && bash "$SH" abort "$D" >/dev/null   # a mid-flight abort is requested after op 2
done
echo "NO-HALT ran=$ran"; exit 1
