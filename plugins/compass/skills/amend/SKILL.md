---
name: amend
user-invocable: false
description: Change your mind. Edit one part of the Idea page; only that part is re-planned, rebuilt and attacked again. No new build is created. The change is a dated decision on the card.
---

# compass:amend

Ideas change while you build. This is the only door for a change. It keeps build to spec true in both directions: the spec changes first, then the build follows.

## 1. Which part
If the state carries an `ask:` from a drift stop, the part is the one its promise belongs to. Otherwise ask one question: "Which part changes?" with the parts as options, plus "Add a new part".

## 2. Re-interview only that part
Run the interview questions that touch it, from `shared/interview.md`: the part's promises (question 6, for this part only), its done-number if it changes (7), its look if it has a screen (8). Nothing else is asked. Rewrite the part's block in `idea.md` with one Bash heredoc of the whole file; every other part's text must be byte-identical. Bump the eyebrow version in the page by re-rendering (`scripts/compass idea-page <dir> --check`, then render and publish, same URL). For a new part, append it as the next number.

## 3. Spec and plan, that part only
Regenerate the spec lines whose pointer is a promise of this part; leave the rest. Rewrite that part's slice in `plan.md`; leave the other slices. Run `scripts/compass plan-check <dir>`. Run the plan attacks (`attacks <dir> plan`) as `skills/plan/SKILL.md` §3 describes.

## 4. Record, un-prove, continue
`scripts/compass receipt <dir> amend "part <n> edited" "decision: <what changed and why, in the person's words>" "supersede: S<n>.1 S<n>.2 …" "answered: <their answer>"`
The `supersede:` line un-proves exactly the steps of that part's slice; `state` then names the first of them as next. Promises of other parts keep their state. Re-render the card and invoke `compass:build`.

## Never
- Never start a new build folder for a change of mind.
- Never touch a part the person did not change. A diff of `idea.md` shows one block changed.
- Never carry a change through without the receipt; an unrecorded change is drift.
