# Changelog

All notable changes to Compass are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

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
