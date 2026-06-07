---
name: review-contract
description: Review-1 (LIGHT) — adversarially pressure-test a CONTRACT/spec before it locks. A single focused pass (it reviews a spec, not code). Checks completeness, ambiguity, testability, reconciliation-is-pinned, internal consistency, edge states, and feasibility-against-the-data. Converges on one clean pass; cap 2. Trigger after compass:contract, or when the user says "review the contract", "pressure-test this spec", or invokes the Compass orchestrator.
---

# compass:review-contract  (Review-1 · LIGHT)

Lens: **is the WHAT airtight?** No code, no design — just whether the spec can be misread, is incomplete, or can't be verified. Light by design: one focused pass; loop only if gaps are found.

## Prerequisite check (Step 0)
Read `.claude/builds/CURRENT` to find the active slug, then read its `contract.md`. **If `contract.md` is absent, STOP** — say "no contract to review" and offer to run `compass:contract`. Never fabricate a contract.

## Engine (inlined — the canonical spec is `shared/review-core.md`)
- **Assume it fails.** Every finding: what breaks · which invariant it impacts · severity (Critical/Major/Minor) · concrete fix.
- **Ledger:** create `.claude/builds/<slug>/review-ledger.md` if absent. Rows append-only; `Status` updated in place. Columns: `Issue ID | Review(R1) | Round# | Affected area | Failure mode | Impacted invariant | Severity | Root cause | Fix | Validation | Owner stream | Status`. Append a per-round footer: `> Round N (R1): k new Critical/Major, m new Minor. Clean? y/n.`
- **Proof = grounding** (no code yet): every feasibility claim checked against the real schema/data where cheap, else flagged as an explicit owned risk. **Agent agreement is not evidence.**
- **Material issue** = a new Critical or Major. **Clean round** = zero new material issues. **Converged = ONE clean pass** (light review). Cap **2**.
- **Cap without convergence → there is no level above the contract → STOP and hand back to the USER** with the open questions. Never fake "airtight."

## Streams (one focused pass)
1. **Completeness** — all required sections present and substantive (incl. scale, auth, dependencies, reconciliation, idempotency, rollback, observability)? Any thin/silently-absent section is a gap.
2. **Ambiguity** — every term defined? Can any requirement be read two ways? Name the phrase + the resolving question.
3. **Testability** — every feature/goal has a *measurable* check? Any requirement that can't be verified is a defect. **Any deferred flag on an INVARIANT/acceptance item is a Critical gap.**
4. **Reconciliation pinned** — if the build outputs numbers, is the gold source + exact figure + tolerance + reproducing query actually stated? A vague "it should tie out" is a gap.
5. **Internal consistency** — any two requirements conflict? Do acceptance goals contradict scope or the data derivation?
6. **Edge states** — empty / loading / error / scale / permission states specified, not assumed?
7. **Feasibility-vs-data** — does the real source data support the stated derivation/goal? (Quick check where cheap, else flag as a plan-stage assumption — but never on an INVARIANT.)

## Procedure
1. Run the streams as one pass; log gaps in the ledger with exact fixes (precise wording to add/change).
2. **Apply fixes** to `contract.md`; where intent is needed, surface the specific question — don't guess.
3. Re-read; if a new material gap appears, one more pass (cap 2).
4. Converged (one clean pass) → update `progress.md` (status = Contract LOCKED, next = Plan) → the contract is the **locked invariant**.
5. **Standalone STOP:** suggest `compass:plan` and stop — don't invoke it yourself. Under the orchestrator, hand to the gate.

## Sign-off (all must hold)
Every section substantive · no ambiguous requirement · every requirement testable · reconciliation pinned (if numbers) · no deferred flag on an INVARIANT/acceptance item · no internal conflict · edge states specified · feasibility plausible or flagged.
