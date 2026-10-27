---
name: idea
user-invocable: false
description: The Idea stage: an eleven-question product interview that draws the Idea page, then gate 1 and the look.
---

# compass:idea

Read `${CLAUDE_PLUGIN_ROOT}/shared/interview.md` first. It is the interview. This file is the mechanics.

## Files
Build folder `.claude/builds/<slug>/`. `scripts/compass answer <dir> …` writes `idea.md` and renders and checks `idea-page.html`; never write `idea.md` yourself.

## What the page holds
Header: title, purpose, for, hurts, exists (at least two things used today, separated by " · ", each with where it fails), because, done, look. A `## Journey` of at least two ordered moments, each a picture and a caption. Parts, each with a library picture (`idea chat page plan steps shield rocket card pencil list chart clock bell box people money mail map search lock cloud phone`, or `file:pictures/x.svg`), one to three plain sentences, one to three promises each with a number that has a digit, and `--screen` on any part a person sees on a screen. Open questions, Later and Never lists. Promise ids never change once written and are never reused; a reworded promise gets a new one. The checker enforces all of this, plus ≤150 words per part and no fenced text sketches. A mock (premium, clean) or sketch (match) for every screen part is checked at the look, not before.

## Rhythm
1. Scan the folder as `interview.md` says. Take the person's sentence from the door and make a working title from it, and the folder name from the title (kebab-case, no spaces). `answer <dir> set title "<working title>"` creates the folder and the page. With no sentence, resume the folder that exists.
2. Ask the questions as `interview.md` says; after the first publish keep the page's link with `answer <dir> set page <url>`. A person who stops resumes at the next question.
3. Before gate 1, attack the page: `attacks <dir> idea` writes the four idea attacks; run and record them as `skills/attack/SKILL.md` §3 to §5 say (`A<n> page attempt <k> held|broke`; a `broke` quotes the page lines). After any page edit, run every page attack again before `drafted`; the record refuses `drafted` while a row is open on this version.
4. Gate 1 as `interview.md` ends. On Approve: `receipt <dir> idea approved "answered: approve" "decision: Idea page v<n> approved by reading it"`; then write `spec.md` (below) and run `spec-check`; then the look (interview.md, last section) when a part has a screen; then render and publish the card and keep its link (`answer <dir> set card <url>`); invoke `compass:plan`. On Change a part: ask "Which part changes?" as `skills/amend/SKILL.md` §1 writes it, redo only that part's questions, re-attack (§3), return to gate 1. On Pause: "Paused. Type /compass to continue." and stop.

## spec.md — written after approval, read by machines
```
# Spec — <slug> · from idea.md v<n>
## Rules
- <a statement a test can check> → P1.1
## Open
- <each open question from the page, with its answer>
## Assumptions (from the scan, not from the person)
- <engineering fact and where it came from>
## Kind
- visual | data | service | mixed
```
Everything the interview was forbidden to ask goes here: how it is turned off, what data it touches, what runs it, what it must not change. A rule may only point at a promise on the page; if the scan shows the product needs something the page does not say, that is a question for the person, not a rule.

## Never
- Never ask an engineering question or use a banned word.
- Never write a receipt for an answer the person did not give.
