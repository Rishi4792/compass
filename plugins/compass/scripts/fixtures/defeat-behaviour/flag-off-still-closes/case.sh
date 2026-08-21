#!/usr/bin/env bash
# A BEHAVIOUR entry for contract §12, both directions on both halves.
#
# HALF ONE — CLOSURE IS REFUSED WHILE THE FLAG IS OFF. Asserted against the SAME build in both
# states, so the flag is the only variable: it closes with the flag on and is refused with it off.
# HALF TWO — THE FLAG CANNOT SILENCE A MEASUREMENT. Each v0.32 measurement is run twice, with the
# flag on and off, and must print the SAME figure. This is the half §12 was written for: round 2 of
# the contract review found a design where the flag returned every new gate to an N/A-pass,
# including the one that measures the gold.
set -uo pipefail
ROOT="$1"
SH="$ROOT/plugins/compass/scripts/compass.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

mkb() { mkdir -p "$T/$1"; printf '# c\n' > "$T/$1/contract.md"; }

# ── HALF ONE ──────────────────────────────────────────────────────────────────────────────────
# THE FLAG IS THE ONLY VARIABLE. The same build is closed twice, and what is compared is WHICH
# refusal comes back — not whether one does. A first version tried to use a build that closes
# cleanly with the flag on, and the stub could not close for unrelated reasons, so the control
# failed and the case proved nothing. Isolating the flag needs the message, not the exit code:
# other preconditions refuse too, and an exit code they already guarantee measures nothing.
mkb one
_on="$(bash "$SH" close "$T/one" flagcase-on 2>&1 || true)"
_off="$(COMPASS_V32_STRICT=0 bash "$SH" close "$T/one" flagcase-off 2>&1 || true)"
printf '%s' "$_off" | grep -q 'COMPASS_V32_STRICT is off' \
  || { echo "with the flag OFF, close did not refuse for the flag's own reason — §12 says closure is REFUSED while it is off"; exit 1; }
printf '%s' "$_off" | grep -q '§12' \
  || { echo "the refusal never names §12 — a reader cannot tell it from any other refusal"; exit 1; }
printf '%s' "$_off" | grep -q 'v32-strict=off' \
  || { echo "the refusal does not name the receipt stamp §12 requires"; exit 1; }
printf '%s' "$_on" | grep -q 'COMPASS_V32_STRICT is off' \
  && { echo "with the flag ON, close STILL refused for the flag's reason — the guard fires regardless of the flag, so it is not a switch"; exit 1; }

# ABANDON must stay open: cancelling claims nothing about the build, and blocking it would strand it.
mkb ab
COMPASS_V32_STRICT=0 bash "$SH" close "$T/ab" flagcase-ab --abandon >/dev/null 2>&1 \
  || { echo "--abandon was refused with the flag off; cancelling a build claims nothing about it and blocking it only strands the build"; exit 1; }
# ...and every spelling of "off" behaves the same, or the switch has a silent bypass.
# BY MESSAGE, for the same reason as above: close refuses this stub anyway, so an exit code proves
# nothing about the flag. A first version checked the exit code here and a mutation that recognised
# ONLY "0" sailed straight through it.
for _v in 0 off OFF false FALSE no NO; do
  mkb "sp$_v"
  _m="$(COMPASS_V32_STRICT="$_v" bash "$SH" close "$T/sp$_v" "flagcase-$_v" 2>&1 || true)"
  printf '%s' "$_m" | grep -q 'COMPASS_V32_STRICT is off' \
    || { echo "COMPASS_V32_STRICT='$_v' did NOT refuse closure for the flag's own reason — one spelling of off is a silent bypass of the whole section"; exit 1; }
done
# ...and a spelling that means ON must NOT trip it, or the guard is unconditional rather than a switch.
for _v in 1 on ON true yes; do
  mkb "sn$_v"
  _m="$(COMPASS_V32_STRICT="$_v" bash "$SH" close "$T/sn$_v" "flagcase-on-$_v" 2>&1 || true)"
  printf '%s' "$_m" | grep -q 'COMPASS_V32_STRICT is off' \
    && { echo "COMPASS_V32_STRICT='$_v' means ON, but closure was refused for the flag's reason — the guard is unconditional, not a switch"; exit 1; }
done

# ── HALF TWO ──────────────────────────────────────────────────────────────────────────────────
command -v node >/dev/null 2>&1 || exit 0
FX="$ROOT/plugins/compass/scripts/fixtures/corpus"
[ -d "$FX" ] || { echo "no fixture corpus at $FX — the measurement half would be unmeasured, which is not a pass"; exit 1; }
_fig() { bash "$ROOT/plugins/compass/scripts/reachable-argument-check.sh" "$ROOT" --corpus "$FX" 2>&1 \
          | sed -nE 's/^[[:space:]]*(REACHABLE|UNREACHABLE|SOURCE UNREACHABLE)[[:space:]]*:[[:space:]]*([0-9]+).*/\1=\2/p' | sort | tr '\n' ' '; }
_on="$(_fig)"
_off="$(COMPASS_V32_STRICT=0 _fig 2>/dev/null || true)"
[ -n "$_on" ] || { echo "the measurement printed no figures at all with the flag ON — unmeasured is not a pass"; exit 1; }
_off="$(COMPASS_V32_STRICT=0 bash "$ROOT/plugins/compass/scripts/reachable-argument-check.sh" "$ROOT" --corpus "$FX" 2>&1 \
        | sed -nE 's/^[[:space:]]*(REACHABLE|UNREACHABLE|SOURCE UNREACHABLE)[[:space:]]*:[[:space:]]*([0-9]+).*/\1=\2/p' | sort | tr '\n' ' ')"
[ "$_on" = "$_off" ] \
  || { echo "the kill switch CHANGED the measurement: with the flag ON [$_on] and OFF [$_off]. §12: it may disable reporting, never the measurement the build is graded on"; exit 1; }
# And the strongest form: no v0.32 measurement READS the flag, so it cannot silence one by accident.
for _f in reachable-argument.mjs reachable-argument-check.sh page-audit.mjs behaviour-corpus-check.sh evidence-shape-check.sh declared-check.sh defeat-corpus-check.sh redfirst-count.sh; do
  _p="$ROOT/plugins/compass/scripts/$_f"
  [ -f "$_p" ] || continue
  if grep -vE '^[[:space:]]*(#|//)' "$_p" | grep -q 'COMPASS_V32_STRICT'; then
    echo "$_f READS COMPASS_V32_STRICT in code — a measurement that consults the kill switch can be silenced by it"; exit 1
  fi
done
exit 0
