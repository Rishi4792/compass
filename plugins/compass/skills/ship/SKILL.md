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

## Step 0.6 — prod-safety pre-flight (v0.15.0, F-RESTORE / F-PARITY — UNCONDITIONAL HARD STOP)
Run **all three**, always, **before the first deploy action** — never operator-skippable; an N/A is *invoked and recorded as an N/A-pass*, not skipped:
- **`compass.sh restore-point <slug>`** — HARD STOP before any destructive migration/backfill: requires a confirmed, COMPLETE snapshot (snapshot-id + timestamp + restore command) whenever the contract declares `schema-touching: yes` or `destructive-backfill: yes`; N/A-passes (recorded) when nothing destructive is declared. **Non-zero → STOP, take the snapshot, re-run.**
- **`compass.sh config-parity <slug>`** — HARD STOP if the change references a prod env key prod lacks (diffs the contract's `env-keys-referenced:` vs `prod-keys:`); N/A-passes when no new keys are referenced. **Non-zero → STOP, provision the key in prod, re-run.**
- **`compass.sh rollback-fwdcompat-gate <slug>`** (v0.21, INV-ROLLBACK-FWDCOMPAT) — a schema/data-changing ship must RECORD `rollback data-safety: old-code reads new-version writes → OK` (run the OLD read path against NEW-version writes on the deploy's OWN copy/branch DB, then record it); N/A-passes when no schema/data change is declared. **Non-zero → STOP, run + record the forward-compat check, re-run.** This is a discipline record — review-build re-challenges it, it is never independent proof.
Record `restore-point: exit N`, `config-parity: exit N`, and `rollback-fwdcompat: exit N` into the ship receipt (the `prodsafety-box`). `compass.sh ship-prodsafety-receipt-match <dir>` verifies the restore-point + config-parity lines are present — a silent skip fails the suite, so the HARD STOPs cannot be bypassed.

## Step 0.7 — cutover safety net (v0.16.0, survive-the-cutover — HARD STOP, N/A recorded not skipped)
Run **all three**, always, **after prod-safety and before the terminal SHIPPED write** — each is invoked-and-recorded (an N/A is an *N/A-pass*, never a skip); the config lives in the contract (`canary:` / `bake-window:` / `bake-bound:` / `watcher:`), the readings in this ship receipt.
- **`compass.sh canary-analysis <slug>`** — promote a slice only on INDEPENDENT green (canary reconcile + route-smoke; gold-cmd ≠ slice-cmd, external). No traffic split → records `SUBSTITUTED-BAKE` (which REQUIRES a `bake-window:`). A recorded **burn-rate `BREACH` auto-fires the rehearsed rollback** (Procedure step 7 — no human wait) and REFUSES promotion. Byte-inert (N/A) if the contract declares no `canary:`.
- **`compass.sh bake-gate <slug>`** — the required soak before SHIPPED; asserts error/latency/memory stayed within the **declared** `bake-bound:` (an absent ceiling OR reading is NEVER in-bound — esp. memory), or, for a LIBRARY bound, re-runs the observation-channel green. **When canary returned SUBSTITUTED-BAKE, bake-gate MUST return `IN-BOUND` (not N/A)** — a no-traffic-split cutover cannot ship without a real bake. Write a `bake-observed: dur=<s> err=<v> lat=<v> mem=<v>` line first.
- **`compass.sh watcher-check <slug>`** — a NAMED watcher + window, OR (in `--auto`) a **proven-armed** rollback (`rollback-rehearsed: <cmd> → exit 0`, not a bare `armed`). Neither → HARD STOP.
Record the results in the **cutover-box** below, then **`compass.sh ship-cutover-receipt-match <dir>`** — verifies all three lines are present AND (for a `deploy: in scope` build) that they are not ALL N/A without an explicit `cutover: waived — <reason>` — so a real deploy can never fail-OPEN by omitting cutover config. **Non-zero → STOP.**

**Own-ship dispositions (Compass releasing itself — no traffic split):** `canary: none — no traffic split` → `SUBSTITUTED-BAKE`; `burn-rate` N/A; `bake-gate` is the ACTIVE gate in **LIBRARY** mode — its `bake-bound:` names the suites, so bake-gate re-runs `selftest+smoke+recon` green (a fresh-clone-of-tag soak); `watcher:` = the operator at the push gate. The **fixtures** (`fixtures/{canary,bake,watcher,cutover-receipt}/`) carry the end-to-end managed-build proof.

## Procedure
1. **Deploy via the repo's own path** — the deploy/predeploy scripts Phase 0 found; never an ad-hoc deploy. Respect the contract's rollout order + flags.
2. **Post-deploy reconciliation on PROD data** — run the reproducing query against prod (read-only), then `compass.sh reconcile <actual> <gold> <tol>`. **Non-zero = STOP and roll back** via the contract's exact revert path.
   - **PROD-VERIFY IS A HARD STOP (v0.7.0):** if prod is unreachable / the reproducing query can't run, the build **CANNOT be marked SHIPPED** — it stays at CLOSED, you surface the blocker, ship resumes once verifiable. **No `PARTIAL`, no "deferred to <user>", no unchecked prod-verify box.** (This is the exact `pg-method-rates` soft-pass that reached prod.)
   - **Schema builds:** before trusting prod, `compass.sh migration-gate .claude/builds/<slug>` must be PASS (a real migration in the canonical deploy dir reproduces the schema on a fresh DB — STRICT). A schema delivered by `db execute` / hand-apply is a FAIL, not a ship.
3. **Confirm observability EMITS in prod** — the exact metric/log the contract named is actually flowing (query it / tail it), not just present in code.
4. **Smoke the critical flow** — the contract's headline behavior works in prod (read-only asserts; Playwright against prod with env-supplied auth, never a committed token).
   - **Prod route-smoke is a HARD STOP (v0.8.0, when the plan declares `## Affected routes`):** GET **each declared route on prod** (200-with-content, read-only) + a reversible **create→assert→delete** probe for write flows; record one canonical line per route in the ship receipt: `- [x] route <path>: <prod-cmd> → 200 <content-assert> (prod)`. **Prod unreachable / any route not 200 ⇒ the build CANNOT be marked SHIPPED** — it stays CLOSED, you surface the blocker. `lifecycle-audit … SHIPPED` enforces a CHECKED prod route-smoke line per declared route — missing = STOP. (The exact `pg-method-rates` failure was a named-but-never-loaded route reaching prod.)
5. **Kill-switch proof (v0.15.0, F-FLAG)** — confirm the feature flag disables the feature **without a redeploy**: flip the declared flag OFF in prod (config / flag service — no new deploy), assert the feature is dark, flip it back; record it. (Contract `no flag — <reason>` waives this.)
6. **Secret-scan the release patch (v0.15.0)** — once the release commit exists, `compass.sh secret-scan --commits <prev-tag>..HEAD` → 0 hits, so the actual committed patch is proven clean (review-build scans the pre-commit working tree; this covers anything the release commit itself introduces). **Any hit → STOP, scrub, re-commit before push.**
7. **On any failure → roll back** using the rehearsed path (review-build exercised it on a copy): pre-push `git reset --hard <prev-tag> && git clean -fd`; post-push `git revert <prev-tag>..<ship-HEAD>` — then `git status --porcelain` empty + suites at floors. Record what happened. **(v0.16.0) A burn-rate BREACH at Step 0.7 auto-fires THIS exact path with no human wait** — the cutover net's automatic halt, not a new rollback.

## Emit
**Terminal-status guard (v0.7.0, re-ordered v0.13.0):** FIRST run `compass.sh postship-required <dir>`. **N/A / waived** → run `compass.sh lifecycle-audit .claude/builds/<slug> SHIPPED` — **non-zero → STOP** — and only on PASS write SHIPPED (exactly the pre-v0.12 flow). **REQUIRED** → do NOT attempt `lifecycle-audit … SHIPPED` yet (G-O1 correctly fails with zero rounds — that is not a broken chain, it is the loop demanding to run): emit the ship receipt, set `**Status:** post-ship (round 1/cap)`, and enter §5; `lifecycle-audit … SHIPPED` runs only after `loop-converged` exits 0, and only then is SHIPPED written.
**EMIT the ship receipt** (both paths emit it — the deploy happened):
```
## RECEIPT — ship · <slug> · PASS
- [x] gate: review-build receipt OK
<!-- TEMPLATE: prodsafety-box -->
- [x] restore-point: exit <N>   (`compass.sh restore-point <slug>` — pre-deploy HARD STOP / N/A-pass)
- [x] config-parity: exit <N>   (`compass.sh config-parity <slug>` — pre-deploy HARD STOP / N/A-pass)
- [x] rollback-fwdcompat: exit <N>   (`compass.sh rollback-fwdcompat-gate <slug>` — old-code-reads-new-writes RECORDED / N/A-pass; re-challenged by review-build)
<!-- TEMPLATE: cutover-box -->
- [x] canary: exit <N> · CANARY: <PASS|SUBSTITUTED-BAKE|N/A>   (`compass.sh canary-analysis <slug>` — a burn-rate BREACH auto-fires the rehearsed rollback)
- [x] bake: exit <N> · BAKE: <IN-BOUND|N/A>   (`compass.sh bake-gate <slug>` — when canary=SUBSTITUTED-BAKE this MUST be IN-BOUND, never N/A)
- [x] watcher: exit <N> · WATCHER: <NAMED|AUTO-ARMED|N/A>   (`compass.sh watcher-check <slug>` — named owner, or a proven-armed rollback in --auto)
- [x] cutover-receipt-match: `compass.sh ship-cutover-receipt-match <dir>` → 0
- [x] kill-switch: flag OFF disables the feature WITHOUT a redeploy (or `no flag — <reason>`)
- [x] deployed via repo path: `<cmd>` → <result>
- [x] release-patch secret-scan: `compass.sh secret-scan --commits <prev-tag>..HEAD` → 0 hits
- [x] prod reconcile: `compass.sh reconcile <actual> <gold> <tol>` → PASS
- [x] observability emits in prod: `<cmd>` → <signal seen>
- [x] critical flow smoke (prod, read-only): <result>
- [x] post-ship loop: <open (round 1/cap — §5 in progress) · converged round n/cap · waived: <reason> · legacy-N/A> — `compass.sh loop-converged <dir> postship` → <exit>
<!-- TEMPLATE: observation-box -->
- [x] observation <facet>: `<capture-cmd>` → evidence/round-1/<file>
```
Self-check: `compass.sh scan-receipt .claude/builds/<slug> ship`.

**Then set the terminal status — by branch (NEVER write SHIPPED unconditionally):**
- **N/A / waived path:** run `compass.sh lifecycle-audit .claude/builds/<slug> SHIPPED` — **non-zero → STOP** — and only on PASS write `progress.md` = `**Status:** SHIPPED` (or `ROLLED-BACK` on a rollback). Done — no §5. (The post-ship loop box reads `waived: <reason>` or `legacy-N/A`.)
- **REQUIRED path:** do NOT run `lifecycle-audit … SHIPPED` yet and do NOT write SHIPPED — write `progress.md` = `**Status:** post-ship (round 1/cap)` (the receipt's post-ship box reads `open (round 1/cap — §5 in progress)`), then enter §5. SHIPPED is written only at §5.6, after `loop-converged` passes AND `lifecycle-audit … SHIPPED` re-runs clean.

## §5 — Post-ship critique loop (v0.12.0): SHIPPED is not the finish line
(Entered from §Emit when `postship-required` said REQUIRED — the Emit receipt exists; the SHIPPED audit deliberately has NOT run yet.) Recap of the policy:
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
6. **CONVERGED** — `compass.sh loop-converged <dir> postship` exit 0 → update the ship receipt's post-ship box to `converged round n/cap` → run `compass.sh lifecycle-audit .claude/builds/<slug> SHIPPED` — **non-zero → STOP** (fix the named gap, re-audit) — and **only on PASS** write `progress.md` = `**Status:** SHIPPED (post-ship CONVERGED n/cap)`. Audit BEFORE the terminal write, never after. 
7. **CAP with open findings** — `compass.sh fire-g2 <dir> "post-ship cap: <open PS ids>"` + a 4-option menu: **Accept & ship-as-is** (write the pinned column-0 line into receipts.md:
   <!-- TEMPLATE: user-accepted -->
   `user-accepted: ship-as-is — <PS ids> · <ISO ts>`
   — any PS row opened AFTER it voids the acceptance) / **Keep trying** (one more capped loop — WITHDRAWN once `g2_fires` ≥ 3, the v0.10 rule) / **Re-scope** (Amend) / **Pause**. Never fake done.
`ship-release` still fires on EVERY exit path, including between rounds. If prod reconciliation drifts LATER (a future month), that's a new signal → reopen via `compass:contract` (amend) — the drift guard doesn't end at deploy.

<!-- FEYNMAN -->
## In plain words — where we are and what's next
**What just happened.** I deployed safely, not just deployed: took a restore point, confirmed prod has every setting the new code needs, re-ran the reconciliation against real prod data, and confirmed the monitoring signal emits.
**Why it matters.** A deploy that isn't proven in prod isn't done. There's a one-flip kill switch that disables the change without a redeploy if we ever need it off.
**Your options:**
- **Approve & continue** — mark the build SHIPPED (the prod checks passed).
- **Revise** — re-run ship with a change you name.
- **Amend** — a real scope change: bump the contract and re-review just the delta.
- **Pause** — stop cleanly; you resume exactly here, nothing lost.
**My recommendation.** Approve — the prod checks passed.
Progress — ⑦ ship: deployed + proven in prod · done — build SHIPPED.
<!-- CONFIDENCE -->
**The rigor I'm applying, so you can trust the machine:** "Deploying safely, not just deploying. First I take a restore point and confirm the prod environment has every setting the new code needs. I re-run the reconciliation against real prod data, confirm the monitoring signal emits, and there's a one-flip kill switch if we need it off — no redeploy required."

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
