---
name: attack
user-invocable: false
description: The attack protocol used inside every stage. Promises × failure catalogue → chosen attacks → one fresh reviewer per attack → one line, held or broke → fix → permanent check → one re-attack. No rounds, no findings lists.
---

# compass:attack

An attack is one attempt, in a fixed box, to make one promise false. It ends in exactly one of two ways: `held`, or `broke` with a reproduction the main session re-ran. Nothing else exists: no finding, no severity, no nit, no round.

## 1. Choose the attacks
`node "${CLAUDE_PLUGIN_ROOT}/scripts/compass" attacks <dir> <stage>` writes `attacks.md` with a state column from the record. For `build`: whole-product classes once (`When: last part`), a conformance row for every promise of a part with a mock or sketch, a load row for every promise whose number is a time or a volume, then two rows per promise chosen by the promise's own words. For `idea` and `plan`: the fixed sets in the catalogue (`stage: idea` / `stage: plan`). Never add or remove a row by hand.

## 2. One fresh reviewer per attack
Spawn one subagent with the Agent tool, `subagent_type: general-purpose`, never `fork` (a fork inherits your context; the reviewer must not have it). Its prompt contains only: the promise sentence and number; the catalogue's `attack:` recipe word for word; where the product is and how to run it; for a conformance attack, the mock path `mocks/part-<n>.html`, the states it exposes and `templates/tokens.css`; the box: at most 25 tool calls; and the output rule, quoted exactly:
*Your whole final message must be exactly one line. Either `held`, or `broke: <a command or exact steps that reproduce it> → observed <x>, expected <y>`. One break per line. Any other message is discarded unread.*
No builder reasoning, no plan, no earlier results go into that prompt.

## 3. Count only what you can re-run
Pass the reviewer's entire final message to `attack-receipt-check "<message>"`. It rejects more than one line, any other shape, a second break on the same line, and an expected clause that smuggles extra findings ("also", "and", "plus", ";", dashes, numbering). On rejection, spawn a replacement reviewer with the same prompt; a second rejection does the same once more; a third leaves the row open (no receipt) and you say so in the part line. A discarded message is never recorded as `held`.
On `broke`, re-run the reproduction yourself. For `duplicate-output`, `retry` and `data-lost`, run it five times; one reproduction counts. Not reproducible in five runs → `held` with the note. Reproducible → `receipt <dir> attack "A<n> P<id> attempt 1 broke" "class: <key>" "reproduction: <command> → observed <x>, expected <y>"`. On `held`: `receipt <dir> attack "A<n> P<id> attempt 1 held" "class: <key> · tool calls used: <k>"`. The record refuses a receipt whose attack is not a row in `attacks.md`, an attempt 2 without attempt 1 broke and a `fix` receipt between them, and a `resolved` without attempt 2 broke.

## 4. Break → fix → permanent check → one re-attack
1. Fix the cause, not the symptom.
2. Add the check the catalogue names for that class to the repo's own test folder, red on the old code and green now.
3. `receipt <dir> build "fix A<n>" "check added: <path>" "red: <command> → <output on the old code>" "cause: <one line>"`.
4. Re-run the same attack once with a fresh reviewer. Record `attempt 2 held` or `attempt 2 broke`.
5. On `attempt 2 broke`: fix that break too and add its check (a demonstrated bug never ships). Record the question before asking it: `receipt <dir> build "second break at A<n>" "[ ] ask: Part <k>: '<promise sentence>' broke twice when tested: <cause 1>, then <cause 2>. Both are fixed. What now? · Move on, note it on the card (Recommended) → it ships; the note stays visible · Try once more and show me → one more fresh test, then I show you the result · Leave this promise out → the page and plan lose it; the rest stays"`. Then ask exactly that. On Move on: `receipt <dir> attack "A<n> P<id> attempt 2 resolved" "answered: move on" "decision: <their words>" "leftover: Part <k>, '<sentence>' broke twice under <class>; fixed; no third attempt"`; on Try once more run one more fresh attempt and record it; on Leave out invoke `compass:amend` to remove the promise. No automatic attempt 3.

## 5. Idea and plan attacks
Same reviewer rule. For `idea`, inputs are the page (`idea.md`), `spec.md` and the recipe; `broke` means an edit through `answer`, a re-render, and one re-attack, or one product question to the person. For `plan`, the two mechanical rows are answered by `plan-check`; the other two use reviewers with `plan.md`, `idea.md`, `spec.md`.

## 6. The look: judged once, on the mock
For Premium and Clean parts with a screen, right after gate 1 (`shared/interview.md`, last section):
1. `shots <mock> --out=<dir>/shots --name=part-<n> --states=empty,loading,error,long,first`.
2. Three fresh reviewers (general-purpose, not fork), each with only the screenshots, the sketch if any, `shared/look-rubric.md`, and the rule quoted exactly: *Your whole final message is one line: `scores: hierarchy=<1-5> spacing=… type=… color=… components=… states=… alignment=… polish=… responsive=… copy=… depth=… structure=… controls=… | low: item@"exact region"; …`. Any other message is discarded.*
3. `attack-receipt-check --look "<message>"` on each; a bad shape is re-asked once, then that reviewer is replaced.
4. `look-score <level> "<l1>" "<l2>" "<l3>"` → `held` or `broke` naming items and regions. Record `attack "L<n> P<id> attempt <k> held|broke"`. On broke, fix the mock, re-shoot, one re-panel, then the person decides as in §4.5.
After the person approves the look, the mock is spec. At build time there is no rubric: the `picture-mismatch` row compares the built screen to the mock at both widths and every state, within the catalogue's tolerance.

## 7. What the person sees
Nothing, until the card re-renders. One line when a part's attacks finish. A `for you` question only after a second break.
