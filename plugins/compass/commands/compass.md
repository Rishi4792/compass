---
description: Run the Compass contract-first build lifecycle end-to-end — contract → review → plan → review → build → review — with user-driven gates between every stage, auto-pause when context runs low, and clean cross-session resume.
---

# /compass — the lifecycle orchestrator

Compass builds software **true to spec, with zero drift**. The contract is the invariant; every stage is checked against it. You (the orchestrator) sequence the six skills, but **you never auto-advance** — each transition is a user-driven gate.

## State (file-based, resumable)
All state lives in `.claude/builds/<slug>/`:
- `contract.md` — the locked invariant (from `compass:contract`)
- `plan.md` — the executable step checklist with verify commands (from `compass:plan`)
- `review-ledger.md` — open/closed issues across all three reviews
- `progress.md` — the cursor: current stage, status (draft / in-review / LOCKED), next action, and a one-line resume pointer.

Because state is on disk, a build survives any session ending. Always read `progress.md` first to know where you are.

## The pipeline (and what gates each hop)
```
① compass:contract ─gate→ ② compass:review-contract ─gate→ [contract LOCKED]
   ─gate→ ③ compass:plan ─gate→ ④ compass:review-plan ─gate→ [plan LOCKED]
   ─gate→ ⑤ compass:build ─gate→ ⑥ compass:review-build ─gate→ [CLOSED]
```
- Reviews loop internally to convergence (2 clean rounds) before they offer their gate. Caps: R1=2, R2=3, R3=5.
- A review that hits its cap un-converged does **not** advance — it escalates UP a level (plan stuck → contract; build stuck → plan) and tells the user why.

## The gate (between every stage — never auto-advance)
When a stage finishes, present a short summary of what it produced and ask via **AskUserQuestion** with these four options:
1. **Approve & continue** — lock this stage's artifact and move to the next.
2. **Revise** — user gives a change; re-run the stage with it. (Stays on this stage.)
3. **Pause here** — stop cleanly; write the resume pointer (see Auto-pause). User can `/compass resume` later.
4. **Show full artifact** — print the complete `contract.md` / `plan.md` / `review-ledger.md`, then ask again.

Only **Approve** advances. The contract is read at the start of every later stage; if a stage detects drift from it, STOP and surface it rather than proceeding.

## Standalone / enter-anywhere
Each skill works on its own. The user can run `compass:plan` directly if a `contract.md` already exists, or `compass:review-build` on an existing build. If a stage's prerequisite file is missing, say so and offer to start at the right earlier stage — don't fabricate the missing artifact.

## Auto-pause (elegant cross-session handoff)
When context runs low (the pre-compaction hook fires) OR the user picks **Pause**:
1. Finish only the current atomic step — never pause mid-write or mid-verify.
2. Update `progress.md`: stage, status, the first unchecked `plan.md` step, and open ledger items.
3. Print the **resume block**:
   ```
   ─── Compass: paused at a clean boundary ───────────────
   Open a new terminal, run `claude`, and paste:

   change directory to "<abs build root>" and then run `/compass resume`.
   Stage: <stage> · Next: <the single next action>.
   ───────────────────────────────────────────────────────
   ```
This is the same elegance as session-handoff: one paste, zero ceremony, nothing lost.

## `/compass resume`
Read `.claude/builds/<slug>/progress.md`, state in one line where things stand ("Resuming — plan LOCKED, building step 4/11"), and continue from the recorded next action. Do not recite the files; just pick up.

## Bottom line
Sequence the six skills, gate every hop with the four options, keep the contract as the invariant, prove every "done" with the verify-ladder, and hand off cleanly when context ends.
