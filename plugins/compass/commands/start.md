---
description: Start (or continue) the Compass contract-first build lifecycle — contract → review → plan → review → build → review — with user-driven gates between every stage, auto-pause when context runs low, and clean cross-session resume.
---

# /compass:start — the lifecycle orchestrator

Compass builds software **true to spec, with zero drift**. The contract is the invariant; every stage is checked against it. You (the orchestrator) sequence the six skills, but **you never auto-advance** — each transition is a user-driven gate.

> Invocations are namespaced: this is `/compass:start`. The stages are `/compass:contract`, `/compass:review-contract`, `/compass:plan`, `/compass:review-plan`, `/compass:build`, `/compass:review-build`. Resume with `/compass:resume`.

## State (file-based, resumable)
All state lives in `.claude/builds/<slug>/`:
- `contract.md` — the locked invariant.
- `plan.md` — the executable step checklist with verify commands (its checkboxes are the **authoritative** record of build progress).
- `review-ledger.md` — open/closed issues across all three reviews (each review creates it if absent).
- `progress.md` — the cursor: current stage, status (draft / in-review / LOCKED / CLOSED), next action.

**`.claude/builds/CURRENT`** holds the active slug on one line. The contract skill writes it; you update it whenever the user switches builds. **Always read `CURRENT` first** to know which build you're on — never guess by globbing.

## The pipeline (and what gates each hop)
```
① contract ─gate→ ② review-contract ─gate→ [contract LOCKED]
   ─gate→ ③ plan ─gate→ ④ review-plan ─gate→ [plan LOCKED]
   ─gate→ ⑤ build ─gate→ ⑥ review-build ─gate→ [CLOSED]
```
- Reviews loop internally to convergence before they offer their gate. **Light review (review-contract) = one clean pass; full reviews = two consecutive clean rounds.** Caps: R1=2, R2=3, R3=5.
- A review that hits its cap un-converged does **not** advance — it escalates UP a level (plan stuck → contract; build stuck → plan; contract stuck → back to the user) and says why.

## The gate (between every stage — never auto-advance)
When a stage finishes, present a short summary of what it produced and ask via **AskUserQuestion** with four options:
1. **Approve & continue** — lock this stage's artifact, update `progress.md`, move to the next stage.
2. **Revise** — user gives a change; re-run the stage with it. (Stays on this stage.)
3. **Pause here** — stop cleanly; write the resume pointer (see Auto-pause).
4. **Show full artifact** — print the complete `contract.md` / `plan.md` / `review-ledger.md`, then ask again.

Only **Approve** advances. Every later stage reads `contract.md` as the invariant; if a stage detects drift from it, STOP and surface it rather than proceeding.

## Standalone / enter-anywhere
Each skill works on its own and does its own prerequisite check — if its required input file is missing it STOPs and offers the right earlier stage (it never fabricates the missing artifact). So the user can run `compass:plan` directly when a `contract.md` exists, or `compass:review-build` on an existing build.

## Auto-pause (elegant cross-session handoff)
When context runs low (the pre-compact hook fires) OR the user picks **Pause**:
1. **Write `progress.md` FIRST** (compaction can't be deferred) — stage, status, the first unchecked `plan.md` step, open ledger items. Never pause with a step's checkbox set whose verify didn't finish.
2. Print the **resume block**:
   ```
   ─── Compass: paused at a clean boundary ───────────────
   Open a new terminal, run `claude`, and paste:

   change directory to "<abs PROJECT root, where .claude/ lives>" and then run /compass:resume.
   Stage: <stage> · Next: <the single next action>.
   ───────────────────────────────────────────────────────
   ```
One paste, zero ceremony, nothing lost.

## Bottom line
Read `CURRENT`, sequence the six skills, gate every hop with the four options, keep the contract as the invariant, prove every "done" with the verify-ladder, and hand off cleanly when context ends.
