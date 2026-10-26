---
name: deploy
user-invocable: false
description: The Deploy stage. Pre-flight, rehearsal, one question before production, then deploy, write the live numbers back onto the Idea page, a plain release note, and a watch period with an end date.
---

# compass:deploy

Ship what was built and prove it did what the Idea page says. Nothing touches production before gate 4.

## 1. Pre-flight (nothing deployed yet)
`node "${CLAUDE_PLUGIN_ROOT}/scripts/compass" preflight <dir>` from the repo root. It takes a restore point (a git tag you can reset to), checks every config key declared in `.env.example` exists here, and scans tracked files for secrets. Any line marked `•` stops you: fix it, run again. Record `scripts/compass receipt <dir> deploy preflight "<each line>"`.

## 2. Rehearse the undo
Follow the plan's §12 on a copy or a throwaway branch: deploy, then undo, then confirm the state is back to before. If §12 cannot be followed as written, fix §12 first. Record `deploy rehearsal` with what you ran.

## 3. Gate 4: one question
Re-render and publish the card. Ask with AskUserQuestion: "Pre-flight passed and the undo is rehearsed. Deploy <title> to production now?" Options: **Deploy now (Recommended)** · Not yet. On Not yet: "Paused before production. Type /compass to continue." and stop.

## 4. Deploy, the repo's own way
Use the deploy path the plan's §3 found: its script, its pipeline, its command. Never an ad-hoc copy. Follow §11: behind the switch, off first; a few users first where the repo supports it, then everyone; if it does not, record `all at once, because <reason>`. Prove the kill switch: turn the feature off without a redeploy, confirm it is dark, turn it on; record it. If the product has no switch (a script, a plugin, a file), the switch is the previous version: record how to pin it.

## 5. Smoke the critical flow on production
Walk the Idea page's part 1 as the person would, read-only. If it fails, undo with §12 now and record `deploy rolled back` with the reason. Do not debug on production.

## 6. Write the live numbers back
Measure each promise's number against the live system the way its check does. Then:
`scripts/compass writeback <dir> P1.1="<value> ✓" P1.2="<value> ✗" … --watch-until=<today + 7 days>`
It records the receipt and re-renders the Idea page with a live badge beside every promise. Publish the page (same file, same URL). A ✗ is not hidden; it stays on the page and the card.

## 7. Release note and watch
`scripts/compass release-note <dir>` writes `release-note.md` in plain words, under 200 words, from the promises, the live numbers, the leftovers and the Never list. Publish or send it where the plan's §11 says. Re-render the card; it now shows the watch end date. Say one line: "<title> is live. <n> of <m> promises show their live number. Watch until <date>." Then stop. The next `/compass` after the end date re-measures the numbers; a ✗ reopens that part through `compass:amend`.

## Never
- Never deploy before gate 4, and never ask gate 4 before pre-flight and the rehearsal pass.
- Never mark a promise ✓ you did not measure on the live system.
- Never fix on production. Undo, then fix, then deploy again.
