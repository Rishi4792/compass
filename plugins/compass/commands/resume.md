---
description: Resume an in-progress Compass build from file-based state — picks up exactly where the last session left off, with nothing lost.
---

# /compass:resume

Continue a Compass build that was paused or interrupted. State is on disk, so closing the terminal loses nothing.

## Procedure
1. **Read `.claude/builds/CURRENT`** to get the active slug. If it's missing, read `.claude/builds/INDEX` (or list `.claude/builds/*/`) and ask the user which build to resume (don't guess).
2. Read that build's `receipts.md` (the last emitted receipt tells you which stage actually completed and whether it PASSed), `progress.md` (the cursor), and — if building — `plan.md` (its **checkboxes are the authoritative** progress; if `progress.md` and the checkboxes disagree, trust the checkboxes). Read `contract.md` (the invariant) and `review-ledger.md` (open issues).
3. State in ONE line where things stand — e.g. "Resuming — plan LOCKED, building step 4/11 (next: add the reconciliation query)." Do not recite the files.
4. Continue from the recorded next action, handing back to the right stage skill (`compass:build`, `compass:review-build`, etc.) and back into the orchestrator's gate flow.

## Note
If the user `cd`'d into the build folder itself, `.claude/builds/` won't resolve — they should be at the **project root** (where `.claude/` lives). If you can't find `.claude/builds/`, say so and ask for the project root.
