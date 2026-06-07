---
name: review-plan
description: Review-2 (FULL) — adversarially pressure-test the engineering PLAN before it locks and the build begins. Multi-agent fan-out across traceability, DB/migration, API/contract, blast-radius/regression, rollback, test-plan, performance/scale, and security/RBAC. Caps at 3 iterations; real stop is 2 consecutive clean rounds. Cap-without-convergence escalates UP to the contract. Trigger after compass:plan, or when the user says "review the plan", "stress-test the plan", or invokes /compass.
---

# compass:review-plan  (Review-2 · FULL)

Lens: **will this plan, built exactly as written, work — and break nothing else?** This is comprehensive: a multi-agent fan-out, not a single pass. Uses `../shared/review-core.md` (engine, ledger, convergence) and `../shared/verify-ladder.md` (proof). Cap **3** iterations; real stop = **2 consecutive clean rounds**.

## Grounding (do this first)
Read `contract.md` (the invariant) AND `plan.md`. The first job is **does the plan deliver the whole contract and nothing it forbids?** Any plan step that drifts from the contract is a CRITICAL finding. Any contract requirement with no plan step is a CRITICAL gap.

## Streams (fan out in parallel — Dynamic Workflows / multi-agent)
1. **Traceability** — every contract requirement maps to ≥1 plan step; nothing dropped, nothing invented beyond scope.
2. **DB / migration** — is the migration safe (locks, long-running ALTERs, backfill), reversible, forward/back-compatible during a rolling deploy? Zombie connections / blocked DDL? (Check the repo's real deploy model.)
3. **API / contract** — request/response shape, backward compatibility for existing clients, validation, idempotency, error semantics.
4. **Blast radius / regression** — every existing feature/workflow the changed files touch: what could regress? Is there a test that would catch it?
5. **Rollback & rollout** — deploy order, flags, the exact revert path. Can a bad deploy be undone without data loss?
6. **Test plan** — does every feature/goal have a deterministic test? Migration test? Permission test? Perf test where the contract sets a bar?
7. **Performance / scale** — at real data volume and concurrency (read from the repo, not assumed): N+1s, full scans, memory ceiling, single-DB bottleneck.
8. **Security / RBAC / cost** — data-leakage across roles/tenants, auth coupling, and any cost-control invariant the plan could violate.

## Procedure (the convergence loop)
1. Round 1: fan out all eight streams. Merge findings into `review-ledger.md` (engine format) with concrete fixes.
2. **Apply the fixes to `plan.md`** (or surface to the user where it needs their decision).
3. Rounds 2+: re-review only the surface the fixes touched (diff-scoped) + re-check.
4. **Stop when 2 consecutive rounds surface no new material issue** (converged) → plan ready to LOCK. Or at cap 3.
5. **Cap 3 without convergence = NOT converged.** Do not fake it. The plan churning usually means the **contract is under-specified** → STOP and escalate UP: bounce to `compass:contract` with the unresolved questions.

## Sign-off (all must hold)
Full contract traced · migration safe + reversible · API back-compatible · regression risks each have a guarding test · rollback path exists · every requirement has a deterministic test · perf bar met at real scale · no RBAC/cost-invariant violation. Then `plan.md` becomes the **locked build spec**.
