# Changelog

All notable changes to Compass are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

## [0.7.1] — 2026-06-18

Fixed — the `deploy: out-of-scope` waiver detection (in `lifecycle-audit` and `stop-guard`) was an **unanchored** grep, so it matched the phrase anywhere in the contract — including prose that merely *describes* the waiver. That let the "ship is mandatory" guarantee be bypassed by a contract that only mentions the phrase. Now anchored to a real field line (`^[-* ]*deploy: out-of-scope`); prose/backtick mentions no longer count. Self-test gains an INV-5 prose-only case (18 assertions). Caught by v0.7.0's own ship audit printing a false "deploy waived" — dogfooding worked.

## [0.7.0] — 2026-06-18

Two failure modes promoted from prose to executable gates ("prose drifts, gates don't"). Born from a real prod outage: a Compass-built feature (`pg-method-rates`) hand-applied a schema change to the dev DB via `prisma db execute` — no migration ever landed in the deploy's canonical folder — and ship was marked SHIPPED with prod-verify left unchecked. The lifecycle showed all green while prod broke.

- **Migration-delivery gate (`compass.sh migration-gate`)** — for `schema-touching: yes` builds: a real migration must exist in the deploy's **canonical** dir (Prisma: `prisma/schema/migrations` when `prisma/schema/` exists, else `prisma/migrations`), `db execute`/hand-apply can't substitute, a **stray migration in a non-canonical dir is caught** (the exact incident class), and a **fresh-DB apply must reproduce the schema (STRICT — no waiver)**. Wired as a hard gate into build, review-build, and ship.
- **Ship prod-verify is a HARD STOP** — unreachable prod = the build stays CLOSED, never `PARTIAL`/"deferred"/SHIPPED-with-an-unchecked-box.
- **Lifecycle enforced every time, always** — `compass.sh lifecycle-audit` (full-chain receipt + terminal-status guard, wired into `close`/ship) + a new **`Stop` hook** (`compass.sh stop-guard`) that blocks the agent from going quiet, skipping a gate, or forgetting ship while a build is mid-lifecycle (honors `stop_hook_active` to avoid deadlock). **Ship is now mandatory** unless the contract carries `deploy: out-of-scope — <reason>`. `close --abandon` cancels an incomplete build.
- Reproduction self-test `compass.selftest.sh` (INV-1..INV-7) encodes both real failures and proves the new gates catch them. Built with Compass itself; its review caught the Stop-hook deadlock risk, the `close`-traps-abandon regression, and a private-data-in-fixtures leak before build.

## [0.6.0] — 2026-06-17

Elegant parallel builds. Worktrees move out of sight, and parallel builds on one repo become visible and merge-aware. Born from a real mess — three confusingly-similar sibling folders (`GQ Business CRM`, `GQ Business CRM.compass/`, `GQ-Business-CRM-obs`) next to the project, plus un-GC'd worktrees and hand-rolled ones. Built with Compass itself; the reviews caught two that would have re-created the mess (the pre-commit guard silently breaking, and `close` deleting uncommitted work — the v0.5.0 incident).

### Added
- **Centralized worktree home.** Build worktrees now live in `~/.compass/worktrees/<project-id>/<slug>` (project-id = `<basename>-<cksum>`, collision-safe), out of the project's parent — so you only ever see the project folder next to your other projects, never a `.compass` or `-obs` sibling. Overridable via `COMPASS_WORKTREE_HOME`. State stays in-project (`.claude/builds/`).
- **`compass.sh builds`** — a live table of every in-flight build on the repo (slug · status · branch · worktree). `/compass:status` shows it when more than one build is active.
- **`compass.sh post-merge-check <slug>`** — the merge-consequence gate. When a sibling merges first, this checks the build against **`origin/<base>` (after fetch — never local `main`)**: is the base advanced? did the merge touch this build's claimed files (blast radius)? If so it STOPs and requires integrating the new base + re-verifying — **flagged during build, a hard block before ship.** Never auto-rebases (conflicts need human eyes). The base SHA is recorded at worktree creation as the diff anchor.
- **`compass.sh doctor [--migrate]`** — audits every worktree (managed vs stray, status, dirty, merged), sweeps clean terminals, and `--migrate` relocates clean ad-hoc siblings into the home via `git worktree move`. **Never touches dirty/unmerged — only flags them.**

### Changed
- **Dirty-safe removal everywhere (the v0.5.0 incident fix).** `gc` and `close` now use one shared **non-force** remove — a worktree with uncommitted work is LEFT in place and flagged, never force-deleted. (v0.5.0's `close` force-removed a dirty worktree and lost 55 files; that can't happen now.) `gc` also prunes orphans and scans the centralized home.
- **Worktree identity by branch, not path.** `cwd_slug` (used by the pre-commit guard, resume, and assert-worktree, via the new `compass.sh cwd-slug`) derives the slug from the `compass/<slug>` branch — location-independent, so the contamination guard keeps working after worktrees move. **Always create worktrees via `compass.sh worktree` — never hand-roll `git worktree add`.**

**Why:** parallel builds were technically isolated but operationally messy — siblings cluttered the project's parent, GC missed shipped worktrees, and a first-merge could silently invalidate the others. v0.6.0 makes the worktrees invisible, the parallel builds identifiable, and a merge's consequences a hard gate. Smoke: 28 → 40 assertions, including the merge gate against a real bare remote and the dirty-safe close.

## [0.5.0] — 2026-06-16

Design fidelity becomes a brutal, non-negotiable gate, and post-build verification stops being ceremonial. The most important behavioral change since inception: it redefines what "verified" and "done" mean. Built with Compass itself (contract → review → plan → review → build → review → ship); the reviews caught the ceremonial trap twice before it shipped (see below).

### Added
- **The mockup is the SPEC, not inspiration.** When a mockup exists, the contract now extracts an **itemized, binding Design Spec** (exact tokens, layout, every control, every state). No mockup → the contract must name a design standard (e.g. Stripe-level `frontend-design`); "use your judgment" is rejected. This is the only way to make "no drift" verifiable.
- **A brutal, non-negotiable design-fidelity gate** in review-build (and per-step in build): render the built UI vs the mockup at every viewport + state, log each difference to a `design-ledger.md`, and **loop until zero open rows — one drift = FAIL.** The bar is **identical** whether the mockup is an HTML file or a flat image; only the technique differs (HTML adds `design-style-diff` token checks + computed-CSS; an image uses disciplined element-by-element side-by-side reading).
- **Real script teeth (not prose):** four new deterministic `compass.sh` subcommands — `design-drift-gate` (blocks while any drift row is open; a design-scoped build with a missing/empty ledger FAILS — review-not-done ≠ clean), `converge-gate` (won't pass unless BOTH the correctness and design ledgers are clean), `design-style-diff` (a real token diff over real artifacts), and `status` (the where-am-I surface). Covered by new smoke assertions, including a **catch-the-drift fixture** that proves the gate FLAGS a real drift and PASSES the faithful build (both directions, non-circular).
- **`/compass:status`** — prints build · stage · step k/n · last passed receipt · the single next action + command, on demand.

### Changed
- **Post-build verify is no longer ceremonial.** review-build now **independently renders the live product on real/representative data** and adversarially reads the actual values + pixels — it does **not** re-run the build's own checks. Every check must be **falsifiable** (able to fail if broken); tautological or screenshot-only "looks right" checks are deleted, not counted. Convergence requires `converge-gate` (both ledgers clean), not just "no new findings."
- **Clean stage transitions + elegant hand-off.** Every stage ends with a one-line footer (what passed ✓ · next stage · exact command) — Compass never goes quiet mid-build. When a new terminal is needed, it prints exactly one clean, copy-paste-ready block (`cd "<root>" && claude`), nothing interleaved.

**Why:** real builds shipped correct-but-ugly UIs and "all-green but reader-useless" pages because every hard review checked logic and safety while design fidelity was a soft, one-shot screenshot eyeball — and post-build verify mostly re-ran the build's own checks. v0.5.0 makes design a first-class, looping, evidence-backed gate and forces verify to look at the live thing on real data. Fittingly, building it with Compass surfaced the same failure mode twice (invariants asserted by grepping prose; a missing ledger counting as "pass") — both caught and closed by the contract and plan reviews before any code shipped.

## [0.4.0] — 2026-06-09

Parallel builds, learned from running two Compass builds at once on a live CRM (one of them overnight, unattended). The two shared one working directory, so one build's `git add -A` swept in the other's files and a manual de-commingle was needed at the end. This release makes N builds in one repo safe — and the design was hardened by an 8-stream adversarial review (73 raw → 22 findings, all folded in) before any code was written.

### Added
- **One git worktree per build (the keystone).** Each parallel build gets its own working folder + branch backed by the same `.git`, so no two builds share a checkout. State stays canonical in the *main* checkout's `.claude/builds` and is reached from any worktree via the new `compass.sh state-root` (no symlink, no migration). Single-build runs are unchanged.
- **The teeth, extended.** New `compass.sh` subcommands, all deterministic and exit-coded: `state-root`, `active-builds`, `worktree`, `promote`, `worktree-rm`, `assert-worktree`, `claim`, `check-overlap`, `check-db-isolation`, `install-guard`, `audit-staged`, `merged-recon`, `gc`. Covered by a committed smoke test (`compass.smoke.sh`, 16 assertions) that runs in a path with spaces and parentheses.
- **A single slug-agnostic pre-commit guard** that blocks any staged file outside the active build's claimed file list — inside a worktree it enforces that build's claim; from the main checkout it refuses to commit any in-flight build's claimed file. This is what actually stops the `git add -A` contamination, including on unattended overnight runs.
- **Enforced cross-build overlap.** `claim` (file-level, expanded via `git ls-files` in the worktree) + `check-overlap` turn the old prose "coordinate additively" warning into a hard gate; shared files surface as an explicit, acknowledged overlap rather than a silent clobber. Builds claim `package-lock.json` and their migration dir so lockfile/migration conflicts surface early, not at merge.
- **DB-isolation gate.** Worktrees isolate files, not the database — so a contract may declare `isolation.db_provision`/`db_teardown` (a per-worktree `DATABASE_URL`), and `check-db-isolation` REFUSES a schema-touching parallel build that has no isolation (concurrent migrations on one dev DB corrupt it).
- **Post-merge reconciliation gate.** `merged-recon` re-runs both builds' recorded `RECON-CMD` on the *merged* tree before the second ships — two independently-green branches don't prove the union is green.

### Changed
- **Resume no longer trusts the global `CURRENT`.** It derives the build from the worktree (cwd/branch) and, in the main checkout, refuses to guess when more than one build is active — the exact ambiguity that resumed the wrong build before. `CURRENT` is demoted to a non-authoritative hint.
- **Build, ship, contract, start** skills now wire the gates above (worktree assertion, overlap/DB checks at build start, scoped commits with no `git add -A` / `--no-verify`, the merge gate in ship, the isolation block in contract).

**Why:** the parallel run shipped both features, but the shared checkout cost a manual cleanup and the riskiest moment was the unattended run committing with `git add -A`. The adversarial review found the naive "just use worktrees" design left DB corruption, lockfile merges, and a bypassable guard unsolved; v0.4.0 closes those before turn-on.

## [0.3.0] — 2026-06-08

Two improvements learned from the first real end-to-end run (a production feature on a live CRM, where the reviews caught a self-introduced IDOR and a shipped-incomplete data-redaction fix).

### Changed
- **A fix is treated as new code and re-attacked before convergence.** review-build now requires the final clean round to be a genuine *verify-the-fixes* round: any round that applied a fix is not clean by definition, and the independent **Security/RBAC, Secret-leak, and Verification-audit agents re-spawn on every fix diff — regardless of which group the fix belonged to**. A "functional" fix routinely opens a security hole (e.g. a pagination fix that introduces an IDOR); this no longer depends on the user asking for an extra round.
- **Coverage, not sample — fixes are checked against canonical definitions.** When a fix is defined relative to a canonical set (sensitive/commercial fields, roles, allowed values, redaction targets), review-build now requires the implementation to be **driven by the canonical source itself**, not a hand-maintained copy/regex that can drift, and the test to exercise the **full set**, not a hand-picked sample. A duplicated canonical set is a Major finding.

**Why:** on the first real run, a Round-4 fix passed its own test but had silently drifted from the canonical field list, leaving commercial data visible — caught only because a manual verify round was added. These changes make that catch automatic.

## [0.2.0] — 2026-06-07

### Added
- **Zero-drift-from-imagined-design as a first-class verification.** The contract now *requires* capturing the **design intent** for web builds (a mockup/screenshot path, reference URL, or precise described visual). At build and in review-build, the live UI is **screenshotted and read back against that captured intent**, naming any drift from what was imagined (layout, hierarchy, spacing, feel).

### Changed
- **The verify layer now uses two complementary UI checks instead of banning screenshots.** *Exact things* (a number, a hex, a spacing value) are still proven by exact assertions (DOM text / computed CSS) — never a screenshot. *Design-intent fidelity* is now proven by a **screenshot read-back vs the captured design**, because the gestalt "does it match what we imagined" is a judgment an exact assertion cannot make. Both are required for web builds.

**Why:** a feature should ship with zero drift from what was conceptualized during planning — including the design. Computed-CSS assertions catch a wrong token but cannot catch "this doesn't look like what we pictured." That holistic match needs a visual eyeball, anchored to a design intent captured up front.

## [0.1.0] — 2026-06-07

First public release. A contract-first build lifecycle for Claude Code, hardened over three independent adversarial review rounds.

### Added
- **Seven-stage lifecycle:** `contract → review-contract → plan → review-plan → build → review-build → ship`, with user-driven gates (Approve / Revise / Amend contract / Pause / Show) between every hop and a required human sign-off before close.
- **The contract as the invariant** — every later stage is checked against the locked spec; any deviation stops and asks.
- **Real enforcement, not prose** (`scripts/compass.sh`): a deterministic gate that exits non-zero when the prior stage's receipt is absent, FAIL, has an unchecked box, or was superseded. Reconciliation and secret-scan are deterministic `PASS/FAIL` gates that block close. Escalation supersedes downstream receipts so re-reviews actually re-run.
- **Reconciliation to an independent gold figure** — the target must be a published/audited number, never the build's own query agreeing with itself; runs duplicate/fan-out/source-table bug-class checks.
- **Verify ladder** — cheapest real proof first, by project facet (`web` / `pipeline` / `library`, composable). Asserts DOM text + computed CSS for UI; prod stays read-only; Playwright over Chrome MCP (no cross-project lock).
- **Adversarial reviews** that fan out as ~6 agents, converge on recorded evidence (one clean pass for the light review, two consecutive clean rounds for the full reviews), and escalate up a level when stuck instead of faking done.
- **File-based, resumable state** in `.claude/builds/<slug>/` with clean cross-session handoff (`/compass:resume`).

### Notes
- Built and pressure-tested via three rounds of independent adversarial review (26 + 17 + 16 findings, all resolved), then a token-efficiency pass. See `docs/REVIEW-FINDINGS.md`.

[0.1.0]: https://github.com/Rishi4792/compass/releases/tag/v0.1.0
