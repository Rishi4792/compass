#!/usr/bin/env bash
# A BEHAVIOUR entry. COULD-NOT-VERIFY is the honest verdict when a spawn genuinely fails — and it
# is also three words that buy a clean round. Contract §8: it requires MACHINE evidence of the
# failed spawn and HARD-BLOCKS closure without one. Both directions asserted.
set -uo pipefail
SH="$1/plugins/compass/scripts/compass.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
RV=review-plan
streams="$(bash "$SH" review-streams "$RV")" || { echo "review-streams could not read the declared list at all"; exit 1; }
n="$(printf '%s\n' "$streams" | grep -c .)"
first="$(printf '%s\n' "$streams" | head -1)"

seed() { # <dir>  — every stream well-formed and CLEAN
  mkdir -p "$1/agents"
  printf '# r\n\n## RECEIPT — %s · t · PASS\n- [x] streams: %s r1 -> %s of %s\n' "$RV" "$RV" "$n" "$n" > "$1/receipts.md"
  for s in $streams; do
    printf 'nonce: n7f3a91c4e2b8d605x\nstream: %s\nreview: %s\nround: 1\ntarget-sha: 8e1fc84\nverdict: CLEAN\n' "$s" "$RV" > "$1/agents/$RV-r1-$s.md"
  done
}

# ── CONTROL: all CLEAN, no spawn logs needed -> PASSES ─────────────────────────────────────────
seed "$T/good"
bash "$SH" review-evidence-gate "$T/good" "$RV" 1 >/dev/null 2>&1 \
  || { echo "an all-CLEAN round was REFUSED — the gate demands spawn logs it should not"; exit 1; }

# ── THE CHEAT: COULD-NOT-VERIFY with nothing behind it ─────────────────────────────────────────
seed "$T/bad"
printf 'nonce: n7f3a91c4e2b8d605x\nstream: %s\nreview: %s\nround: 1\ntarget-sha: 8e1fc84\nverdict: COULD-NOT-VERIFY\n' "$first" "$RV" > "$T/bad/agents/$RV-r1-$first.md"
bash "$SH" review-evidence-gate "$T/bad" "$RV" 1 >/dev/null 2>&1 \
  && { echo "COULD-NOT-VERIFY was accepted with no machine evidence of the failed spawn"; exit 1; }

# ── THE HONEST UNAVAILABLE: same verdict, with the spawn log beside it -> PASSES ───────────────
seed "$T/honest"
printf 'nonce: n7f3a91c4e2b8d605x\nstream: %s\nreview: %s\nround: 1\ntarget-sha: 8e1fc84\nverdict: COULD-NOT-VERIFY\n' "$first" "$RV" > "$T/honest/agents/$RV-r1-$first.md"
printf 'Agent spawn refused: tool unavailable in this environment (exit 2)\n' > "$T/honest/agents/$RV-r1-$first.spawn.log"
bash "$SH" review-evidence-gate "$T/honest" "$RV" 1 >/dev/null 2>&1 \
  || { echo "a genuinely-unavailable stream WITH its spawn log was refused — the honest path must stay open, or the rule just teaches people to lie"; exit 1; }

# ── AND AN EMPTY LOG IS NOT A LOG ─────────────────────────────────────────────────────────────
seed "$T/empty"
printf 'nonce: n7f3a91c4e2b8d605x\nstream: %s\nreview: %s\nround: 1\ntarget-sha: 8e1fc84\nverdict: COULD-NOT-VERIFY\n' "$first" "$RV" > "$T/empty/agents/$RV-r1-$first.md"
: > "$T/empty/agents/$RV-r1-$first.spawn.log"
bash "$SH" review-evidence-gate "$T/empty" "$RV" 1 >/dev/null 2>&1 \
  && { echo "an EMPTY spawn log satisfied the machine-evidence requirement"; exit 1; }
exit 0
