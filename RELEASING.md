# Releasing Compass

How every update reaches users on GitHub and the Claude community marketplace. Follow this each time.

## Versioning
[SemVer](https://semver.org/): `MAJOR.MINOR.PATCH`.
- **PATCH** — wording/bug fixes, no behavior change.
- **MINOR** — new skills/checks/options, backward-compatible.
- **MAJOR** — a change that breaks existing builds (renamed commands, changed receipt/gate format, removed stages).

## Release checklist (run for every update)
1. **Make the change** on a branch; validate: `claude plugin validate ./plugins/compass`.
2. **Bump the version** in BOTH:
   - `plugins/compass/.claude-plugin/plugin.json` → `version`
   - `.claude-plugin/marketplace.json` → `metadata.version`
3. **Add a CHANGELOG.md entry** under a new `## [x.y.z] — YYYY-MM-DD` heading — say **what changed and why** (Added / Changed / Fixed / Removed). This is the user-facing "what's new."
4. **Commit** with a clear message; **merge to `main`**.
5. **Tag + GitHub Release:**
   ```
   git tag vX.Y.Z && git push origin main --tags
   gh release create vX.Y.Z --title "Compass vX.Y.Z" --notes-file <(sed -n '/## \[X.Y.Z\]/,/## \[/p' CHANGELOG.md)
   ```
6. **Marketplace propagation — automatic.** Once Compass is accepted into the Anthropic community marketplace, its CI re-pins to the latest commit on each push and the public catalog syncs nightly. Self-hosted users (`/plugin marketplace add Rishi4792/compass`) get the new version on `/plugin marketplace update compass` (or auto-update if they enabled it). **No manual marketplace step is needed per release** — just push.

## First-time community-marketplace listing (one-time)
Submit the repo once at **https://claude.ai/settings/plugins/submit** (or https://platform.claude.com/plugins/submit). Anthropic runs `claude plugin validate` + a safety screen; on approval it's pinned and auto-bumped thereafter.

## Golden rule
A version bump without a CHANGELOG entry, or a CHANGELOG entry without a version bump, is a broken release. Always do both.
