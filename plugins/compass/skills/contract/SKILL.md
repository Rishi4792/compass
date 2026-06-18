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

## 2. Interview (AskUserQuestion) — fill or mark explicit N/A (silent omission = defect)
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
  ```
- **Self-check:** run `compass.sh scan-receipt .claude/builds/<slug> contract` (must exit 0).

## 5. STOP
Standalone: suggest `compass:review-contract` and **STOP — don't invoke it.** Under the orchestrator, hand to the gate. The receipt boxes ARE the done-criteria — if any can't be honestly checked, set status FAIL and fix it first.
