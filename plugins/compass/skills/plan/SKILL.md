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
   - **Security design — threat-model / RBAC matrix (v0.18.0, for any build adding a view/endpoint):** design the **role×resource matrix** the reviews will assert against — every role × the new view/endpoint's resources+actions, allow/deny per cell, traced to the contract's role×view — plus a STRIDE-lite line per surface and the IDOR expectation (each lower role → 403/empty). This is the design artifact review-plan `[E]` / review-build `[D]` (the RBACSTRIDE method) check the built code against. Wire the `permission-matrix` skill when present; N/A when the build adds no new view/endpoint.
   - **Concurrency/TOCTOU analysis (v0.19.0, for any build with a read-modify-write):** for every read-modify-write on shared state, name the **losing interleaving** (the concurrent order that corrupts) and the guard that defeats it — a row lock / unique constraint / atomic upsert — and flag any long transaction that holds a lock across I/O. This is the analysis review-plan `[A]` / review-build `[A]` (the EDGERACE method) assert the built code against; also enumerate the boundary/edge checklist (off-by-one · timezone+DST · rollover) for numeric/temporal inputs. N/A when the build has no boundary or read-modify-write surface.
   - **FMEA / perf design (v0.20.0, for any build with an external dependency or non-trivial scale):** a per-dependency **failure-mode analysis** — for each external dependency (DB / API / cron / queue / third-party), state its behavior when slow and when down + the mitigation (timeout / retry-backoff / fallback); **no dependency called with no timeout**. Plus the anti-patterns to avoid at the contract's row count (N+1 / paginationless / O(n²); the query count + peak memory to hold). This is the design artifact review-plan `[D]` / review-build (the PERFFMEA method) assert the built code against. N/A when the build has no external dependency or data-volume-sensitive loop.
   - **Cross-table invariant design (v0.21.0, for any build touching ≥2 related tables):** enumerate the invariants that must hold ACROSS the tables — **child-sums-to-parent**, no orphan FK, one active generation — and for each name the **DB-constraint / trigger** (not app-only) that enforces it, plus the zero-violators pre-flight query that returns empty before CLOSED. This is the design artifact review-plan `[B]` / review-build `[B]` (the CROSSTAB method) assert the built code against. N/A when the build has no ≥2-related-table surface.
   - **Compliance / PII design (v0.21.0, for any build touching customer PII / financial records):** state a `compliance/PII:` line covering what is logged (assert **no raw PII/secret in logs**), retention, residency, and that no regulated field crosses into an out-of-scope view. This is what `compass.sh pii-gate` (plan seam) requires when the contract declares `pii: yes`; N/A when the build touches no PII/financial surface.
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

<!-- FEYNMAN -->
## In plain words — where we are and what's next
**What just happened.** I read your live codebase first — real files, real readers and writers — then wrote a step-by-step build plan where every step has a command that proves it works.
**Why it matters.** Every promise in the contract now maps to a step and a test, so "done" will mean proven, not assumed. It also names what breaks if an outside service is slow, and the exact one-command undo.
**Your options:**
- **Approve & continue** — move to review-plan (independent reviewers tear the plan apart before any code).
- **Revise** — re-run planning with a change you name.
- **Amend** — a real scope change: bump the contract and re-review just the delta.
- **Pause** — stop cleanly; you resume exactly here, nothing lost.
**My recommendation.** Approve & continue — send the plan to an independent review before writing code.
Progress — ③ plan drafted (grounded in the real codebase) · next: ④ review-plan.
<!-- CONFIDENCE -->
**The rigor I'm applying, so you can trust the machine:** "I read your live codebase first — real file paths, real readers and writers — then wrote a build plan where every step has a command that proves it works. Every contract promise maps to a step and a test. I've listed what breaks if each outside service is slow or down, and the exact one-command way to undo this."

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
