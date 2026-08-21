# Contract — deferred-inv · v1

facets: library
schema-touching: no

## Goal & scope
**Goal:** exercise the two `invariants()` destroying paths. This second sentence exists so the goal has more than two. This third sentence exists so that a counter firing without checking WHICH candidate was selected would over-count here. This fourth one too, because this fixture HAS a Done section and must never select the goal fallback.

### NOW
1. Carry one deferred invariant and one ordinary one.

### LATER
1. Nothing.

### NEVER
1. Lose the deferral marker — it is the whole point of this fixture.

## Done
This fixture is done when both invariant paths fire.

## Acceptance & INVARIANTs
- **INV-ORDINARY:** the assert tail is split off and never reaches the page. → *assert:* `node scripts/lossy-instrument.mjs . --json | grep assertTail`
- **INV-NO-TAIL:** this invariant carries no assert recipe at all, so nothing is destroyed on its line. A counter that fires without checking would count it anyway.
- **INV-DEFER (PROGRESS-TRUE) → DEFERRED TO v0.33 (see CARRY-FORWARD.md)** — original text retained for traceability: **(PROGRESS-TRUE) — progress is always visible and always true.** Zero shipped builds report a step count contradicting their receipts, and this sentence exists so the replacement has something real to discard. → *assert:* deferred, so nothing runs.
