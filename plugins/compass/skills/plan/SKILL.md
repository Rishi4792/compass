---
name: plan
description: Turn a locked CONTRACT into a detailed, industry-standard engineering plan a top engineer could build right the first time. STRICT PREREQUISITE — first scan and deeply understand the existing LIVE codebase (or, for a greenfield build, the chosen stack/conventions) before writing any plan. Produces plan.md as an executable step-by-step checklist where each step has its own verify command and every contract INVARIANT becomes a named assertion. Trigger after the contract is locked, or when the user says "make the plan", "compass plan", or invokes the Compass orchestrator.
---

# compass:plan

Convert `contract.md` into the engineering plan the world's best engineers would expect — enough that they deliver it **right the first time**, with no surprises.

## Prerequisite check (Step 0)
Read `.claude/builds/CURRENT` → the slug → its `contract.md`. **If `contract.md` is absent, STOP** — offer to run `compass:contract`. Never plan against a missing contract. The contract is the invariant for everything below.

## ⛔ STRICT PREREQUISITE — understand the codebase FIRST (do not skip)

**Before writing a single line of plan, scan and deeply understand the existing code.** A plan written without grounding in the real code is fiction — the #1 cause of "the plan didn't match reality." Do this Phase 0 and *write what you found into the plan*:

1. **Inventory the repo's guidance + tooling** (and PREFER existing workflows over inventing new ones): `CLAUDE.md` (+ nested), `.claude/`, `architecture.md`, `invariants.md`, `CONTEXT.md`, CI scripts, `package.json` scripts, `Makefile`, test runners, migration tooling, seed/perf/load/OOM scripts, deploy/predeploy hooks, `render.yaml`/CI config.
2. **Map the real blast radius** — for every area the contract touches, read the *actual* code: files, modules, readers, writers, API routes, jobs, DB tables/relations, and which **existing workflows depend on them**. Trace direct AND indirect dependencies. Name the existing features that could regress.
3. **Discover the real infra constraints** from the repo — DB plan/size, instance count, caching/precompute layer, worker/memory ceiling, RBAC matrix, cost-control invariants. Read them; do NOT assume.
4. **Confirm the contract's data-derivation + reconciliation against reality** — does the live schema/data actually support the stated derivation/gold-figure? If not, that's a finding to surface (the contract may need to bounce back).

**Greenfield branch:** if there is no existing codebase, Phase 0 instead inventories the chosen stack, the scaffolding/boilerplate, the conventions you'll follow, and the test/deploy tooling you'll set up — and says explicitly "greenfield: no prod code to scan." Don't fabricate a blast radius that doesn't exist.

Only after this grounding do you write the plan. **Cite real file paths and real constraints — no generic placeholders.**

## The plan (industry-standard, executable)
Write `plan.md` in the build folder. It must include:
1. **Traceability** — a row per contract requirement → the plan step(s) that deliver it. Nothing dropped.
2. **INVARIANT → assertion map** — every contract INVARIANT (reconciliation ±X%, page <Ns, RBAC rule) mapped to the **exact verify command that asserts its specific bound**. An INVARIANT with no named assertion is an incomplete plan.
3. **Files to change/add** — exact paths (from Phase 0).
4. **Codebases & workflows touched** — the named blast radius + which existing features could regress.
5. **DB / schema / migration** — changes, migration + rollback strategy, lock/index behaviour, backfills, forward/back compatibility during a rolling deploy.
6. **API / contract** — endpoints, request/response shape, backward compatibility, validation, idempotency.
7. **Code invariants** — the rules the implementation must hold (from the contract + the repo's own invariants).
8. **Step-by-step checklist** — ordered, atomic steps. **Each step has: what it does · which contract requirement it serves · its VERIFY command · a done/in-progress/pending checkbox.** A step whose result can't be checked at build time may set verify = **"deferred — proven by step N / post-deploy check X"**, stated explicitly; a deferred verify with no named later proof is itself a defect. This checklist is what makes the build resumable.
9. **Test plan** — unit/integration/migration/API/UI/permission/regression/perf tests, mapped to features, incl. the **reconciliation** check and the **design-token** checks.
10. **Rollout & rollback** — deploy order, flags, the exact revert path.
11. **Assumptions & open risks** — explicit, each with how it'll be validated.

## Procedure
1. Read `contract.md`. 2. Run Phase 0. 3. Write `plan.md`. 4. Update `progress.md` (stage ② Plan draft, next = Review-2). 5. **Standalone STOP:** suggest `compass:review-plan` and stop — don't invoke it. Under the orchestrator, hand to the gate.

## Done when
Phase 0 grounding is real (cited paths + constraints), every contract requirement is traced, every INVARIANT has a named assertion, every step has a verify (or an explicit deferred-with-named-proof), and `plan.md` is written. A deviation from `contract.md` discovered here = STOP and surface (the contract may need to change first).
