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
   A finding in a COMMITTED patch cannot be cleared either way — fix the file and commit again, or,
   when the finding is a false alarm now frozen into history, name that ONE line in
   `fixtures/secrets/cleared-history.txt` by its path and the SHA-256 of the line, with a reason and a
   signer. One character different and the finding stands; every use is printed in the summary. It
   exists because the rule that is right for a real secret — deleting it next commit does not un-leak
   it — makes a false alarm permanent, and a check that can never pass is one somebody switches off.
   `secret-corpus-check` scores the scanner against a fixed corpus of real leaks and ordinary code;
   if you find a case it gets wrong, add a LINE to `fixtures/secrets/{leaks,not-leaks}.txt`.

   **Then check the commit MESSAGES**, which the scans above never look at:
   ```sh
   bash plugins/compass/scripts/session-trailer-check.sh origin/main..HEAD
   ```
   Assistant session links reached **150 commit messages, 132 of them already on public `main`**,
   before anyone looked. They are disclosed in `SECURITY.md` rather than rewritten, because a
   published history is published and rewriting the unmerged remainder would have changed every
   commit sha this release pinned its measurements to. This check fails on any commit written on or
   after the policy date that carries one, so it cannot start again quietly.
5. **Check the speed bound** — it is a release step, not a suite check, because it runs the whole
   test suite several times over:
   ```sh
   bash plugins/compass/scripts/perf-cap-check.sh .          # clones itself and times a clean tree
   ```
   Exit 0 is inside the bound. The bound lives in `plugins/compass/scripts/perf-ceiling.txt`, which
   is tracked so a fresh clone can read it, and in the current build's contract, which is the
   authority that sets it. If those two disagree the check refuses rather than picking one.
   **Never raise the bound to fit a change.** If a release is over it, either make it faster or say
   so in the CHANGELOG with the measurement — a limit moved to accommodate the thing it limits is
   not a limit.
6. **Commit** with a clear message; **merge to `main`**.
7. **Tag + GitHub Release:**
   ```
   git tag vX.Y.Z && git push origin main --tags
   gh release create vX.Y.Z --title "Compass vX.Y.Z" --notes-file <(sed -n '/## \[X.Y.Z\]/,/## \[/p' CHANGELOG.md)
   ```
8. **Marketplace propagation — automatic.** Once Compass is accepted into the Anthropic community marketplace, its CI re-pins to the latest commit on each push and the public catalog syncs nightly. Self-hosted users (`/plugin marketplace add Rishi4792/compass`) get the new version on `/plugin marketplace update compass` (or auto-update if they enabled it). **No manual marketplace step is needed per release** — just push.

## First-time community-marketplace listing (one-time)
Submit the repo once at **https://claude.ai/settings/plugins/submit** (or https://platform.claude.com/plugins/submit). Anthropic runs `claude plugin validate` + a safety screen; on approval it's pinned and auto-bumped thereafter.

## Golden rule
A version bump without a CHANGELOG entry, or a CHANGELOG entry without a version bump, is a broken release. Always do both.
