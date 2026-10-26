---
name: idea
user-invocable: false
description: The Idea stage. A product interview of about 8 questions that draws the Idea page as you talk. Never asks an engineering question. Ends with the person approving the page.
---

# compass:idea

Read `${CLAUDE_PLUGIN_ROOT}/shared/interview.md` first. It is the interview. This file is the mechanics around it.

## Files
The build folder is `.claude/builds/<slug>/`, slug = a short kebab-case name from the purpose. You write:
- `idea.md` — the source of the page. Grammar below. The state, the card and the page are all computed from it.
- `idea-page.html` — rendered by `node "${CLAUDE_PLUGIN_ROOT}/scripts/compass" idea-page <dir>`. Never hand-edit it.
- `pictures/part-<n>.svg` — only when no library picture fits a part (`picture: file:pictures/part-<n>.svg`).
- `spec.md` — after approval. Section below.
- `receipts.md` — through `scripts/compass receipt`.

## idea.md grammar
```
# Idea — <slug>
title: <Product name, two to four words>
page: <published URL, or the local path until one exists>
for: <who, in one line>
hurts: <what hurts today, with the last time it happened>
purpose: <one sentence>
done: <the one number that says it worked, and by when>
look: premium | clean | match        (only when some part has a screen)

### Part 1 — <Title>
picture: <library key, or file:pictures/part-1.svg>
<One to three plain sentences: what this part does for the person.>
- P1.1 <one sentence a person could check> → <number>
mock: mocks/part-1.html              (premium or clean visual parts: the approved mock, shown on the page and binding on the build)
sketch: pictures/sketch-1.svg        (match level, or alongside a mock; or a fenced ```ascii block on the next lines)

## Later
- <item>
## Never
- <item>
```
Library picture keys: `idea chat page plan steps shield rocket card pencil list chart clock bell box people money mail map search lock cloud phone`. Pick the closest. Limits the renderer enforces: at most 150 words per part including its promises, a number after `→` on every promise, a picture on every part. Run `scripts/compass idea-page <dir> --check` before every publish; fix what it names.

## Rhythm
1. Scan the folder. Ask nothing. Create the folder and `idea.md` with the header lines you can already fill.
2. Ask the ten questions one at a time, exactly as `interview.md` says: frame (1 to 3), clarify (4), expand (5), parts (6), the done-number (7), the look (8), what is out (9), the line never crossed (10). After each answer: update `idea.md` → `scripts/compass idea-page <dir>` → publish `idea-page.html` with the Artifact tool, same file every time so the URL stays the same, and put that URL on the `page:` line. Without the Artifact tool, write the file and open it in the browser once; print the path once.
3. Record `scripts/compass receipt <dir> idea drafted "[ ] ask: Approve the Idea page?"` after the first render; later renders need no receipt.
4. Gate 1, as `interview.md` ends. On Approve: `scripts/compass receipt <dir> idea approved "answered: approved" "decision: Idea page v1 approved by reading it"`, then write `spec.md`, then re-render the card (`scripts/compass card <dir>`, publish it, same file each time) and print the state line. On Change a part: ask which part and re-run only the questions that touch it. On Pause: say "Paused. Type /compass to continue." and stop.

## spec.md — written after approval, read by machines
Every rule the build must obey, each line ending with the promise it serves. The person never has to read it. Grammar:
```
# Spec — <slug> · from idea.md v1
## Rules
- <a statement a test can check> → P1.1
## Assumptions (from the scan, not from the person)
- <engineering fact and where it came from>
## Kind
- visual | data | service | mixed
```
Put here everything the interview was forbidden to ask: how it is turned off, what data it touches, what runs it, what it must not change. Check with `scripts/compass spec-check <dir>`; every rule line must carry `→ P<n>.<m>`.

## Writing idea.md without showing it
Write the whole file each time with one Bash call:
```
cat > .claude/builds/<slug>/idea.md <<'EOF'
…the full file…
EOF
node "${CLAUDE_PLUGIN_ROOT}/scripts/compass" idea-page .claude/builds/<slug> --check
```
Never use the Edit or Write tools on `idea.md`; the terminal would show the person a diff.

## Never
- Never ask about rollback, flags, schemas, environments, permissions or any banned word.
- Never use the AskUserQuestion `preview` field. Never draw in the chat.
- Never summarise the page in the chat. The page is the summary.
- Never exceed twelve questions. Never ask two in one call.
- Never check a receipt box the person did not actually answer.
