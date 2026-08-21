#!/usr/bin/env bash
# A BEHAVIOUR entry, not a cheat. It asserts BOTH directions, because a gate that refuses
# everything would satisfy a one-directional "must refuse" for free:
#   the ACCEPTING fixture must PASS, and the offending one must be REFUSED.
set -uo pipefail
SH="$1/plugins/compass/scripts/compass.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/good" "$T/bad"
printf '# r\n\n## RECEIPT — build · t · PASS\n- [x] stage-end: cockpit=printed · asked=yes · answer=continue\n' > "$T/good/receipts.md"
printf '# r\n\n## RECEIPT — build · t · PASS\n- [x] stage-end: %s\n' 'cockpit=printed' > "$T/bad/receipts.md"
bash "$SH" stage-end-gate "$T/good" >/dev/null 2>&1 || { echo "the ACCEPTING fixture was refused — the gate refuses everything"; exit 1; }
bash "$SH" stage-end-gate "$T/bad" >/dev/null 2>&1 && { echo "a stage end recording no ask at all was ACCEPTED — the next step must be asked, or the receipt must say why it was not"; exit 1; }
exit 0
