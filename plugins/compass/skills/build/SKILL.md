---
name: build
description: Build-Test-Verify — execute the locked PLAN one step at a time, where VERIFY is adversarial and proof-based (never "looks right"). Reads contract.md as the invariant before every step; any deviation STOPS and asks. Uses the verify-ladder (cheapest real proof first; Playwright over Chrome MCP). Updates plan.md checkboxes so the build is resumable across sessions. Trigger after the plan is locked, or when the user says "build it", "compass build", "start building", or invokes /compass.
---

# compass:build

Execute the locked `plan.md` step by step. The loop per step is **Build → Test → Verify**, and **Verify is adversarial** — you are trying to prove the step is WRONG, and only when you can't, with a real check, is it done.

## The invariant (read before every step)
Before each step, re-read the relevant part of `contract.md`. The contract is the invariant. **If a step would deviate from the contract — even slightly — STOP and ask.** Drift is the failure mode this whole plugin exists to kill. Do not "improve" beyond the contract silently.

## The per-step loop
For each unchecked step in `plan.md`, in order:
1. **Build** — make the change exactly as the step specifies. No scope creep beyond the step.
2. **Test** — run/add the deterministic test the plan named for this step.
3. **Verify (adversarial)** — pick the **lowest rung of `../shared/verify-ladder.md` that genuinely proves the step**, and try to break it:
   - typecheck/build → DB query (counts/sums/reconciliation) → page HTML via curl+cookie → API response → **Playwright flow + screenshot** (read screenshots back) → Chrome MCP (last resort only).
   - **Never claim done on reading the code or agent agreement.** Record the exact command + its real output.
   - For "does the page/flow actually work" — use **Playwright (rung 5), not Chrome MCP** (no cross-project lock; the spec persists as a regression test).
4. **Mark the step done in `plan.md`** (checkbox) and note the proof. This is what makes the build resumable — a fresh session reads `plan.md` and continues at the first unchecked step.
5. **If verify fails:** diagnose root cause (don't layer patches). Fix, re-verify. If the same step fails repeatedly, the **plan likely has a flaw** → STOP and escalate UP to `compass:plan` rather than forcing it.

## Resumability
State lives in files: `plan.md` checkboxes (progress), `progress.md` (stage), `review-ledger.md` (open issues). At any clean step boundary the build can pause and resume in a new session — the orchestrator's auto-pause handles the handoff.

## Done when
Every step in `plan.md` is checked with a recorded real proof, all named tests pass, and the contract's acceptance INVARIANTs are each demonstrated with an actual check (not asserted). Then hand to `compass:review-build` (Review-3, FULL) for the final adversarial pass before close.
