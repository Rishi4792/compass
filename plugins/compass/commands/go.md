---
description: The Compass front door — one command that reads where your build is and asks what to do next, then routes you into the right stage (contract, plan, review, build, ship, or resume). The simplest way to use Compass.
tier: primary
---

# /compass:go — the front door

**This is the single entry point for Compass.** You don't need to remember the stage commands — `/compass:go` reads the current state and asks you where to go, every time.

<!-- WELCOME:START -->
The orientation block is **rendered by a script, not written here** — `compass.sh orient`. It picks the right block from your actual state: the mental model when nothing is in flight, a where-you-are block when a build is running. A `UserPromptSubmit` hook prints it before this command even starts, so you see it with zero typing.

**This file deliberately contains no copy of that text.** From v0.15.0 to v0.27.0 the welcome lived here as prose with a "print it" instruction nowhere, and its only tests grepped this file for the words — so it passed for twelve versions while printing **0 times in 30 real `/compass:go` invocations**. One renderer, one source, behaviour-tested (INV-ONE-RENDERER, INV-ORIENT-DELIVERED).
<!-- WELCOME:END -->

## What to do when invoked

0. **Orientation first (INV-ORIENT).** The hook normally paints it already. If it did not (hook disabled, `COMPASS_QUIET`, an older install), run **`compass.sh orient`** and show its output before anything else. Never retype the block from memory — one renderer, three doors.

1. **Read the build state** (never guess it):
   - `compass.sh state-root` → the `.claude/builds` dir.
   - `.claude/builds/CURRENT` → the last-active slug hint · `.claude/builds/INDEX` → every build (`slug · goal · status · facets · touches`) · the active build's `.claude/builds/<slug>/progress.md` → the authoritative status + Stage + Next.
   - `compass.sh builds` (or `active-builds`) → the in-flight (non-terminal) builds.

   - **PUSH the cockpit immediately (INV-PUSH-RESUME).** As soon as an in-flight build is identified, run `compass.sh cockpit <state-root>/<slug>` and show it FIRST — the two-altitude view (program phases + contracts, if any, above the current build's stage + step k/n + next) — so a returning user (incl. a fresh terminal) sees exactly where they are with **zero further typing**, before any menu.

2. **ALWAYS ask the user what to do next** — present an **AskUserQuestion** menu of the possible next steps (this command NEVER auto-advances or auto-picks). Tailor the options to the state:
   - **In-flight build(s) exist** → lead with **Resume `<slug>`** (Stage `<stage>`, Next `<next action>` from its `progress.md`), then offer starting something new.
   - **Options to present** (choose the 2–4 that fit): **Resume** the in-flight build · **New build → contract** · **I have a spec → plan** · **Adversarial review** (pick review-contract / review-plan / review-build by the current stage) · **Ship** · **Show status**. The auto-provided **Other** covers anything else.

3. **Route** — invoke the **Skill** for the chosen stage (`compass:contract`, `compass:plan`, `compass:review-contract` / `compass:review-plan` / `compass:review-build`, `compass:build`, `compass:ship`, or the `compass:start` orchestrator for a full new-build run). For **Resume** or **Show status**, run the `/compass:resume` / `/compass:status` command. That stage owns its own logic and its own transition gate; **this router adds no second gate of its own.**

## Edge states (handle explicitly)
- **Starting a multi-build PROGRAM:** `.claude/builds/PROGRAM.md` is written by **`compass.sh program-init <program-name>`** — nothing else creates it. Until v0.30 the file had two readers (`program-ledger`, `program-next`) and no reachable writer, so the whole program feature was unreachable unless someone guessed the subcommand name. When the user describes work spanning several builds, run `program-init` first, then start the first phase's contract with a `program:` header.
- **No in-flight build (empty state):** if `.claude/builds/PROGRAM.md` exists, FIRST run `compass.sh program-ledger <program>` to **surface any staleness/structural FLAG before trusting the ledger** (M15 — warn, don't silently offer a later phase), then `compass.sh program-next <program>`; if it yields a next phase, lead with **Continue the program → next phase (`<next-slug>`)?** (offer only — a FLAGGED ledger warns instead). Otherwise the menu leads with **New build → contract**; there is nothing to resume.
- **Multiple in-flight builds:** list them by `slug · status` from the INDEX so the user picks which one to resume (CURRENT is only a hint and cannot disambiguate parallel builds).
- **A chosen downstream stage whose Step-0 gate isn't satisfied** (e.g. the user picks "build" but no plan is LOCKED): route to that stage anyway — its OWN `compass.sh gate` will surface the block and offer the prior stage. The router NEVER fakes readiness or skips a gate.

## Note
The `/` menu shows just three doors — `/compass:go`, `/compass:status`, `/compass:resume`. All the stage logic lives in skills that Compass invokes **for** you (`compass:contract`, `compass:plan`, `compass:build`, `compass:ship`, the reviews, and the `compass:start` orchestrator); they're hidden from the menu (`user-invocable: false`) so you never have to remember which one — `/compass:go` reads your state and routes into the right one.
