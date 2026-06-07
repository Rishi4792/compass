---
name: plan
description: Turn a locked CONTRACT into an industry-standard engineering plan. STRICT PREREQUISITE — first scan and deeply understand the existing live codebase (or, greenfield, the chosen stack) before planning. Each step gets a verify command; every INVARIANT a non-deferred bound-asserting check; migrations dry-run on a copy. Trigger after the contract locks, or on "make the plan", "compass plan", or the Compass orchestrator.
---

# compass:plan

Convert `contract.md` into the plan the world's best engineers would deliver right the first time.

## Step 0 — gate
Run `compass.sh gate .claude/builds/<slug> review-contract`. **Non-zero → STOP** (contract not LOCKED), offer `compass:review-contract`. Read `contract.md` — the invariant below.

## ⛔ Phase 0 — understand the codebase FIRST (write findings INTO the plan; cite real paths)
1. **Repo guidance + tooling** (PREFER existing workflows): `CLAUDE.md`, `.claude/`, architecture/invariants docs, CI, package scripts, Makefile, test/migration/seed/perf/OOM scripts, deploy hooks.
2. **Real blast radius** — read the *actual* code for every area the contract touches; name files, readers/writers, routes, jobs, DB tables, and the **existing workflows that depend on them** (direct + indirect) that could regress. **Rewrite the INDEX `touches` line with this real file list**, and if it overlaps another in-flight build, surface it and ask.
3. **Real infra constraints** — DB plan/size, instances, caching, memory ceiling, RBAC, cost invariants. Read, don't assume.
4. **Confirm reconciliation against reality** — can the reproducing query recompute toward the pinned gold? If not, surface it (the contract may bounce back).
**Greenfield:** no code → inventory the chosen stack/scaffolding/conventions/tooling and say "greenfield."

## The plan (`plan.md`)
1. **Traceability** — every contract requirement → step(s).
2. **INVARIANT → assertion map** — each INVARIANT → the exact command asserting its bound. **An INVARIANT's assertion may NOT be deferred.**
3. **Files to change/add** (real paths) · **Workflows touched** + regression risks.
4. **DB / migration** — changes; **every migration includes a DRY-RUN step: apply forward + roll back on a restored copy/branch DB, assert row-count + checksum identical, BEFORE prod**; reversibility; rolling-deploy compatibility.
5. **Dependencies** — any install/upgrade/lockfile/version-pin change is its **own explicit step with its own verify** (don't let it be improvised).
6. **API** — shape, backward compatibility, idempotency. · **Code invariants.**
7. **Step checklist** — ordered, atomic. Each: what · which requirement · **VERIFY command** (project-facet rungs) · checkbox. A verify may be **"deferred — proven by step N / post-deploy X"** ONLY for **non-INVARIANT** steps with a named later proof.
8. **Test plan** — unit/integration/migration/API/UI-or-golden-file/permission/regression/perf + reconciliation + (web) design-token + a11y + an **idempotency test** (run twice → identical end-state).
9. **Rollout & rollback** (exact revert path) · **Assumptions/open risks** (each with how it's validated).

## Emit
`progress.md` = ② Plan draft. **EMIT RECEIPT** (fill honestly):
```
## RECEIPT — plan · <slug> · PASS
- [x] gate: review-contract receipt OK
- [x] Phase 0 grounded — cited paths: <…> (or greenfield); INDEX touches updated
- [x] every contract requirement traced to a step
- [x] every INVARIANT → NON-deferred bound-asserting check
- [x] every migration has a dry-run-on-copy step; dependency changes are explicit steps
```
Self-check: `compass.sh scan-receipt .claude/builds/<slug> plan`. **Standalone STOP:** suggest `compass:review-plan`; don't invoke it. A deviation from `contract.md` found here = STOP and surface.
