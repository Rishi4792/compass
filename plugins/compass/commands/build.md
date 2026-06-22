---
description: Build-Test-Verify — execute the locked PLAN one step at a time, proof-gated. Namespaced entry to the compass:build stage.
---

# /compass:build

Namespaced entry point for the Compass **build** stage. It delegates to the `compass:build` skill, which owns the full stage logic, reads `contract.md` as the invariant, and ends with the canonical 4-button transition gate.

**Do this now:** invoke the **Skill** tool with `skill: compass:build`. Do not duplicate, summarize, or re-implement the stage here — run the skill. The skill presents the gate at its transition; this wrapper adds none.
