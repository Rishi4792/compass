#!/usr/bin/env bash
# compass.recon.sh — the EXECUTABLE reconciliation guard for the Compass plugin itself
# (build loop-eyes-intake-v0-12-13, contract v3a "Reconciliation", RC-7/RD-13/Q4/VZ).
#
# PASS (exit 0) iff BOTH suites run green AND their pass-counts — extracted PER SUITE from that
# suite's own pinned, last-line-anchored output shape (so the two counts can never cross-match) —
# meet the pinned baselines AND every pinned INV-group name appears in the suites' output.
# The gold is self-editable by the build, so this guard enforces the count FLOOR: a build that
# deletes or weakens baseline tests cannot reconcile. Refusal codes (stderr `refuse: <code>`):
# floor-selftest · floor-smoke · inv-missing · cross-match.
#
# Test stubs (INV-RECON fixtures, the P18 pattern): COMPASS_RECON_SELFTEST_CMD /
# COMPASS_RECON_SMOKE_CMD override the suite commands with canned-tail emitters.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ST_CMD_DEFAULT="bash \"$HERE/compass.selftest.sh\""
SM_CMD_DEFAULT="bash \"$HERE/compass.smoke.sh\""
ST_CMD="${COMPASS_RECON_SELFTEST_CMD:-$ST_CMD_DEFAULT}"
SM_CMD="${COMPASS_RECON_SMOKE_CMD:-$SM_CMD_DEFAULT}"

FLOOR_SELFTEST=349
FLOOR_SMOKE=114
# PINNED literal INV-group list (v0.12; S15 appends the v0.13 groups). Authored from the plan's
# INV map — NEVER derived from the suites this script runs (circularity closed, Q4b).
INV_NAMES="INV-ENGINEFIX INV-GRAMMAR INV-PS-NOVERIFIER INV-PS-BUDGET INV-COLDGO INV-SUSPEND F-CONV F-STATUS INV-INTAKE INV-SKETCH INV-TEMPLATES INV-WIRED"

fail() { echo "refuse: $1" >&2; echo "COMPASS-RECON: FAIL — $2" >&2; exit 1; }

ST_OUT="$(eval "$ST_CMD" 2>&1 || true)"
SM_OUT="$(eval "$SM_CMD" 2>&1 || true)"

# selftest count: ONLY from selftest's own shape, last occurrence wins
ST_LINE="$(printf '%s\n' "$ST_OUT" | grep -E '^selftest: [0-9]+ passed, [0-9]+ failed$' | tail -1 || true)"
if [ -z "$ST_LINE" ]; then
  # cross-match probe: a smoke-shaped line masquerading in the selftest channel
  printf '%s\n' "$ST_OUT" | grep -qE '^──────── [0-9]+ passed, [0-9]+ failed ────────$' \
    && fail cross-match "selftest channel carries only a smoke-shaped tally — counts must come from their OWN suite's pinned shape."
  fail floor-selftest "no pinned selftest tally line found (suite crashed or output shape changed — that is itself a reconciliation break)."
fi
ST_N="$(printf '%s' "$ST_LINE" | sed -E 's/^selftest: ([0-9]+) passed.*/\1/')"
ST_F="$(printf '%s' "$ST_LINE" | sed -E 's/.* ([0-9]+) failed$/\1/')"
[ "$ST_F" = "0" ] || fail floor-selftest "selftest reports $ST_F failures."
[ "$ST_N" -ge "$FLOOR_SELFTEST" ] || fail floor-selftest "selftest count $ST_N under the pinned baseline $FLOOR_SELFTEST."

SM_LINE="$(printf '%s\n' "$SM_OUT" | grep -E '^──────── [0-9]+ passed, [0-9]+ failed ────────$' | tail -1 || true)"
if [ -z "$SM_LINE" ]; then
  printf '%s\n' "$SM_OUT" | grep -qE '^selftest: [0-9]+ passed, [0-9]+ failed$' \
    && fail cross-match "smoke channel carries only a selftest-shaped tally."
  fail floor-smoke "no pinned smoke tally line found."
fi
SM_N="$(printf '%s' "$SM_LINE" | sed -E 's/^──────── ([0-9]+) passed.*/\1/')"
SM_F="$(printf '%s' "$SM_LINE" | sed -E 's/.* ([0-9]+) failed ────────$/\1/')"
[ "$SM_F" = "0" ] || fail floor-smoke "smoke reports $SM_F failures."
[ "$SM_N" -ge "$FLOOR_SMOKE" ] || fail floor-smoke "smoke count $SM_N under the pinned baseline $FLOOR_SMOKE."

for name in $INV_NAMES; do
  printf '%s\n%s\n' "$ST_OUT" "$SM_OUT" | grep -qF "$name" \
    || fail inv-missing "pinned INV group '$name' absent from the suites' output."
done

echo "COMPASS-RECON: PASS — selftest ${ST_N}≥${FLOOR_SELFTEST}, smoke ${SM_N}≥${FLOOR_SMOKE}, all $(printf '%s\n' $INV_NAMES | wc -l | tr -d ' ') pinned INV groups present."
exit 0
