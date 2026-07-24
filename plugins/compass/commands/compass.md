---
description: The Compass front door — one command that reads where your build is and asks what to do next, then routes you into the right stage (contract, plan, review, build, ship, or resume). The simplest way to use Compass.
---

# /compass — the front door

**This is the single entry point for Compass.** You don't need to remember the stage commands — `/compass` reads the current state and asks you where to go, every time.

## What to do when invoked

1. **Read the build state** (never guess it):
   - `compass.sh state-root` → the `.claude/builds` dir.
   - `.claude/builds/CURRENT` → the last-active slug hint · `.claude/builds/INDEX` → every build (`slug · goal · status · facets · touches`) · the active build's `.claude/builds/<slug>/progress.md` → the authoritative status + Stage + Next.
   - `compass.sh builds` (or `active-builds`) → the in-flight (non-terminal) builds.

2. **ALWAYS ask the user what to do next** — present an **AskUserQuestion** menu of the possible next steps (this command NEVER auto-advances or auto-picks). Tailor the options to the state:
   - **In-flight build(s) exist** → lead with **Resume `<slug>`** (Stage `<stage>`, Next `<next action>` from its `progress.md`), then offer starting something new.
   - **Options to present** (choose the 2–4 that fit): **Resume** the in-flight build · **New build → contract** (`/compass:start` or `/compass:contract`) · **I have a spec → plan** (`/compass:plan`) · **Adversarial review** (`/compass:review-contract` · `/compass:review-plan` · `/compass:review-build` — pick by the current stage) · **Ship** (`/compass:ship`) · **Show status** (`/compass:status`). The auto-provided **Other** covers anything else.

3. **Route** — invoke the **Skill** for the chosen stage (`compass:contract`, `compass:plan`, `compass:review-*`, `compass:build`, `compass:ship`, or `compass:resume` / `compass:start`). That stage owns its own logic and its own transition gate; **this router adds no second gate of its own.**

## Edge states (handle explicitly)
- **No in-flight build (empty state):** the menu leads with **New build → contract**; there is nothing to resume.
- **Multiple in-flight builds:** list them by `slug · status` from the INDEX so the user picks which one to resume (CURRENT is only a hint and cannot disambiguate parallel builds).
- **A chosen downstream stage whose Step-0 gate isn't satisfied** (e.g. the user picks "build" but no plan is LOCKED): route to that stage anyway — its OWN `compass.sh gate` will surface the block and offer the prior stage. The router NEVER fakes readiness or skips a gate.

## Note
Everything `/compass` does is also reachable directly by the namespaced stage commands (`/compass:start`, `/compass:contract`, `/compass:plan`, …) and `/compass:resume` — `/compass` is just the friendly way in that means you never have to remember which one.
