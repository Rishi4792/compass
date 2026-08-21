#!/usr/bin/env bash
# A BEHAVIOUR entry. Both directions are asserted, because a gate that refuses everything would
# satisfy a one-directional "must refuse" for free.
#   HONEST: one well-formed evidence file per DECLARED stream -> the gate PASSES.
#   CHEAT : the same receipt, claiming every stream ran, with the agents directory EMPTY -> REFUSED.
# The third case is the one that made this defect possible: a receipt that picks its own
# denominator. "1 of 1 streams" is arithmetically perfect and means nothing.
set -uo pipefail
SH="$1/plugins/compass/scripts/compass.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
RV=review-plan
streams="$(bash "$SH" review-streams "$RV")" || { echo "review-streams could not read the declared list at all"; exit 1; }
n="$(printf '%s\n' "$streams" | grep -c .)"
[ "$n" -ge 3 ] || { echo "the declared stream list is $n long — a denominator that small is the defect, not the fixture"; exit 1; }

mk_receipt() { printf '# r\n\n## RECEIPT — %s · t · PASS\n- [x] all streams run; ledger updated\n- [x] streams: %s r1 -> %s of %s\n' "$RV" "$RV" "$1" "$2"; }

# ── HONEST ────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$T/good/agents"
mk_receipt "$n" "$n" > "$T/good/receipts.md"
for s in $streams; do
  printf 'nonce: n7f3a91c4e2b8d605x\nstream: %s\nreview: %s\nround: 1\ntarget-sha: 8e1fc84\nverdict: CLEAN\n' "$s" "$RV" > "$T/good/agents/$RV-r1-$s.md"
done
bash "$SH" review-evidence-gate "$T/good" "$RV" 1 >/dev/null 2>&1 \
  || { echo "the HONEST fixture (one well-formed file per declared stream) was REFUSED — the gate refuses everything"; exit 1; }

# ── THE CHEAT: the receipt says every stream ran; the directory is empty ───────────────────────
mkdir -p "$T/bad/agents"
mk_receipt "$n" "$n" > "$T/bad/receipts.md"
bash "$SH" review-evidence-gate "$T/bad" "$RV" 1 >/dev/null 2>&1 \
  && { echo "a receipt claiming all $n streams ran with ZERO evidence files was ACCEPTED"; exit 1; }

# ── THE CHEAT'S SUBTLER FORM: the receipt picks its own denominator ────────────────────────────
mkdir -p "$T/den/agents"
mk_receipt 1 1 > "$T/den/receipts.md"
printf 'nonce: n7f3a91c4e2b8d605x\nstream: %s\nreview: %s\nround: 1\ntarget-sha: 8e1fc84\nverdict: CLEAN\n' \
  "$(printf '%s\n' "$streams" | head -1)" "$RV" > "$T/den/agents/$RV-r1-$(printf '%s\n' "$streams" | head -1).md"
bash "$SH" review-evidence-gate "$T/den" "$RV" 1 >/dev/null 2>&1 \
  && { echo "a receipt declaring its own denominator ('1 of 1') was ACCEPTED — the denominator must come from the skill's stream list"; exit 1; }

# ── THE DENOMINATOR RULE, ISOLATED ────────────────────────────────────────────────────────────
# Every declared stream HAS its file here, so the one-file-per-stream rule is satisfied and cannot
# be what refuses this. The only thing wrong is that the receipt states a smaller denominator than
# the skill declares. Without this case the denominator rule could be deleted and the corpus would
# not notice — which is how a rule ends up looking like protection without being it.
mkdir -p "$T/den2/agents"
# The NUMERATOR is honest here — it matches the files on disk exactly — so the numerator check
# cannot be what refuses this. Only the denominator is wrong. A first attempt used "3 of 3", and
# the numerator rule caught it, which proved nothing about the denominator rule at all.
mk_receipt "$n" 3 > "$T/den2/receipts.md"
for s in $streams; do
  printf 'nonce: n7f3a91c4e2b8d605x\nstream: %s\nreview: %s\nround: 1\ntarget-sha: 8e1fc84\nverdict: CLEAN\n' "$s" "$RV" > "$T/den2/agents/$RV-r1-$s.md"
done
bash "$SH" review-evidence-gate "$T/den2" "$RV" 1 >/dev/null 2>&1 \
  && { echo "a receipt stating a denominator of 3 while the skill declares $n streams was ACCEPTED, with every file present and the numerator honest — the denominator was taken from the receipt"; exit 1; }

# ── AND A MALFORMED FILE IS NOT A PRESENT ONE ─────────────────────────────────────────────────
mkdir -p "$T/shape/agents"
mk_receipt "$n" "$n" > "$T/shape/receipts.md"
for s in $streams; do
  printf 'stream: %s\nreview: %s\nround: 1\nverdict: CLEAN\n' "$s" "$RV" > "$T/shape/agents/$RV-r1-$s.md"
done
bash "$SH" review-evidence-gate "$T/shape" "$RV" 1 >/dev/null 2>&1 \
  && { echo "evidence files with no nonce and no target-sha were counted as PRESENT — contract §4 calls those ABSENT"; exit 1; }
exit 0
