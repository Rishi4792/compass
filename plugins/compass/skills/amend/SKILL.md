---
name: amend
user-invocable: false
description: Change your mind. The only door for a change: the drift question is asked first; one part of the Idea page is edited; only that part is re-planned, rebuilt and attacked again; proven parts stay proven; the page version goes up.
---

# compass:amend

The spec changes first, then the build follows. Nothing else may change the page.

## 1. Ask before anything changes
If you arrived from a drift stop or a ✗ and the question has not been answered yet, ask it now with AskUserQuestion: "Part <k>: <the change in plain words>. Build it as written (Recommended), or change the page?" with the two consequence lines. On "as written": record `answered:` and `decision:` and return to `compass:build`; nothing is superseded. Otherwise, if no part is named, ask "Which part changes?" with the parts as options plus "Add a new part".

## 2. Re-interview only that part
Run only the interview questions that touch it: the part's moments and promises (question 7, this part only), its done-number if it changes (8), its look if it has a screen (9 and the look section). Every edit goes through `answer <dir> part <n> …`; other parts are not touched, and the page version shown in the eyebrow goes up by itself. Promise ids never change: `answer` keeps the id of a sentence it already knows and gives a new sentence the next free number; a removed id is never reused, so no record ever attaches to the wrong sentence. For a removed promise, rewrite the part's `--promise=` list without it. For a removed part, `answer <dir> part <n> --remove`. Re-render and publish the page, same URL. After a part that was already live is edited, its live numbers are dropped with the superseded steps and the line reads "Building again" until the part is re-proven and re-measured.

## 3. Spec and plan, that part only
Regenerate the spec rules whose pointer is a promise of this part; remove rules for removed promises. Rewrite that part's slice in `plan.md`; leave the other slices. Run `plan-check`. Run the plan attacks as `skills/plan/SKILL.md` §3 describes.

## 4. Record, un-prove, continue
`receipt <dir> amend "part <n> edited" "decision: <what changed and why, in the person's words>" "supersede: S<x>.<y> …" "answered: <their answer>"`.
The record refuses a `supersede:` that names a step not serving a promise of part n. Superseded steps become unproven, and that part's attack results are reset, so its rows run again; other parts keep their state. Re-render the card and invoke `compass:build`.

## Never
- Never start a new build folder for a change of mind.
- Never touch a part the person did not change.
- Never carry a change through without the receipt; an unrecorded change is drift.
