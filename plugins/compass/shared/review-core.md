# Review Core — the shared adversarial-review engine (illustrative reference)

> **The SKILLS are authoritative.** A plugin skill cannot reliably read this file at runtime, so each
> review skill INLINES the rules it needs. This file is a human-readable overview; if it ever
> disagrees with a skill, **the skill wins.** Do not treat it as a spec to sync against.

## The engine
1. **Fan out, don't read linearly.** Parallel specialized streams (list comes from the specific review).
2. **Assume it fails.** Every finding: what breaks · impacted invariant · severity (Critical/Major/Minor) · concrete fix · the Validation command that proves the fix.
3. **Prove, don't vibe. Agent agreement is NOT evidence — restate this every round.** At contract/plan stages there's no code; proof = grounding (checked against real repo/data, or flagged as an owned open risk — a flag is not a pass).

## The ledger (`review-ledger.md`) — created by whichever review runs first
Rows append-only; only the `Status` cell updates in place. Stable columns (identical in all three reviews):

`Issue ID | Review (R1/R2/R3) | Round # | Affected area | Failure mode | Impacted invariant | Severity | Root cause | Fix | Validation | Owner stream | Status`

## Convergence — computed from evidence, not self-assertion
- **Material issue** = a new **Critical or Major**. (Minors are logged, don't reset convergence.)
- **Clean round** = zero new material issues **AND** the deterministic suite re-ran green this round. **Proof-of-work is mandatory:** each round writes a footer that CARRIES its evidence, or the round does not count:
  `> Round N (Rx): suite=\`<cmd>\` exit=0 passed=<k>/<k>; reconcile=\`<query>\`→actual=<x> gold=<y> Δ=<%> PASS. New Crit/Maj=0. Clean? yes`
  A footer that says "Clean? yes" with no command + exit + counts is **automatically not clean.**
- **Closed issue** = its Validation command was **RE-RUN with fresh output recorded.** Re-reading the diff is not closure.
- **Converged:** light review (review-contract) = **one clean pass**; full reviews (review-plan, review-build) = **two consecutive clean rounds.**

Round 1 = broad sweep; rounds 2+ diff-scope what you *review* but **still re-run the full suite** before counting a round clean (a regression on an un-reviewed surface must not slip through).

## Caps & escalation (cap = ceiling, not target)
review-contract → **2** · review-plan → **3** · review-build → **5**. Cap WITHOUT convergence is never "converged" — don't downgrade issues to fake a green. Escalate UP:
- plan review stuck → contract under-specified → `compass:contract`.
- build review stuck → plan flawed → `compass:plan` (or `compass:contract` if the build proved the contract's premise false).
- **contract review stuck → no level above → hand back to the USER** with the open questions.

## Receipts & gating (the teeth)
Every stage EMITS a receipt to `receipts.md` (see the skills). A review's Step-0 **refuses to start** if the prior stage's receipt is absent, FAILed, or has an unchecked box. A review that converges flips `progress.md` status (LOCKED / CLOSED) and writes its own PASS receipt.

## Grounding
Read `contract.md` first; a deviation from it is CRITICAL. **Every contract INVARIANT must trace to a passing assertion of its exact bound** (the ±X%, the <Ns, the RBAC rule); an INVARIANT with no bound-asserting check is a CRITICAL gap. Ungrounded standalone use → say so and offer to create a contract.
