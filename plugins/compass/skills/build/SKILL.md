---
name: build
description: Build-Test-Verify — execute the locked PLAN one step at a time, where VERIFY is adversarial and proof-based (never "looks right"). Reads contract.md as the invariant before every step; any deviation STOPS and asks. Uses the project-type verify rungs (assert DOM text / computed CSS for UI; reconciliation is a hard PASS/FAIL gate; Playwright auth is discovered not guessed; prod = read-only). A step's box is checked only after its verify passes. Trigger after the plan is locked, or when the user says "build it", "compass build", or invokes the Compass orchestrator.
---

# compass:build

Execute the locked `plan.md` step by step. The loop is **Build → Test → Verify**, and **Verify is adversarial** — you try to prove the step WRONG; only when you can't, with a real check, is it done.

## Step 0 — gate
Read `.claude/builds/CURRENT` → slug → `receipts.md`. **If the `review-plan` receipt is absent or FAIL (plan not LOCKED), STOP** and offer `compass:review-plan`/`compass:plan`. **Never improvise a build from the contract or the prompt** — that is the exact drift Compass prevents. `plan.md` checkboxes are the AUTHORITATIVE record of build progress; `progress.md` is a pointer (on conflict, trust the checkboxes).

## The invariant (before every step)
Re-read the relevant part of `contract.md`. **If a step would deviate — even slightly — STOP and ask.** Never "improve" beyond the contract silently.

## Per-step loop (for each unchecked step, in order)
1. **Build** — exactly as specified. No scope creep.
2. **Test** — run/add the deterministic test the plan named.
3. **Verify (adversarial)** — lowest project-type rung that genuinely proves it; try to break it. Essentials (skill authoritative; `shared/verify-ladder.md` is an overview):
   - **web:** typecheck → DB query (counts/sums/reconciliation) → page HTML → API → **Playwright** (assert DOM text + computed CSS) → Chrome MCP (last resort). **pipeline/CLI:** exit code → golden-file diff → unit asserts → **numeric reconciliation** → determinism (same input twice → identical) → idempotent re-run.
   - **Never claim done on reading code or agent agreement.** Record the exact command + fresh output.
   - **Rung 2 / source data does NOT prove the UI/output shows it** — a number/page/token a user reads cannot stop below the UI rung. **Screenshots are layout-sanity only** — assert exact DOM text vs the rung-2 value; assert computed CSS vs the contract tokens.
   - **INVARIANT steps:** the verify MUST run and assert the exact bound (±X%, <Ns, RBAC). **An INVARIANT assertion may NOT be deferred.**
   - **Reconciliation = a HARD GATE, not an opinion.** Run the contract's reproducing query and emit `RECONCILE: actual=<x> gold=<y> tol=<t> PASS|FAIL`. **FAIL means the build cannot close — no severity discretion.** Default tolerance is exact (0) unless the contract carries a justified, user-signed band.
   - **Playwright auth:** discover the scheme from the repo (or STOP and ask — never guess); read the token from **env, never commit it**; assert a **positive authed-only DOM element with real data** (a blank 200 shell = FAIL). **Prod = read-only asserts only;** a write-flow runs against local/staging, or — if none exists — a reversible **create→assert→delete probe on a test-tagged row with teardown in `finally`**, or is marked **UNVERIFIED — no non-prod env** and surfaced.
4. **Only after verify fully passes**, check the step's box in `plan.md`, record the proof, and update `progress.md` (current/next step). **Never check a box before its verify passes** — an interrupted verify always resumes as "pending," never falsely "done."
5. **Verify fails** → diagnose root cause (no patch-layering), fix, re-verify.

## Escalation (don't force it)
- Step fails repeatedly → **plan flaw** → STOP, escalate to `compass:plan`.
- The build reveals the **contract's premise is false** (e.g. the named gold source can't reconcile) → STOP, escalate to `compass:contract` — don't churn the plan around a wrong contract.
- **Irrecoverable mid-build failure** → leave committed work in a **known-good, revertible state**, record the cursor in `progress.md`, surface it. Never a half-applied build with no record.

## Auto-pause
On low context the pre-compact hook fires a *reminder* (it can't write for you, and compaction can't be deferred) — the real safety net is per-step discipline: progress.md is fresh after every step and a box is never checked before its verify passes, so a lost compaction costs at most one step.

## EMIT RECEIPT (when all steps checked)
```
## RECEIPT — build · <slug> · PASS
- [x] review-plan LOCKED receipt was present
- [x] every plan.md step checked, each with recorded fresh proof
- [x] every INVARIANT asserted at its exact bound (none deferred)
- [x] RECONCILE: actual=<x> gold=<y> tol=<t> PASS   (or N/A — no numbers)
- [x] (web) design tokens asserted via computed CSS
- [x] no secret committed in any verify spec
- [x] progress.md current
```
**Standalone STOP:** suggest `compass:review-build`; don't invoke it.

## Done when
Receipt PASS: every step checked with a real recorded proof, all named tests pass, every acceptance INVARIANT demonstrated at its exact bound, **RECONCILE PASS** (if numbers), tokens asserted (web). Then hand to `compass:review-build`.
