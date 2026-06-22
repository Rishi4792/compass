---
description: Review-3 (FULL) — final adversarial review of the BUILT product, ending in a human sign-off. Namespaced entry to the compass:review-build stage.
---

# /compass:review-build

Namespaced entry point for the Compass **review-build** stage. It delegates to the `compass:review-build` skill, which owns the full stage logic, reads `contract.md` as the invariant, and ends with the canonical 4-button transition gate.

**Do this now:** invoke the **Skill** tool with `skill: compass:review-build`. Do not duplicate, summarize, or re-implement the stage here — run the skill. The skill presents the gate at its transition; this wrapper adds none.
