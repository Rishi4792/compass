---
name: review-plan
description: Review-2 (FULL) — adversarially pressure-test the engineering PLAN before it locks and the build begins. Multi-agent fan-out across traceability, INVARIANT-assertion coverage, DB/migration, API, blast-radius/regression, rollback, test-plan, reconciliation feasibility, performance/scale, and security/RBAC. Converges on two consecutive clean rounds; cap 3; cap-without-convergence escalates UP to the contract. Trigger after compass:plan, or when the user says "review the plan", or invokes the Compass orchestrator.
---

# compass:review-plan  (Review-2 · FULL)

Lens: **will this plan, built exactly as written, work — and break nothing else?** Comprehensive: a multi-agent fan-out, not a single pass.

## Prerequisite check (Step 0)
Read `.claude/builds/CURRENT` → slug → `contract.md` AND `plan.md`. **If `plan.md` is absent, STOP** and offer `compass:plan`. If `contract.md` is absent, STOP and offer `compass:contract`.

## Engine (inlined — canonical spec is `shared/review-core.md`)
- **Ledger:** create `review-ledger.md` if absent; append-only rows, `Status` in place. Columns include `Review(R2) | Round#` and a per-round footer `> Round N (R2): k new Critical/Major, m new Minor. Clean? y/n.`
- **Material** = new Critical or Major. **Clean round** = zero new material issues AND the deterministic checks re-run green. **Converged = two consecutive clean rounds.** Cap **3**.
- Round 1 = broad sweep; rounds 2+ diff-scoped review BUT still re-run the full checks before calling a round clean. **A fix is "closed" only when its Validation command is RE-RUN with fresh output recorded — re-reading the diff is not closure. Agent agreement is not evidence.**
- **Cap 3 without convergence = NOT converged.** Don't fake it. The plan churning usually means the **contract is under-specified → STOP and escalate UP to `compass:contract`** with the unresolved questions.

## Grounding (first)
Does the plan deliver the WHOLE contract and nothing it forbids? A plan step that drifts from the contract is CRITICAL. A contract requirement with no plan step is CRITICAL. **Every contract INVARIANT must map to a named assertion of its exact bound — a missing or vague assertion is CRITICAL.**

## Streams (fan out in parallel)
1. **Traceability** — every contract requirement → ≥1 plan step; nothing dropped or invented beyond scope.
2. **INVARIANT-assertion coverage** — each INVARIANT has a concrete verify command asserting its specific bound (the ±1%, the <2s, the RBAC check), not a generic "it works."
3. **DB / migration** — safe (locks, long ALTERs, backfill), reversible, forward/back-compatible during a rolling deploy? Zombie connections / blocked DDL?
4. **API / contract** — request/response shape, backward compatibility, validation, idempotency, error semantics.
5. **Blast radius / regression** — every existing feature/workflow the changed files touch: what could regress, and is there a test that catches it?
6. **Rollback & rollout** — deploy order, flags, the exact revert path; can a bad deploy be undone without data loss?
7. **Test plan** — every feature/goal has a deterministic test; migration test; permission test; perf test where the contract sets a bar.
8. **Reconciliation feasibility** — does the planned query actually reproduce the gold figure within tolerance? (Run it if cheap.)
9. **Performance / scale** — at the contract's stated volume + concurrency: N+1s, full scans, memory ceiling, single-DB bottleneck.
10. **Security / RBAC / cost** — data-leakage across roles/tenants, auth coupling, any cost-control invariant the plan could violate.

## Procedure
1. Round 1: fan out all streams → ledger with concrete fixes. 2. **Apply fixes to `plan.md`** (or surface where it needs the user). 3. Rounds 2+: diff-scoped re-review + re-run checks. 4. Two consecutive clean rounds → update `progress.md` (Plan LOCKED, next = Build) → `plan.md` is the locked build spec. 5. **Standalone STOP:** suggest `compass:build`; don't invoke it. Under the orchestrator, hand to the gate.

## Sign-off (all must hold)
Full contract traced · every INVARIANT has a bound-asserting check · migration safe + reversible · API back-compatible · regression risks each guarded by a test · rollback path exists · every requirement has a deterministic test · reconciliation query reproduces the gold figure · perf bar met at real scale · no RBAC/cost-invariant violation.
