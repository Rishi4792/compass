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
   - **Intake (v0.13.0):** status `intake (phase N)` means the contract interview is mid-flight — run `compass.sh intake-phase <dir>` for the highest completed phase and re-enter the contract skill's Intake Protocol at the next phase (intake.md is append-only truth; an in-flight question is simply re-asked).
   - **Post-ship loop (v0.12.0):** status `post-ship (round k/cap)` means SHIPPED-but-not-final — the post-ship critique loop is open. Re-enter the ship skill's loop at the first round WITHOUT a `loop.log` registration (`loop.log` is the truth; a round receipt without a matching log line means that round must RE-RUN). `compass.sh loop-converged <dir> postship` tells you exactly where the loop stands.
3. State in ONE line where things stand — e.g. "Resuming — plan-LOCKED, building step 4/11 (next: the reconciliation query)." Do not recite the files.
4. **Re-bind ownership to THIS session before handing off:** `compass.sh own <slug> --session "$CLAUDE_CODE_SESSION_ID"`. The build's Stop-hook guard now follows the live (resuming) session — an orphaned build (its old terminal closed) is silent until this re-bind restores the guard (v0.9.0).
5. Continue from the recorded next action, handing back to the right stage skill (`compass:build`, `compass:review-build`, etc.) and back into the orchestrator's gate flow.

## Autonomous resume (`/compass:resume <slug> --auto`, v0.10.0)
A build with a `.auto-mode` marker resumes in autonomous mode (this is how the Stop hook's cross-session spawn re-enters — `/compass:resume <slug> --auto`). After the ownership re-bind (step 4), re-enter the `--auto` orchestrator loop (see start.md "Autonomous mode"): per-stage `budget-check --bump-stage` (→ `fire-g2 budget-stop` on non-zero), auto-advance while `can-advance` passes, stop at G1/G2. **If the build is at `gate-wait-G2`** (a human-resumed G2): present the human's choices — ship-despite-miss / relax-the-bound (Amend) / keep-trying / abort — and on a continue choice, remove the gate-lock (`.locks/<slug>.gate-lock`) before proceeding. Budget is cumulative across resumes (read from `budget.env`).

## Clean hand-off (when telling the user to open a new terminal)
Print **exactly one clean, copy-paste-ready fenced block and nothing interleaved**:
```
cd "<abs PROJECT root>" && claude
```
then, on its own line, `/compass:resume <slug>` to run once Claude starts. No prose mixed into the command lines — the user copies it clean.

## Note
If the user `cd`'d into the build folder itself, `.claude/builds/` won't resolve — they should be at the **project root** (where `.claude/` lives). If you can't find `.claude/builds/`, say so and ask for the project root.
