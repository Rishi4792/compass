---
description: Show where a Compass build stands — current stage, step k/n, last passed receipt, and the single next action + command. The "where am I / what's next" surface.
---

# /compass:status

Print, at a glance, where the current Compass build is and what to do next — so a long build never leaves you wondering.

## Procedure
1. Resolve the build (same identity rule as `/compass:resume`): inside a build's worktree → that slug; else `compass.sh active-builds` (1 → it; >1 → list and ask which; 0 → "no active build"). Resolve state via `compass.sh state-root`.
2. Run `compass.sh status "<state-root>/<slug>"` — it reads `progress.md` + `plan.md` + `receipts.md` and prints: **Status · Stage · Steps k/n · Last ✓ (last PASS receipt) · Next** (the single next action + its exact command).
   - **If `compass.sh active-builds` shows more than one in-flight build, ALSO run `compass.sh builds`** — the live table of every parallel build on this repo (slug · stage · branch · worktree). That's how you see what else is running before you act, and remember: if one merges, the others must pass `compass.sh post-merge-check <slug>` before they ship.
3. Print that block verbatim, then add one plain-English line on what the next action does. Do not recite the files.

## Note
Read-only. If `.claude/builds/` won't resolve, the user is not at the project root (where `.claude/` lives) — say so and ask for the root.

## v0.12.0 additions
- `Post-ship: round k/cap · consecutive-clean j/N · open PS m` — rendered when `loop.log` exists (the post-ship critique loop's live position; bounds parsed from the contract's `post-ship-loop:` header).
- `auto: SUSPENDED (driver)` — rendered when `.auto-suspended` exists (an interactive driver suspended the self-spawn via `compass.sh auto-suspend`; budget metering stays armed; `auto-resume` re-arms).
