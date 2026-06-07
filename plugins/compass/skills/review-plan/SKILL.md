---
name: review-plan
description: Review-2 (FULL) — adversarially pressure-test the engineering PLAN before it locks and the build begins. Multi-agent fan-out across traceability, INVARIANT-assertion coverage (non-deferred), DB/migration + dry-run, API, blast-radius/regression, rollback, test-plan, reconciliation feasibility, performance/scale, security/RBAC, and a secret-leak quick check. Converges on two consecutive clean rounds; cap 3; cap-without-convergence escalates UP to the contract. Trigger after compass:plan, or when the user says "review the plan", or invokes the Compass orchestrator.
---

# compass:review-plan  (Review-2 · FULL)

Lens: **will this plan, built exactly as written, work — and break nothing else?** Comprehensive multi-agent fan-out.

## Step 0 — gate + status
Read `.claude/builds/CURRENT` → slug → `receipts.md`. **If the `plan` receipt is absent or FAIL, STOP** and offer `compass:plan`; if the contract isn't LOCKED, offer `compass:review-contract`. Read `contract.md` + `plan.md`. **Set `progress.md` status = `in-review (R2)` now.**

## Engine (inlined; skill is authoritative)
- **Ledger:** create if absent; columns `Issue ID | Review (R1/R2/R3) | Round # | Affected area | Failure mode | Impacted invariant | Severity | Root cause | Fix | Validation | Owner stream | Status`.
- **Material** = new Critical/Major. **Clean round** = zero new material issues AND the deterministic checks re-ran green. **Proof-of-work:** the round footer must carry evidence or it doesn't count — `> Round N (R2): checks=\`<cmd>\` exit=0; new Crit/Maj=0. Clean? yes`. **Converged = two consecutive clean rounds.** Cap **3**.
- Round 1 broad; rounds 2+ diff-scoped review but **re-run the full checks** before calling clean. **A fix is closed only when its Validation command is RE-RUN with fresh output. Agent agreement is not evidence.**
- **Cap 3 un-converged = NOT converged.** The plan churning usually means the **contract is under-specified → STOP and escalate UP to `compass:contract`** with the open questions.

## Grounding
Plan must deliver the WHOLE contract, nothing it forbids. A drifting step = CRITICAL; a requirement with no step = CRITICAL. **Every INVARIANT must map to a NON-deferred bound-asserting check** — a missing, vague, or deferred INVARIANT assertion = CRITICAL.

## Streams (fan out)
1. **Traceability** — every requirement → ≥1 step; nothing dropped or invented beyond scope.
2. **INVARIANT-assertion coverage** — each INVARIANT has a concrete, non-deferred command asserting its exact bound.
3. **DB / migration** — safe (locks, long ALTERs, backfill), reversible, rolling-deploy compatible; **the dry-run-on-a-copy step exists** and is real.
4. **API** — shape, backward compatibility, validation, idempotency, error semantics.
5. **Blast radius / regression** — every existing feature the changed files touch: what regresses, and the test that catches it.
6. **Rollback & rollout** — deploy order, flags, exact revert path; undo without data loss.
7. **Test plan** — every feature/goal has a deterministic test; migration, permission, perf where the contract sets a bar.
8. **Reconciliation feasibility** — the planned query reproduces the gold figure within the (exact-by-default) tolerance; run it if cheap. **Greenfield carve-out:** if there's no data yet, reconciliation is a **post-data acceptance check**, not a plan-feasibility gate — don't fail/bounce the plan for an empty greenfield source.
9. **Performance / scale** — at the contract's stated volume + concurrency: N+1s, full scans, memory ceiling, single-DB bottleneck.
10. **Security / RBAC / cost** — data-leakage across roles/tenants, auth coupling, cost-invariant violations.
11. **Secret-leak quick check** — does any planned verify harness embed a real cookie/JWT/key/connection-string? It must read secrets from env, never commit them.

## Procedure
1. Round 1 fan-out → ledger + fixes. 2. Apply fixes to `plan.md` (or surface to user). 3. Rounds 2+ diff-scoped + re-run checks. 4. Two consecutive clean rounds → `progress.md` = Plan LOCKED, next = Build. 5. **EMIT RECEIPT**:
   ```
   ## RECEIPT — review-plan · <slug> · PASS
   - [x] plan receipt present; all 11 streams run
   - [x] every INVARIANT → non-deferred bound-asserting check
   - [x] migration dry-run-on-copy present; rollback path exists
   - [x] reconciliation feasible (or greenfield post-data carve-out)
   - [x] no secret embedded in any planned harness
   - [x] converged in <n> rounds; progress.md = Plan LOCKED
   ```
6. **Standalone STOP:** suggest `compass:build`; don't invoke it. Under the orchestrator, hand to the gate.

## Sign-off
Full contract traced · every INVARIANT has a non-deferred bound-asserting check · migration safe + dry-run-on-copy + reversible · API back-compatible · regressions guarded by tests · rollback path exists · reconciliation feasible/carve-out · perf bar met at scale · no RBAC/cost violation · no harness secret · receipt PASS.
