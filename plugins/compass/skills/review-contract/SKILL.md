---
name: review-contract
description: Review-1 (LIGHT) — adversarially pressure-test a CONTRACT/spec before it locks. A single focused pass (it reviews a spec, not code). Checks completeness for the project type, ambiguity, testability, reconciliation-pinned-and-exact, internal consistency, edge states, feasibility. Converges on one clean pass; cap 2. Trigger after compass:contract, or when the user says "review the contract", "pressure-test this spec", or invokes the Compass orchestrator.
---

# compass:review-contract  (Review-1 · LIGHT)

Lens: **is the WHAT airtight?** No code — just whether the spec can be misread, is incomplete, or can't be verified. One focused pass; loop only if gaps.

## Step 0 — gate + grounding
Read `.claude/builds/CURRENT` → slug → `receipts.md`. **If the contract receipt is absent or FAIL, STOP** and offer `compass:contract`. Read `contract.md`. **Set `progress.md` status = `in-review (R1)` now** (so a resume mid-review reports the right stage). Never fabricate a contract.

## Engine (inlined; the skill is authoritative — `shared/review-core.md` is just an overview)
- **Ledger:** create `.claude/builds/<slug>/review-ledger.md` if absent. Rows append-only, `Status` in place. Columns exactly: `Issue ID | Review (R1/R2/R3) | Round # | Affected area | Failure mode | Impacted invariant | Severity | Root cause | Fix | Validation | Owner stream | Status`.
- **Material** = new Critical or Major. **Clean round** = zero new material issues. **Converged = ONE clean pass.** Cap **2**. Per-round footer: `> Round N (R1): new Crit/Maj=0. Clean? yes`.
- **Proof = grounding** (no code yet): feasibility checked against real schema/data where cheap, else flagged as an owned risk. **Agent agreement is not evidence.**
- **Cap without convergence → no level above the contract → STOP and hand to the USER** with the open questions. Never fake "airtight."

## Streams (one focused pass)
1. **Completeness for the project type** — all required sections present and substantive (incl. scale, dependencies, reconciliation, idempotency, rollback, observability; web: auth + UI tokens; pipeline: input-contract + determinism + output-schema + reproducibility). Thin/absent = gap.
2. **Ambiguity** — every term defined; name any phrase readable two ways + the resolving question.
3. **Testability** — every feature/goal measurable. **Any deferred flag on an INVARIANT/acceptance item is CRITICAL.**
4. **Reconciliation pinned & exact** — if numbers: gold source + exact figure + reproducing query + tolerance all stated, and **tolerance = 0 unless a band is explicitly justified and user-signed**. A non-zero band with no justification is a Critical gap.
5. **Internal consistency** — no two requirements conflict; acceptance goals don't contradict scope/derivation.
6. **Edge states** — empty/loading/error/scale/permission specified, not assumed.
7. **Feasibility-vs-data** — real source data supports the derivation/goal (quick check where cheap, else flag — but never flag an INVARIANT).

## Procedure
1. Run the streams; log gaps with exact fixes. 2. Apply fixes to `contract.md`; surface intent questions, don't guess. 3. Re-read; one more pass if a new material gap (cap 2). 4. Converged → `progress.md` status = Contract LOCKED, next = Plan. 5. **EMIT RECEIPT** to `receipts.md`:
   ```
   ## RECEIPT — review-contract · <slug> · PASS
   - [x] contract receipt was present & PASS
   - [x] all 7 streams run; ledger updated
   - [x] reconciliation pinned & tolerance exact (or justified+signed)
   - [x] converged in <n> pass(es); 0 open Critical/Major
   - [x] progress.md = Contract LOCKED
   ```
6. **Standalone STOP:** suggest `compass:plan`; don't invoke it. Under the orchestrator, hand to the gate.

## Sign-off
Every section substantive · no ambiguity · every requirement testable · reconciliation pinned & exact (or justified+signed) · no deferred flag on an INVARIANT · no internal conflict · edge states specified · feasibility plausible or flagged · receipt PASS.
