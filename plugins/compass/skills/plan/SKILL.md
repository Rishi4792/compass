---
name: plan
user-invocable: false
description: The Plan stage: reads the code, writes the 21-section plan, attacks it, asks for approval.
---

# compass:plan

Turn an approved Idea page into the plan the best engineering teams write. Build to spec: no step the page and `spec.md` do not call for; no spec line without a step.

## 1. Read, then scan
Read `idea.md` and `spec.md`. If `spec.md` is missing, write it as `skills/idea/SKILL.md` describes and run `spec-check`. Then read the codebase as a senior engineer would on day one: `CLAUDE.md` or `README`, how it runs and ships, the files the parts touch, existing tests, data shapes. In an empty folder, choose the stack and start §3 with "greenfield".

## 2. Write the plan
If a `plan.md` fails `plan-check`, rewrite it in full, keeping any `## 21. Decision log` lines. Copy the 21 headings from `${CLAUDE_PLUGIN_ROOT}/shared/plan-template.md`, fill every one, and write the file with one Bash heredoc (never the editing tools). Rules the checker enforces:
- §3 cites at least one path that exists in the target repo, or starts with "greenfield".
- Slice 1 is the walking skeleton and says so. Then one slice per part, in value order.
- Every step: `- [ ] S<slice>.<n> <what> → P<id> · verify: \`<one command>\` → <expected output> · ≈ <estimate>`. The command runs from the project root, exercises the product, and prints the expected text; `true`, `echo`, "it looks right" and an exit code as the expected output are refused. Every promise has a step; a step with no promise is deleted. No step over six hours. Before approval a split step is renumbered (`S2.1`, `S2.2`, shift the rest); never `S2.1a`.
- §12 names the exact undo. §19 has a "how to run it" line and at least one "failure → action" line. §20 has up to three `- R<n>` risks written as consequences for the person ("texts may arrive late on a busy day") with the guard, and any `- Q<n> (<who>)` questions.
Run `plan-check <dir>` and fix what it names until it passes.
Your questions first, before §3, so folding an answer does not reset the attacks: ask every `Q` line in §20, one AskUserQuestion each, shaped by the door's Rules. A question may only choose between readings the page already allows. Record each as `receipt <dir> plan "question answered" "answered: …" "decision: You decided: <the answer in their words>"`, fold the answer into the plan, and mark the line `- Q1 (answered) …`. If an answer would change a promise, do not fold it in: invoke `compass:amend` for that part.

## 3. Attack the plan
`attacks <dir> plan` writes the four plan attacks. The two `plan-check` rows (classes `plan-promise-no-step` and `plan-step-no-promise`) are answered by `plan-check`: record each as `receipt <dir> attack "A<n> plan attempt 1 held" "class: <its key>" "plan-check green"`. Run and record the other two as `skills/attack/SKILL.md` §3 to §5 say; fix a break with an edit to `plan.md` and `plan-check`. A plan edit after §3 means §3 again before `drafted`.

## 4. The card, then gate 2
Re-render and publish the card. Never print `plan-card` or a link line; ask only the question, which carries the link. Record `receipt <dir> plan drafted "plan: 21 sections · <n> parts · <m> steps" "trace: every promise has a step" "[ ] ask: Your plan is on your card: <link>. Approve and build? · Approve and build (Recommended) → I build a thin version of the whole thing first; you get one line per finished step · Revise → tell me what to change; I redo the plan and show it again · Pause → nothing happens until you type /compass again"` (refused while `plan-check` fails, a plan attack is open or the screens are not approved). Ask exactly that. On Approve: `receipt <dir> plan approved "answered: approve" "decision: plan v<n> approved from the card"`, invoke `compass:build`. On Revise: change, re-check, re-attack (§3), record `plan revised`, re-card, ask again.

## 5. When the build finds the plan wrong
Record, then ask exactly: `receipt <dir> plan "plan wrong" "[ ] ask: Part <k> cannot be built the way the plan says: <the reason in plain words>. Change the plan? · Change the plan (Recommended) → I add the steps it needs; your page stays the same · Pause → nothing happens until you type /compass again"`. On Change the plan: add steps only, with the next ids after that part's last id, run `plan-check`, record `receipt <dir> plan revised "answered: change the plan" "decision: <what changed and why, in plain words>"`, and return to `compass:build`. A change that would alter a promise goes through `compass:amend`.

## Never
- Never ask the person an engineering question (a name, a version, a place); decide it from the scan and write it in §20 as an assumption.
- Never show the plan file, a path or a diff in the chat; the plan lives on the card.
- A need the scan finds becomes a `Q` for the person; on yes it goes through `compass:amend`.
