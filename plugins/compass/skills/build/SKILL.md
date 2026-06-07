---
name: build
description: Build-Test-Verify — execute the locked PLAN one step at a time, where VERIFY is adversarial and proof-based (never "looks right"). Reads contract.md as the invariant before every step; any deviation STOPS and asks. Uses the verify-ladder (cheapest real proof first; assert DOM text / computed CSS for UI; Playwright over Chrome MCP; prod = read-only). Updates plan.md checkboxes and progress.md so the build is resumable. Trigger after the plan is locked, or when the user says "build it", "compass build", or invokes the Compass orchestrator.
---

# compass:build

Execute the locked `plan.md` step by step. The loop per step is **Build → Test → Verify**, and **Verify is adversarial** — you are trying to prove the step is WRONG, and only when you can't, with a real check, is it done.

## Prerequisite check (Step 0)
Read `.claude/builds/CURRENT` → slug → `plan.md` AND `contract.md`. **If `plan.md` is absent, STOP** — say so and offer `compass:plan`. **Never improvise a build from the contract or the prompt** — that is the exact drift Compass exists to prevent. `plan.md` checkboxes are the authoritative record of build progress; `progress.md` is a pointer (on conflict, trust the checkboxes).

## The invariant (read before every step)
Before each step, re-read the relevant part of `contract.md`. **If a step would deviate from the contract — even slightly — STOP and ask.** Do not "improve" beyond the contract silently.

## The per-step loop
For each unchecked step in `plan.md`, in order:
1. **Build** — make the change exactly as the step specifies. No scope creep beyond the step.
2. **Test** — run/add the deterministic test the plan named.
3. **Verify (adversarial)** — pick the **lowest verify-ladder rung that genuinely proves the step**, and try to break it. Inlined ladder essentials (full spec in `shared/verify-ladder.md`):
   - typecheck/build → **DB query** (counts/sums/**reconciliation to the gold figure**) → page HTML via curl+cookie → API response → **Playwright** (assert DOM text + computed CSS; screenshot is layout-sanity only) → Chrome MCP (last resort).
   - **Never claim done on reading code or agent agreement.** Record the exact command + its fresh output.
   - **Rung 2 proves the data, not that the UI shows it.** Any claim about a page/number/token a user sees cannot stop below Playwright.
   - **Screenshots are never a numeric or token check** — assert exact DOM text vs the rung-2 value; assert computed CSS vs the contract's tokens.
   - **Playwright: prod = read-only asserts ONLY; any write-flow runs against local/staging.** First assertion must fail loudly if redirected to login (so a bad cookie can't fake a pass).
   - For any step implementing a contract **INVARIANT**, the verify MUST assert its exact bound (the ±X%, the <Ns, the RBAC rule) — not a generic "it works."
4. **Only after verify fully passes**, check the step's box in `plan.md` and record the proof, then update `progress.md` (current step, next step). **Never check a box before its verify passes** — so an interrupted verify always resumes as "pending," never falsely "done."
5. **If verify fails:** diagnose root cause (don't layer patches). Fix, re-verify.

## Escalation (don't force it)
- Same step fails repeatedly → the **plan likely has a flaw** → STOP and escalate to `compass:plan`.
- The build reveals the **contract's premise was false** (e.g. the named gold source doesn't actually reconcile) → STOP and escalate directly to `compass:contract` — don't churn the plan around a wrong contract.
- **Irrecoverable mid-build failure** → leave the committed work in a **known-good, revertible state**, record the cursor in `progress.md`, and surface it. Never leave a half-applied build with no record.

## Resumability & auto-pause
State lives in files: `plan.md` checkboxes (authoritative progress), `progress.md` (pointer), `review-ledger.md` (open issues). On low context the pre-compact hook fires — write `progress.md` FIRST (before finishing anything else), since compaction can't be deferred. Never pause with a box checked whose verify didn't complete.

## Done when
Every step in `plan.md` is checked with a recorded real proof, all named tests pass, and **every contract acceptance INVARIANT is demonstrated with an actual check that asserts its specific bound** (incl. reconciliation to the gold figure and design tokens) — not asserted. Then hand to `compass:review-build` (Review-3). **Standalone STOP:** suggest it; don't invoke it yourself.
