#!/usr/bin/env bash
# A BEHAVIOUR entry covering BOTH halves of INV-DISCLOSE-UNVERIFIED — the receipt and the page.
# Both directions each time: the disclosing case must PASS and the silent one must be REFUSED, or a
# gate that refuses everything would satisfy this for free.
set -uo pipefail
SH="$1/plugins/compass/scripts/compass.sh"
GEN="$1/plugins/compass/skills/compass-visual/gen.mjs"
AG="$1/plugins/compass/scripts/artefact-gate.mjs"
SENT='this review was NOT independently verified'
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ── RECEIPT HALF ──────────────────────────────────────────────────────────────────────────────
# SCOPE IS THE v0.30 STAMP, not a line in the receipt. The first version keyed scope on a `streams:`
# line and an independent reviewer showed five of seven natural ways to write it took the rule out
# of scope — including backticks, which the skill's own template uses on that very line. Scope
# decided by the thing being judged is the defect S10 exists to fix, one level up.
mkdir -p "$T/good" "$T/bad" "$T/legacy" "$T/rounds" "$T/forms"
: > "$T/good/.compass-format"; : > "$T/bad/.compass-format"; : > "$T/rounds/.compass-format"; : > "$T/forms/.compass-format"
printf '# r\n\n## RECEIPT — review-plan · t · PASS\n- [x] streams: review-plan r1 -> 6 of 6\n- [x] %s — contract §4\n' "$SENT" > "$T/good/receipts.md"
bash "$SH" review-disclose-gate "$T/good" >/dev/null 2>&1 \
  || { echo "a receipt that DOES disclose was refused — the gate refuses everything"; exit 1; }

printf '# r\n\n## RECEIPT — review-plan · t · PASS\n- [x] streams: review-plan r1 -> 6 of 6\n- [x] all streams run; ledger updated\n' > "$T/bad/receipts.md"
bash "$SH" review-disclose-gate "$T/bad" >/dev/null 2>&1 \
  && { echo "a stamped review round that says nothing about independence was ACCEPTED"; exit 1; }

# EVERY natural way of writing the streams line must stay IN scope, including the ones that took
# the first version out of it.
for _w in 'streams: review-plan r1 -> 6 of 6' 'streams: `review-plan` r1 -> 6 of 6' 'streams — review-plan r1 -> 6 of 6' 'Streams: review-plan r1 -> 6 of 6' 'all streams run; ledger updated'; do
  printf '# r\n\n## RECEIPT — review-plan · t · PASS\n- [x] %s\n' "$_w" > "$T/forms/receipts.md"
  bash "$SH" review-disclose-gate "$T/forms" >/dev/null 2>&1 \
    && { echo "a stamped, silent review round written as '$_w' was ACCEPTED — the receipt must not decide whether the rule applies to it"; exit 1; }
done

# GUARD-FIRST: an UNSTAMPED build must N/A-PASS *and say so*. 30 of this repo's 31 build folders
# carry a review receipt and 27 are unstamped; a silent pass there would read as a clean bill.
printf '# r\n\n## RECEIPT — review-plan · t · PASS\n- [x] all streams run; ledger updated\n' > "$T/legacy/receipts.md"
_out="$(bash "$SH" review-disclose-gate "$T/legacy" 2>&1)" \
  || { echo "an UNSTAMPED build was REFUSED — legacy builds must N/A-pass"; exit 1; }
printf '%s' "$_out" | grep -q 'predates the rule' \
  || { echo "the legacy N/A pass does not SAY it is an N/A — a silent pass reads as a clean bill"; exit 1; }
printf '%s' "$_out" | grep -q 'NOT a statement that any review was independently verified' \
  || { echo "the legacy N/A pass does not say what it is NOT claiming"; exit 1; }

# EACH ROUND DISCLOSES FOR ITSELF. Two GLOBAL counts passed this: round 1 said it twice and round 2
# said nothing at all.
printf '# r\n\n## RECEIPT — review-plan · t · PASS\n- [x] %s\n- [x] %s\n\n## RECEIPT — review-build · t · PASS\n- [x] streams: review-build r1 -> 6 of 6\n' "$SENT" "$SENT" > "$T/rounds/receipts.md"
bash "$SH" review-disclose-gate "$T/rounds" >/dev/null 2>&1 \
  && { echo "round 1 saying it TWICE covered a silent round 2 — each round must disclose in its own block"; exit 1; }
# ...and two rounds that each disclose in their own block PASS.
printf '# r\n\n## RECEIPT — review-plan · t · PASS\n- [x] %s\n\n## RECEIPT — review-build · t · PASS\n- [x] %s\n' "$SENT" "$SENT" > "$T/rounds/receipts.md"
bash "$SH" review-disclose-gate "$T/rounds" >/dev/null 2>&1 \
  || { echo "two rounds that EACH disclose were refused — the control for the case above"; exit 1; }

# ── PAGE HALF ─────────────────────────────────────────────────────────────────────────────────
command -v node >/dev/null 2>&1 || exit 0
mkdir -p "$T/b"
printf '# Contract — d · v1\n\nfacets: library\n\n## Goal & scope\n**Goal:** a fixture.\n\n## Acceptance & INVARIANTs\n- **INV-X:** a thing. → *assert:* it holds.\n' > "$T/b/contract.md"
printf '| Issue ID | Sev | Status |\n|---|---|---|\n| A-1 | Maj | OPEN |\n' > "$T/b/review-ledger.md"
node "$GEN" "$T/b" review --out "$T/r.html" >/dev/null 2>&1 || { echo "the review page did not render at all"; exit 1; }
grep -qi "$SENT" "$T/r.html" || { echo "the rendered review page does not carry the disclosure sentence"; exit 1; }
# CAPTURE, then grep. `artefact-gate` exits 1 whenever ANY rule fails, and a stub fixture page
# fails unrelated structural rules — under `pipefail` that non-zero poisons the whole pipeline even
# though grep matched. This build has been bitten by that exact shape before.
_ag() { node "$AG" "$1" --json 2>/dev/null || true; }
_j="$(_ag "$T/r.html")"
printf '%s' "$_j" | grep -q '"review-disclosure"' \
  || { echo "artefact-gate did not record the review-disclosure rule as passing on an honest review page"; exit 1; }
# and a page with the sentence removed is REFUSED by name
sed 's/This review was NOT independently verified\.//' "$T/r.html" > "$T/silent.html"
_j="$(_ag "$T/silent.html")"
printf '%s' "$_j" | grep -q 'review-disclosure — ' \
  || { echo "a review page with the disclosure stripped out was NOT refused"; exit 1; }
# a NON-review page records the N/A branch rather than skipping in silence
node "$GEN" "$T/b" plan-map --out "$T/p.html" >/dev/null 2>&1 || { echo "the plan map did not render"; exit 1; }
_j="$(_ag "$T/p.html")"
printf '%s' "$_j" | grep -q '"review-disclosure-na"' \
  || { echo "a non-review page did not RECORD that the disclosure rule was N/A — a silent skip is indistinguishable from a pass"; exit 1; }
exit 0
