# Changelog

All notable changes to Compass are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

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
