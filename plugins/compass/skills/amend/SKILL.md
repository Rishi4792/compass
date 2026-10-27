---
name: amend
user-invocable: false
description: Change your mind: one part of the Idea page is edited, then re-planned, rebuilt and attacked again.
---

# compass:amend

The spec changes first, then the build follows. Nothing else may change the page.

## 1. Ask before anything changes
If the stage that sent you has not asked already, record the question first (`receipt <dir> build "change asked" "[ ] ask: …"`), then ask exactly it. Three ways in:
- **The person chose "Change something in this build".** Ask "Which part changes?": each part an option labelled "Part <n>, <title>" (up to three, the likeliest first, with "(Recommended)"), each "→ I redo only that part", plus "Add a new part → I ask its questions". Do not record that answer alone (an answer uses its question up); the §4 receipt carries it word for word (`answered: Part <n>, <title>`). §2's question 7 for that part follows at once.
- **A drift stop.** "Your page says: '<line>'. <the change in plain words>. Build it as written, or change the page? · Build it as written (Recommended) → nothing on your page changes · Change the page → I redo that part". On "as written": record it as the build stage does and return to `compass:build`; nothing is superseded.
- **A promise ✗ live.** "Part <k>: '<the promise>' measured <value> live. Fix it, or change the page? · Fix it so the number is met (Recommended) → I add a step for that part, rebuild it and measure again · Change the page → I redo that part". On Fix, the page stays: skip §2 and add the step in §3.

## 2. Re-interview only that part
Run only the interview questions that touch it: its moments and promises (question 7, this part only), its done-number if it changes (8), and question 9 and the look only when its screen changes. Every edit goes through `answer <dir> part <n> …`; the page version goes up by itself. A reworded promise gets a new id; the old one is retired and never reused. List the steps that served it on `supersede:` (§4). For a removed promise, rewrite the part's `--promise=` list without it. For a removed part, `answer <dir> part <n> --remove`. Re-render and publish the page, same URL. A part that was already live loses its live numbers, and the line reads "Building again" until it is proven and measured again.

## 3. Spec and plan, that part only
Regenerate the spec rules whose pointer is a promise of this part; remove rules for removed promises. Rewrite that part's slice in `plan.md`; leave the other slices. Run `plan-check`.

## 4. Record, attack the plan, continue
`receipt <dir> amend "part <n> edited" "decision: <what changed and why, in the person's words>" "supersede: <each changed step or promise>" "answered: <the chosen option's label, word for word, such as change the page>"`; the record refuses any other answer. Superseded steps become unproven, and that part's attack results are reset, so its rows run again; other parts keep their state. Then run the plan attacks as `skills/plan/SKILL.md` §3 describes. Re-render the card and invoke `compass:build`.

## Never
- Never start a new build folder for a change of mind.
- Never touch a part the person did not change.
- Never carry a change through without the receipt; an unrecorded change is drift.
