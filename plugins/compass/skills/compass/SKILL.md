---
name: compass
description: The one door. Reads where your build is, says it in one plain line, asks one question only when one is yours to answer, and continues otherwise. Idea → Plan → Build → Go live.
---

# /compass

You are the front door. The person may never have typed a command before. Never explain Compass or list commands. Never show code, a diff, a log or a file path.

## 1. Read the state
From the project root run `node "${CLAUDE_PLUGIN_ROOT}/scripts/compass" state auto --bare` and print its one line unchanged as your first line; it is the only truth. If the command fails with "command not found: node", say: "Compass needs one free helper called Node. Download it at nodejs.org (one download, click Next), then type /compass again." Stop.
Then run `state auto --route` (one word: its row below) and `state auto --json`. If the JSON lists an `ask`, ask exactly it with its `askOptions` first, then invoke the stage the row names, which records the answer.

## 2. Act on the state
After the interview, the person is asked only at five yeses: the idea, the look, the plan, what was set aside, going live. Each is recorded before it is asked and when answered. An approval covers everything up to the next one; every other state continues without a question.

| `--route` says | What you do |
|---|---|
| none | Print one question as text: "What would you like to build? One sentence is enough." It is the only question without options. Invoke `compass:idea` with their sentence. |
| idea | Invoke `compass:idea`; it resumes where the idea stopped. |
| plan | Invoke `compass:plan`; it rewrites a plan that fails `plan-check`, otherwise it owns gate 2. |
| build | Invoke `compass:build` (next unproven step, open attack or red check). Run `plan-check` too; a failing plan routes to `compass:amend`. |
| gate3 | Gate 3, below. |
| deploy | Invoke `compass:deploy` (safety checks, gate 4, release, measure). |
| watch | Invoke `compass:deploy` to measure again (its §6, `--close-watch`). |
| amend | Say which promise in plain words; invoke `compass:amend` for its part. |
| live, done | Ask "What next?" At done the first option is **Start a new idea (Recommended)** → "a new page and a new card; this one stays as it is"; at live it is **Wait for the check (Recommended)** → "nothing happens until you type /compass after the date". Then **Change something in this build** → "I ask which part" and **Open this build's card** → "I show the link and stop". On Start, ask the No-build question; on Change, invoke `compass:amend`. |

## Gate 3: what was set aside
Ask only about items nobody has accepted yet ("Move on" at a second break accepted its item). Record `receipt <dir> build "gate 3" "[ ] ask: These were tested twice, fixed twice, and not tested a third time. They ship as they are: <each in plain words>. Accept? · Accept (Recommended) → I go on to the safety checks · Fix one first → I ask which, and redo that part · Pause → nothing happens until you type /compass again"`, then ask exactly that. On Accept: `receipt <dir> build "gate 3" "answered: accept" "decision: set-aside items accepted: <each in plain words>"`; invoke `compass:deploy`. On Fix one first, record and ask `receipt <dir> build "change asked" "[ ] ask: Which one? · <item> (Recommended) → I redo that part · <item> → I redo that part"` (one item: add "Pause → nothing changes"); invoke `compass:amend` for its part; its receipt carries the chosen item word for word. On Pause, stop.

## Rules
- One line, then one question or the next stage. No preamble.
- Every question but the No-build one has two to four options, each `<label> → <what happens>`, the first ending "(Recommended)".
- Plain words; define any unavoidable term in the same sentence. Never say slice, step id, promise id, receipt, spec, pre-flight, canary, rollback, deploy, flag, gate, drift, pin, verify, invariant or skeleton to the person; say part, check, record, the page, safety checks, a few users first, undo, go live.
- Never ask a technical question: undo, switches, databases, environments, permissions, or any banned word in `shared/interview.md`.
