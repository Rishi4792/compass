---
name: build
description: Build-Test-Verify — execute the locked PLAN one step at a time, where VERIFY is adversarial and proof-based (never "looks right"). Reads contract.md as the invariant before every step; any deviation STOPS and asks. Reconciliation is a deterministic PASS/FAIL gate against the contract's independent gold figure; INVARIANT assertions can't be deferred; Playwright auth is discovered not guessed; prod = read-only. A step's box is checked only after its verify passes. Trigger after the plan is locked, or when the user says "build it", "compass build", or invokes the Compass orchestrator.
---

# compass:build

Execute the locked `plan.md` step by step. Loop = **Build → Test → Verify**; verify is adversarial (try to prove the step WRONG).

## Step 0 — gate
Run `compass.sh gate .claude/builds/<slug> review-plan`. **Non-zero → STOP** (plan not LOCKED), offer `compass:review-plan`. Also: if `CURRENT`'s INDEX line is `status=closed`, STOP and ask which build this is. **Never improvise a build from the contract or prompt.** `plan.md` checkboxes are the AUTHORITATIVE progress record.

## The invariant (before every step)
Re-read the relevant `contract.md` part. **A step that would deviate — even slightly — STOPS and asks.** Never "improve" beyond the contract silently.

## Per-step loop (each unchecked step, in order)
1. **Build** exactly as specified — no scope creep.
2. **Test** — run/add the deterministic test the plan named.
3. **Verify (adversarial)** — lowest project-facet rung that genuinely proves it; record the exact command + fresh output:
   - **web:** typecheck → DB query → page HTML → API → **Playwright** (assert DOM text + computed CSS + a11y basics) → Chrome MCP (last resort). **pipeline/CLI:** exit code → golden-file diff → asserts → numeric reconciliation → determinism (run twice → identical) → idempotent re-run.
   - **Source-data/rung-2 does NOT prove the UI shows it** — any number/page/token a user reads needs the UI rung. **Screenshots = layout sanity only;** assert exact DOM text vs the query value, computed CSS vs the contract tokens.
   - **INVARIANT steps:** the verify MUST run and assert the exact bound; **never deferred.**
   - **Reconciliation = a script gate, not an opinion:** run the contract's reproducing query for `actual`, then `compass.sh reconcile <actual> <gold-literal-from-contract> <tol>`. **Non-zero exit = the build cannot close.** (Gold is the contract's *independent published* figure — if the reproducing query shares the build query's logic, note that the gate only catches display drift; run the dup / fan-out / source-table bug-class checks too.)
   - **Playwright auth:** discover the scheme from the repo (or STOP and ask — never guess); read the token from **env, never commit it**; assert a **positive authed-only element with real data** (a blank 200 shell = FAIL). **Prod = read-only;** writes run on local/staging, or a reversible **create→assert→delete probe (teardown in `finally`)**, or are marked **UNVERIFIED — no non-prod env** and surfaced.
4. **Only after verify passes**, check the step's box in `plan.md`, record the proof, and **append a progress receipt** `## RECEIPT — build · <slug> · IN-PROGRESS · step k/n` (so a crash mid-build is distinguishable from "never started"). **Never check a box before its verify passes.**
5. **Verify fails** → diagnose root cause (no patch-stacking), fix, re-verify.

## Escalation (supersede, then stop)
- Step fails repeatedly → plan flaw → `compass.sh supersede .claude/builds/<slug> plan`, STOP, escalate to `compass:plan`.
- Build reveals the **contract premise is false** → `compass.sh supersede .claude/builds/<slug> contract`, STOP, escalate to `compass:contract` (contract → review-contract → plan → review-plan all re-run).
- Irrecoverable mid-build failure → leave committed work **known-good + revertible**, record the cursor, surface it.

## Final receipt (when all steps checked)
**EMIT RECEIPT** with real commands/outputs (a bare `[x]` with no command = auto-FAIL via `scan-receipt`):
```
## RECEIPT — build · <slug> · PASS
- [x] gate: review-plan receipt OK
- [x] all plan steps checked, each with recorded fresh proof
- [x] INVARIANT <id>: `<cmd>` → <actual> vs <bound> PASS   (one line PER invariant, none deferred)
- [x] RECONCILE: `compass.sh reconcile <actual> <gold> <tol>` → PASS   (or N/A iff contract reconciliation is N/A)
- [x] (web) token <name>: getComputedStyle → <rgb> == <hex> PASS
- [x] secret-scan: `compass.sh secret-scan .` → 0 hits
```
Self-check: `compass.sh scan-receipt .claude/builds/<slug> build`. **Standalone STOP:** suggest `compass:review-build`; don't invoke it.
