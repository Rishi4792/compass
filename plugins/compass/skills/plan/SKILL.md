---
name: plan
user-invocable: false
description: The Plan stage. Reads the code first, writes the 21-section engineering plan with a command and an expected output per step, attacks it, shows one screen, asks for approval.
---

# compass:plan

Turn an approved Idea page into the plan the best engineering teams write, then show the person one screen. Build to spec: no step the page and `spec.md` do not call for; no spec line without a step.

## 1. Read, then scan
Read `idea.md` and `spec.md`. If `spec.md` is missing, write it as `skills/idea/SKILL.md` describes and run `spec-check`. Then read the codebase as a senior engineer would on day one: `CLAUDE.md` or `README`, how it runs and deploys, the files the parts touch, existing tests, data shapes. In an empty folder, choose the stack and write "greenfield" at the start of §3.

## 2. Write the plan
If a `plan.md` exists and `plan-check` fails on it, rewrite it in full, keeping any `## 21. Decision log` lines. Copy the 21 headings from `${CLAUDE_PLUGIN_ROOT}/shared/plan-template.md`, fill every one, and write the file with one Bash heredoc (never the editing tools). Rules the checker enforces:
- §3 cites at least one path that exists in the target repo, or starts with "greenfield".
- Slice 1 is the walking skeleton and says so. Then one slice per part, in value order.
- Every step: `- [ ] S<slice>.<n> <what> → P<id> · verify: \`<one command>\` → <expected output> · ≈ <estimate>`. The command runs from the project root, exercises the product, and prints the expected text; `true`, `echo` and "it looks right" are refused, and so is an exit code as the expected output. The record later runs that exact command before it accepts the step as proven. Every promise has a step; a step with no promise is deleted. No step over six hours. When a step must be split, renumber (`S2.1`, `S2.2`, shift the rest); never `S2.1a`.
- §12 names the exact undo. §19 has a "how to run it" line and at least one "failure → action" line. §20 has up to three `- R<n>` risks written as consequences for the person ("texts may arrive late on a busy day") with the guard, and any `- Q<n> (<who>)` questions.
Run `plan-check <dir>` and fix what it names until it passes.

## 3. Attack the plan
`attacks <dir> plan` writes the four plan attacks. The two mechanical ones are answered by `plan-check`: record `receipt <dir> attack "A1 plan attempt 1 held" "plan-check green"` and the same for A2. For the other two, run the protocol in `skills/attack/SKILL.md` with fresh reviewers whose only inputs are `plan.md`, `idea.md`, `spec.md` and the catalogue recipe. `broke` means an edit to `plan.md`, a re-check, and one re-attack.

## 4. Your questions first, then one screen, then gate 2
Every `Q` line in §20 is asked before the plan screen, one AskUserQuestion each, in plain words with a recommended answer and a consequence per option; record each as `receipt <dir> plan "question answered" "answered: …" "decision: You decided: <the answer in their words>"`, fold the answer into the plan, and mark the line `- Q1 (answered) …` so the screen stops owing it. An engineering question (a name, a version, a place) is yours to decide and goes in §20 as an assumption, never to the person.
`plan-card <dir>` prints the screen; print it unchanged. Re-render and publish the card. Record `receipt <dir> plan drafted "plan: 21 sections · <n> parts · <m> steps" "trace: every promise has a step" "[ ] ask: Approve the plan?"` (the record refuses this while plan-check fails or the screens are not yet approved).
Ask with the card link in the question: "The plan is on one screen at <card url>. Approve and build?" Options: **Approve and build (Recommended)** → "I start with the skeleton; you hear from me when a part is done" · Revise → "Tell me what to change; I redo the plan and show it again" · Pause → "Nothing happens until you type /compass again". On Approve: `receipt <dir> plan approved "answered: approve" "decision: plan v<n> approved on one screen"`, invoke `compass:build`. On Revise: change, re-check, record `plan revised`, re-card, ask again.

## Never
- Never ask the person an engineering question; decide it from the scan and write it in §20 as an assumption.
- Never show the plan file, a path or a diff in the chat. The screen is `plan-card`; the full plan is a link on the card.
- Never add a step the page or spec does not call for. A need the scan finds becomes a `Q` for the person; on yes it goes through `compass:amend`.
