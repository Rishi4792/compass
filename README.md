# 🧭 Compass

**Build software true to spec, with zero drift.**

Compass is a Claude Code plugin that turns any non-trivial build into a contract-first lifecycle. You write a locked **contract** (the single source of truth), and every later stage — plan, build, and three adversarial reviews — is checked against it. The contract is the invariant; the moment anything drifts, Compass stops and asks.

It exists because the #1 failure in AI-assisted building is **drift**: the thing that ships isn't the thing that was agreed. Compass makes the agreement explicit, testable, and enforced at every step.

## The lifecycle

```
① contract ──▶ ② review-contract ──▶ [CONTRACT LOCKED]
                                       │
        ┌──────────────────────────────┘
        ▼
③ plan ──▶ ④ review-plan ──▶ [PLAN LOCKED]
                              │
        ┌──────────────────────┘
        ▼
⑤ build ──▶ ⑥ review-build ──▶ [CLOSED]
```

Between every hop is a **user-driven gate** (Approve / Revise / Pause / Show full artifact) — Compass never auto-advances.

## The six skills

| # | Skill | What it does |
|---|-------|--------------|
| ① | `compass:contract` | Interviews you (ask-user-tool) until the spec is airtight: data derivation, schema, UI/UX, features, **measurable** acceptance goals. Won't finish with gaps. |
| ② | `compass:review-contract` | **Review-1 (light)** — pressure-tests the spec for completeness, ambiguity, testability. Cap 2. |
| ③ | `compass:plan` | **Scans the live prod codebase first**, then turns the contract into an industry-standard, step-by-step engineering plan — each step with its own verify command. |
| ④ | `compass:review-plan` | **Review-2 (full)** — multi-agent: traceability, migration safety, blast radius, rollback, tests, performance, security. Cap 3. |
| ⑤ | `compass:build` | **Build-Test-Verify**, one step at a time. Verify is adversarial and proof-based — never "looks right". |
| ⑥ | `compass:review-build` | **Review-3 (full)** — final adversarial sweep; every "it works" backed by a real check. Cap 5. |

### Two engines shared across the skills
- **Verify ladder** — cheapest real proof first: typecheck → DB query → curl+cookie HTML → API → **Playwright** → Chrome MCP (last resort). Never claim correctness on agent agreement.
- **Review core** — fan-out streams, one issue ledger, and a convergence loop that stops only on **2 consecutive clean rounds**. Hitting a cap un-converged escalates UP a level (it never fakes "done").

## Use it three ways
- **Full pipeline:** `/compass` — runs the whole lifecycle with gates.
- **Any single stage:** run e.g. `compass:plan` or `compass:review-build` directly. Each skill is standalone; it'll tell you if a prerequisite file is missing.
- **Resume anytime:** `/compass resume` — picks up from `progress.md`. State is file-based, so closing the terminal loses nothing.

## Install

```
/plugin marketplace add <owner>/compass
/plugin install compass@compass
```

Then `/compass` to start, or invoke any skill by name.

## Why "Compass"
A compass keeps you pointed true no matter the terrain. Same idea here: the contract is your true north, and every stage checks the bearing.

---

*State for each build lives in `.claude/builds/<slug>/` — `contract.md`, `plan.md`, `review-ledger.md`, `progress.md`.*
