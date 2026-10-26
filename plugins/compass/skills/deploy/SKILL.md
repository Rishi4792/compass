---
name: deploy
user-invocable: false
description: The Deploy stage. Safety checks, a rehearsed undo, one plain question before anything goes live, the release through the repo's own path, every promise measured on the live system by the script, a plain release note with the runbook, and a watch period that re-measures.
---

# compass:deploy

Ship what was built and prove it did what the page says. Nothing touches production before gate 4.

## 1. Safety checks (nothing deployed yet)
`node "${CLAUDE_PLUGIN_ROOT}/scripts/compass" preflight <dir> --record [--env-from="<command that lists the target's keys>"] [--data-restore="<where the data copy is>"] [--health=<url>]` from the repo root. It checks declared config keys on the target (or says plainly it could only check this machine), asks for a data restore point when the plan changes data (a path that exists, or a command that succeeds), checks a health address if given, scans for secrets, and only when all of that passes takes a restore point and verifies the tag exists. A `•` line stops you: fix it, run again. `--record` writes the receipt itself; the record refuses a typed one.

## 2. Rehearse the undo
Follow §12 of the plan on a copy or a throwaway branch: deploy, undo, confirm the state is back to before. If §12 cannot be followed as written, fix §12 first. For a product with no switch (a script, a plugin, a file), the undo is pinning the previous version: run that exact command on the copy. Record `receipt <dir> deploy rehearsal "ran: <commands> → <observed>"`.

## 3. Gate 4: one plain question
First `gates <dir> --run --record`; anything red or a promise with no check stops you here. Re-render and publish the card. Record `receipt <dir> deploy "gate 4" "[ ] ask: Make <title> live for real users now?"`. Ask: "The safety checks passed and I practised switching it back. Make <title> live for real users now?" Options: **Go live (Recommended)** → "I release it the way this project always releases, a few users first where that is possible" · Not yet → "Nothing goes live until you type /compass again". Record a second `gate 4` receipt with `answered:` and `decision:`; only an answer that is not "not yet" opens the release. On Not yet, stop.

## 4. Release, the repo's own way
Use the path §3 found; never an ad-hoc copy. Follow §11: behind the switch, off first; a few users first where the repo supports it, else record `all at once, because <reason>`. Prove the kill switch: turn it off without a redeploy, confirm dark, turn it on; for a switchless product record the pin command and its observed output from the rehearsal. Then `receipt <dir> deploy released "<release command> → <output>" "switch: <proved how>"`.

## 5. Smoke the critical flow on production
Walk Part 1 as the person would, read-only. If it fails, undo with §12 now and record `deploy rolled back` with the reason. Do not debug on production.

## 6. Measure every promise on the live system
`writeback <dir> --target=<production folder, or a URL> --watch-until=<YYYY-MM-DD, today + 7 days>`. It runs each promise's own command (from the project root, with the URL in `COMPASS_TARGET` when the target is a web address), counts every check born from a break against its promise, records `live <value> ✓|✗` per promise or `not measured` when a promise has no runnable check, and re-renders the Idea page with a badge beside every promise. It takes no values from you. Publish the page. A ✗ stays visible. After the watch date, run it again with `--close-watch` and no date: all ✓ closes the watch and the line reads "Live · done"; a ✗ reopens that part.

## 7. Release note and watch
`release-note <dir>` refuses unless §19 holds a runbook; it writes `release-note.md` in plain words with the live numbers, the set-aside items, the Never list, the watch date and the runbook. Publish it where §11 says. Re-render the card. Say one line: "<title> is live. Open it: <the target address, or the runbook's first line for a product with no address>. <n> of <m> promises show their live number. I check again on <date>." Then stop. After the watch date the door runs §6 again; a ✗ reopens that part through `compass:amend`.

## Never
- Never release before gate 4; never ask gate 4 before the checks and the rehearsal pass.
- Never type a live value; only `writeback` measures.
- Never fix on production. Undo, fix, release again.
