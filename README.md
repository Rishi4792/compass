# 🧭 Compass

**Build software true to spec, with zero drift.**

Compass is a Claude Code plugin that turns any non-trivial build into a contract-first lifecycle. You write a locked **contract** (the single source of truth), and every later stage — plan, build, and three adversarial reviews — is checked against it. The contract is the invariant; the moment anything drifts, Compass stops and asks.

It exists because the #1 failure in AI-assisted building is **drift**: the thing that ships isn't the thing that was agreed. Compass makes the agreement explicit, testable, and enforced at every step.

## The lifecycle

```
① contract ─▶ ② review-contract ─▶ [contract-LOCKED]
                                     │
        ┌────────────────────────────┘
        ▼
③ plan ─▶ ④ review-plan ─▶ [plan-LOCKED]
                            │
        ┌───────────────────┘
        ▼
⑤ build ─▶ ⑥ review-build ─(human sign-off)▶ [CLOSED] ─▶ ⑦ ship (optional) ─▶ [SHIPPED]
```

Between every hop is a **user-driven gate** (Approve / Revise / **Amend contract** / Pause / Show) — Compass never auto-advances. Reviews loop to convergence first: the light review on **one clean pass**, the full reviews on **two consecutive clean rounds**.

## The skills

| # | Skill | What it does |
|---|-------|--------------|
| ① | `/compass:contract` | Interviews you until the spec is airtight, for the chosen **facets** (`web` / `pipeline` / `library`, composable): data derivation, schema, scale, dependencies, **reconciliation to an *independent* gold figure**, measurable acceptance INVARIANTs, and (web) auth + UI tokens + a11y. Won't finish with gaps. |
| ② | `/compass:review-contract` | **Review-1 (light)** — pressure-tests completeness, ambiguity, testability, and that reconciliation is pinned, *independent*, and exact. One clean pass; cap 2. |
| ③ | `/compass:plan` | **Scans the live codebase first** (or the chosen stack, for greenfield), then writes a step-by-step plan — each step a verify command, every INVARIANT a non-deferred bound-asserting check, every migration a dry-run-on-a-copy. |
| ④ | `/compass:review-plan` | **Review-2 (full)** — traceability, INVARIANT coverage, migration/dry-run, dependencies, blast radius, rollback, tests, reconciliation feasibility, perf, security, secret-leak. Two clean rounds; cap 3. |
| ⑤ | `/compass:build` | **Build-Test-Verify**, one step at a time. Reconciliation is a script `PASS/FAIL`; a step's box is checked only after its verify passes. |
| ⑥ | `/compass:review-build` | **Review-3 (full)** — feature/regression/RBAC/perf + reconciliation, design+a11y, exercised rollback, wired observability, idempotency, secret-scan. Ends with a **human sign-off** on the evidence. Two clean rounds; cap 5. |
| ⑦ | `/compass:ship` | Optional — deploys via the repo's own path, then re-runs reconciliation on prod data and confirms the observability signal actually emits. Skipped if the contract marks deploy out of scope. |

### Two engines + the teeth
- **Verify ladder** — cheapest real proof first, by facet. Web: typecheck → DB query → curl+cookie HTML → API → **Playwright** (assert DOM text + computed CSS; prod read-only) → Chrome MCP (last resort). Pipeline/CLI: exit code → golden-file diff → asserts → numeric reconciliation → determinism. Never correctness on agent agreement.
- **Review core** — fan-out streams, one ledger, a convergence loop. Light review = one clean pass; full = two consecutive clean rounds, and a round counts as clean only if its evidence (command + exit + counts) is recorded. Cap un-converged escalates UP (and *supersedes* downstream receipts) — never fakes done.
- **The teeth = a real script, not prose.** Each stage emits a receipt to `receipts.md` carrying the actual commands + outputs; the next stage's Step-0 runs **`scripts/compass.sh gate`**, which **exits non-zero** if the prior receipt is absent, FAIL, has an unchecked box, or was superseded — a hard error the build can't step past. Reconciliation (`compass.sh reconcile`) and secret-scan (`compass.sh secret-scan`) are deterministic `PASS/FAIL` gates that block close. Escalation calls `compass.sh supersede` so the re-reviews it triggers actually re-run.

## Use it three ways
- **Full pipeline:** `/compass:start` — runs the whole lifecycle with gates.
- **Any single stage:** run e.g. `/compass:plan` or `/compass:review-build` directly. Each downstream skill does its own Step-0 prerequisite check — if the prior stage's receipt is missing or FAIL it STOPs and points you to the right earlier stage (it never fabricates the missing artifact). (`contract` is the entry point, so it has no prerequisite.)
- **Resume anytime:** `/compass:resume` — picks up from `progress.md`. State is file-based, so closing the terminal loses nothing.

## Install

```
/plugin marketplace add <owner>/compass
/plugin install compass@compass
```

Then `/compass:start` to begin, or invoke any stage by name (`/compass:contract`, `/compass:plan`, …).

> Plugin commands are namespaced, so it's `/compass:start`, not `/compass`.

## Why "Compass"
A compass keeps you pointed true no matter the terrain. Same idea here: the contract is your true north, and every stage checks the bearing.

---

*State for each build lives in `.claude/builds/<slug>/` — `contract.md`, `plan.md`, `review-ledger.md`, `progress.md` — and `.claude/builds/CURRENT` points to the active build so resume never has to guess.*

## Verify, honestly
Compass never claims correctness on an LLM eyeballing output. The verify ladder climbs from the cheapest real proof to the costliest: typecheck → DB query → page HTML → API → **Playwright** (assert DOM text + computed CSS; prod = read-only) → Chrome MCP (last resort, because it locks across projects). Screenshots are layout sanity only — numbers are asserted against the DB value, design tokens against computed CSS.
