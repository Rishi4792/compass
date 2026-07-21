# 🧭 Compass

**Build software true to spec, with zero drift.** A contract-first build lifecycle for [Claude Code](https://claude.com/claude-code).

![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-8A63D2)
![version](https://img.shields.io/badge/version-0.11.0-1f6feb)
![license](https://img.shields.io/badge/license-MIT-3fb950)

> **The problem in one line:** AI coding agents drift from what you asked — and worse, they say *"done"* when the numbers are wrong or a step was skipped. **Compass makes "done" something the agent has to *prove*, with a real gate it can't talk past.**

![Compass: contract → plan → build with adversarial reviews at every gate — drift in the numbers or the UI can't pass](docs/compass-demo.gif)

---

## Compass is a graph

Stages are nodes, **script gates are the edges** (exit codes — never model-chosen), adversarial reviews and the post-ship critique loop are independent verifier nodes with fresh context and on-disk evidence only. Every cycle is bounded (caps + convergence bounds from the contract header + stall detection + budget metering inside the registration gate). `SHIPPED` is not the finish line: it is unwritable until the post-ship loop converges on the live system.

## What is Compass?

Compass turns any non-trivial build into a disciplined, contract-first lifecycle. You write a locked **contract** — the single source of truth for what's being built — and every later stage (plan, build, three adversarial reviews, and an optional ship) is checked against it. The contract is the invariant; the moment anything drifts, Compass **stops and asks**.

It exists because the #1 failure in AI-assisted building is **drift** — the thing that ships isn't the thing that was agreed. Worse, an AI will often *say* it's done when the numbers are wrong or a step was skipped. Compass makes the agreement explicit and testable, and — crucially — **enforces it with a real gate script, not just prose an AI can talk past.**

## Who is it for?

- Anyone using **Claude Code (or AI agents) to build real software or data work** who keeps hitting *"it drifted from what I asked"* or *"it said done, but it was wrong."*
- Builds where **correctness matters**: production features, anything that must **reconcile to a number** (analytics, finance, reporting), schema/migration work, multi-session efforts.
- People who want the AI to **prove** each step rather than vouch for it.

## When *not* to use it

- Throwaway scripts, one-off edits, quick spikes, or pure exploration where you want speed over rigor. Compass adds discipline on purpose — that discipline is overhead you don't want for a five-minute task.

---

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
⑤ build ─▶ ⑥ review-build ─(human sign-off)▶ [CLOSED] ─▶ ⑦ ship (mandatory*) ─▶ [SHIPPED]
                                                             * unless the contract marks `deploy: out-of-scope`
```

Between every hop is a **user-driven gate** (Approve / Revise / **Amend contract** / Pause / Show) — Compass never auto-advances. Reviews loop to convergence first: the light review on **one clean pass**, the full reviews on **two consecutive clean rounds**.

## The skills

| # | Skill | What it does |
|---|-------|--------------|
| ① | `/compass:contract` | Interviews you until the spec is airtight, for the chosen **facets** (`web` / `pipeline` / `library`, composable): data derivation, schema, scale, dependencies, **reconciliation to an *independent* gold figure**, measurable acceptance INVARIANTs, and (web) auth + UI tokens + a11y. Won't finish with gaps. |
| ② | `/compass:review-contract` | **Review-1 (light)** — pressure-tests completeness, ambiguity, testability, and that reconciliation is pinned, *independent*, and exact. One clean pass; cap 2. |
| ③ | `/compass:plan` | **Scans the live codebase first** (or the chosen stack, for greenfield), then writes a step-by-step plan — each step a verify command, every INVARIANT a non-deferred bound-asserting check, every migration a dry-run-on-a-copy. |
| ④ | `/compass:review-plan` | **Review-2 (full)** — traceability, INVARIANT coverage, migration/dry-run, dependencies, blast radius, rollback, tests, reconciliation feasibility, perf, security, secret-leak. Two clean rounds; cap 3. |
| ⑤ | `/compass:build` | **Build-Test-Verify**, one step at a time. Reconciliation is a script `PASS/FAIL`; a step's box is checked only after its verify passes. For builds that touch pages, **every route in the declared blast radius gets a recorded page-load proof** (`route-coverage`) — typecheck-only for a page step is rejected. |
| ⑥ | `/compass:review-build` | **Review-3 (full)** — feature/regression/RBAC/perf + reconciliation, design+a11y, exercised rollback, wired observability, idempotency, secret-scan, **blast-radius `route-coverage` (hard CRITICAL) with each declared route independently RE-LOADED**. Ends with a **human sign-off** on the evidence. Two clean rounds; cap 5. |
| ⑦ | `/compass:ship` | **Mandatory** (unless the contract marks deploy out of scope) — deploys via the repo's own path, then re-runs reconciliation on prod data and confirms the observability signal actually emits. **Prod-verify is a hard stop**: unreachable prod keeps the build at CLOSED, never a soft "shipped". **Post-deploy route smoke** GETs each declared route on prod (200-with-content) — any miss blocks SHIPPED. For schema builds, `migration-gate` must pass (a real migration reproduces the schema on a fresh DB). |

### Two engines + the teeth
- **Verify ladder** — cheapest real proof first, by facet. Web: typecheck → DB query → curl+cookie HTML → API → **Playwright** (assert DOM text + computed CSS for exact things, **plus a screenshot read-back vs the design you captured at planning time** so the result has zero drift from what you imagined; prod read-only) → Chrome MCP (last resort). Pipeline/CLI: exit code → golden-file diff → asserts → numeric reconciliation → determinism. Never correctness on agent agreement.
- **Review core** — fan-out streams, one ledger, a convergence loop. Light review = one clean pass; full = two consecutive clean rounds, and a round counts as clean only if its evidence (command + exit + counts) is recorded. Cap un-converged escalates UP (and *supersedes* downstream receipts) — never fakes done.
- **The teeth = a real script, not prose.** Each stage emits a receipt to `receipts.md` carrying the actual commands + outputs; the next stage's Step-0 runs **`scripts/compass.sh gate`**, which **exits non-zero** if the prior receipt is absent, FAIL, has an unchecked box, or was superseded — a hard error the build can't step past. Reconciliation (`compass.sh reconcile`) and secret-scan (`compass.sh secret-scan`) are deterministic `PASS/FAIL` gates that block close.
- **Parallel builds — one worktree per build.** A repo can run N builds at once (including one unattended) without them stepping on each other: each build gets its own git worktree under `~/.compass/worktrees/<project-id>/<slug>`, so one build's `git add` can never sweep another's files. `compass.sh builds` shows everything in flight, `compass.sh doctor` audits/sweeps worktrees, and when a sibling merges first **`compass.sh post-merge-check`** blocks the others (base-advanced + blast-radius vs `origin/<base>`) until they re-verify. Schema builds must declare per-worktree DB isolation or Compass refuses to run them in parallel. (See [docs/PARALLEL-BUILDS-KEYSTONE.md](docs/PARALLEL-BUILDS-KEYSTONE.md).)

---

## Install

```
/plugin marketplace add Rishi4792/compass
/plugin install compass@compass
```

Or, once it's listed in the Anthropic community marketplace:

```
/plugin marketplace add anthropics/claude-plugins-community
/plugin install compass@claude-community
```

Then `/compass:start` to run the full lifecycle, or invoke any stage by name (`/compass:contract`, `/compass:plan`, …). Resume anytime with `/compass:resume`.

> Plugin commands are namespaced, so it's `/compass:start`, not `/compass`.
>
> Every stage is reachable two ways: the namespaced `/compass:build` and the bare skill `/build` (the skill name also auto-triggers on natural language like "build it"). Both run the same stage, and **every stage presents the 4-button next-step gate** (Approve / Revise / Amend / Pause) at its transition — whichever way you entered.

## Use it three ways
- **Full pipeline:** `/compass:start` — the whole lifecycle with gates.
- **Any single stage:** run e.g. `/compass:plan` or `/compass:review-build` directly. Each downstream stage gates on the previous one's proof and STOPs (pointing you to the right earlier stage) rather than fabricating it.
- **Resume anytime:** `/compass:resume` — picks up from on-disk state, so closing the terminal loses nothing.

## Autonomous mode (`--auto`, v0.11.0) — opt-in, self-spawning
`/compass:start --auto` runs the whole lifecycle **without the per-hop gate**, stopping for a human at only **two** points: **G1** (one upfront approval of the contract + design intent) and **G2** (fires only when an invariant fails, a review can't converge, the budget is hit, or prod-verify fails). Everything in between auto-advances, and the autonomous adversarial reviews still self-correct exactly as in gated mode. *(Why two? An audit of 38 past Compass builds showed humans only ever changed direction at those two kinds of moment — taste/strategy, and "ship despite a miss" — while the reviews caught all mechanical correctness on their own.)*

It's bounded by a **mandatory measurable budget** (`--auto` refuses to start without one): wall-clock seconds + max-sessions + max-stages (defaults 1h / 6 / 40), enforced cumulatively. When context runs low it **auto-spawns a fresh session** (`/compass:resume <slug> --auto`) — at *any* stage (v0.11) — and continues with no human, guarded so it can never bypass a gate, run two sessions at once, or exceed the budget. The runaway ceiling is proven to hold across **real separate spawned processes** (INV-HALT), so the chain cannot exceed the budget regardless of what it launches — the explicit guard against an autonomous loop running away. Default (no flag) behavior is unchanged.

Turn it on two ways (v0.11):
```
# one command, then start:
compass.sh auto-start <build-dir> --wall 3600 --sessions 6 --stages 40 && /compass:start --auto
# …or just run /compass:start — it asks "Gated or Autonomous?" up front.
```
**Rollback** to fully-gated: delete the auto artifacts from the build dir (`budget.env`, `session-chain.log`, the `.auto-mode` marker, and any `.locks/<slug>.{gate-lock,owner,blocked}`). All `--auto` behavior is flag-gated, so removing the marker restores gated mode exactly. `--auto` is mutually exclusive with `--unattended`.

## A quick taste of "the teeth"
You can't skip a stage by claiming you did the work — the gate is a real command:

```
$ compass.sh gate .claude/builds/my-feature review-plan
COMPASS-GATE: FAIL — 'review-plan' receipt has an UNCHECKED box — its work is incomplete:
- [ ] migration dry-run-on-copy present
# (exit 1 — the build cannot proceed)
```

Reconciliation is arithmetic, not opinion:

```
$ compass.sh reconcile 1208 1155 1%
RECONCILE: actual=1208 gold=1155 tol=1% diff=53 FAIL   # exit 1 — build cannot close
```

---

## State & resumability
Each build's state lives in `.claude/builds/<slug>/` — `contract.md`, `plan.md`, `review-ledger.md`, `progress.md`, `receipts.md` — and `.claude/builds/CURRENT` points to the active build so resume never has to guess.

## Versioning & updates
Semantic versioning; every change is recorded in **[CHANGELOG.md](CHANGELOG.md)** (what changed and why). See **[RELEASING.md](RELEASING.md)** for the release process. Self-hosted installs update via `/plugin marketplace update compass`.

## Proof: Compass builds its own releases
Every release since v0.5.0 has been built *by running Compass on Compass* — the full contract → review → plan → review → build → review → ship lifecycle, on itself. And on its own releases the reviews keep catching the exact failures the project exists to kill, **before** anything ships:
- **v0.5.0** — an invariant being "proven" by grepping prose, and a missing design ledger that would have counted as a pass. Both stopped at the contract/plan gates.
- **v0.10.0** (the opt-in `--auto` autonomous loop) — review-contract killed a *token* budget that can't actually be measured from a shell (→ a measurable wall/sessions/stages ceiling) and caught that the auto-close would be blocked by the existing sign-off gate; review-plan caught that JSON can't be parsed in POSIX shell (→ line-oriented state) and that the time ceiling wouldn't bind without a per-stage check; review-build found 8 defects in the built code, including the spawn path enforcing only the session cap, not the time limit. None reached `main`.

The reviews earn their keep — on their own releases. (See [CHANGELOG.md](CHANGELOG.md).)

## Why "Compass"
A compass keeps you pointed true no matter the terrain. Same idea here: the contract is your true north, and every stage checks the bearing.

## License
[MIT](LICENSE) © 2026 Rishi Kapoor.
