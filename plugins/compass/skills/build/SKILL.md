---
name: build
user-invocable: false
description: Build-Test-Verify — execute the locked PLAN one step at a time, verify adversarial and proof-based (never "looks right"). Reads contract.md as the invariant before each step; deviation STOPS. Reconciliation is a deterministic PASS/FAIL gate vs the independent gold; a step's box is checked only after its verify passes. Trigger after the plan locks, or on "build it", "compass build", or the Compass orchestrator.
---

# compass:build

Execute the locked `plan.md` step by step. Loop = **Build → Test → Verify**; verify is adversarial (try to prove the step WRONG).

<!-- DOCTRINE:START -->
**Read these before you start.** They are the standards this stage is held to, and they
live in `plugins/compass/shared/` so they are the same for every stage that uses them:

- **`shared/engine.md`** — how this build keeps moving between steps.
- **`shared/verify-ladder.md`** — what counts as a real verify for this project's facets.

(A standard nobody loads is not a standard. `shared/MANIFEST` declares who reads each file and
`doctrine-wired-check.sh` proves it — `feynman.md` sat unread for three releases while its own
first line claimed three stages loaded it.)
<!-- DOCTRINE:END -->

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
0. **Abort sentinel (INV-ABORT, v0.16.0):** at the TOP of each step **and before every mutating op** (a file write, a migration, a bulk data op), run `compass.sh abort-check <slug>` — **non-zero (exit 3) → HALT cleanly**: stop *before* the mutation, leave committed + working state known-good and revertible, record the cursor in `progress.md`, and exit. **Bulk mutations run in bounded batches with a checkpoint after each batch**, re-checking `abort-check` between batches so a mid-flight `compass.sh abort <slug>` bounds blast radius (never a half-applied bulk op). This is the clean mid-flight stop for an autonomous/`--auto` build.
1. **Build** exactly as specified — no scope creep. **(web, v0.14.0) Apply the design-standard:** before building any UI surface, load the contract's `design-standard` bundled skill — invoke the `rk-house-style` skill (product surfaces: dashboards/tables/forms/charts) and/or the `cinematic-hero` skill (hero/launch/motion) — and compose from ITS pinned tokens + component recipes; never invent off-system styles. The contract's `## Design Spec` (extracted from that same bundled skill) is the binding target, and its gates (`rk-house-style` anti-drift + compose-check against the active theme) are the per-surface craft check.
   - **(v0.15.0) Kill-switch spine (F-FLAG):** any **user-visible** change is built behind the contract's declared feature flag, **flag defaulted OFF** (dark). The step's verify must exercise **both states**: flag OFF = the old behavior is intact (no user-visible change), flag ON = the new behavior. A user-visible change with only one state proven is not done. (`no flag — <reason>` in the contract waives this for that build.)
2. **Test** — run/add the deterministic test the plan named.
3. **Verify (adversarial)** — lowest project-facet rung that genuinely proves it; record the exact command + fresh output:
   - **web:** typecheck → DB query → page HTML → API → **Playwright** (assert DOM text + computed CSS + a11y basics) → Chrome MCP (last resort). **pipeline/CLI:** exit code → golden-file diff → asserts → numeric reconciliation → determinism (run twice → identical) → idempotent re-run.
   - **Source-data/rung-2 does NOT prove the UI shows it** — any number/page/token a user reads needs the UI rung. Use BOTH UI checks: *exact things* → assert DOM text vs the query value and computed CSS vs the contract tokens (never a screenshot for these); *design-intent fidelity* → **screenshot the built UI and read it back against the contract's captured DESIGN INTENT**, naming any drift from what was imagined (layout, hierarchy, spacing, feel). The screenshot is the gestalt check; the assertions are the exact check.
   - **Screenshot secret hygiene (v0.21.0, INV-IMG-SECRET):** any cold screenshot captures only redacted / `test-tenant` data — never a real-secret view (a live token, key, or another tenant's PII on screen). Boundary: Compass's `secret-scan is text-only` (grep over text; there is NO image/OCR scanner — the plugin is dependency-free), so this is a reviewer checklist line, not an automated image scan. (The green-CI / expand-contract / backfill-recon gates ride the review-build seam; rollback-fwd-compat rides ship Step 0.6.)
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
   - **SHOW THE PROGRESS CARD (v0.28.0, INV-CARD / INV-CARD-RECEIPT — not optional, not prose).** Run `compass.sh progress-card <build-dir>`, **show its output to the user**, and append that same output into the step receipt between the literal fences `<!-- progress-card -->` and `<!-- /progress-card -->`. The user must never have to ask where the build is: every step shows what is planned, what is done, what is running, and what remains. `COMPASS_QUIET=1` suppresses the *printing* only — the card is still written to the receipt, because the gate reads the receipt and a quiet mode that also stopped recording would deadlock every build.
   - **THEN GATE ON IT (INV-CARD-GATE).** Run `compass.sh progress-gate <build-dir>` before starting step k+1. **Non-zero → STOP**: the step is not done until its card is on its receipt. An empty fence fails too — a marker with no card is the byte-inert failure this gate exists to end.
5. **Verify fails** → diagnose root cause (no patch-stacking), fix, re-verify.

## Escalation (supersede, then stop)
- Step fails repeatedly → plan flaw → `compass.sh supersede .claude/builds/<slug> plan`, STOP, escalate to `compass:plan`.
- Build reveals the **contract premise is false** → `compass.sh supersede .claude/builds/<slug> contract`, STOP, escalate to `compass:contract` (contract → review-contract → plan → review-plan all re-run).
- Irrecoverable mid-build failure → leave committed work **known-good + revertible**, record the cursor, surface it.

## Final receipt (when all steps checked)
**Test-rigor gates (v0.22.0) — run BEFORE emitting the receipt:** `compass.sh mutation-check .claude/builds/<slug>` (RUNS each declared `mutation:` recipe: red green-on-pristine → red-after-break; a decorative/broken recipe → non-zero; **N/A-pass if the build declares none**) and `compass.sh redgreen-check .claude/builds/<slug>` (a build with `adds-test: yes` MUST carry a real, non-placeholder `red-green:` line; **N/A-pass if `adds-test: no`/absent**). Both are byte-inert for a build that opts out — but if you added a test or a guard, declare them.

### Write the artefact-data block (v0.31, INV-DECLARED)

Before emitting the receipt, append a `compass-artefact-data` fence to `progress.md` carrying the
fields THIS STAGE owns. The generator states these verbatim and marks them `declared`; the gate holds
the page to them. A field you do not write is counted by reading and disclosed to the reader as such,
which is a worse but honest outcome — so write what you actually know, and nothing you do not.

**Only declare a field with an EXACT, mechanically checkable source.** A plan checkbox and a bolded
`INV-` id are syntax Compass itself writes, so counting them is not a heuristic. Do NOT declare
`findings.*`: those come from classifying free text in a ledger, which is precisely the guessing this
build removed. `compass.sh gold-numbers-gate` cross-checks every declared field against its source
file and fails on a disagreement, so a wrong number here is caught, not shipped.

```compass-artefact-data
{
  "steps.total": <count of `- [ ]` + `- [x]` lines in plan.md, outside code fences>,
  "steps.done":  <count of `- [x]` lines in plan.md, outside code fences>,
  "invariants.total": <count of distinct **INV-* ids in contract.md>
}
```

**EMIT RECEIPT** with real commands/outputs (a bare `[x]` with no command = auto-FAIL via `scan-receipt`):
```
## RECEIPT — build · <slug> · PASS
- [x] engine: long-build armed, cap <N> — or `engine: none` with a reason. `compass.sh engine-gate <build-dir>` refuses an armed loop with no cap, and N/A-passes when the skill is not installed (Compass does not ship it).
- [x] gate: review-plan receipt OK
- [x] all plan steps checked, each with recorded fresh proof
- [x] INVARIANT <id>: `<cmd>` → <actual> vs <bound> PASS   (one line PER invariant, none deferred)
- [x] RECONCILE: `compass.sh reconcile <actual> <gold> <tol>` → PASS   (or N/A iff contract reconciliation is N/A)
RECON-CMD: <the exact reproducing-query command>   (verbatim, so a parallel sibling's merged-recon can re-run it on the merged tree)
- [x] (web) token <name>: getComputedStyle → <rgb> == <hex> PASS
- [x] test-rigor (v0.22.0): `compass.sh mutation-check .claude/builds/<slug>` → PASS + `compass.sh redgreen-check .claude/builds/<slug>` → PASS   (N/A-pass if the build declares no `mutation:`/`adds-test:`)
adds-test: <yes|no>
red-green: <the failing test + WHY it failed before the fix — REQUIRED when adds-test: yes; omit/`no` otherwise>
mutation: <INV-id · file=<relpath> · break=<cmd on {}> · red=<cmd on {}>>   (0+ lines; each proven to bite by mutation-check)
- [x] secret-scan: `compass.sh secret-scan <build-dir>` (per-build text artifacts) + `compass.sh secret-scan --commits <base>..HEAD` (committed patches) → 0 hits
```
Self-check: `compass.sh scan-receipt .claude/builds/<slug> build`.

<!-- FEYNMAN -->
## In plain words — where we are and what's next
**What just happened.** I built the plan one small step at a time, and didn't check a box until a command proved that step actually works on real data — not just that it compiles.
**Why it matters.** Risky changes went behind an off-by-default switch, and every number was reconciled against the locked gold figure with a script, not an opinion. If anything drifted from the spec, I stopped and asked.
**Your options:**
- **Approve & continue** — move to review-build (the final adversarial pass before deploy).
- **Revise** — re-run a build step with a change you name.
- **Amend** — a real scope change: bump the contract and re-review just the delta.
- **Pause** — stop cleanly; you resume exactly here, nothing lost.
**My recommendation.** Approve & continue to the final adversarial review.
Progress — ⑤ build complete (each step proof-gated) · next: ⑥ review-build.
<!-- CONFIDENCE -->
**The rigor I'm applying, so you can trust the machine:** "I build one small step at a time and don't check the box until a command proves that step actually works on real data — not just that it compiles. Risky changes go behind an off-by-default switch. I reconcile every number against the locked gold figure with a script, not an opinion, and I stop and ask if anything drifts from the spec."

<!-- GATE:START -->
## Stage transition — the gate (fires on EVERY entry path)

This stage owns its own transition gate. Present it whether this stage was invoked on its own
(the `compass:build` skill) or sequenced by the `compass:start` orchestrator. The orchestrator
does **not** present a second gate — the stage owns it.

1. First print the one-line **transition footer**, in exactly this shape:

   `✓ <this stage> PASSED — <one-line proof>.  Next: <next stage> · run \`/compass:go\`.`

   That footer line is for the READER: it names where they are and the door they can take if they
   want to steer. It is not your instruction — yours is the Approve branch at the end of this block.

   `<next stage>` is not guessed. Run `compass.sh next-stage <build-dir>` and branch on its EXIT
   CODE, never on its output, because two different states both print nothing:
   **0** → the stage it named · **3** → every stage has passed, so Next is `done — build SHIPPED` ·
   **anything else** → the build state could not be read; say exactly that and stop, rather than
   guessing a stage or reporting the build finished.

   Then PUSH the RAIL when this stage produced an artefact — run
   `compass.sh rail <build-dir> --artefact <view> --url <the published URL>` (or `--local <path>`
   when nothing could publish it) and show it, so the link is in front of the user beside the
   buttons rather than described in prose. (v0.30: the rail existed and nothing called it — a
   surface nobody invokes is not a surface, the same defect this build was raised to fix.)

   Then PUSH the cockpit — run `compass.sh cockpit <build-dir>` and show it — so the user always
   sees where they are (the 7-stage strip · step k/n · next; plus program phases + contracts when
   in a program) with **zero typing** (v0.24.0 INV-PUSH-STAGE). Silence between stages is a defect.

   Then RUN the stage-end gate on what you just printed — `compass.sh cockpit-gate <build-dir>`.
   It checks the four elements a reader needs are actually there (what happened · where you are ·
   what is next · the options, each naming a real command). v0.32 built it and NOTHING invoked it,
   so it never ran on a single installation; v0.33.3 wires it here, which is its only correct home
   because it validates a block the model PRINTS rather than a file on disk. Non-zero → fix the
   block and print it again before presenting the gate.

2. Then present the gate using **AskUserQuestion** with exactly these **4 options**
   (AskUserQuestion caps at 4; "Show full artifact" is offered via the auto-provided **Other**,
   or just print the artifact if the user asks):
   - **Approve & continue** — advance to the next stage.
   - **Revise** — re-run this stage with the user's change.
   - **Amend** — a legitimate scope change (not drift): bump the contract version + changelog,
     run a mini review-contract on the delta, `supersede` downstream, re-baseline.
   - **Pause here** — stop cleanly; write the resume pointer to `progress.md`.

Only **Approve** or **Amend** advances — and on **Approve** you CONTINUE, you do not stop to ask a
second time. Run `compass.sh next-stage <build-dir>` — the build directory is the one this stage has
been working in — and on exit 0 **invoke the named stage with the Skill tool**, whose skill name is
`compass:` followed by that stage, exactly the way this stage was invoked. On exit 3 the build is
finished; on any other code, say the state could not be read and stop. The user has already said
yes; the silence after that yes is the stall this gate exists to end.

The seven stage skills are hidden from the `/` menu, and that is not an obstacle — it is a division
of labour. A person types **`/compass:resume`**; a model uses the Skill tool. Both reach the same
stage. What nobody has is a `/compass:` slash command named after a stage, so never print one: it
sends the reader to a door that is not there.

On **Revise**, re-run this stage with the change. On **Pause**, stop cleanly. On any detected drift
from `contract.md`, STOP and surface instead of advancing.

*(Until v0.35 this paragraph forbade invoking the next skill at all. It told the reader what would
NOT happen and never what would, so an approved stage ended in silence and the build waited for a
human to remember the next command. The old sentence is not quoted here, because the check that
proves it is gone greps for it — a note about a banned string that contains the banned string keeps
the defect alive in the file that fixed it. The gate still ASKS. What changed is that an answer of
Approve is now acted on rather than described.)*
<!-- GATE:END -->
