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
mkdir -p "$T/good" "$T/bad" "$T/legacy" "$T/rounds"
printf '# r\n\n## RECEIPT — review-plan · t · PASS\n- [x] streams: review-plan r1 -> 6 of 6\n- [x] %s — contract §4\n' "$SENT" > "$T/good/receipts.md"
bash "$SH" review-disclose-gate "$T/good" >/dev/null 2>&1 \
  || { echo "a receipt that DOES disclose was refused — the gate refuses everything"; exit 1; }

printf '# r\n\n## RECEIPT — review-plan · t · PASS\n- [x] streams: review-plan r1 -> 6 of 6\n- [x] all streams run; ledger updated\n' > "$T/bad/receipts.md"
bash "$SH" review-disclose-gate "$T/bad" >/dev/null 2>&1 \
  && { echo "a per-stream-format receipt that says nothing about independence was ACCEPTED"; exit 1; }

# GUARD-FIRST: a receipt predating the format must N/A-PASS *and say so*. 20 of this repo's 31
# build folders are in exactly that state, and a silent pass there would read as a clean bill.
printf '# r\n\n## RECEIPT — review-plan · t · PASS\n- [x] all streams run; ledger updated\n' > "$T/legacy/receipts.md"
_out="$(bash "$SH" review-disclose-gate "$T/legacy" 2>&1)" \
  || { echo "a receipt predating the per-stream format was REFUSED — legacy builds must N/A-pass"; exit 1; }
printf '%s' "$_out" | grep -q 'predates the per-stream format' \
  || { echo "the legacy N/A pass does not SAY it is an N/A — a silent pass reads as a clean bill"; exit 1; }
printf '%s' "$_out" | grep -q 'NOT a statement that the review was independently verified' \
  || { echo "the legacy N/A pass does not say what it is NOT claiming"; exit 1; }

# One disclosure cannot speak for a round recorded later.
printf '# r\n\n## RECEIPT — review-plan · t · PASS\n- [x] streams: review-plan r1 -> 6 of 6\n- [x] %s\n\n## RECEIPT — review-build · t · PASS\n- [x] streams: review-build r1 -> 6 of 6\n' "$SENT" > "$T/rounds/receipts.md"
bash "$SH" review-disclose-gate "$T/rounds" >/dev/null 2>&1 \
  && { echo "two recorded rounds with ONE disclosure line were ACCEPTED — each round discloses for itself"; exit 1; }

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
