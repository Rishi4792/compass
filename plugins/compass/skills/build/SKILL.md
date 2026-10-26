---
name: build
user-invocable: false
description: The Build stage. Part by part; each step is built, proven by its own command and expected output, and recorded; one plain line per step; the card updates; attacks at each part boundary and whole-product attacks at the last; a step that would drift from the page stops and asks.
---

# compass:build

Execute the approved plan one step at a time, in order. Build to spec: nothing is built that the Idea page and `spec.md` do not say, and nothing they say is left unbuilt.

## Before every step: the drift stop
Read the step and the spec lines of its promises (`grep "→ P<id>" spec.md`). If doing the step would change what the page or a spec line says, even to improve it, do not start. Record the question first:
`receipt <dir> build "drift stop at S<n>" "spec line: <quote>" "better way: <one line>" "[ ] ask: Part <k>: <the better way in plain words>. Build it as written (Recommended), or change the page?"`
Then ask it yourself with AskUserQuestion: **Build it as written (Recommended)** → "nothing on your page changes" · Change the page → "that part is re-planned and rebuilt". On "as written": `receipt <dir> build "drift answered" "answered: build as written" "decision: kept the page as approved at S<n>"` and continue. On "change": invoke `compass:amend` for that part. Never a silent improvement.

## The step loop
1. **Resume from the record.** `state <dir>` names the next unproven step. Nothing else is trusted.
2. **Size.** If the step would not finish in one sitting, split it in `plan.md` first: renumber (`S2.1`, `S2.2`, shift the rest), same promises, each with its own real command and expected output; run `plan-check`; record `receipt <dir> plan revised "split S<n> into S<n> and S<n+1>"`. A verify may never be weakened mid-build; the record re-checks every step's verify before anything goes live.
3. **Build** exactly what the step says, with the stack and conventions §3 found. For a visual part, compose from the approved mock, `templates/tokens.css` and `design/house-style/SYSTEM.md`; no new styles, no browser-default control; every state the mock shows.
4. **Prove by running** the step's own command; keep its fresh output. "It compiles" or "it looks right" is not proof.
5. **Record.** `receipt <dir> build "step S<n> proven" "verify: <the command> → <the output>"`. The record runs the step's own command itself and refuses the receipt unless the output contains the expected text; what it observed is what gets written. Then `card <dir>` and publish it (same file).
6. **One line to the person, in plain words:** "Part 2, step 3 of 4 done: the list now shows every saved link." Nothing else in the chat.

## When a part's steps are all proven: attack it
Run `skills/attack/SKILL.md` for the rows whose `When` is this part (`attacks <dir> build` writes them with their state). For a part with a mock, the conformance row runs against the approved mock at both widths and every state; for a sketch-only part, against the sketch's elements and order. At the last part, also run the rows marked `last part` (the whole-product attacks). Then run `gates <dir> --run --record` and print exactly the line `part-line <dir> <n>` gives you; never compose it by hand.

## The gate suite
`gates <dir>` lists what gates progress: each promise's command and expected output, and every check born from a break. `gates <dir> --run --record` runs them, records `gates green` or `gates red`, and fails on zero checks, any miss, or a promise with no check. Nothing can go live without a green record newer than the last proven step. No other test gates progress.

## When every step is proven
For a visual build, take the final screenshots (`shots <built screen> --out=<dir>/shots --name=final-part-<n>`) so the card shows them. Then hand back to `/compass`: it asks gate 3 if anything is set aside, otherwise invokes `compass:deploy`. Do not ask anything here.

## If a step cannot pass
Diagnose and fix; re-run. If the plan itself is wrong, record `[ ] ask:` with the plan line and the reason in plain words, and invoke `compass:plan` to revise that slice. Leave the tree working before you stop.
