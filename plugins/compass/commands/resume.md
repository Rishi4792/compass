---
description: Resume an in-progress Compass build from file-based state — picks up exactly where the last session left off, with nothing lost.
---

# /compass:resume

Continue a Compass build that was paused or interrupted. State is on disk, so closing the terminal loses nothing.

## Procedure
1. **Identify the build WITHOUT trusting the global `CURRENT`** (a stale/ambiguous `CURRENT` is what resumed the wrong build before — so it is only a last-resort hint, never the disambiguator):
   - **In a build's worktree?** If `git rev-parse --show-toplevel` ends in `*.compass/<slug>` (or the branch is `compass/<slug>`), THAT is the build. The cwd identifies it unambiguously — use it.
   - **Otherwise** run `compass.sh active-builds`: **0** → nothing to resume; **1** → resume it; **>1 → REFUSE to guess** — list them and require `/compass:resume <slug>`. Only if exactly one is active and the user gave no slug may you fall back to the `CURRENT` hint.
   - Resolve state paths via `compass.sh state-root` (so this works from inside a worktree too).
2. Read that build's `receipts.md`, `progress.md`, and — if building — `plan.md`. Disambiguate the stage:
   - The **last PASS receipt** tells you the last *completed* stage. A `build · IN-PROGRESS · step k/n` receipt (or an absent build receipt with some `plan.md` boxes checked) means the build is **mid-flight, not done** — resume at the first unchecked step. An absent build receipt with zero boxes checked means build never started.
   - **`plan.md` checkboxes are authoritative** for build progress; if `progress.md` disagrees, trust the checkboxes. `progress.md` status qualifies the stage (`contract-LOCKED` vs `plan-LOCKED`, `in-review (Rn)`, etc.).
   - Read `contract.md` (the invariant) and `review-ledger.md` (open issues).
3. State in ONE line where things stand — e.g. "Resuming — plan-LOCKED, building step 4/11 (next: the reconciliation query)." Do not recite the files.
4. Continue from the recorded next action, handing back to the right stage skill (`compass:build`, `compass:review-build`, etc.) and back into the orchestrator's gate flow.

## Note
If the user `cd`'d into the build folder itself, `.claude/builds/` won't resolve — they should be at the **project root** (where `.claude/` lives). If you can't find `.claude/builds/`, say so and ask for the project root.
