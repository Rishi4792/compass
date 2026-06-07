---
name: ship
description: Ship (optional) — deploy the CLOSED build and prove it in prod — deploy via the repo's own path, re-run reconciliation on prod data, confirm the observability signal emits. Skipped if the contract marks deploy out of scope. Trigger after compass:review-build closes, or on "ship it", "deploy", "compass ship".
---

# compass:ship

The lifecycle verifies locally (prod stays read-only during build). This stage takes a CLOSED build to production and proves it there — closing the gap where the contract's Observability check only means something post-deploy.

## When NOT to run
If the contract's Non-goals mark **deploy out of scope**, skip — the build is done at CLOSED and the observability check was scoped to staging. Say so and stop.

## Step 0 — gate
Run `compass.sh gate .claude/builds/<slug> review-build`. **Non-zero → STOP** (build not CLOSED/signed-off), offer `compass:review-build`. Read `contract.md` (deploy/rollback/observability sections are the invariant here).

## Procedure
1. **Deploy via the repo's own path** — the deploy/predeploy scripts Phase 0 found; never an ad-hoc deploy. Respect the contract's rollout order + flags.
2. **Post-deploy reconciliation on PROD data** — run the reproducing query against prod (read-only), then `compass.sh reconcile <actual> <gold> <tol>`. **Non-zero = STOP and roll back** via the contract's exact revert path.
3. **Confirm observability EMITS in prod** — the exact metric/log the contract named is actually flowing (query it / tail it), not just present in code.
4. **Smoke the critical flow** — the contract's headline behavior works in prod (read-only asserts; Playwright against prod with env-supplied auth, never a committed token).
5. **On any failure → roll back** using the rehearsed path (review-build exercised it on a copy), record what happened.

## Emit
`progress.md` = `SHIPPED` (or `ROLLED-BACK`). **EMIT RECEIPT**:
```
## RECEIPT — ship · <slug> · PASS
- [x] gate: review-build receipt OK
- [x] deployed via repo path: `<cmd>` → <result>
- [x] prod reconcile: `compass.sh reconcile <actual> <gold> <tol>` → PASS
- [x] observability emits in prod: `<cmd>` → <signal seen>
- [x] critical flow smoke (prod, read-only): <result>
```
Self-check: `compass.sh scan-receipt .claude/builds/<slug> ship`.

## Post-ship note
If prod reconciliation later drifts (a future month), that's a new signal → reopen via `compass:contract` (amend) — Compass's drift guard doesn't end at deploy.
