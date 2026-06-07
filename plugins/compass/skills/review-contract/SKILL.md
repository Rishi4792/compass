---
name: review-contract
description: Review-1 (LIGHT) — adversarially pressure-test a CONTRACT before it locks — completeness, ambiguity, testability, reconciliation pinned/independent/exact, consistency, edge states, feasibility. One clean pass; cap 2. Trigger after compass:contract, or on "review the contract", "pressure-test this spec", or the Compass orchestrator.
---

# compass:review-contract  (Review-1 · LIGHT)

Lens: **is the WHAT airtight?** One focused pass; loop only if gaps.

## Step 0 — gate (real, not prose)
Run `compass.sh gate .claude/builds/<slug> contract` (slug from `.claude/builds/CURRENT`). **Non-zero exit → STOP**, offer `compass:contract`. Read `contract.md`. Set `progress.md` status = `in-review (R1)`.

## Engine
- **Ledger:** create `.claude/builds/<slug>/review-ledger.md` if absent. Append-only rows, `Status` in place. Columns: `Issue ID | Review (R1/R2/R3) | Round # | Affected area | Failure mode | Impacted invariant | Severity | Root cause | Fix | Validation | Owner stream | Status`.
- **Material** = new Critical/Major. **Converged = ONE clean pass** (zero new material). Cap **2**. Footer per round: `> Round N (R1): new Crit/Maj=0. Clean? yes`.
- Proof here = **grounding** (checked against real schema/data, or flagged as an owned risk — a flag is not a pass). **Agent agreement is not evidence.**
- Cap without convergence → **no level above the contract → STOP, hand to the USER** with the open questions.

## Streams (one pass)
1. **Completeness** for the chosen facets — every required section substantive (incl. scale, deps, reconciliation, idempotency, rollback, observability; web: auth + tokens + a11y; pipeline: input-contract + determinism + output-schema + reproducibility).
2. **Ambiguity** — every term defined; name any phrase readable two ways.
3. **Testability** — every requirement measurable. **A deferred flag on an INVARIANT/acceptance item = CRITICAL.**
4. **Reconciliation — pinned, INDEPENDENT, exact.** Grep `contract.md` and assert: gold is a **literal with published provenance, NOT self-computed** (self-computed gold = CRITICAL); tolerance = displayed precision (a looser band must carry justification + user sign-off); the known-bug-class checklist (dup / fan-out / source-table) is present. Quote the matched lines in the ledger — don't just re-state the contract's own claim.
5. **Internal consistency** — no two requirements conflict.
6. **Edge states** — empty/loading/error/scale/permission specified.
7. **Feasibility-vs-data** — real source data supports the derivation/goal (cheap check, else flag — never flag an INVARIANT).

## Procedure → emit
Run the streams; log + apply fixes (surface intent questions, don't guess). One more pass if a new material gap (cap 2). Converged → `progress.md` = `Contract LOCKED`. **EMIT RECEIPT**:
```
## RECEIPT — review-contract · <slug> · PASS
- [x] gate: contract receipt OK (compass.sh gate → PASS)
- [x] all streams run; ledger updated
- [x] reconciliation independent+exact: grep `contract.md` → gold=<literal> provenance=<artifact>; tol=<…>
- [x] 0 open Critical/Major; progress.md = Contract LOCKED
```
Self-check: `compass.sh scan-receipt .claude/builds/<slug> review-contract`. **Standalone STOP:** suggest `compass:plan`; don't invoke it.
