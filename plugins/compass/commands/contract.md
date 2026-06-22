---
description: Define a build's CONTRACT — the locked spec that becomes the invariant for the whole build. Namespaced entry to the compass:contract stage.
---

# /compass:contract

Namespaced entry point for the Compass **contract** stage. It delegates to the `compass:contract` skill, which owns the full stage logic, reads `contract.md` as the invariant, and ends with the canonical 4-button transition gate.

**Do this now:** invoke the **Skill** tool with `skill: compass:contract`. Do not duplicate, summarize, or re-implement the stage here — run the skill. The skill presents the gate at its transition; this wrapper adds none.
