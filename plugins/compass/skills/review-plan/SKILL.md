---
name: review-plan
description: Review-2 (FULL) — adversarially pressure-test the engineering PLAN before the build begins. Multi-agent fan-out across traceability, INVARIANT-assertion coverage (non-deferred), DB/migration + dry-run, dependencies, API, blast-radius/regression, rollback, test-plan, reconciliation feasibility, performance/scale, security/RBAC, and a secret-leak quick check. Converges on two consecutive clean rounds; cap 3; cap-without-convergence escalates UP to the contract. Trigger after compass:plan or when the user says "review the plan".
---

# compass:review-plan  (Review-2 · FULL)

Lens: **will this plan, built exactly as written, work — and break nothing else?**

## Step 0 — gate
Run `compass.sh gate .claude/builds/<slug> plan`. **Non-zero → STOP**, offer `compass:plan`. Read `contract.md` + `plan.md`. Set `progress.md` = `in-review (R2)`.

## Engine
- **Ledger** (create if absent): same columns as the other reviews.
- **Material** = new Critical/Major. **Clean round** = zero new material AND the deterministic checks re-ran green. **Proof-of-work:** the footer carries evidence or it doesn't count — `> Round N (R2): checks=\`<cmd>\` exit=0; new Crit/Maj=0. Clean? yes`. **Converged = two consecutive clean rounds.** Cap **3**.
- Round 1 broad; rounds 2+ diff-scoped review but **re-run the full checks** before calling clean. A fix is closed only when its Validation command is **re-run with fresh output**. **Agent agreement is not evidence.**
- **Cap 3 un-converged = NOT converged** → contract likely under-specified → **`compass.sh supersede .claude/builds/<slug> contract` then STOP and escalate to `compass:contract`** with the open questions.

## Grounding
Plan delivers the WHOLE contract, nothing it forbids. Drifting step / un-stepped requirement = CRITICAL. **Every INVARIANT → a NON-deferred bound-asserting check** (missing/vague/deferred = CRITICAL).

## Streams (fan out)
1. **Traceability** · 2. **INVARIANT-assertion coverage** (non-deferred, exact bound) · 3. **DB/migration** — safe, reversible, rolling-deploy-safe, and the **dry-run-on-a-copy step is real** · 4. **Dependencies** — installs/pins are explicit steps with verifies · 5. **API** — back-compat, idempotency · 6. **Blast radius/regression** — each risk has a guarding test · 7. **Rollback & rollout** — undo without data loss · 8. **Test plan** — deterministic tests incl. reconciliation, (web) tokens + a11y, idempotency · 9. **Reconciliation feasibility** — the query can recompute toward the **independent** gold; **greenfield carve-out:** no data yet → reconciliation is a post-data acceptance check, don't bounce the plan · 10. **Performance/scale** at the contract's volume + concurrency · 11. **Security/RBAC/cost** · 12. **Secret-leak quick check** — no planned harness embeds a real cookie/JWT/key (must read from env).

## Procedure → emit
Round 1 fan-out → ledger + fixes; apply to `plan.md`; rounds 2+ diff-scoped + re-run. Two clean rounds → `progress.md` = `Plan LOCKED`. **EMIT RECEIPT**:
```
## RECEIPT — review-plan · <slug> · PASS
- [x] gate: plan receipt OK
- [x] 12 streams run; every INVARIANT → non-deferred bound-asserting check
- [x] migration dry-run-on-copy present; rollback path exists; deps are explicit steps
- [x] reconciliation feasible toward INDEPENDENT gold (or greenfield carve-out)
- [x] secret-scan of planned harness: `compass.sh secret-scan .` → 0 hits
- [x] converged in <n> rounds; progress.md = Plan LOCKED
```
Self-check: `compass.sh scan-receipt .claude/builds/<slug> review-plan`. **Standalone STOP:** suggest `compass:build`; don't invoke it.
