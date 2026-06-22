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
   - **Affected routes (v0.8.0, blast-radius):** if the build adds or changes the data/render path of ANY page/route (direct OR indirect readers), the plan MUST carry a machine-readable **`## Affected routes`** block — one route per line, each starting with its path (e.g. `- /accounts/[branchId] — prospect page`). This is the canonical set `route-coverage` checks. Each such route's step VERIFY must be a **page-load rung** (GET/Playwright → 200-with-content, on the migration-built schema) — **typecheck alone is BANNED for a page/route step** (it proves it compiles, not that it runs; the exact `pg-method-rates` miss). Omitting the block when page/route files change is not allowed — `route-coverage` G-R0 makes declaration mandatory.
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
Self-check: `compass.sh scan-receipt .claude/builds/<slug> plan`.

<!-- GATE:START -->
## Stage transition — the gate (fires on EVERY entry path)

This stage owns its own transition gate. Present it whether the stage was run standalone
(bare skill, e.g. `/build`), via the namespaced command (`/compass:build`), or sequenced by
`/compass:start`. The orchestrator does **not** present a second gate — the stage owns it.

1. First print the one-line **transition footer**, in exactly this shape:

   `✓ <this stage> PASSED — <one-line proof>.  Next: <next stage> · run \`/compass:<next stage>\`.`

   (For the terminal `ship` stage, Next is `done — build SHIPPED`.)

2. Then present the gate using **AskUserQuestion** with exactly these **4 options**
   (AskUserQuestion caps at 4; "Show full artifact" is offered via the auto-provided **Other**,
   or just print the artifact if the user asks):
   - **Approve & continue** — advance to the next stage.
   - **Revise** — re-run this stage with the user's change.
   - **Amend** — a legitimate scope change (not drift): bump the contract version + changelog,
     run a mini review-contract on the delta, `supersede` downstream, re-baseline.
   - **Pause here** — stop cleanly; write the resume pointer to `progress.md`.

Only **Approve** or **Amend** advances. **Never auto-invoke the next skill** — the gate ASKS;
it does not advance by itself. On any detected drift from `contract.md`, STOP and surface
instead of advancing.
<!-- GATE:END -->
