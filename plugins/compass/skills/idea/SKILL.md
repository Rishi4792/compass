---
name: idea
user-invocable: false
description: The Idea stage. A product interview of eleven questions that draws the Idea page as you talk; what exists today and why build anyway; a 10x option that may change the purpose; the journey as pictures. Never an engineering question. Ends with the person approving the page, then the look.
---

# compass:idea

Read `${CLAUDE_PLUGIN_ROOT}/shared/interview.md` first. It is the interview. This file is the mechanics.

## Files
Build folder `.claude/builds/<slug>/`, slug kebab-case from the purpose, no spaces. You never write `idea.md` yourself: `scripts/compass answer <dir> …` does, and it renders `idea-page.html` and checks the page every time. Other files: `pictures/*.svg` (custom pictures, sketches), `mocks/part-<n>.html`, `shots/` (made by `shots`), `spec.md` (after approval), `receipts.md` (through `receipt`).

## What the page holds
Header: title, purpose, for, hurts, exists (at least two things used today, separated by " · ", each with where it fails), because, done, look. A `## Journey` of at least two ordered moments, each a picture and a caption. Parts, each with a library picture (`idea chat page plan steps shield rocket card pencil list chart clock bell box people money mail map search lock cloud phone`, or `file:pictures/x.svg`), one to three plain sentences, one to three promises each with a number that has a digit, `--screen` on any part a person sees on a screen, and a mock (premium, clean) or sketch (match) for every screen part. Later and Never lists. Promise ids never change once written; a removed promise's id is never reused. The checker enforces all of this, plus ≤150 words per part and no fenced text sketches.

## Rhythm
1. Scan the folder. Ask nothing. `answer <dir> set title "<working title>"` creates the folder and the page.
2. Ask the eleven questions one per call, exactly as `interview.md` says; after each answer one `answer` command, one Artifact publish of `idea-page.html` (same file, same URL; put the URL on `page:` with `answer set page <url>`), and `answer <dir> question <k> 11`. The state line then reads "Idea · question k of 11 answered", so a person who stops can resume at the next question.
3. Before gate 1, attack the page: `attacks <dir> idea` writes the four idea attacks; run them as `skills/attack/SKILL.md` §5 says (fresh reviewers; `broke` is an edit through `answer` or one product question). Record each as `attack "A<n> page attempt 1 held|broke" "class: <key>"`.
4. Gate 1 as `interview.md` ends. On Approve: `receipt <dir> idea approved "answered: approve" "decision: Idea page v<n> approved by reading it"`; then write `spec.md` (below) and check it with `spec-check`; then the look (interview.md, last section) for visual parts; then re-render and publish the card; invoke `compass:plan`. On Change a part: ask which, redo only its questions, return to gate 1. On Pause: "Paused. Type /compass to continue." and stop.

## spec.md — written after approval, read by machines
```
# Spec — <slug> · from idea.md v<n>
## Rules
- <a statement a test can check> → P1.1
## Open
- <each ambiguity from the clarify step, how it was resolved or that it was asked>
## Assumptions (from the scan, not from the person)
- <engineering fact and where it came from>
## Kind
- visual | data | service | mixed
```
Everything the interview was forbidden to ask goes here: how it is turned off, what data it touches, what runs it, what it must not change. A rule may only point at a promise on the page; if the scan shows the product needs something the page does not say, that is a question for the person, not a rule.

## Never
- Never ask about rollback, flags, schemas, environments, permissions or any banned word.
- Never summarise the page in the chat; the page is the summary. Never draw in the chat. Never use the preview field.
- Never exceed twelve questions. Never ask two in one call. Never write a receipt for an answer the person did not give.
