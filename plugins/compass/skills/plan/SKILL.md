---
name: plan
user-invocable: false
description: The Plan stage. Reads the code first, writes the 21-section engineering plan, shows one screen, asks for approval.
---

# compass:plan

Turn an approved Idea page into the plan the best engineering teams write, then show the person one screen of it. Build to spec: the plan may not contain a step the spec does not call for, and may not leave a spec line without a step.

## 1. Read, then scan
Read `idea.md` and `spec.md` in the build folder. If `spec.md` is missing, write it first, exactly as `skills/idea/SKILL.md` describes (rules each ending `→ P<id>`, assumptions from the scan, kind), and check it with `scripts/compass spec-check <dir>`. Then read the codebase the way a senior engineer would on day one: `CLAUDE.md` or `README`, how it runs and deploys, the files the parts will touch, existing tests, data shapes. Note every real path you will cite. In an empty folder, choose the stack and say "greenfield".

## 2. Write the plan
If a `plan.md` already exists and `plan-check` fails on it, it came from an older stage or a placeholder: rewrite it in full. Keep its `## 21. Decision log` lines, if any.
Copy the 21 headings from `${CLAUDE_PLUGIN_ROOT}/shared/plan-template.md`, in order, and fill every one. Write the whole file in one Bash heredoc to `plan.md` (never the editing tools; the person must not see a diff). Rules the checker enforces:
- §3 cites at least one path that exists.
- Slice 1 is the walking skeleton and its heading says so.
- One slice per part of the Idea page after the skeleton, in value order.
- Every step: `- [ ] S<slice>.<n> <what> → P<id> · verify: <command> · ≈ <estimate>`. Every promise has at least one step. A step with no promise is deleted, not kept.
- Every step fits one sitting. Split any that would not.
- Up to three `- R<n>` risk lines and any `- Q<n> (<who>)` questions in §20.
Then run `node "${CLAUDE_PLUGIN_ROOT}/scripts/compass" plan-check <dir>` and fix what it names until it passes.

## 3. Attack the plan
`scripts/compass attacks <dir> plan` writes the four fixed plan attacks. Two are mechanical and already answered by `plan-check` (a promise with no step; a step with no promise): record them `held` from its output. For the other two, run the protocol in `skills/attack/SKILL.md` with fresh reviewers whose only inputs are `plan.md`, `idea.md`, `spec.md` and the attack: *a step that cannot be undone and has no rollback line* · *a dependency that does not exist in the registry or the repo*. `broke` means an edit to `plan.md` and a re-check, then one re-attack.

## 4. Show one screen, then gate 2
`scripts/compass plan-card <dir>` prints the one screen: slices in order with step counts, the three biggest risks, the questions for the person. Print it unchanged. Re-render and publish the card (`scripts/compass card <dir>`, same file each time). Record `scripts/compass receipt <dir> plan drafted "plan: 21 sections · <n> slices · <m> steps" "trace: <p> of <p> promises have a step" "[ ] ask: Approve the plan?"`.

Then ask with AskUserQuestion, the card link in the question text: "The plan is on one screen at <card url>. Approve and build?" Options: **Approve and build (Recommended)** · Revise · Pause. On Approve: `scripts/compass receipt <dir> plan approved "answered: approve" "decision: plan v1 approved on one screen"`, then invoke `compass:build`. On Revise: ask what to change, change it, re-check, re-card, ask again. On Pause: "Paused. Type /compass to continue."

## Never
- Never ask the person an engineering question. Decide it from the scan and write it in §20 as an assumption.
- Never show the plan file in the chat. The screen is `plan-card`; the file is a link.
- Never add a step the Idea page or spec does not call for. If the scan shows the idea needs something the page does not say, that is a `Q` for the person at gate 2, and on their yes it goes through `compass:amend`.
