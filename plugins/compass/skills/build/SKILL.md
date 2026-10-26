---
name: build
user-invocable: false
description: The Build stage. Part by part; each step is built, proven by running, and recorded; the card updates after every step; attacks run at each part boundary; a step that would drift from the spec stops.
---

# compass:build

Execute the approved plan one step at a time, in order. Build to spec: nothing is built that the Idea page and `spec.md` do not say, and nothing they say is left unbuilt.

## Before every step: the drift stop
Read the step's line in `plan.md` and the spec lines of the promises it serves (`grep "→ P<id>" spec.md`). If doing the step would change what the Idea page or a spec line says, even to improve it, do not start it. Say in one line which spec line it would change, record `scripts/compass receipt <dir> build "drift stop at S<n>" "spec line: <quote>" "[ ] ask: <the change in plain words>. Change the idea, or build it as written?"`, and invoke `compass:amend`. Never a silent improvement.

## The step loop
1. **Resume from the record.** `scripts/compass state <dir>` names the next unproven step. Nothing else is trusted: not a checkbox, not a note, not memory.
2. **Size.** If the step would not finish in one sitting, split it in `plan.md` first (same promise IDs, same verify), then continue. `plan-check` refuses any step over 6 hours.
3. **Build** exactly what the step says, with the stack and conventions the plan's §3 found. For a visual part, compose from the approved mock and the bundled design system; no new styles.
4. **Prove by running.** Run the step's verify command and keep its fresh output. "It compiles" or "it looks right" is not proof. For a screen, load it with real data.
5. **Record.** Only after the verify passes: `scripts/compass receipt <dir> build "step S<n> proven" "verify: <command> → <output>"`. Then `scripts/compass card <dir>` and publish it (same file, same URL). Never write a receipt for a step whose verify did not pass.
6. **Say one line.** "S2.3 proven: <what the output showed>." Nothing else in the chat.

## When a part's steps are all proven: attack it
Run `skills/attack/SKILL.md` for that part's promises (`scripts/compass attacks <dir> build` chooses them; run the rows whose promise belongs to this part, plus the product-wide rows once, at the first part). For a visual part the conformance attack compares the built screen at both widths to the approved mock. Then one line: "Part 2: 6 attacks, 5 held, 1 broke and fixed."

## The gate suite
`scripts/compass gates <dir>` lists what gates progress: each promise's verify commands and every check born from a break. `scripts/compass gates <dir> --run` runs them. No other test runs at a part boundary; the builder's own scratch tests are not gates.

## When every step is proven
For a visual build, take the final screenshots (`scripts/compass shots`) and put them on the card. If `state` shows leftovers, gate 3 belongs to the door. Otherwise invoke `compass:deploy`. Do not ask anything here.

## If a step cannot pass
Diagnose the cause; fix it; re-run. If the plan itself is wrong (the step cannot be done as written), do not improvise: record `[ ] ask:` with the plan line and the reason, and invoke `compass:plan` to revise that slice. Leave the tree in a working state before you stop.
