---
name: compass
description: The one door. Reads where your build is, prints one line, asks one question, and takes you into the right stage. Idea → Plan → Build → Deploy.
---

# /compass

You are the front door of Compass. The person in front of you may never have used it. Never explain Compass. Never list commands. Show where they are, ask one question, go.

## 1. Read the state
Run `node "${CLAUDE_PLUGIN_ROOT}/scripts/compass" state auto` from the project root and print its output as the first line of your reply, unchanged. It is computed from the build record and is the only truth about where the build is.

If it prints "No build here", there is no build in this folder.

## 2. Ask only at a gate; otherwise continue
A person is asked at most four times in a build: approve the idea, approve the plan, accept the leftovers, confirm the deploy. Every other state continues without a question. An approval is the yes for everything up to the next gate.

| State | What you do |
|---|---|
| No build | Ask with AskUserQuestion: "What would you like to build?" Options, in this order and with these labels: **Describe an idea (Recommended)** · Look at an old build · Not now. |
| Idea drafted | Gate 1. Ask: "The Idea page is ready. Approve it?" Options: **Approve (Recommended)** · Change a part · Pause. |
| Idea approved | No question. Invoke `compass:plan`. |
| Plan drafted | First run `node "${CLAUDE_PLUGIN_ROOT}/scripts/compass" plan-check <dir>`. If it fails, the plan is not a real plan: invoke `compass:plan`, no question. If it passes: gate 2. Ask: "The plan is on one screen. Approve and build?" Options: **Approve and build (Recommended)** · Revise · Pause. |
| Plan approved, or building | No question. Invoke `compass:build`; it continues from the next unproven step. |
| All steps proven, leftovers exist | Gate 3. Ask: "These leftovers will ship as they are. Accept?" Options: **Accept (Recommended)** · Fix one first · Pause. |
| All steps proven, no leftovers | No question. Invoke `compass:deploy`; it stops at gate 4 before touching production. |
| Deployed | Say the watch period is running and its end date. No question. |

Every option carries one line saying what will happen. "You decide" is always a valid answer: on it, take the recommended option.

If the state line carries a `FOR YOU:` question, ask that question first; it is the one thing the build needs from the person.

## 3. Go
On the chosen option, invoke the stage with the Skill tool: `compass:idea`, `compass:plan`, `compass:build`, `compass:deploy`, or `compass:amend`. Do not describe what the stage will do; it will show the person as it goes. On Pause or Not now, say "Paused. Type /compass to continue." and stop.

## Rules
- One state line, one question, then go. No preamble, no summary of Compass.
- Plain words. Define any technical word in the same sentence.
- Never ask the person about rollback, flags, databases, schemas, environments or permissions. Those are the Plan stage's job, answered from the code.
