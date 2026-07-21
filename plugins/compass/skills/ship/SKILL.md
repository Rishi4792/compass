---
name: ship
description: Ship (optional) — deploy the CLOSED build and prove it in prod — deploy via the repo's own path, re-run reconciliation on prod data, confirm the observability signal emits. Skipped if the contract marks deploy out of scope. Trigger after compass:review-build closes, or on "ship it", "deploy", "compass ship".
---

# compass:ship

The lifecycle verifies locally (prod stays read-only during build). This stage takes a CLOSED build to production and proves it there — closing the gap where the contract's Observability check only means something post-deploy.

## When NOT to run
If the contract's Non-goals mark **deploy out of scope**, skip — the build is done at CLOSED and the observability check was scoped to staging. Say so and stop.

## Step 0 — own, claim the ship lock (single-flight), then gate
1. **Own this build:** `compass.sh own <slug> --session "$CLAUDE_CODE_SESSION_ID"` (the Stop hook guards this session through ship).
2. **Claim the ship lock FIRST and unconditionally (v0.9.0 single-flight):** `compass.sh ship-claim <slug>`. **Non-zero → STOP** — another build holds the lock (it names the holder); only one build per project ships at a time. The lock self-heals (steals a SHIPPED/ROLLED-BACK or >2h-stale holder), so a crashed ship never deadlocks future ships. **You MUST `compass.sh ship-release <slug>` on EVERY exit from ship — success (SHIPPED), yield (Step 0.4), or any hard-stop (prod unreachable)** — so the lock is never leaked.
3. **Gate:** `compass.sh gate .claude/builds/<slug> review-build`. **Non-zero → STOP** (build not CLOSED/signed-off; `ship-release` first), offer `compass:review-build`. Read `contract.md` (deploy/rollback/observability are the invariant here).

## Step 0.4 — ship-contention ordering gate (v0.9.0, before the merge-consequence gate)
`compass.sh ship-contenders <slug>` lists OTHER ship-ready builds in this project (CLOSED, deploy not waived). If non-empty, **AskUserQuestion: which build ships first?**
- **This build chosen** → keep the claim, continue to Step 0.5.
- **The other chosen** → `compass.sh ship-release <slug>` + **yield** (write the resume pointer, STOP). The user ships the other; when this build resumes ship, Step 0.5 re-checks against the now-advanced base and hard-blocks until you integrate + re-verify. (This is exactly "the loser re-checks the implications to its merge.")

## Step 0.5 — parallel-build merge-consequence gate (HARD BLOCK — v0.6.0)
If other builds are/were in flight on this repo, a sibling may have merged into the base after this build's branch diverged. **Two independently-green branches do not prove the union is green.** Before shipping this build:
- **`compass.sh post-merge-check <this-slug>` — MANDATORY, non-zero → STOP.** It fetches, checks this build against `origin/<base>` (never local `main`): is the base **advanced**? did the merged change touch **this build's claimed files** (blast radius)? If so you must **integrate `origin/<base>` (rebase/merge) + re-verify** the touched surface before shipping. (No remote / current → it passes.)
- Then `compass.sh merged-recon <this-slug> <sibling-slug> <base-branch>` — re-runs **both** builds' recorded `RECON-CMD` on the *merged* tree (resolve `package-lock.json`/migration-order conflicts first — whoever merged first wins, you rebase). **Non-zero → STOP.** Then `compass.sh gc`.
  - **Non-reconciling (library) builds (v0.9.0):** a build with no `RECON-CMD` (library/tooling, no numeric gold) has no merged-recon teeth — so on the merged tree **re-run its test suite** (`compass.sh`'s own `compass.selftest.sh` + `compass.smoke.sh`, or the repo's equivalent) and require green before shipping. The post-merge-check (base-advanced + blast-radius) above is the primary loser-re-check; the merged test-suite green is its reconciliation analogue.

## Procedure
1. **Deploy via the repo's own path** — the deploy/predeploy scripts Phase 0 found; never an ad-hoc deploy. Respect the contract's rollout order + flags.
2. **Post-deploy reconciliation on PROD data** — run the reproducing query against prod (read-only), then `compass.sh reconcile <actual> <gold> <tol>`. **Non-zero = STOP and roll back** via the contract's exact revert path.
   - **PROD-VERIFY IS A HARD STOP (v0.7.0):** if prod is unreachable / the reproducing query can't run, the build **CANNOT be marked SHIPPED** — it stays at CLOSED, you surface the blocker, ship resumes once verifiable. **No `PARTIAL`, no "deferred to <user>", no unchecked prod-verify box.** (This is the exact `pg-method-rates` soft-pass that reached prod.)
   - **Schema builds:** before trusting prod, `compass.sh migration-gate .claude/builds/<slug>` must be PASS (a real migration in the canonical deploy dir reproduces the schema on a fresh DB — STRICT). A schema delivered by `db execute` / hand-apply is a FAIL, not a ship.
3. **Confirm observability EMITS in prod** — the exact metric/log the contract named is actually flowing (query it / tail it), not just present in code.
4. **Smoke the critical flow** — the contract's headline behavior works in prod (read-only asserts; Playwright against prod with env-supplied auth, never a committed token).
   - **Prod route-smoke is a HARD STOP (v0.8.0, when the plan declares `## Affected routes`):** GET **each declared route on prod** (200-with-content, read-only) + a reversible **create→assert→delete** probe for write flows; record one canonical line per route in the ship receipt: `- [x] route <path>: <prod-cmd> → 200 <content-assert> (prod)`. **Prod unreachable / any route not 200 ⇒ the build CANNOT be marked SHIPPED** — it stays CLOSED, you surface the blocker. `lifecycle-audit … SHIPPED` enforces a CHECKED prod route-smoke line per declared route — missing = STOP. (The exact `pg-method-rates` failure was a named-but-never-loaded route reaching prod.)
5. **On any failure → roll back** using the rehearsed path (review-build exercised it on a copy), record what happened.

## Emit
**Terminal-status guard (v0.7.0):** before recording SHIPPED, run `compass.sh lifecycle-audit .claude/builds/<slug> SHIPPED` — **non-zero → STOP** (a stage receipt is missing/soft-passed, or prod-verify is unchecked). Only on PASS write the status.
`progress.md` = `SHIPPED` (or `ROLLED-BACK`). **EMIT RECEIPT**:
```
## RECEIPT — ship · <slug> · PASS
- [x] gate: review-build receipt OK
- [x] deployed via repo path: `<cmd>` → <result>
- [x] prod reconcile: `compass.sh reconcile <actual> <gold> <tol>` → PASS
- [x] observability emits in prod: `<cmd>` → <signal seen>
- [x] critical flow smoke (prod, read-only): <result>
- [x] post-ship loop: <converged round n/cap · waived: <reason> · legacy-N/A> — `compass.sh loop-converged <dir> postship` → <exit>
- [x] observation <facet>: `<capture-cmd>` → evidence/round-1/<file>
```
Self-check: `compass.sh scan-receipt .claude/builds/<slug> ship`.

## §5 — Post-ship critique loop (v0.12.0): SHIPPED is not the finish line
After the Emit receipt passes `lifecycle-audit`, run `compass.sh postship-required <dir>`:
- **N/A / waived** (deploy waived · `post-ship-loop: off — <reason>` · legacy header-less contract) → record `**Status:** SHIPPED` exactly as before. Done.
- **REQUIRED** (header `on (clean N / cap M)` — the v0.12 contract skill writes it for every new shipping build) → the loop below. First, pre-flight: `compass.sh postship-signal <dir>` — **non-zero → `compass.sh fire-g2 <dir> "post-ship: no external verifier"`** (the loop NEVER grades on self-critique alone). Set column-0 `**Status:** post-ship (round 1/cap)`.

**Per round k (in-session — NEVER a headless spawn):**
1. **OBSERVE** into `evidence/round-<k>/`: web → screenshots of the DEPLOYED system at the contract's pinned viewports/states (real PNGs — the gate enforces magic bytes + ≥20KB); pipeline/library → run the contract's `observation-channel:` command; `observe.txt` line 1 = that command in backticks, then ≤50 key lines. Auth via env-vars only — **never a literal token in any receipt or evidence file**. Blocked channel: gated mode may record `HUMAN-OBSERVED: "<verbatim quote>"` inside the round receipt (any line in the block); in `--auto` a blocked channel → fire-g2.
2. **CRITIQUE** — spawn a FRESH in-session subagent whose ONLY inputs are `contract.md` (INVARIANTs, DoD, `post-ship-check:` lines, `CRITIQUE-TARGET:` seeds from intake) and this round's evidence. No builder reasoning, no prior-round transcripts. A Crit/Maj finding COUNTS only when reproduced by a command the main session re-runs (reproduce-to-count); material findings must cite the contract line/INVARIANT violated — uncited findings become FUTURE rows (logged, non-blocking) unless the contract sets `observation: strict-design`.
3. **RECORD** — findings → `| PS-<k>-<j> | R<k> | <SEV> | <where> | <finding · cite=…> | <fix> | OPEN |` rows in review-ledger.md, then append (fresh block AFTER any redeploy — the LAST block governs):
   <!-- TEMPLATE: round-receipt -->
   ```
   ## RECEIPT — post-ship-critique · round <k> · <CLEAN|MATERIAL>
   - [x] LIVE-TARGET: <prod url / system name — never a secret>
   - [x] check: `<command>` → <observed output>
   ```
4. **REGISTER** — `compass.sh loop-round <dir> postship <CLEAN|MATERIAL> --sig $(git rev-parse --short=12 HEAD)` (non-git target → `--sig nogit`). The gate owns every refusal (cap · receipt · evidence · ledger · order · stalls · budget-in-auto). A refusal names its code — fix the cause or fire-g2; never re-word the receipt to slip past.
5. **MATERIAL →** smallest fix → `post-merge-check` → **gated mode: present a 4-option AskUserQuestion menu BEFORE the redeploy (a DISTINCT menu — never the canonical GATE block)** → re-claim ship lock → redeploy via the repo's own path (full Procedure 1-4) → close the PS rows with re-run proof → `ship-release` → fresh ship receipt → next round.
6. **CONVERGED** — `compass.sh loop-converged <dir> postship` exit 0 → write `**Status:** SHIPPED (post-ship CONVERGED n/cap)` (only now does `lifecycle-audit … SHIPPED` pass its G-O1). 
7. **CAP with open findings** — `compass.sh fire-g2 <dir> "post-ship cap: <open PS ids>"` + a 4-option menu: **Accept & ship-as-is** (write the pinned column-0 line into receipts.md:
   <!-- TEMPLATE: user-accepted -->
   `user-accepted: ship-as-is — <PS ids> · <ISO ts>`
   — any PS row opened AFTER it voids the acceptance) / **Keep trying** (one more capped loop — WITHDRAWN once `g2_fires` ≥ 3, the v0.10 rule) / **Re-scope** (Amend) / **Pause**. Never fake done.
`ship-release` still fires on EVERY exit path, including between rounds. If prod reconciliation drifts LATER (a future month), that's a new signal → reopen via `compass:contract` (amend) — the drift guard doesn't end at deploy.

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
