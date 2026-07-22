# 🧭 Compass

**Write the contract. Walk away. It builds to spec.**

An autonomous **engineering team in one plugin** for [Claude Code](https://claude.com/claude-code) — Engineering Manager, coder, QA, DevOps. You finalize one super-contract; it does the rest: **plan → code → tests → ship**, following the engineering best-practices a real team would, and it doesn't stop until the work is *proven* against your spec.

![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-8A63D2)
![version](https://img.shields.io/badge/version-0.13.0-1f6feb)
![license](https://img.shields.io/badge/license-MIT-3fb950)

Built on the architecture serious builders are converging on — an explicit **graph** of stages with hard gates as edges, and adversarial **loops** that make every output top-notch. *(That's the whole trick — [see below](#how-it-works-loops-and-graphs-with-real-edges).)*

> **You choose how hands-off.** By default Compass stops for you at **every** stage (approve / revise / amend). Flip on autonomous mode and it stops at only **two** — you approve the contract up front, and it wakes you only for a genuine judgment call (ship-despite-a-miss, an infeasible invariant, a budget ceiling). Everything from "review every step" to "wake me only if it needs me" is a setting. Your call, your risk tolerance.

![Compass hero: write the contract and walk away → an autonomous team (EM · Coder · QA · DevOps) runs a gated pipeline → it catches a Critical in its own code (exit 1) → fixed, re-proven, and shipped to spec](docs/compass-demo.gif)

---

## Meet the team

Compass isn't a prompt or a checklist — it's a **full engineering org, autonomous**, with every role a real team has, and one contract as the single source of truth they all answer to:

- 🧭 **Engineering Manager** — sits with you to lock the **contract**, scans the live codebase, and turns it into a real **engineering plan**: every step with a verify command, every invariant with a check, every migration with a dry-run.
- ⌨️ **Coder** — builds it **one step at a time**, and a step isn't "done" until its verify command passes. No big-bang commits, no "trust me."
- 🔍 **QA** — **three adversarial review passes** (on the contract, the plan, and the built code) whose only job is to *break* each output — and they **loop until they can't**. Then a **post-ship critique loop** checks the live system with its own eyes.
- 🚀 **DevOps** — **ships** via the repo's own deploy path, re-runs the number check against **prod** data, and confirms the monitoring signal actually fires — or it stays un-shipped.

The reason each role's output is top-notch is the **adversarial review loop**: nothing advances on a claim of "done" — it advances only after an independent reviewer has tried to break it and failed, twice.

## The one thing you do: the contract

You write **one super-contract** — the single source of truth for what's being built: the goal, the data, the scale, the acceptance criteria, and (crucially) **a number to reconcile against** so "correct" is measurable, not a matter of opinion. And Compass's contract interview doesn't just transcribe you — it **expands your thinking** (pre-mortem / 10x / adjacent-use-case menus, with a hard "something must be rejected" gate) and **sketches what you're describing as you decide it** (a throwaway UI wireframe that becomes the binding spec, or a Mermaid logic map otherwise).

Once the contract locks, the team runs. **That's the deal: finalize the spec, then do nothing — and it builds to spec.**

## Why you can trust it unattended — proof, not vibes

An autonomous team is only useful if you can trust it *while you're not watching*. Compass's answer: **every "done" is a recorded command with an exit code an agent can't argue with.**

```
$ compass.sh gate .claude/builds/my-feature review-plan
COMPASS-GATE: FAIL — 'review-plan' receipt has an UNCHECKED box — its work is incomplete:
- [ ] migration dry-run-on-copy present
# (exit 1 — the build cannot proceed)
```

Correctness is arithmetic, not opinion — if the number's wrong, the build **can't close**:

```
$ compass.sh reconcile 1208 1155 1%
RECONCILE: actual=1208 gold=1155 tol=1% diff=53 FAIL   # exit 1 — build cannot close
```

Every guardrail you've tried before was *prose the agent could talk past* — a rule it rationalizes around, a checklist it marks complete. Compass makes "done" a **script with an exit code.** The agent doesn't get to be the judge.

## It catches its own bugs

Every release since v0.5.0 is built *by running Compass on Compass* — the full lifecycle, on itself. And its own reviews keep catching the exact failures the project exists to kill, **before** `main`:

- **The most recent release** — QA caught a **Critical in Compass's own gate**: a status parser that would have let Compass authorize `SHIPPED` over an *unresolved open bug*. Its own adversarial review found it across five rounds of re-attack; it was fixed and re-proven with ~80 regression tests before it shipped. The tool caught itself trying to ship a bug.
- **v0.10.0** — the reviews killed a *token* budget that can't be measured from a shell (→ a measurable ceiling), caught that JSON can't be parsed in POSIX shell (→ line-oriented state), and found **7 real defects** in the built code before any reached `main`.
- **v0.5.0** — an invariant "proven" by grepping prose, and a missing design ledger that would have counted as a pass. Both stopped at the gates.

If a tool's own discipline can't survive its own reviews, it doesn't work. Compass's does — on itself, every release. *(Receipts in [CHANGELOG.md](CHANGELOG.md).)*

## How it works: loops and graphs, with real edges

This is the whole trick, and it's the architecture the best builders are reaching for right now — Compass is one you can install today.

**It's a graph.** The stages are nodes; the **edges are exit-code scripts, never model-chosen.** The build advances from one node to the next *only* when a gate script returns zero — never because an LLM decided the previous step "looked done." That single property is what separates Compass from an orchestration DAG (and rebuts "it's just a state machine"): a state machine doesn't verify.

**And it's loops.** Inside the graph are the verifier loops that make each role's output excellent — the adversarial reviews that repeat until **two consecutive clean rounds**, and the post-ship critique loop that runs on the live system until it finds nothing. Every loop is bounded: a cap, a convergence rule, stall detection, and — when it runs autonomously — a budget ceiling **proven to hold across real spawned processes**, so it can't run away.

Loops *and* graphs, both bounded and enforced: an explicit stage-graph whose edges a script guards, with convergence loops that keep hammering each output until it's provably done. That's how you get a team you can leave alone.

```
① contract ─▶ ② review-contract ─▶ [contract-LOCKED]
                                     │
        ┌────────────────────────────┘
        ▼
③ plan ─▶ ④ review-plan ─▶ [plan-LOCKED]
                            │
        ┌───────────────────┘
        ▼
⑤ build ─▶ ⑥ review-build ─(sign-off)▶ [CLOSED] ─▶ ⑦ ship ─▶ ⑧ post-ship review ─(loop to convergence)▶ [SHIPPED]
                                                       │
                     SHIPPED is not the finish line ───┘  it critiques the LIVE system until it converges
```

## The stages — who does what

| # | Stage | Role · what it does |
|---|-------|--------------|
| ① | `/compass:contract` | **EM** — interviews you into an airtight, locked spec; expands your thinking + sketches the UI/logic; pins the facets (`web` / `pipeline` / `library`), the acceptance INVARIANTs, and **reconciliation to an *independent* gold figure**. Won't finish with gaps. |
| ② | `/compass:review-contract` | **QA (light)** — pressure-tests completeness, ambiguity, testability, and that reconciliation is pinned, independent, exact. One clean pass; cap 2. |
| ③ | `/compass:plan` | **EM** — scans the live codebase first, then writes the step-by-step plan: each step a verify command, every INVARIANT a non-deferred check, every migration a dry-run-on-a-copy. |
| ④ | `/compass:review-plan` | **QA (full)** — traceability, invariant coverage, migration, dependencies, blast radius, rollback, tests, perf, security, secret-leak. Two clean rounds; cap 3. |
| ⑤ | `/compass:build` | **Coder** — Build-Test-Verify, one step at a time; a box is checked only after its verify passes; page builds get a real page-load proof (typecheck-only is rejected). |
| ⑥ | `/compass:review-build` | **QA (full)** — feature/regression/RBAC/perf + reconciliation, design+a11y, exercised rollback, wired monitoring, secret-scan, blast-radius re-load. Ends with your sign-off. Two clean rounds; cap 5. |
| ⑦ | `/compass:ship` | **DevOps** — deploys via the repo's own path, re-runs the number check on **prod**, confirms monitoring fires. Prod-verify is a hard stop — unreachable prod stays CLOSED, never a soft "shipped." |
| ⑧ | *post-ship critique loop* | **QA, on the live system** — critiques what actually deployed against the contract (screenshots for UI, re-run numbers for data), loops back to fix on any material finding. `SHIPPED` is *unwritable* until it converges. |

### Under the teeth
- **Verify ladder** — cheapest real proof first, by facet: typecheck → DB query → page HTML → API → Playwright (assert DOM + computed CSS, plus a screenshot read-back vs the design you captured) for web; exit code → golden-file → asserts → numeric reconciliation → determinism for data. Never correctness on agent agreement.
- **The teeth = a real script.** Each stage emits a receipt of actual commands + outputs; the next stage runs `compass.sh gate`, which **exits non-zero** if the prior receipt is absent, FAIL, unchecked, or superseded. `reconcile` and `secret-scan` are deterministic `PASS/FAIL` gates that block close.
- **Parallel builds** — a repo can run N builds at once (incl. one unattended), each in its own git worktree so one build's `git add` can't sweep another's; a sibling that merges first blocks the others until they re-verify. (See [docs/PARALLEL-BUILDS-KEYSTONE.md](docs/PARALLEL-BUILDS-KEYSTONE.md).)

## You decide how hands-off

Compass runs on a spectrum, and it's a setting — from a checkpoint at every stage down to nearly none:
- **Fully gated (default):** it stops at **every** stage for Approve / Revise / **Amend the contract** / Pause — you review each hop.
- **Autonomous (`--auto`):** it stops at only **two** — you approve the contract + intent up front, and it wakes you only for a genuine judgment call (ship-despite-a-miss, an infeasible invariant, a budget ceiling). Everything else auto-advances, and the adversarial reviews still self-correct exactly as when gated.
- **Anywhere in between:** run a single stage, resume across sessions, or drive it interactively and hand off. It's your risk tolerance, not ours.

Autonomous mode refuses to start without a **measurable budget** (wall-clock + max-sessions + max-stages); that ceiling is proven to hold across real spawned processes, so a walk-away build can't run up your bill.

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

Then `/compass:start` for the full lifecycle (add `--auto` to run it autonomously), or invoke any stage by name (`/compass:contract`, `/compass:plan`, …). Resume anytime with `/compass:resume`.

> Plugin commands are namespaced (`/compass:start`, not `/compass`). Every stage is also reachable as the bare skill `/build` (which auto-triggers on natural language like "build it"), and every stage presents its 4-button next-step gate at its transition.

## State & resumability
Each build's state lives in `.claude/builds/<slug>/` — `contract.md`, `plan.md`, `review-ledger.md`, `progress.md`, `receipts.md` — so closing the terminal loses nothing; `/compass:resume` picks up exactly where it left off.

## Versioning & updates
Semantic versioning; every change is in **[CHANGELOG.md](CHANGELOG.md)**. See **[RELEASING.md](RELEASING.md)** for the release process. Update via `/plugin marketplace update compass`.

## Why "Compass"
A compass keeps you pointed true no matter the terrain. Same idea: the contract is your true north, and every stage checks the bearing.

## License
[MIT](LICENSE) © 2026 Rishi Kapoor.
