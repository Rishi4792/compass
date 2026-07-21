---
name: contract
description: Define a build's CONTRACT — the locked spec that becomes the invariant for the whole build. An AskUserQuestion interview that won't finish until every required section for the chosen facets is filled, incl. reconciliation to an independent gold figure and measurable INVARIANTs. Trigger when starting a non-trivial build, or on "define the contract", "compass contract", "spec this out", or the Compass orchestrator.
---

# compass:contract

The contract is the **single source of truth** — the invariant every later step is checked against. A vague contract guarantees drift. Interview until airtight, then write `contract.md`. (Entry point — no prerequisite gate.)

## 1. Folder, index, facets
- Create `<state-root>/<slug>/` (resolve `<state-root>` via `compass.sh state-root`). Write the slug to `<state-root>/CURRENT` (a non-authoritative hint only — resume disambiguates by worktree, not this file); append to `<state-root>/INDEX`: `<slug> · <goal> · status=draft · facets=<…> · touches=<rough paths, refined by plan>`.
- **Isolation (REQUIRED iff this build may run in PARALLEL and touches DB schema):** declare `isolation.db_provision` and `isolation.db_teardown` shell commands that stand up / tear down a **per-worktree** database (e.g. a fresh Postgres schema, emitting its `DATABASE_URL` into the worktree's `.env.compass`). Without this, `compass.sh check-db-isolation` REFUSES a schema-touching parallel build — concurrent migrations on one shared dev DB corrupt the migration history. Mark **N/A** for single-build or no-schema builds.
- **`schema-touching: yes|no` (REQUIRED, v0.7.0):** a header field declaring whether this build changes DB schema. `yes` → build/review-build/ship run `compass.sh migration-gate` (STRICT: a real migration in the deploy's canonical dir must reproduce the schema on a fresh DB; `db execute`/hand-apply, stray dir, or replay-fail = FAIL). For non-Prisma tools add a `## Migration recipe` block (`canonical_migrations_dir`, `migrate_diff_cmd`, `migrate_deploy_fresh_cmd`). `no` → migration-gate is N/A. Silent omission = the gate refuses to run.
- **`deploy: out-of-scope — <reason>` (optional):** ship is MANDATORY unless this exact line is present. Without it, a build cannot reach a final state without `compass:ship` (enforced by `lifecycle-audit` + the Stop hook).
- **Project facets (one OR MORE — composable):** `web` · `pipeline` · `library`. A CRM with a data sync is `web + pipeline` → both facets' sections and verify rungs apply. (touches here is a coarse pre-filter; plan rewrites it with the real file list.)
- Optional **budget**: token/time ceiling for the whole build (Compass surfaces "approaching budget" rather than grinding silently).
- **v0.12/v0.13 headers the interview ALWAYS writes (authoring-time defaults — legacy contracts without them stay byte-identical):**
  - `post-ship-loop: on (clean 2 / cap 5)` for every shipping build (opting out requires `post-ship-loop: off — <reason>`); with 0+ `post-ship-check: <cmd>` lines pinning domain checks as commands, and one `observation-channel: <facet> = <capture command / viewport spec / digest cmd>` line naming HOW the live system gets observed (declare blindness HERE — OAuth-gated/air-gapped — not at ship time). Optional `observation: strict-design` makes design drift material without a contract cite.
  - `cold-critic: on` for every web-facet build (2×cold-GO gate at build/review-build; waive only via `cold-critic: off — <reason>`; optional `cold-critic-fallback: human-eyeball` for un-screenshotable apps).
  - `intake: co-construct-v1` when the interview below ran interactively; `intake: classic` when a headless/--auto session had to fall back (an auto session NEVER authors intake.md — F-AUTODEGRADE).

## 2. Interview — the Intake Protocol (co-construct-v1; every decision via AskUserQuestion)
Six phases, recorded live in `<state-root>/<slug>/intake.md` (append-only, column-0 grammar: `MODE:` · `COVERAGE:` · `Q: <question> → A: <answer>` · `GEN <premortem|relax|10x|adjacent>: OPT <possibility> → NOW|LATER|NEVER` · `SCOPE NOW|LATER|NEVER: <item>` · `PHASE <n> DONE · <ts>`). `compass.sh intake-gate` enforces: ordered phases, ≥2 disposed options per generator, **≥1 LATER/NEVER (an all-NOW ledger FAILS — expansion must be real)**, the Phase-4 question budget, ladder count-sync, ≥1 recorded answer. `compass.sh intake-phase` is the resume pointer (status `intake (phase N)` at column 0).

- **Phase 0 — SCAN (zero questions):** read the repo + request; write the `COVERAGE:` line; pre-answer everything the code/request/convention already answers — never spend a question on it. ONE menu: **Full co-construction / Light** (trivial-mechanical; skips Phase 2, Phase-4 cap 2) **/ Pause**. Record `MODE:`.
- **Phase 1 — FRAME (1 call, 2 questions):** WHY menu (recurring pain / new capability / defensive / efficiency) + success-anchor menu (3-4 concrete "this succeeded if …" statements anchored in a specific past event — never "would you use X?"). Record as `Q: … → A: …`.
- **Phase 2 — EXPAND (FULL only; 4 multiSelect menus, one per generator):** GENERATE concrete possibilities the user hasn't considered — they react to menus, never "anything else?": **premortem** ("it shipped and FAILED — the 4 likeliest post-mortems"), **constraint relaxation** ("if <detected limit> weren't a limit…"), **10x** ("the 10x version is…"), **adjacent** ("this almost also gives you … for <adjacent user>"). ≥2 options per generator; ≥1 option per interview explicitly "recommend AGAINST — here's the cost" (anti-yes-bias). Selected → NOW; unselected → LATER. **Premortem items binned NOW become `CRITIQUE-TARGET: <failure>` lines in contract.md — the post-ship critic's seed list.**
- **Phase 3 — CONVERGE (1 call, loops until locked):** print the scope ladder (NOW = walking skeleton / LATER / NEVER→Non-goals) — web facet: the ASCII sketch prints FIRST (§2b renders alongside); menu: **Lock ladder (Recommended) / Promote-demote / Expand more / Pause**. On lock: `SCOPE` lines into intake.md AND a `## Scope ladder` section into contract.md in the same step (the gate count-syncs them).
- **Phase 4 — CLARIFY (≤4 questions FULL / ≤2 LIGHT, hard cap):** only residual gaps the scan couldn't answer, impact×uncertainty-ranked, one per call. Every menu carries a recommended default WITH its reason — EXCEPT questions flagged OPEN-CALL (irreversible / pure product taste), where the recommendation is deliberately withheld. Confirm here (not interrogate): the classic required sections — **Goal & scope · Data derivation · Schema/output shape · Scale · Dependencies (version pins) · Features ("when X → Y") · Acceptance & INVARIANTs · Idempotency/failure/retry · Rollback · Observability · Non-goals** — plus the facet extras below. Fill or mark explicit N/A (silent omission = defect).
- **Phase 5 — LOCK:** write contract.md v1 (+ `## Scope ladder`; NEVER items → Non-goals; premortem-NOW → CRITIQUE-TARGET lines), then §4's receipt + self-checks.

### 2b. Sketch Loop — render, don't describe (runs inside Phases 1-3)
- **Track:** web → grayscale THROWAWAY wireframe `sketch/mock-v<N>.html` (line 1 EXACTLY `<!-- COMPASS-MOCK slug=<slug> v=<N> throwaway=true -->`, a visible "THROWAWAY WIREFRAME — critique structure, not polish" banner, tokens in one `:root{}` block); non-web → a Mermaid logic map (one node per stage/transform, data-shape edge labels, dashed failure paths, INVARIANTs annotated). web+pipeline → both.
- **Render EARLY** (after the first 1-2 answers — people recognize what they can't specify), re-render per structural decision; **contested decisions render 2-3 labeled alternatives side-by-side THEN ask (options A / B / C / merge)**. Announce the cost every time: "this took ~2 minutes — tear it apart." Each render appends one `sketch/LEDGER` line: `v<N> · <ts> · decision=<id> · alternatives=<…> · picked=<…> · render=artifact|local|file-only · file=<path>`.
- **Delivery ladder:** Artifact URL (same file → same URL, live-updates across the interview) → local `open` → ASCII in-terminal; the LEDGER records which (degradation is visible, never silent).
- **Lock extraction:** web → one final render flips to the pinned house tokens, then the itemized `## Design Spec` + `mockup: sketch/mock-v<N>.html (ACCEPTED v<N>)` line (the mockup IS the binding spec — or, decision 6, a `design-standard: <name>` line remains a valid no-sketch path); non-web → `## Logic Map` with the final Mermaid fence EMBEDDED in contract.md (every edge maps to a "when X → Y" behavior). Explicit escape: `sketch: out-of-scope — <reason>`. `compass.sh sketch-gate` enforces all of it, including the LINE-1 leak tracer: the marker may NEVER appear as line 1 of a tracked product file.
- **F-AUTODEGRADE:** a headless/--auto contract run writes v1 sketch + extraction with `picked=auto · render=file-only`, skips all menus, records `intake: classic`, and never authors intake.md.

### Facet extras (confirmed in Phase 4)
**All facets:** Goal & scope · Data derivation · Schema/output shape · Scale (volume, concurrency) · Dependencies/integrations (incl. version pins) · Features (as behaviors "when X → Y") · Acceptance & accuracy goals (measurable; mark non-negotiables **INVARIANT**) · Idempotency/failure & retry · Rollback (what "revert" means; what must not be lost) · Observability (the exact metric/log that proves it's correct in prod) · Non-goals (e.g. "docs/changelog out of scope" — state it).

**Reconciliation goal (REQUIRED when the build outputs any number; INVARIANT by default):**
- **Gold figure must be INDEPENDENT** — a *published / audited / human-signed* number (data-room Excel, gold MIS, board figure), pinned as a **literal** in `contract.md`. **It may NOT be computed by the reproducing query** (a query agreeing with itself proves nothing). Name its provenance.
- **Reproducing query/command** to recompute `actual`; note whether it shares logic with the build query (if so, the gate only catches display drift, not query bugs — say so).
- **Tolerance = exact at the figure's displayed precision** (counts → exact 0; currency shown to ₹Cr 1-dp → exact at 0.1 Cr; rates/latency → the stated bound IS the tolerance). A *looser* band than displayed precision needs a written justification + user sign-off.
- **Known bug-class checklist** the reproducing query must pass: no duplicate-stage double-count · no join fan-out multiplication · correct source table.

**`web` also:** Auth model (who logs in, session mechanism, how a test harness authenticates) · UI/UX: exact tokens (colors/type/spacing); flow; empty/loading/error; a11y target (contrast/focus/keyboard); **DESIGN INTENT — required and BINDING.**
- **A mockup is the SPEC, not inspiration.** When a mockup exists (HTML file, screenshot, or image), extract an **itemized Design Spec** into the contract — the **binding** ground truth the build is graded against: exact tokens (colors/type/spacing/radius/shadow), layout structure, every control/affordance, and **every state** (empty/loading/error/overflow/hover/focus). Name the mockup path. review-build holds the live UI to this, brutally, until zero drift.
- **No mockup → name the design standard that serves as the spec** (e.g. the `frontend-design` Stripe-level standard, or `apple-frontend-design`). "Use your judgment" is **rejected** — there must be a checkable visual ground truth, or "no design drift" is unverifiable.
**`pipeline` also:** Input-data contract · Determinism (same input → identical output) · Output schema · Reproducibility.

## 3. Testability + deferred-flag cap
Every requirement needs a concrete check. A "resolve in plan" flag is allowed ONLY for non-INVARIANT, non-acceptance items, naming who/when/how. **Zero deferred flags on INVARIANT/acceptance items.**

## 4. Write + emit
- Write `contract.md` (version it: `v1` + a CHANGELOG section — later **amendments** bump the version and re-lock). Update `progress.md` (stage ① Contract draft).
- **EMIT RECEIPT** to `receipts.md` — fill each box with what you actually did:
  ```
  ## RECEIPT — contract · <slug> · PASS
  - [x] facets: <web|pipeline|library …>
  - [x] all required sections for those facets filled or explicit N/A
  - [x] reconciliation: gold=<literal> provenance=<published artifact, NOT self-computed>; tol=<displayed precision>
  - [x] no deferred flag on any INVARIANT/acceptance item
  - [x] CURRENT + INDEX + progress.md written
  <!-- TEMPLATE: postship-box -->
  - [x] post-ship-loop: <on (clean N / cap M)|off — reason>
  <!-- TEMPLATE: intake-box -->
  - [x] intake-gate: compass.sh intake-gate <dir> → 0
  <!-- TEMPLATE: sketch-box -->
  - [x] sketch-gate: compass.sh sketch-gate <dir> → 0
  ```
- **Self-check:** run `compass.sh scan-receipt .claude/builds/<slug> contract` AND `compass.sh intake-gate .claude/builds/<slug>` AND `compass.sh sketch-gate .claude/builds/<slug>` (each must exit 0).

## 5. STOP
The receipt boxes ARE the done-criteria — if any can't be honestly checked, set status FAIL and fix it first.

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
