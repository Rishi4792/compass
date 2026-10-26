# Spec — compass-1-0 · from idea.md
## Rules
- Exactly one user-visible skill exists; every other skill is user-invocable: false. → P1.1
- Every AskUserQuestion option carries one line of consequence; the suggested option is first with (Recommended) in its label. → P1.2
- The door works with no .claude/builds folder and inside an existing git repo. → P1.3
- The interview has ten to eleven questions; twelve is the cap including re-asks. → P2.1
- No question or option contains a word from the banned list. → P2.2
- The renderer refuses a part over 150 words, a promise without a number, a part without a picture. → P2.3
- Gate 1 is one AskUserQuestion with Approve (Recommended) first. → P2.4
- A visual part has a mock (premium, clean) or a sketch (match) before gate 1. → P2.5
- plan-card prints at most 40 lines: slices, three risks, questions. → P3.1
- plan-check refuses a step with no promise and a promise with no step. → P3.2
- plan-check refuses a first slice not named skeleton. → P3.3
- plan-check refuses a current-state section that cites no existing path. → P3.4
- state is a pure function of idea.md, plan.md and receipts.md. → P4.1
- The build skill re-renders the card after every proven step. → P4.2
- gates lists only promise checks and checks born from breaks. → P4.3
- plan-check refuses a step estimated over six hours. → P4.4
- The build skill stops and asks before any change the Idea page does not say. → P4.5
- attack-receipt-check accepts only held or broke with a reproduction; the chooser emits no round concept. → P5.1
- The state machine knows attempt 1 and 2 only; a third attempt has no receipt shape. → P5.2
- A fix receipt needs check added and red lines; gates runs those checks. → P5.3
- A second break surfaces as needs you and an ask line. → P5.4
- writeback runs every promise's check itself and refuses typed values. → P6.1
- The deploy skill proves the switch or records the pin command. → P6.2
- preflight verifies the restore tag exists before printing it. → P6.3
- release-note refuses without a runbook and records the watch date. → P6.4
- The card is rendered from state only. → P7.1
- The door asks only at the four gates. → P7.2
- Every decision: line in receipts appears on the card with its date. → P7.3
- No status file other than receipts.md is read by state. → P7.4
- An amend receipt un-proves only steps serving the edited part. → P8.1
- Superseded steps reset their promises' attack state. → P8.2
- An amend receipt carries a decision line and bumps the page version. → P8.3
## Assumptions (from the scan, not from the person)
- Claude Code loads a plugin skill named compass as bare /compass (docs: skills.md).
- Headless Chrome will not open narrower than 500 px; phone shots use a 390 px frame.
- git tag may be configured to sign; tags are created with -a -m and verified.
## Kind
- mixed
