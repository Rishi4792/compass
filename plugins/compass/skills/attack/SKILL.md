---
name: attack
user-invocable: false
description: The attack protocol: one fresh reviewer per attack, one line held or broke, fix, one re-attack.
---

# compass:attack

An attack is one attempt, in a fixed box, to make one promise false. It ends in exactly one of two ways: `held`, or `broke` with a reproduction the main session re-ran. Nothing else exists: no finding, no severity, no nit, no round.

## 1. Choose the attacks
`node "${CLAUDE_PLUGIN_ROOT}/scripts/compass" attacks <dir> <stage>` writes `attacks.md` with a state column from the record, and for `build` records the chosen rows itself (whole-product rows are marked `When: last part`). For `idea` and `plan` it takes the catalogue's fixed sets. Never add or remove a row by hand.

## 2. One fresh reviewer per attack
Spawn one subagent with the Agent tool, `subagent_type: general-purpose`, never `fork` (a fork inherits your context; the reviewer must not have it). Its prompt contains only: the promise sentence and number; the catalogue's `attack:` recipe word for word; where the product is and how to run it; for a conformance attack, the mock path `mocks/part-<n>.html`, the states it exposes and `templates/tokens.css`; the box: at most 25 tool calls; and the output rule, quoted exactly:
*Your whole final message must be exactly one line. Either `held`, or `broke: <a command or exact steps that reproduce it> → observed <x>, expected <y>`. `<y>` may use "and"; a second "observed" or "broke:", like any other message, is discarded unread.*

## 3. Count only what you can re-run
Pass the reviewer's entire final message to `attack-receipt-check "<message>"`. It rejects anything but one line in the shape above, with one break and no extra findings. On rejection, spawn a replacement reviewer with the same prompt, once more on a second rejection; a third leaves the row open and the part line says so. A discarded message is never `held`.
On `broke`, re-run the reproduction yourself. For `duplicate-output`, `retry` and `data-lost`, run it five times; one reproduction counts. Not reproducible in five runs → `held` with the note. Reproducible → `receipt <dir> attack "A<n> P<id> attempt <k> broke" "class: <key>" "reproduction: <command> → observed <x>, expected <y>"`. On `held`: `receipt <dir> attack "A<n> P<id> attempt <k> held" "class: <key> · tool calls used: <n>"`. For page and plan attacks, `page` or `plan` stands in place of `P<id>`. The record keeps the order: a row of `attacks.md`, attempt 1, a `fix` receipt, attempt 2, then `resolved` only after attempt 2 broke. A row that held on an older version of the page or plan runs again as attempt 1; the record counts attempts per version.

## 4. Break → fix → permanent check → one re-attack
1. Fix the cause, not the symptom.
2. Add the check the catalogue names for that class to the repo's own test folder, red on the old code and green now: `receipt <dir> build "fix A<n>" "check added: <path>" "red: <command> → <output on the old code>" "cause: <one line>"`. A page or plan fix is an edit, with no check file: `receipt <dir> build "fix A<n>" "edit: <what changed in plain words>"`.
3. Re-run the same attack once with a fresh reviewer. Record `attempt 2 held` or `attempt 2 broke`.
4. On `attempt 2 broke`: fix that break too and add its check (a demonstrated bug never ships). Record the question before asking it: `receipt <dir> build "second break at A<n>" "[ ] ask: Part <k>: '<promise sentence>' broke twice when tested: <cause 1>, then <cause 2>. Both are fixed, but it may fail a third way I have not found. What now? · Move on, note it (Recommended) → it ships; the note stays visible · Try once more and show me → one more fresh test, then I show you the result · Leave this promise out → the page and plan lose it; the rest stays"`. Then ask exactly that. On Move on: `receipt <dir> attack "A<n> P<id> attempt 2 resolved" "answered: move on" "decision: Part <k>: ships with a note on the card" "leftover: Part <k>, '<promise sentence>': tested twice for <the class's name: line in failure-catalogue.md, in lower case>, fixed twice, not tested a third time"`. Never put the class key or an id in a leftover. This answer is the person's acceptance; gate 3 does not ask about it again. The note closes by itself when the row runs again after a later change and holds. On Try once more: `receipt <dir> build "second break at A<n>" "answered: try once more"`, then one fresh `attempt 3 held|broke`; a third break re-asks without that option, then `attempt 3 resolved` as above. On Leave out, invoke `compass:amend` to remove the promise.

## 5. Idea and plan attacks
Same reviewer rule. Idea reviewers get only `idea.md` and the recipe; plan reviewers get `plan.md`, `idea.md` and `spec.md`. A break is fixed by an edit recorded as in §4.2 (through `answer` for the page, or one product question), then one re-attack.

## 6. The look: judged once, on the mock
For Premium and Clean parts with a screen, right after gate 1 (`shared/interview.md`, last section):
1. `shots <mock> --out=<dir>/shots --name=part-<n> --states=empty,loading,error,long,first`.
2. Three fresh reviewers (general-purpose, not fork), each with only the screenshots, the sketch if any, `shared/look-rubric.md`, and the rule quoted exactly: *Your whole final message is one line: `scores: hierarchy=<1-5> spacing=… type=… color=… components=… states=… alignment=… polish=… responsive=… copy=… depth=… structure=… controls=… | low: item@"exact region"; …`. Any other message is discarded.*
3. `attack-receipt-check --look "<message>"` on each; a bad shape is re-asked once, then that reviewer is replaced.
4. `look-score <level> "<l1>" "<l2>" "<l3>"` → `held` or `broke` naming items and regions. Record `receipt <dir> attack "L<part> P<first promise of the part> attempt 1 held" "class: look"`. A `broke` adds `"reproduction: look-score <level> → observed <items and regions>, expected held"`; fix the mock, record `receipt <dir> build "fix L<part>" "edit: <what changed in plain words>"`, re-shoot, one re-panel as attempt 2; a second break goes to the person as in §4.4.
After approval there is no rubric: the build is compared with the mock (`picture-mismatch`).

## 7. What the person sees
Nothing, until the card re-renders. One line when a part's attacks finish. A question only after a second break.
