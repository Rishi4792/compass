---
name: review-contract
description: Review-1 (LIGHT) — adversarially pressure-test a CONTRACT/spec before it locks. It reviews a spec, not code, so it is a single focused pass (no multi-agent fleet). Checks completeness, ambiguity, testability, internal consistency, edge-state coverage, and feasibility-against-the-data. Cap 2 iterations. Trigger after compass:contract, or when the user says "review the contract", "pressure-test this spec", or invokes /compass.
---

# compass:review-contract  (Review-1 · LIGHT)

Lens: **is the WHAT airtight?** No code, no design — just whether the spec can be misread, is incomplete, or can't be verified. Light by design: one focused pass; loop only if gaps are found. Cap **2** iterations. Uses `../shared/review-core.md` (engine + ledger + convergence).

## Streams (run as one focused pass)
1. **Completeness** — are all required sections present and substantive (goal, data derivation, schema, UI/UX, features, acceptance goals, non-goals)? Any thin section is a gap.
2. **Ambiguity** — is every term defined? Can any requirement be read two ways? Name each ambiguous phrase and the question that resolves it.
3. **Testability** — does every feature/goal have a *measurable* acceptance check? If a requirement can't be verified, it's a defect.
4. **Internal consistency** — do any two requirements conflict? Do the acceptance goals contradict the scope or the data derivation?
5. **Edge states** — are empty / loading / error / scale / permission states specified, or silently assumed?
6. **Feasibility-vs-data** — does the real source data actually support the stated derivation/goal? (Light grounding: a quick check against the schema/data where cheap, else flag as an assumption to verify in the plan stage.)

## Procedure
1. Read `contract.md`. Run the six streams as one pass.
2. Log every gap in `review-ledger.md` (engine format): each with the exact fix (the precise wording/section to add or change).
3. **Apply the fixes** to `contract.md` (or, where it needs the user's intent, surface the specific question — don't guess on intent).
4. Re-read; if a new gap appears, one more pass (cap 2).
5. **Converged** = a pass with no new material gap. Then the contract is ready to LOCK.
6. Cap-without-convergence → stop, list remaining open gaps, and surface them — the spec needs the user's decisions, don't fake "airtight".

## Sign-off (all must hold)
Every section substantive · no ambiguous requirement · every requirement testable · no internal conflict · edge states specified · feasibility plausible or flagged. Then `contract.md` becomes the **locked invariant**.
