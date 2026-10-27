---
name: build
user-invocable: false
description: The Build stage: each step built, proven by its own command and recorded; attacks at each part.
---

# compass:build

Execute the approved plan one step at a time, in order. Build to spec: nothing is built that the Idea page and `spec.md` do not say, and nothing they say is left unbuilt.

## Before every step: the drift stop
Read the step and the spec lines of its promises (`grep "→ P<id>" spec.md`). If doing the step would change what the page or a spec line says, even to improve it, do not start. Record the question first:
`receipt <dir> build "drift stop at S<n>" "spec line: <quote>" "better way: <one line>" "[ ] ask: Your page says: '<the page line>'. <the better way in plain words>. Build it as written, or change the page? · Build it as written (Recommended) → nothing on your page changes · Change the page → I redo that part"`
Then ask exactly that. On "as written": `receipt <dir> build "drift answered" "answered: build it as written" "decision: Part <k>: kept the page as approved"` and continue. On "change": invoke `compass:amend` for that part. Never a silent improvement.

## The step loop
1. **Resume from the record.** `state <dir>` names the next unproven step. Nothing else is trusted.
2. **Size.** If the step would not finish in one sitting, split it in `plan.md` first, without renumbering: the new steps take the next ids after that part's last id (`S2.4`, `S2.5`), together cite the same promises, and each has its own real command and expected output. Run `plan-check`; record `receipt <dir> plan revised "decision: one step split in two" "split: S2.1"`, where `split:` names the step that goes. After approval a revision may only add steps or split one this way.
3. **Build** exactly what the step says, with the stack and conventions §3 found. For a visual part, compose from the approved mock, `templates/tokens.css` and `design/house-style/SYSTEM.md`; no new styles, no browser-default control. The built page answers `?state=<state>` with the same states as its mock (a step of each screen part builds them).
4. **Prove by running** the step's own command. "It compiles" or "it looks right" is not proof.
5. **Record.** `receipt <dir> build "step S<n> proven" "verify: <the command> → <the output>"`. The record runs the command itself and refuses the receipt unless the output holds the expected text. Then `card <dir>` and publish it (same file).
6. **One line to the person, in plain words:** "Part 2, step 3 of 4 done: the list now shows every saved link." Nothing else in the chat.

## When a part's steps are all proven: attack it
`attacks <dir> build` writes and records the rows. Run `skills/attack/SKILL.md` for the rows whose `When` is this part, and at the last part also the `last part` rows (the whole-product attacks). Until its rows close, the line reads "Testing · Part k, <title> · x of y tests done"; nothing is asked. A sketch-only part is compared with the sketch's elements and order. Then run `gates <dir> --run --record`; checks of parts not built yet read "not yet built" and are not a failure. Print exactly the line `part-line <dir> <n>` gives (k held, m fixed, n set aside); never compose it by hand.

## The gate suite
`gates <dir> --run --record` runs every promise's command and every check born from a break, and records green or red; zero checks, a miss or a promise with no check is red. Nothing goes live without a green record newer than the last proven step; no other test gates progress. After a red run the line reads "Built · next: I fix the red checks": fix the cause, then run the suite again.

## When every step is proven
For a visual build, take one final shot per screen with `shots <built screen> --out=<dir>/shots --name=final-<screen> --states=<its mock's states>`; `shots` fails if a picture is missing or two states give the same picture. The card shows them. Then hand back to `/compass` (gate 3 or `compass:deploy`). Do not ask anything here.

## If a step cannot pass
Diagnose and fix; re-run. If the plan itself is wrong, invoke `compass:plan`; its §5 asks the person before anything changes. Leave the tree working before you stop.
