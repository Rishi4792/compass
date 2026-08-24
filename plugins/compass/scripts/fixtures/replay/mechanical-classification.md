# The replay set — v0.32's findings, classified

This file is the **denominator of v0.33's gold**. The gold is *"0 defects of a mechanical class
reach an adversarial reviewer"*, and it is measured by replaying the findings six independent
reviewers recorded during v0.32 against the mechanical suite this build adds.

**Why it is committed here rather than read from the build state.** The source ledger lives at
`.claude/builds/user-invariants-v0-32/review-ledger.md`, which is gitignored. A gold that can only
be computed on one laptop is not a gold. This file is the tracked copy; the source is quoted, never
paraphrased.

**Source figures, re-derived, not asserted:** 59 distinct issue ids across 61 ledger rows.
(`awk` over the ledger's id column, deduped. The CHANGELOG rounds this to "61 real defects"; the
ledger is the record and 59 is the count.)

## The split

| class | count | share |
| --- | --- | --- |
| **mechanical** — a script could have caught it with no judgment | **32** | 54% |
| **judgment** — someone had to decide whether a thing was true or misleading | **27** | 46% |
| total | 59 | |

**Just over half of what six adversarial reviews found needed no reviewer at all.** That figure is
this build's whole argument, and until now it was asserted rather than counted.

## Classification rules, stated before the rows so they can be argued with

- **mechanical** — the defect is a count, a duplicate, a shape, a missing file, a call site that
  does not exist, a check that cannot fail, or a stated number that does not reproduce. A script
  decides it, the same way every time, for no tokens.
- **judgment** — the defect is that something is TRUE but MISLEADING, or that a rule cannot be
  satisfied honestly, or that a mechanism does not do what its name claims. No script decides it.
- **The boundary case, resolved consistently:** a finding whose *evidence* is a count but whose
  *conclusion* is a judgment is classed **judgment**. Counting the lossy call sites is mechanical;
  concluding that the gold therefore rewards hiding evidence is not.

## Rows

Each row: the id, the class, the check class that would catch it, and why in one line.

| id | class | caught by | why |
| --- | --- | --- | --- |
| A1 | judgment | — | whether an LLM harness can assert a numeric bound is a judgment about the mechanism |
| A2 | judgment | — | two prose sections specifying contradictory paths; reading intent |
| A3 | mechanical | figures | a 6-value enum against an 8-item list — two declared counts disagree |
| A4 | mechanical | doctrine-wired | an invariant names a skill the plugin does not ship |
| B1 | judgment | — | whether a guard-first rule undermines the gold is an argument, not a count |
| B2 | mechanical | figures | "settled-closed value" undefined; the ledgers use six distinct statuses — enumerate them |
| B5 | mechanical | figures | "68 of 404" — the denominator counts source lines, the suite executes 687 |
| C1 | judgment | — | whether the page's dedupe behaviour matches the contract's intent |
| C3 | judgment | — | an invariant ordering an action the safety rules ban |
| CAP-1 | judgment | — | a step overriding a locked contract is a semantic conflict |
| CON-1 | mechanical | figures | 0 disclosure elements on any rendered page — grep the output |
| CON-2 | mechanical | vacuous-assert | the gate passes with the file it checks deleted — it cannot fail |
| CON-3 | mechanical | figures | two more stated numbers that do not reproduce |
| D1 | judgment | — | the gold is reachable without keeping the promise: satisfiability, not arithmetic |
| D2 | mechanical | figures | three stated figures do not reproduce |
| D3 | mechanical | figures | a test called "the one that decides" with no row in the invariant table — cross-reference |
| DG-1 | mechanical | figures | one section demands >=717, another states 546-599; the two numbers contradict |
| DG-2 | mechanical | unwired-gate | four more destroying call sites outside the counted function — enumerate call sites |
| DG-3 | judgment | — | inventing a fifth defeat (CSS clamp) is adversarial creativity |
| DM-1 | judgment | — | that forgery-proof independence is impossible here is a conclusion about the environment |
| DM-2 | judgment | — | that an agent-proof counter is not buildable as worded |
| E-R1 | judgment | — | a refutation of another reviewer's claim |
| E-R2 | judgment | — | a refutation of another reviewer's claim |
| E1 | judgment | — | whether an id is genuinely caller-independent is a claim about a mechanism |
| E2 | mechanical | vacuous-assert | the gate passes when its artifact is deleted — mutation proves it cannot fail |
| E3 | mechanical | figures | "0 disclosure elements anywhere" is imprecise against the rendered set |
| P1 | judgment | — | a proposed fix that does not work, shown by reasoning about inheritance |
| PLAN-1 | mechanical | figures | a number the page computes disagreeing with the number it declares |
| R2-1 | judgment | — | the gold scores hiding the evidence as a win |
| R2-10 | mechanical | figures | "15 of 15 name a command" — resolve each command, one does |
| R2-11 | mechanical | figures | "340 rows" against a real 717 |
| R2-12 | judgment | — | an acceptance test no honest implementation can pass |
| R2-13 | judgment | — | a third defeat: an empty disclosure that satisfies the letter |
| R2-2 | judgment | — | the identity mechanism fails in both directions |
| R2-3 | mechanical | unwired-gate | the promised replacement has one call site, gated — count them |
| R2-4 | judgment | — | an unassertable check swapped for an unspecified one |
| R2-5 | judgment | — | two errors in a carried-defect row's reasoning |
| R2-6 | mechanical | figures | the command the gold cites does not exist on disk |
| R2-7 | mechanical | vacuous-assert | with the switch off every new gate returns to a pass — run it both ways and diff |
| R2-8 | mechanical | unwired-gate | the counter's trigger appears zero times in the tree |
| R2-9 | mechanical | figures | "the skill's own stream list" is not parseable as a list |
| RA-1 | mechanical | dup-fact | two step ids that are the same step — a duplicate |
| RA-3 | mechanical | unwired-gate | five status parsers where three were found — count the call sites |
| RA-2 | judgment | — | a fix breaking the rule it was meant to protect |
| RA-4 | judgment | — | a patch overriding a locked contract |
| RA-5 | judgment | — | an objection withdrawn by its own author after measuring |
| RA-6 | judgment | — | a step that is unbuildable because a harness lacks a capability |
| RA-R1 | judgment | — | a refutation of another reviewer's claim |
| RK-1 | mechanical | shell-trap | a captured trailing space in a shell variable |
| RP-1 | mechanical | vacuous-assert | the corpus is gitignored, so a clean clone measures zero pages and passes |
| RP-2 | mechanical | vacuous-assert | the independence check cannot fail |
| RP-4 | mechanical | vacuous-assert | four verifies that cannot fail, one of them a grep for a word |
| RP-3 | judgment | — | whether a deterministic bound can cover an LLM step |
| RP-5 | mechanical | figures | a hook registered to match every prompt in every project — read the config shape |
| RP-6 | mechanical | unwired-gate | 22 call sites, 19 wrapping the result — count them |
| SELF-1 | mechanical | figures | a stated baseline that was never measured, and a ceiling derived from it |
| SELF-2 | mechanical | figures | a clean clone reports one failing assertion; the claim said none |
| SELF-3 | judgment | — | a reviewer correcting their own evidence |
| SELF-4 | mechanical | shell-trap | macOS has no `timeout`, so the command silently did not run |

## What this file is NOT

It does not claim the 32 mechanical findings would have been caught **by this build's suite as
built** — that is what the replay measures, and the replay is the acceptance test, not this file.
This file fixes the denominator so the replay has something honest to divide by.

**And the classification is a judgment made by the party being measured.** That is this gold's
weakest joint, stated rather than hidden: every row carries its reason so any single one can be
re-challenged, and the boundary rule above is written down so the calls can be checked for
consistency rather than taken on trust.
