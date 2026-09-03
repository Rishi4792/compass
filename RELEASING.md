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
4. **Scan for anything private BEFORE the merge** — this is a gate, not a reminder:
   ```sh
   bash plugins/compass/scripts/compass.sh secret-scan --tracked     # run at the repo root
   # ...and every line this branch adds. A fresh clone has no local `main`, so name the remote:
   bash plugins/compass/scripts/compass.sh secret-scan --commits origin/main..HEAD
   ```
   Both must exit 0. An absolute home path shipped inside this public plugin across **14 tagged
   releases**, v0.28.0 through v0.33.5, and it was found by a person reading files by hand during a
   release soak. There was no CI, no git hook, and no scan step here. `mechanical-suite.sh` runs the
   first of these two commands as `leak-scan-check`, but the suite is not the release path — this is.
   If it refuses, it prints both routes out. A home-directory name that is not a person — a fixture
   stand-in, a container account, a CI runner, a URL segment — goes in
   `plugins/compass/scripts/fixtures/secrets/allowed-names.txt`, one per line with a comment.
   Anything else takes `# compass-allow-secret: <reason>` on the line itself, at least eight
   characters, and declared exceptions are counted in the summary so they cannot quietly pile up.
   A finding in a COMMITTED patch cannot be cleared either way — fix the file and commit again.
   `secret-corpus-check` scores the scanner against a fixed corpus of real leaks and ordinary code;
   if you find a case it gets wrong, add a LINE to `fixtures/secrets/{leaks,not-leaks}.txt`.
5. **Commit** with a clear message; **merge to `main`**.
6. **Tag + GitHub Release:**
   ```
   git tag vX.Y.Z && git push origin main --tags
   gh release create vX.Y.Z --title "Compass vX.Y.Z" --notes-file <(sed -n '/## \[X.Y.Z\]/,/## \[/p' CHANGELOG.md)
   ```
7. **Marketplace propagation — automatic.** Once Compass is accepted into the Anthropic community marketplace, its CI re-pins to the latest commit on each push and the public catalog syncs nightly. Self-hosted users (`/plugin marketplace add Rishi4792/compass`) get the new version on `/plugin marketplace update compass` (or auto-update if they enabled it). **No manual marketplace step is needed per release** — just push.

## First-time community-marketplace listing (one-time)
Submit the repo once at **https://claude.ai/settings/plugins/submit** (or https://platform.claude.com/plugins/submit). Anthropic runs `claude plugin validate` + a safety screen; on approval it's pinned and auto-bumped thereafter.

## Golden rule
A version bump without a CHANGELOG entry, or a CHANGELOG entry without a version bump, is a broken release. Always do both.
