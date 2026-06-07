---
name: plan
description: Turn a locked CONTRACT into a detailed, industry-standard engineering plan a top engineer could build right the first time. STRICT PREREQUISITE — first scan and deeply understand the existing LIVE codebase (or, for greenfield, the chosen stack/conventions). Produces plan.md as an executable step checklist where each step has its own verify command, every INVARIANT maps to a bound-asserting check that may NOT be deferred, and migrations are dry-run on a copy. Trigger after the contract is locked, or when the user says "make the plan", "compass plan", or invokes the Compass orchestrator.
---

# compass:plan

Convert `contract.md` into the plan the world's best engineers would expect — enough to deliver it **right the first time**.

## Step 0 — gate
Read `.claude/builds/CURRENT` → slug → `receipts.md`. **If the `review-contract` receipt is absent or FAIL (contract not LOCKED), STOP** and offer `compass:review-contract` (or `compass:contract`). Read `contract.md` — the invariant for everything below.

## ⛔ STRICT PREREQUISITE — understand the codebase FIRST (Phase 0)
A plan ungrounded in real code is fiction. Scan and write findings INTO the plan:
1. **Repo guidance + tooling** (PREFER existing workflows): `CLAUDE.md` (+nested), `.claude/`, `architecture.md`, `invariants.md`, `CONTEXT.md`, CI, `package.json` scripts, `Makefile`, test/migration/seed/perf/load/OOM scripts, deploy/predeploy hooks, `render.yaml`/CI config.
2. **Real blast radius** — read the *actual* code for every area the contract touches: files, readers/writers, API routes, jobs, DB tables/relations, and which **existing workflows depend on them** (direct + indirect). Name the features that could regress.
3. **Real infra constraints** — DB plan/size, instances, caching/precompute, worker/memory ceiling, RBAC matrix, cost invariants. Read them; don't assume.
4. **Confirm derivation + reconciliation against reality** — does the live schema/data support the stated gold figure? If not, surface it (the contract may need to bounce back).

**Greenfield branch:** no existing code → Phase 0 inventories the chosen stack, scaffolding, conventions, and the test/deploy tooling you'll set up, and says "greenfield: no prod code." Don't fabricate a blast radius.

## The plan (`plan.md`)
1. **Traceability** — a row per contract requirement → the plan step(s). Nothing dropped.
2. **INVARIANT → assertion map** — every INVARIANT mapped to the **exact verify command that asserts its specific bound**. **An INVARIANT's assertion may NOT be deferred** (see step 8) — it runs at build time or the plan is incomplete.
3. **Files to change/add** — exact paths (from Phase 0).
4. **Workflows touched** — named blast radius + features that could regress.
5. **DB / migration** — changes; migration + rollback; lock/index behaviour; backfills; forward/back compatibility during a rolling deploy. **Every migration step includes a DRY-RUN: apply forward + roll back on a restored copy/branch DB and assert row-count + checksum identical, BEFORE the prod apply** — "reversible" on paper is not reverted-on-a-copy.
6. **API** — endpoints, request/response, backward compatibility, validation, idempotency.
7. **Code invariants** — rules the implementation must hold (contract + repo invariants).
8. **Step-by-step checklist** — ordered, atomic steps. Each step: what it does · which contract requirement it serves · its **VERIFY command** (from the project-type rungs) · a checkbox. A step's verify may be **"deferred — proven by step N / post-deploy check X"** ONLY for **non-INVARIANT** steps and only with a named later proof; a deferred verify with no named proof, or any deferred INVARIANT assertion, is a defect.
9. **Test plan** — unit/integration/migration/API/UI(or golden-file)/permission/regression/perf, mapped to features, incl. the **reconciliation** check and (web) **design-token** checks.
10. **Rollout & rollback** — deploy order, flags, the exact revert path.
11. **Assumptions & open risks** — explicit, each with how it'll be validated.

## Procedure
1. Read `contract.md`. 2. Phase 0. 3. Write `plan.md`. 4. `progress.md` = ② Plan draft, next = Review-2. 5. **EMIT RECEIPT**:
   ```
   ## RECEIPT — plan · <slug> · PASS
   - [x] contract LOCKED receipt present
   - [x] Phase 0 grounded with cited paths (or greenfield declared)
   - [x] every contract requirement traced to a step
   - [x] every INVARIANT mapped to a NON-deferred bound-asserting check
   - [x] every migration has a dry-run-on-copy step
   - [x] progress.md = Plan draft
   ```
6. **Standalone STOP:** suggest `compass:review-plan`; don't invoke it. Under the orchestrator, hand to the gate.

## Done when
Receipt PASS: Phase 0 real, every requirement traced, every INVARIANT has a non-deferred bound-asserting check, migrations dry-run on a copy, every step has a verify (or non-INVARIANT deferred-with-named-proof). A deviation from `contract.md` found here = STOP and surface.
