---
description: Ship — deploy the CLOSED build and prove it in prod. Namespaced entry to the compass:ship stage.
---

# /compass:ship

Namespaced entry point for the Compass **ship** stage. It delegates to the `compass:ship` skill, which owns the full stage logic, reads `contract.md` as the invariant, and ends with the canonical 4-button transition gate.

**Do this now:** invoke the **Skill** tool with `skill: compass:ship`. Do not duplicate, summarize, or re-implement the stage here — run the skill. The skill presents the gate at its transition; this wrapper adds none.
