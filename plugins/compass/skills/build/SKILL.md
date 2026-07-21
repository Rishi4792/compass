---
name: build
description: Build-Test-Verify — execute the locked PLAN one step at a time, verify adversarial and proof-based (never "looks right"). Reads contract.md as the invariant before each step; deviation STOPS. Reconciliation is a deterministic PASS/FAIL gate vs the independent gold; a step's box is checked only after its verify passes. Trigger after the plan locks, or on "build it", "compass build", or the Compass orchestrator.
---

# compass:build

Execute the locked `plan.md` step by step. Loop = **Build → Test → Verify**; verify is adversarial (try to prove the step WRONG).

## Step 0 — own this build, then gate
**FIRST, unconditionally (fresh OR resumed/direct entry), before the gate:** `compass.sh own <slug> --session "$CLAUDE_CODE_SESSION_ID"`. This binds the build's owner to THIS session so the Stop hook guards *your* session — and only yours — from the very first edit (a resumed build entered in a new terminal must be owned before any work, never guarded only after the first step). v0.9.0: the Stop hook blocks the owning session of a mid-build and stays quiet for every other session, build, and project — so parallel builds never contaminate each other.

Then run `compass.sh gate "$(compass.sh state-root)/<slug>" review-plan`. **Non-zero → STOP** (plan not LOCKED), offer `compass:review-plan`. Also: if the INDEX line is a terminal status, STOP and ask which build this is. **Never improvise a build from the contract or prompt.** `plan.md` checkboxes are the AUTHORITATIVE progress record.

**Parallel-build gate (when `compass.sh active-builds` shows >1):**
- `compass.sh assert-worktree <slug>` — **non-zero → STOP**; you are in the wrong directory. `cd` to this build's worktree; all build work happens there (a commit from the main checkout would contaminate a sibling).
- `compass.sh claim <slug> <plan touches globs> --from <new-files-list>` then `compass.sh check-overlap <slug>` — re-run as scope grows. **Non-zero → STOP**: a claimed file collides with a sibling build. Coordinate additively, record `ack:<slug>+<other>:<path>` in the locks `acks` file, then continue. (Unattended: write the resume banner and stop instead of asking.) Always claim `package-lock.json` and your migration dir so the conflict surfaces here, not at merge.
- If the plan changes schema: `compass.sh check-db-isolation <slug> 1 <provision-declared>` — **non-zero → STOP** (no per-worktree DB isolation; concurrent migrations corrupt the shared dev DB).
- **Migration-delivery gate (v0.7.0, schema-touching builds):** after any step that changes schema, `compass.sh migration-gate .claude/builds/<slug>` — **non-zero → STOP**. Proves a real migration in the deploy's canonical folder reproduces the schema on a fresh DB (STRICT). A schema applied via `prisma db execute`/hand-SQL, a stray migration in a non-canonical dir, or a fresh-apply that fails = FAIL. **Never** hand-apply to the dev DB to make a step go green — that is the exact `pg-method-rates` outage.
- **Commits:** stage only claimed paths — **never `git add -A`**, **never `--no-verify`** (the pre-commit guard enforces this; a bypass is caught by `compass.sh audit-staged <slug>`).
- **Blast-radius page-load proof (v0.8.0, when the plan declares `## Affected routes`):** for EACH declared route, actually load it (GET/Playwright against the migration-built schema, never a hand-patched dev DB) and record the **canonical proof line** in `receipts.md`, exactly: `- [x] route <path>: <cmd> → 200 <content-assert>` (route token AND `200`/`loaded` on ONE line; echo the declared path **verbatim** so the literal match holds). Before the final build receipt, run `compass.sh route-coverage .claude/builds/<slug>` — **non-zero → STOP** (a declared route has no recorded load proof). Typecheck-only verify for a page/route step is rejected.

## The invariant (before every step)
Re-read the relevant `contract.md` part. **A step that would deviate — even slightly — STOPS and asks.** Never "improve" beyond the contract silently.

## Per-step loop (each unchecked step, in order)
1. **Build** exactly as specified — no scope creep.
2. **Test** — run/add the deterministic test the plan named.
3. **Verify (adversarial)** — lowest project-facet rung that genuinely proves it; record the exact command + fresh output:
   - **web:** typecheck → DB query → page HTML → API → **Playwright** (assert DOM text + computed CSS + a11y basics) → Chrome MCP (last resort). **pipeline/CLI:** exit code → golden-file diff → asserts → numeric reconciliation → determinism (run twice → identical) → idempotent re-run.
   - **Source-data/rung-2 does NOT prove the UI shows it** — any number/page/token a user reads needs the UI rung. Use BOTH UI checks: *exact things* → assert DOM text vs the query value and computed CSS vs the contract tokens (never a screenshot for these); *design-intent fidelity* → **screenshot the built UI and read it back against the contract's captured DESIGN INTENT**, naming any drift from what was imagined (layout, hierarchy, spacing, feel). The screenshot is the gestalt check; the assertions are the exact check.
   - **Per-step design check (web + mockup):** for any UI step, render the built surface vs the mockup on **real/representative data** and log every difference (layout/spacing/typography/color/hierarchy/state) as an OPEN row in `design-ledger.md`. **A UI step's box is NOT checked while it has an open design-drift row.** Use `compass.sh design-style-diff` for token-exact checks (necessary, not sufficient). This catches drift per-step, not only at review-build.
   - **Cold-critic (v0.12.0, web builds with `cold-critic: on` — the v0.12 contract skill writes it for every web contract):** the FINAL web verify runs the cold protocol — a FRESH in-session subagent whose ONLY inputs are cold screenshots (pinned viewport, every contract state, saved in the build dir and path-named in the receipt) + the Design Spec; zero builder reasoning (that echo-check is the point). Append (fresh block per run):
     <!-- TEMPLATE: cold-critic-receipt -->
     ```
     ## RECEIPT — cold-critic · <GO|NO-GO> · tree=<git sha-12>
     - [x] clean-tree: git status --porcelain empty
     - [x] cold screenshots: <evidence path>
     ```
     Build may finish at 1×GO — `compass.sh coldgo-gate <dir>` convergence (2×GO on ONE sha == current HEAD) is owned by review-build [C]. A gated human sign-off uses `## RECEIPT — cold-critic · HUMAN-GO · "<verbatim quote>" · tree=<sha>` and requires `cold-critic-fallback: human-eyeball` in the contract (never valid in --auto).
   - **INVARIANT steps:** the verify MUST run and assert the exact bound; **never deferred.**
   - **Reconciliation = a script gate, not an opinion:** run the contract's reproducing query for `actual`, then `compass.sh reconcile <actual> <gold-literal-from-contract> <tol>`. **Non-zero exit = the build cannot close.** (Gold is the contract's *independent published* figure — if the reproducing query shares the build query's logic, note that the gate only catches display drift; run the dup / fan-out / source-table bug-class checks too.)
   - **Playwright auth:** discover the scheme from the repo (or STOP and ask — never guess); read the token from **env, never commit it**; assert a **positive authed-only element with real data** (a blank 200 shell = FAIL). **Prod = read-only;** writes run on local/staging, or a reversible **create→assert→delete probe (teardown in `finally`)**, or are marked **UNVERIFIED — no non-prod env** and surfaced.
4. **Only after verify passes**, check the step's box in `plan.md`, record the proof, **refresh ownership** (`compass.sh own <slug> --session "$CLAUDE_CODE_SESSION_ID"` — keeps the guard pointed at the live session), and **append a progress receipt** `## RECEIPT — build · <slug> · IN-PROGRESS · step k/n` (so a crash mid-build is distinguishable from "never started"). **Never check a box before its verify passes.**
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
RECON-CMD: <the exact reproducing-query command>   (verbatim, so a parallel sibling's merged-recon can re-run it on the merged tree)
- [x] (web) token <name>: getComputedStyle → <rgb> == <hex> PASS
- [x] secret-scan: `compass.sh secret-scan .` → 0 hits
```
Self-check: `compass.sh scan-receipt .claude/builds/<slug> build`.

<!-- GATE:START -->
## Stage transition — the gate (fires on EVERY entry path)

This stage owns its own transition gate. Present it whether the stage was run standalone
(bare skill, e.g. `/build`), via the namespaced command (`/compass:build`), or sequenced by
`/compass:start`. The orchestrator does **not** present a second gate — the stage owns it.

1. First print the one-line **transition footer**, in exactly this shape:

   `✓ <this stage> PASSED — <one-line proof>.  Next: <next stage> · run \`/compass:<next stage>\`.`

   (For the terminal `ship` stage, Next is `done — build SHIPPED`.)

2. Then present the gate using **AskUserQuestion** with exactly these **4 options**
   (AskUserQuestion caps at 4; "Show full artifact" is offered via the auto-provided **Other**,
   or just print the artifact if the user asks):
   - **Approve & continue** — advance to the next stage.
   - **Revise** — re-run this stage with the user's change.
   - **Amend** — a legitimate scope change (not drift): bump the contract version + changelog,
     run a mini review-contract on the delta, `supersede` downstream, re-baseline.
   - **Pause here** — stop cleanly; write the resume pointer to `progress.md`.

Only **Approve** or **Amend** advances. **Never auto-invoke the next skill** — the gate ASKS;
it does not advance by itself. On any detected drift from `contract.md`, STOP and surface
instead of advancing.
<!-- GATE:END -->
