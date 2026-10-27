---
name: deploy
user-invocable: false
description: The Deploy stage: safety checks, rehearsed undo, gate 4, release, live measurement, release note.
---

# compass:deploy

Ship what was built and prove it did what the page says. Nothing touches production before gate 4. Never ask the person about git.

## 1. Commit, then the safety checks (nothing live yet)
Commit the product yourself. Add `.claude/builds/` to `.gitignore` if it is missing, then `git add -A` and `git commit -m "<title>: ready to go live"` (skip the commit when nothing changed). Then from the repo root run `node "${CLAUDE_PLUGIN_ROOT}/scripts/compass" preflight <dir> --record [--env-from="<command that lists the target's keys>"] [--data-restore="<when the plan changes data: a path that exists, or a command that succeeds>"] [--health=<url>]`. A `•` line stops you: fix it, run again. `--record` writes the receipt itself; the record refuses a typed one.

## 2. Rehearse the undo
Follow §12 on a copy or a throwaway branch: release, undo, confirm the state is back. If §12 cannot be followed as written, fix it first. For a product with no switch (a script, a plugin, a file), the undo is pinning the previous version; run that command on the copy. Record `receipt <dir> deploy rehearsal "ran: <commands> → <observed>"`.

## 3. Gate 4: one plain question
First `gates <dir> --run --record`; anything red or a promise with no check stops you here. Re-render and publish the card. Record `receipt <dir> deploy "gate 4" "[ ] ask: The safety checks passed and I practised switching it back. Make <title> live for real users now? · Go live (Recommended) → I release it the way this project always releases, a few users first where possible · Not yet → nothing goes live until you type /compass again"`, with "Make <title> live now?" when the page's `for:` names one person. Ask exactly that. On Go live: `receipt <dir> deploy "gate 4" "answered: go live" "decision: <title> goes live"`, then release at once (§4); until then the line reads "Going live · next: I release it". On Not yet, stop.

## 4. Release, the repo's own way
Use the path the plan's §3 found; never an ad-hoc copy. Follow §11: behind the switch, off first; a few users first where the repo supports it. Release by recording it: `receipt <dir> deploy released "<release command> → <expected output>"`; the record runs the command itself and refuses the receipt unless the output holds the expected text. Then prove the kill switch: turn it off without releasing again, confirm it is dark, turn it on; a product with no switch reruns the pin command from the rehearsal. Record `receipt <dir> deploy "switch proven" "ran: <commands> → <observed>"`, adding `all at once, because <reason>` when a few users first was not possible. If the release made a commit, run `gates <dir> --run --record` again before §6.

## 5. Smoke the critical flow on production
Walk Part 1 as the person would, read-only. If it fails, undo with §12 now and record `deploy rolled back` with the reason.

## 6. Measure every promise on the live system
`writeback <dir> --target=<the web address, or the folder where it now runs; `local` when it runs on this machine> --watch-until=<YYYY-MM-DD, today + 7 days>`. It runs each promise's own command (with the URL in `COMPASS_TARGET` when the target is a web address), counts every check born from a break, and records `live <value> ✓|✗` or `not measured` per promise. Publish the page. A ✗ stays visible. After the watch date, run `writeback <dir> --target=<same target> --close-watch` (no date): all ✓ closes the watch and the line reads "Done"; a ✗ reopens that part through `compass:amend`.

## 7. Release note and the last line
`release-note <dir>` refuses unless §19 holds a runbook; it writes `release-note.md` in plain words with each promise ✓ or ✗ live, the set-aside items, the Never list, the watch date and the runbook. Publish it with the Artifact tool and put its link on the card: `receipt <dir> deploy "release note" "decision: the release note and how to start it: <link>"`; re-render and publish the card. Say one line: "<title> is live. Open it: <the address>. <n> of <m> promises show their live number. Type /compass after <date> and I check again." With no web address: "<title> is ready on this machine. How to start it: <release note link>. Type /compass after <date> and I check again." Then stop.

## 8. After a change: the line contains "Rebuilt"
Run §1 again, then `gates <dir> --run --record`; anything red stops you. Record `receipt <dir> deploy "gate 4" "[ ] ask: Release the change? · Release (Recommended) → it goes live and I measure again · Not yet → nothing changes"` and ask exactly that. On Release: `receipt <dir> deploy "gate 4" "answered: release" "decision: the change goes live"`; the line reads "Going live · next: I release it", so release at once: §4 records a new `released`, which `writeback` (§6) needs, then §5 to §7. On Not yet, stop.

## Never
- Never release before gate 4; never ask gate 4 before the checks and the rehearsal pass.
- Never type a live value; only `writeback` measures.
- Never fix on production. Undo, fix, release again.
