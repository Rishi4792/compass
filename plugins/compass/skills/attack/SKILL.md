---
name: attack
user-invocable: false
description: The attack protocol used inside every stage. Promises × failure catalogue → ranked attacks → one fresh reviewer per attack → held or broke → fix → permanent check → one re-attack. No rounds, no findings lists.
---

# compass:attack

An attack is one attempt, in a fixed time box, to make one promise false. It ends in exactly one of two ways: `held`, or `broke` with a reproduction the main session re-ran. Nothing else exists: no finding, no severity, no nit, no round.

## 1. Choose the attacks
`node "${CLAUDE_PLUGIN_ROOT}/scripts/compass" attacks <dir> <stage>` writes `attacks.md`: product-wide classes once per build (promise `all`: wrong person, data lost, cannot undo, load, regression, as the product's kind allows), then two attacks per promise chosen by the promise's own words first and the catalogue's likelihood second. For `<stage>` = `idea` or `plan`, the rows are the fixed sets in §5 instead. Never add a row by hand; never remove one. A row with promise `all` is attacked against the whole product and recorded as `A<n> all attempt <k> held|broke`.

## 2. Run each attack with a fresh reviewer
For every row marked `planned`, spawn one subagent with the Agent tool. Its prompt contains only:
- the promise sentence and its number,
- the attack recipe from the catalogue, word for word,
- where the product is and how to run it,
- the time box: at most 25 tool calls,
- the output rule, quoted exactly: *Your whole final message must be one line. Either `held`, or `broke: <a command or exact steps that reproduce it> → observed <x>, expected <y>`. Any other shape is discarded.*

No builder reasoning, no plan, no earlier attack results go into that prompt. The reviewer's ignorance of how it was built is the point.

## 3. Count only what you can re-run
Pass the reviewer's last line to `scripts/compass attack-receipt-check "<line>"`. It exits non-zero on any other shape; then re-run that one attack once with the output rule repeated, and if it fails the shape again, record `held` with the note `reviewer output discarded`.

On `broke`, re-run the reproduction yourself. If it does not reproduce, the attack is `held` with the note `not reproducible`. If it does:
`scripts/compass receipt <dir> attack "A<n> P<id> attempt 1 broke" "reproduction: <command> → observed <x>, expected <y>"`

On `held`: `scripts/compass receipt <dir> attack "A<n> P<id> attempt 1 held" "class: <key> · tool calls used: <k>"`.

## 4. Break → fix → permanent check → one re-attack
1. Fix the cause, not the symptom.
2. Add the check the catalogue names for that class to the repo's own test folder, written so it fails on the old code and passes now. This is the only way a test enters the gate suite.
3. `scripts/compass receipt <dir> build "fix A<n>" "check added: <path>" "cause: <one line>"`.
4. Re-run the same attack once, with a fresh reviewer and the same prompt. Record `attempt 2 held` or `attempt 2 broke`.
5. On `attempt 2 broke`, fix that break too and add its check, exactly as in steps 1 to 3: a demonstrated bug never ships. Then stop and ask the person one question with AskUserQuestion: "Promise P<id> broke twice under the same attack: <both causes in plain words>. Both are fixed. What now?" Options: **Move on, note it as a leftover (Recommended)** · **One more attack by hand with me** · **Cut this promise**. Record the answer as `decision:` and, for move on, also `leftover: P<id> — broke twice under <class>; fixed; no third attempt`. There is no automatic attempt 3.

## 5. Fixed sets for stages without code
- **idea**: four attacks on the page: two parts contradict each other · a promise cannot be checked by anyone · something that already exists does this for this person · the stated person does not need this part. `broke` here means an edit to `idea.md` and one re-render, or one product question to the person. Never an engineering question.
- **plan**: four attacks on the plan: a promise with no step · a step that serves no promise · a step that cannot be undone and has no rollback line · a dependency that does not exist in the registry or the repo. `broke` means an edit to `plan.md`.

## 6. The look: judged once on the mock, then conformance only
Build to spec applies to taste. For a Premium or Clean visual part the Idea stage produced a mock (`mock:` on the part). Judgement happens there, once:
1. `scripts/compass shots <mock.html> --out=<dir>/shots --name=part-<n>` gives a phone and a desktop screenshot.
2. Spawn three fresh reviewers, each with only: the two screenshots, the part's sketch if any, `shared/look-rubric.md`, and the output rule quoted exactly: *Your whole final message must be one line: `scores: hierarchy=<1-5> spacing=… type=… color=… components=… states=… alignment=… polish=… responsive=… copy=… | low: item@"exact region"; …`. Any other shape is discarded.*
3. `scripts/compass attack-receipt-check --look "<line>"` on each; a bad shape is re-asked once, then discarded and the panel runs with the remaining lines only if two remain, else re-spawn one.
4. `scripts/compass look-score <level> "<l1>" "<l2>" "<l3>"` → `held`, or `broke` naming the items and regions. Record as `attack · L<n> P<id> attempt <k> held|broke`. On broke, fix the mock, re-shoot, one re-panel. Two attempts, then the person decides as in §4.5.
5. The person approves the mock at gate 1 by looking at it on the Idea page. From then on the mock is spec.

At build time there is no rubric. The attack is the catalogue class `picture-mismatch` with the approved mock as the reference: the built screen at both widths against the mock, element for element and token for token. `held` or `broke` naming the element.

## 7. What the person sees
Nothing, until the card re-renders: rows move to `held` or `fixed`, and a `FOR YOU` block appears only after an `attempt 2 broke`. In the chat, one line when a part's attacks finish: "Part 3: 6 attacks, 5 held, 1 broke and fixed." No table, no list.
