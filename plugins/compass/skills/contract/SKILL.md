---
name: contract
user-invocable: false
description: Define a build's CONTRACT — the locked spec that becomes the invariant for the whole build. An AskUserQuestion interview that won't finish until every required section for the chosen facets is filled, incl. reconciliation to an independent gold figure and measurable INVARIANTs. Trigger when starting a non-trivial build, or on "define the contract", "compass contract", "spec this out", or the Compass orchestrator.
---

# compass:contract

The contract is the **single source of truth** — the invariant every later step is checked against. A vague contract guarantees drift. Interview until airtight, then write `contract.md`. (Entry point — no prerequisite gate.)

<!-- DOCTRINE:START -->
**Read these before you start.** They are the standards this stage is held to, and they
live in `plugins/compass/shared/` so they are the same for every stage that uses them:

- **`shared/feynman.md`** — the writing standard for the reader-facing copy this stage produces.

(A standard nobody loads is not a standard. `shared/MANIFEST` declares who reads each file and
`doctrine-wired-check.sh` proves it — `feynman.md` sat unread for three releases while its own
first line claimed three stages loaded it.)
<!-- DOCTRINE:END -->

## 1. Folder, index, facets
- **Create the folder with `compass.sh new-build <slug>` — never `mkdir`.** It writes `<dir>/.compass-format`, the stamp that arms `mode-gate` and `redfirst-check`. That stamp is deliberately a file the contract stage cannot author: an earlier design used a `compass-format:` header, the model wrote it, and omitting one line disarmed the gate. A dir made by hand is refused by `contract-gate` at the first seam.
- Then populate `<state-root>/<slug>/` (resolve `<state-root>` via `compass.sh state-root`). Write the slug to `<state-root>/CURRENT` (a non-authoritative hint only — resume disambiguates by worktree, not this file); append to `<state-root>/INDEX`: `<slug> · <goal> · status=draft · facets=<…> · touches=<rough paths, refined by plan>`.
- **Isolation (REQUIRED iff this build may run in PARALLEL and touches DB schema):** declare `isolation.db_provision` and `isolation.db_teardown` shell commands that stand up / tear down a **per-worktree** database (e.g. a fresh Postgres schema, emitting its `DATABASE_URL` into the worktree's `.env.compass`). Without this, `compass.sh check-db-isolation` REFUSES a schema-touching parallel build — concurrent migrations on one shared dev DB corrupt the migration history. Mark **N/A** for single-build or no-schema builds.
- **`schema-touching: yes|no` (REQUIRED, v0.7.0):** a header field declaring whether this build changes DB schema. `yes` → build/review-build/ship run `compass.sh migration-gate` (STRICT: a real migration in the deploy's canonical dir must reproduce the schema on a fresh DB; `db execute`/hand-apply, stray dir, or replay-fail = FAIL). For non-Prisma tools add a `## Migration recipe` block (`canonical_migrations_dir`, `migrate_diff_cmd`, `migrate_deploy_fresh_cmd`). `no` → migration-gate is N/A. Silent omission = the gate refuses to run.
- **`destructive-backfill: yes|no` + `env-keys-referenced: <KEY … | none>` (+ `prod-keys: <KEY …>`) — machine-readable prod-safety signals (v0.15.0, REQUIRED for F-RESTORE/F-PARITY):** the ship stage's `compass.sh restore-point` / `config-parity` HARD STOPs read THESE header fields (not the prose §Rollout/§Security blocks below), so the interview MUST write them. `destructive-backfill: yes` — a row-rewriting/deleting backfill even when `schema-touching: no` — makes `restore-point` demand a confirmed snapshot. `env-keys-referenced:` names the env keys the change newly references; when it is non-`none`, `prod-keys:` names the keys prod declares, and `config-parity` HARD-STOPs on any referenced key prod lacks. Write `destructive-backfill: no` + `env-keys-referenced: none` for the common case — **silent omission leaves both gates with no signal, so they N/A-pass: the exact soft-pass this floor exists to kill.** A NON-destructive value backfill (populates/adds without deleting) is declared `backfill: yes|no`; `backfill: yes` (or `destructive-backfill: yes`) makes `compass.sh backfill-recon-gate` (v0.21) require a recorded `backfill-recon: count + checksum tie-to-source` step before the migration is done.
- **`schema-pin: <field-schema block-ref | N/A — <reason>>` + `perf-budget: <p95/peak-mem/cost literals + SLO ranges | N/A — <reason>>` — machine-readable data/perf pins (v0.21.0, REQUIRED for INV-SCHEMA-PIN / INV-PERFBUDGET):** `compass.sh schema-pin-gate` / `perf-budget-gate` ride the **contract** gate seam and read THESE header lines (guard-first N/A-pass on a missing contract.md or an absent header — legacy contracts stay byte-identical). When `schema-touching: yes`, the contract MUST carry a **filled field-schema block** — a markdown table with columns `name · type · nullable · unit/enum · example` plus an `evolution-rules:` line (web adds `endpoint · method · request · response · status · error-envelope`, or cites an existing OpenAPI/Prisma artifact) — or an explicit `schema-pin: N/A — <reason>` for a non-schema build (the plugin's own contract writes `schema-pin: N/A` since it changes no runtime schema; the gate then bootstraps clean). When Scale is non-trivial, `perf-budget:` MUST pin literal `p95` latency + `peak-mem` + `cost` and attach an SLO healthy-range; a bare `perf-budget: N/A` (no reason) FAILS — write `perf-budget: N/A — <reason>` for a trivial-scale build. Also write `pii: yes|no` (a customer-PII / financial-record surface) and `ci: yes|no` (the repo runs CI): `pii: yes` makes `compass.sh pii-gate` (plan seam) require a `compliance/PII:` plan line, and `ci: yes` makes `compass.sh green-ci-gate` (review-build seam) require a recorded green-CI merge proof — both N/A-pass when the header is `no`/absent.
- **`deploy: out-of-scope — <reason>` (optional):** ship is MANDATORY unless this exact line is present. Without it, a build cannot reach a final state without `compass:ship` (enforced by `lifecycle-audit` + the Stop hook).
- **Project facets (one OR MORE — composable):** `web` · `pipeline` · `library`. A CRM with a data sync is `web + pipeline` → both facets' sections and verify rungs apply. (touches here is a coarse pre-filter; plan rewrites it with the real file list.)
- Optional **budget**: token/time ceiling for the whole build (Compass surfaces "approaching budget" rather than grinding silently).
- **v0.12/v0.13 headers the interview ALWAYS writes (authoring-time defaults — legacy contracts without them stay byte-identical):**
  - `post-ship-loop: on (clean 2 / cap 5)` for every shipping build (opting out requires `post-ship-loop: off — <reason>`); with 0+ `post-ship-check: <cmd>` lines pinning domain checks as commands, and one `observation-channel: <facet> = <capture command / viewport spec / digest cmd>` line naming HOW the live system gets observed (declare blindness HERE — OAuth-gated/air-gapped — not at ship time). Optional `observation: strict-design` makes design drift material without a contract cite.
  - `cold-critic: on` for every web-facet build (2×cold-GO gate at build/review-build; waive only via `cold-critic: off — <reason>`; optional `cold-critic-fallback: human-eyeball` for un-screenshotable apps).
  - **`mode-asked: required` (v0.28.0) — ALWAYS write this header.** It arms `compass.sh mode-gate` on the contract gate seam, which then refuses a receipt whose mode line is missing or not marked `asked=yes`. Legacy contracts have no such header and stay byte-identical (guard-first N/A-pass).
  - `intake: co-construct-v1` when the interview below ran interactively; `intake: classic` when a headless/--auto session had to fall back (an auto session NEVER authors intake.md — F-AUTODEGRADE).
  - **`program: <program-name> · <phase-id>` (v0.22.0, optional)** — write it when this build is one phase of a multi-build **program** (e.g. `program: compass-3-phase · build 7a`). The ship stage's guarded `program-advance` and `go`/`resume`'s next-phase offer read this header; a build with no `program:` line is byte-inert (standalone). Absent = standalone, no ledger interaction.
  - **`adds-test: <yes|no>` (v0.22.0)** — `yes` when the build adds/changes a test; then the build receipt MUST carry a real `red-green:` line (the failing test + why it failed BEFORE the fix) which `compass.sh redgreen-check` requires (empty/placeholder FAILS). `no`/absent is byte-inert. Optional `mutation: <INV-id · file= · break= · red=>` recipe lines let `compass.sh mutation-check` PROVE a guard's test bites.
  - **Durability nits (v0.23.0, template defaults — legacy contracts unaffected):** every contract carries a **`## Glossary`** (domain terms → plain meaning), an **`alternatives-considered:`** line (what else was weighed + why-not — the ADR trace), **`one-way-door:`** labels on irreversible steps (so a reader sees what can't be undone), and a **`RACI:`** owner line (Responsible / Accountable / Consulted / Informed). **Template-presence only — no rejection gate** (a contract missing them is not blocked; the interview just always seeds them so a fresh reader gets the context).

## 2. Interview — the Intake Protocol (co-construct-v1; every decision via AskUserQuestion)
Six phases, recorded live in `<state-root>/<slug>/intake.md` (append-only, column-0 grammar: `MODE:` · `COVERAGE:` · `Q: <question> → A: <answer>` · `GEN <premortem|relax|10x|adjacent>: OPT <possibility> → NOW|LATER|NEVER` · `SCOPE NOW|LATER|NEVER: <item>` · `PHASE <n> DONE · <ts>`). `compass.sh intake-gate` enforces: ordered phases, ≥2 disposed options per generator, **≥1 LATER/NEVER (an all-NOW ledger FAILS — expansion must be real)**, the Phase-4 question budget, ladder count-sync, ≥1 recorded answer. `compass.sh intake-phase` is the resume pointer (status `intake (phase N)` at column 0).

- **Phase 0 — SCAN (zero questions):** read the repo + request; write the `COVERAGE:` line; pre-answer everything the code/request/convention already answers — never spend a question on it. ONE menu: **Full co-construction / Light** (trivial-mechanical; skips Phase 2, Phase-4 cap 2) **/ Pause**. Record `MODE:`.
- **Phase 1 — FRAME (1 call, 2 questions):** WHY menu (recurring pain / new capability / defensive / efficiency) + success-anchor menu (3-4 concrete "this succeeded if …" statements anchored in a specific past event — never "would you use X?"). Record as `Q: … → A: …`.
- **Phase 2 — EXPAND (FULL only; 4 multiSelect menus, one per generator):** GENERATE concrete possibilities the user hasn't considered — they react to menus, never "anything else?": **premortem** ("it shipped and FAILED — the 4 likeliest post-mortems"), **constraint relaxation** ("if <detected limit> weren't a limit…"), **10x** ("the 10x version is…"), **adjacent** ("this almost also gives you … for <adjacent user>"). ≥2 options per generator; ≥1 option per interview explicitly "recommend AGAINST — here's the cost" (anti-yes-bias). Selected → NOW; unselected → LATER. **Premortem items binned NOW become `CRITIQUE-TARGET: <failure>` lines in contract.md — the post-ship critic's seed list.**
- **Phase 3 — CONVERGE (1 call, loops until locked):** print the scope ladder (NOW = walking skeleton / LATER / NEVER→Non-goals) — web facet: the ASCII sketch prints FIRST (§2b renders alongside); menu: **Lock ladder (Recommended) / Promote-demote / Expand more / Pause**. On lock: `SCOPE` lines into intake.md AND a `## Scope ladder` section into contract.md in the same step (the gate count-syncs them).
- **Phase 4 — CLARIFY (≤4 questions FULL / ≤2 LIGHT, hard cap):** only residual gaps the scan couldn't answer, impact×uncertainty-ranked, one per call. Every menu carries a recommended default WITH its reason — EXCEPT questions flagged OPEN-CALL (irreversible / pure product taste), where the recommendation is deliberately withheld. Confirm here (not interrogate): the classic required sections — **Goal & scope · Data derivation · Schema/output shape · Scale · Dependencies (version pins) · Features ("when X → Y") · Acceptance & INVARIANTs · Idempotency/failure/retry · Rollback · Rollout & kill-switch · Security & data-sensitivity · Observability · Non-goals** — plus the facet extras below. Fill or mark explicit N/A (silent omission = defect).
- **Phase 5 — LOCK:** write contract.md v1 (+ `## Scope ladder`; NEVER items → Non-goals; premortem-NOW → CRITIQUE-TARGET lines), then §4's receipt + self-checks.

### 2b. Sketch Loop — render, don't describe (runs inside Phases 1-3)
- **Track:** web → grayscale THROWAWAY wireframe `sketch/mock-v<N>.html` (line 1 EXACTLY `<!-- COMPASS-MOCK slug=<slug> v=<N> throwaway=true -->`, a visible "THROWAWAY WIREFRAME — critique structure, not polish" banner, tokens in one `:root{}` block); non-web → a Mermaid logic map (one node per stage/transform, data-shape edge labels, dashed failure paths, INVARIANTs annotated). web+pipeline → both.
- **Render EARLY** (after the first 1-2 answers — people recognize what they can't specify), re-render per structural decision; **contested decisions render 2-3 labeled alternatives side-by-side THEN ask (options A / B / C / merge)**. Announce the cost every time: "this took ~2 minutes — tear it apart." Each render appends one `sketch/LEDGER` line: `v<N> · <ts> · decision=<id> · alternatives=<…> · picked=<…> · render=artifact|local|file-only · file=<path>`.
- **Delivery ladder:** Artifact URL (same file → same URL, live-updates across the interview) → local `open` → ASCII in-terminal; the LEDGER records which (degradation is visible, never silent).
- **Lock extraction:** web → one final render flips to the pinned house tokens, then the itemized `## Design Spec` + `mockup: sketch/mock-v<N>.html (ACCEPTED v<N>)` line (the mockup IS the binding spec — or, decision 6, a `design-standard: <name>` line, naming a bundled design skill (`rk-house-style` / `cinematic-hero`), remains a valid no-sketch path); non-web → `## Logic Map` with the final Mermaid fence EMBEDDED in contract.md (every edge maps to a "when X → Y" behavior). Explicit escape: `sketch: out-of-scope — <reason>`. `compass.sh sketch-gate` enforces all of it, including the LINE-1 leak tracer: the marker may NEVER appear as line 1 of a tracked product file.
- **F-AUTODEGRADE:** a headless/--auto contract run writes v1 sketch + extraction with `picked=auto · render=file-only`, skips all menus, records `intake: classic`, and never authors intake.md.

### Facet extras (confirmed in Phase 4)
**All facets:** Goal & scope · Data derivation · Schema/output shape · Scale (volume, concurrency) · Dependencies/integrations (incl. version pins) · Features (as behaviors "when X → Y") · Acceptance & accuracy goals (measurable; mark non-negotiables **INVARIANT**) · Idempotency/failure & retry · Rollback (what "revert" means; what must not be lost) · **Rollout & kill-switch** (v0.15.0 — REQUIRED: a flag name or `no flag — <reason>`, its default state, a one-command disable path, and the canary segment; also write the machine-readable `env-keys-referenced`/`prod-keys` + `destructive-backfill` header fields per §1 that `config-parity`/`restore-point` consume) · **Security & data-sensitivity** (v0.15.0 — REQUIRED: per-field classification public/internal/commercial-sensitive/PII + literal never-show fields · a **role×view** allow/deny matrix · a 3-line **STRIDE**-lite; explicit `N/A — <reason>` allowed when there is no sensitive surface) · Observability (the exact metric/log that proves it's correct in prod) · Non-goals (e.g. "docs/changelog out of scope" — state it).

**Reconciliation goal (REQUIRED when the build outputs any number; INVARIANT by default):**
- **Gold figure must be INDEPENDENT** — a *published / audited / human-signed* number (data-room Excel, gold MIS, board figure), pinned as a **literal** in `contract.md`. **It may NOT be computed by the reproducing query** (a query agreeing with itself proves nothing). Name its provenance.
- **Reproducing query/command** to recompute `actual`; note whether it shares logic with the build query (if so, the gate only catches display drift, not query bugs — say so).
- **Tolerance = exact at the figure's displayed precision** (counts → exact 0; currency shown to ₹Cr 1-dp → exact at 0.1 Cr; rates/latency → the stated bound IS the tolerance). A *looser* band than displayed precision needs a written justification + user sign-off.
- **Known bug-class checklist** the reproducing query must pass: no duplicate-stage double-count · no join fan-out multiplication · correct source table.

**`web` also:** Auth model (who logs in, session mechanism, how a test harness authenticates) · UI/UX: exact tokens (colors/type/spacing); flow; empty/loading/error; a11y target (contrast/focus/keyboard); **DESIGN INTENT — required and BINDING.**
- **Design aesthetic — ASK, then bind (v0.14.0).** Every web/dashboard build gets a **high-craft prototype by default.** Ask the user (AskUserQuestion) which aesthetic the UI should take, routing to Compass's **bundled** design skills: **`rk-house-style`** — the enforced product-UI system (dashboards, tables, forms, charts; pinned tokens + 14 component recipes + a neutral default theme + a self-critique gate, with generated visual gold in its `gallery/`) — for the app surfaces; and **`cinematic-hero`** — the cinematic motion + stills system (hero/launch covers, animated wordmarks, social/launch visuals) — for any hero/launch/marketing surface. A dashboard's product surfaces default to **`rk-house-style`**; **`cinematic-hero`** is added when the build also has a hero/launch asset. Record the choice as a **`design-standard: <rk-house-style|cinematic-hero|both>`** header line, then **invoke the chosen bundled skill** (e.g. the `rk-house-style` skill) to load its tokens + recipes and produce the mockup + the itemized `## Design Spec` (the binding ground truth). The bundled skills ship WITH the plugin, so every installer gets this — no external dependency.
- **A mockup is the SPEC, not inspiration.** When a mockup exists (HTML file, screenshot, or image), extract an **itemized Design Spec** into the contract — the **binding** ground truth the build is graded against: exact tokens (colors/type/spacing/radius/shadow), layout structure, every control/affordance, and **every state** (empty/loading/error/overflow/hover/focus). Name the mockup path. review-build holds the live UI to this, brutally, until zero drift.
- **No mockup → name the design standard that serves as the spec** — the bundled **`rk-house-style`** (product UI) or **`cinematic-hero`** (motion/hero), whichever the design-aesthetic step selected; that skill's pinned tokens + recipes ARE the checkable visual ground truth. "Use your judgment" is **rejected** — there must be a checkable visual ground truth, or "no design drift" is unverifiable.
**`pipeline` also:** Input-data contract · Determinism (same input → identical output) · Output schema · Reproducibility.

## 3. Testability + deferred-flag cap
Every requirement needs a concrete check. A "resolve in plan" flag is allowed ONLY for non-INVARIANT, non-acceptance items, naming who/when/how. **Zero deferred flags on INVARIANT/acceptance items.**

## 4. Write + emit
- Write `contract.md` (version it: `v1` + a CHANGELOG section — later **amendments** bump the version and re-lock). Update `progress.md` (stage ① Contract draft).

### Write the artefact-data block (v0.31, INV-DECLARED)

Compass's pages state numbers. Until v0.31 every one of them was worked out by reading hand-written
markdown with ~90 ad-hoc regular expressions, and when that guessing was wrong the page stated the
wrong number with exactly as much confidence as when it was right. A `compass-artefact-data` fence in
this build's state files ends the guessing for the fields it names: the generator states them
verbatim and marks them `declared`, and `compass.sh gold-numbers-gate` cross-checks each one against
the file it describes and FAILS on a disagreement.

**Only declare a field with an EXACT, mechanically checkable source.** A plan checkbox and a bolded
`INV-` id are syntax Compass itself writes, so counting them is not a heuristic. Do NOT declare
`findings.*`: those come from classifying free text in a ledger, which is precisely the guessing this
removed — and a declared number carries no caveat, so a wrong one reads as verified.

A field you do not write is counted by reading and disclosed to the reader as such: a worse but
honest outcome. Write what you actually know, and nothing you do not.

At THIS stage only `invariants.total` has a source yet — there is no plan to count steps from. Append
to `progress.md`:

```compass-artefact-data
{
  "invariants.total": <count of distinct bolded **INV-* ids in contract.md>
}
```

The plan stage adds `steps.total`; the build stage keeps `steps.done` current. Each stage owns the
fields it can actually check.

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
  <!-- TEMPLATE: contract-brief-box -->
  - [x] Contract Brief produced (compass-visual → brief.html + brief.png) and shown; shareable-on-request stated
  - [x] MILESTONE: contract-brief render=brief.html png=<brief.png OR `N/A — <reason>`> artifact=<claude.ai URL OR `N/A — <reason>`>  <!-- v0.26.0 INV-MILESTONE-DELIVERY: HTML body MANDATORY (node, no browser). Write ONE concrete value per key. PNG via `compass.sh render` — a `png=N/A — <reason>` is allowed ONLY after a real failed render attempt. artifact via the Artifact tool — `artifact=N/A — headless (no Artifact tool)` when unavailable. A bare `N/A` (no reason) fails the gate. Then run `compass.sh milestone-gate <dir> contract-brief` (non-zero → STOP). This is delivery, not a file on disk. -->
  <!-- TEMPLATE: mode-choice-box -->
  - [x] explicit lock recorded (button: Lock it, via AskUserQuestion — never a typed phrase)
  - [x] mode choice: asked=yes · answer=<Human-gated|Autonomous> · source=<question|typed-flag>
  <!-- TEMPLATE: security-box -->
  - [x] security block (per-field classification + role×view + STRIDE-lite) filled or explicit N/A — <reason>
  <!-- TEMPLATE: prodsafety-box -->
  - [x] prod-safety signals written: schema-touching / destructive-backfill / env-keys-referenced (+ prod-keys when non-none)
  <!-- TEMPLATE: program-box -->
  - [x] program: <program-name · phase-id | N/A — standalone build> · adds-test: <yes + red-green: evidence | no>
  <!-- TEMPLATE: durability-box -->
  - [x] durability: ## Glossary + alternatives-considered + one-way-door + RACI present (template defaults)
  ```
- **Self-check:** run `compass.sh scan-receipt .claude/builds/<slug> contract` AND `compass.sh intake-gate .claude/builds/<slug>` AND `compass.sh sketch-gate .claude/builds/<slug>` AND `compass.sh mode-gate .claude/builds/<slug>` (each must exit 0).

## 5. STOP
The receipt boxes ARE the done-criteria — if any can't be honestly checked, set status FAIL and fix it first.

## 6. Contract Brief → explicit LOCK → mode choice (at closure, before anything proceeds)
Once the receipt passes, do NOT slide silently into planning. Close the contract deliberately:

1. **Produce the Contract Brief — AND deliver it.** **(v0.30: generate and gate locally, then PUBLISH AS PART OF PRESENTING THE DECISION — never before the user has been asked anything.** Publishing before the first question means opening someone else's repo publishes that repo's model-authored content under your account, unasked. The rail carries the link alongside the buttons.)
   `node skills/compass-visual/gen.mjs <dir> brief --out <dir>/brief.html` → `compass.sh copy-gate <dir>/contract.md` (the reader-copy block, before it is laid out) → `compass.sh artefact-gate <dir>/brief.html --bands --copy --source <dir>/contract.md` (non-zero → STOP; the artefact is wrong, do not show it) → `compass.sh artefact-publish <dir>/brief.html --url <the published URL>` (stores the URL so a republish updates the SAME artefact rather than creating a second one; with no URL and none stored it exits non-zero and names the local file — delivery is never claimed without evidence). A Claude Artifact is now OPTIONAL, not the delivery.
   *(v0.26 text retained below for the shareable/leak-gate rules.)*
1. **Produce the Contract Brief — AND deliver it (v0.26 — delivery, not a file).** Invoke the bundled **`compass-visual`** skill: generate `node skills/compass-visual/gen.mjs <dir> brief --out <dir>/brief.html`, then the **delivery protocol**: (a) **render** `compass.sh render <dir>/brief.html <dir>/brief.png` (a real headless-Chrome screenshot — only write `png=N/A — <reason>` if this genuinely fails); (b) **show the user the PNG inline** (Read it) so they actually SEE what they're locking — the problem→done→proof→moves→guardrails; (c) **publish it via the Artifact tool** so it opens on their laptop AND the Claude Code phone app (a local file path is unreachable on the phone), and put the URL in the receipt's `artifact=`; when the Artifact tool is unavailable (headless), write `artifact=N/A — headless (no Artifact tool)`. **Tell the user a shareable copy exists on request** (`--shareable` redacts the gold + never-show and runs the leak gate) — never hand one off unasked. A Brief written to disk but never shown/published is NOT delivered.
   - **Emit the `brief-data` fence (v0.17.0 — makes the shareable leak-gate CERTAIN for declared values).** When the contract pins a **numeric reconciliation gold** and/or **never-show fields**, write a machine-readable fence into `contract.md`, in its **own trailing block OUTSIDE any `## ` section** (so a later prose scraper never re-reads it), declaring the canonical literal(s):
     ```
     ```compass-brief-data
     gold: <canonical gold literal(s), comma-separated — declare each display form you restate, e.g. `8750000, 87.5 lakh`>
     never-show: <field tokens, comma-separated>
     ```
     ```
     With the fence present, a `--shareable` Brief scrubs each declared value and **every numeric locale reformatting** of it with certainty (undeclared unit/word-spelled forms stay best-effort, honestly labelled). When gold **and** never-show are both **N/A**, emit **no fence** (or `none`) — an N/A build must not hard-error its own Brief.
2. **Require an explicit LOCK — via BUTTONS, never a typed phrase (v0.30 INV-2).** Present **AskUserQuestion** with **Lock it · Revise · Amend · Pause**. Nothing downstream runs until the user picks **Lock it**; until then the contract is `draft` — no plan, no build. On lock, set `progress.md` status to `contract-LOCKED`.
   > The typed lock phrase this replaces sat in front of **both** AskUserQuestion moments — the mode choice below and the 4-button stage gate — so a turn that reached the lock ended on prose and **neither question ever fired**. Measured on real builds: only 2 of 27 contracts had the mode gate armed at all, and both were written by the builds that created the feature. A checkpoint the user cannot answer with a click is a checkpoint that silently does not happen.
3. **The mode choice — ALWAYS ASK, NEVER INFER (AskUserQuestion; v0.28.0 INV-MODE-ASKED).** Ask it in the **same call as the lock, or immediately after** — never behind a render (v0.30). Ask how they want the rest of the lifecycle to run. This question is **mandatory and may NOT be satisfied by any earlier answer** — not by how the build was started, not by a menu choice about something else, not by a default. Record it as `mode choice: asked=yes · answer=<…> · source=question`; a user who explicitly typed `--auto` records `source=typed-flag`. `compass.sh mode-gate` refuses anything else, so an inferred mode cannot leave the contract stage.
   > This exists because it actually happened: in the v0.28.0 build's own session the question was skipped and `Human-gated` was inferred from an unrelated earlier answer, then written to the receipt as if the user had chosen it. That exact string is now a failing test fixture.
   Each option explained:
   - **Auto** — Compass runs the whole assembly line itself and stops for you only at the two real decision points (the contract you just locked, and any gate it can't clear). Fastest; best when you trust the contract.
   - **Human-gated** — Compass pauses at every stage transition for your Approve/Revise/Amend/Pause. Most control; best for high-stakes or exploratory work.
   Record the choice; **Human-gated** proceeds via the per-stage 4-button gate below, **Auto** runs the `--auto` orchestrator loop (two human gates only).

**In `--auto` mode:** the operator's up-front **G1** approval of the contract **is** the lock and the mode choice — do NOT block waiting for a typed "lock it" (that would hang an unattended run). The lock/mode interaction above is the **gated-mode** path; `--auto` records the equivalent via the existing G1 machinery and continues.

<!-- FEYNMAN -->
## In plain words — where we are and what's next
**What just happened.** We turned your idea into a locked, airtight spec — the contract — and rendered it as a one-page **Contract Brief** you can see and lock.
**Why it matters.** Everything after this is checked against the contract. Lock a vague spec and you get drift; lock this one and every later stage has a real target.
**Your options:**
- **Approve & continue** — move to review-contract (an independent pass that tries to break the spec now, while it's cheap).
- **Revise** — re-run the interview with a change you name.
- **Amend** — a real scope change: bump the contract version and re-review just the delta.
- **Pause** — stop cleanly; you resume exactly here, nothing lost.
**My recommendation.** Approve & continue — pressure-test the spec before any code exists.
Progress — ① contract drafted + Brief shown · next: ② review-contract.
<!-- CONFIDENCE -->
**The rigor I'm applying, so you can trust the machine:** "Before we build anything, we lock a spec — and I won't let it lock until it's airtight. I pin the exact fields and what each means, mark the promises that can never break as INVARIANTs, and tie every number to a real published figure we can check against — not a number the code makes up about itself. I pin which fields are sensitive so nothing leaks later, and a one-command off-switch. You see all of this as a one-page brief and you personally lock it — nothing gets built that isn't in that brief."

<!-- GATE:START -->
## Stage transition — the gate (fires on EVERY entry path)

This stage owns its own transition gate. Present it whether this stage was invoked on its own
(the `compass:build` skill) or sequenced by the `compass:start` orchestrator. The orchestrator
does **not** present a second gate — the stage owns it.

1. First print the one-line **transition footer**, in exactly this shape:

   `✓ <this stage> PASSED — <one-line proof>.  Next: <next stage> · run \`/compass:go\`.`

   `<next stage>` is not guessed: `compass.sh next-stage <build-dir>` prints it, and prints nothing
   at all when every stage has passed. (For the terminal `ship` stage, Next is `done — build
   SHIPPED`.)

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
second time. Run `compass.sh next-stage <build-dir>`: it prints the one stage that has not passed
yet, read from the same stage order every gate here uses. Then invoke that stage's skill. The user
has already said yes; the silence after that yes is the stall this gate exists to end.

Name the successor, and name what a person can type. The seven stage skills are hidden from the `/`
menu, so **`/compass:resume`** is the command that reaches the next stage — a `/compass:` name for a
stage is not a command anybody has, and offering one sends the reader to a door that is not there.

On **Revise**, re-run this stage with the change. On **Pause**, stop cleanly. On any detected drift
from `contract.md`, STOP and surface instead of advancing.

*(Until v0.35 this paragraph forbade invoking the next skill at all. It told the reader what would
NOT happen and never what would, so an approved stage ended in silence and the build waited for a
human to remember the next command. The old sentence is not quoted here, because the check that
proves it is gone greps for it — a note about a banned string that contains the banned string keeps
the defect alive in the file that fixed it. The gate still ASKS. What changed is that an answer of
Approve is now acted on rather than described.)*
<!-- GATE:END -->
