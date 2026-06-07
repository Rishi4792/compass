---
name: plan
description: Turn a locked CONTRACT into a detailed, industry-standard engineering plan a top engineer could build right the first time. STRICT PREREQUISITE — first scan and deeply understand the existing LIVE PROD codebase before writing any plan. Produces plan.md as an executable step-by-step checklist (each step with its own verify command). Trigger after the contract is locked, or when the user says "make the plan", "compass plan", "turn this into an engineering plan", or invokes /compass.
---

# compass:plan

Convert `contract.md` into the engineering plan the world's best engineers would expect — enough that they deliver it **right the first time**, with no surprises.

## ⛔ STRICT PREREQUISITE — understand the live prod codebase FIRST (do not skip)

**Before writing a single line of plan, scan and deeply understand the existing, live production codebase.** A plan written without grounding in the real code is fiction — it's the #1 cause of "the plan didn't match reality." Specifically, do this Phase 0 and *write what you found into the plan*:

1. **Inventory the repo's own guidance + tooling** (and PREFER existing workflows over inventing new ones): `CLAUDE.md` (+ nested), `.claude/` (commands, hooks, subagents, settings), `architecture.md`, `invariants.md`, `CONTEXT.md`, CI scripts, `package.json` scripts, `Makefile`, test runners, migration tooling, seed scripts, performance/load/OOM scripts, deploy/predeploy hooks, `render.yaml`/CI config.
2. **Map the real blast radius** — for every area the contract touches, read the *actual* code: which files, modules, readers, writers, API routes, background jobs, DB tables/relations, and which **existing workflows depend on them**. Trace direct AND indirect dependencies. Name the existing features that could regress.
3. **Discover the real infra constraints** from the repo — DB plan/size, instance count, caching/precompute layer, worker/memory ceiling, RBAC matrix, cost-control invariants. Do NOT assume; read them.
4. **Confirm the contract's data-derivation against reality** — does the live schema/data actually support what the contract says? If not, that's a finding to surface (the contract may need to bounce back).

Only after this grounding do you write the plan. **Cite real file paths and real constraints in the plan — no generic placeholders.**

## The plan (industry-standard, executable)

Write `plan.md` in the build folder. It must include:
1. **Traceability** — a row per contract requirement → the plan step(s) that deliver it. Nothing dropped.
2. **Files to change/add** — exact paths (from the Phase 0 scan).
3. **Codebases & workflows touched** — the named blast radius + which existing features could regress.
4. **DB / schema / migration decisions** — schema changes, migration + rollback strategy, index/lock behaviour, backfills, forward/back compatibility during deploy.
5. **API / contract decisions** — endpoints, request/response shape, backward compatibility, validation, idempotency.
6. **Code invariants** — the rules the implementation must hold (from the contract + the repo's own invariants).
7. **Step-by-step checklist** — ordered, atomic steps. **Each step has: what it does · which contract requirement it serves · its own VERIFY command** (from `../shared/verify-ladder.md`) · done/in-progress/pending marker. This checklist *is* what makes the build resumable across sessions.
8. **Test plan** — unit/integration/migration/API/UI/permission/regression/perf tests to add, mapped to features.
9. **Rollout & rollback** — deploy order, feature flags, how to revert.
10. **Assumptions & open risks** — explicit, with how each will be validated.

## Procedure
1. **Read `contract.md`** (the invariant). 2. **Run Phase 0** (above) — the prod-codebase scan. 3. Write `plan.md` as the executable checklist. 4. Update `progress.md` (stage ② Plan draft, next = Review-2). 5. Hand to the gate. Then it must pass `compass:review-plan` before locking.

## Done when
Phase 0 grounding is real (cited paths + constraints), every contract requirement is traced to a step, every step has a verify command, and `plan.md` is written. A deviation from `contract.md` discovered here = STOP and surface (the contract may need to change first).
