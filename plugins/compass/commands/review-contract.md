---
description: Review-1 (LIGHT) — adversarially pressure-test the CONTRACT before it locks. Namespaced entry to the compass:review-contract stage.
---

# /compass:review-contract

Namespaced entry point for the Compass **review-contract** stage. It delegates to the `compass:review-contract` skill, which owns the full stage logic, reads `contract.md` as the invariant, and ends with the canonical 4-button transition gate.

**Do this now:** invoke the **Skill** tool with `skill: compass:review-contract`. Do not duplicate, summarize, or re-implement the stage here — run the skill. The skill presents the gate at its transition; this wrapper adds none.
