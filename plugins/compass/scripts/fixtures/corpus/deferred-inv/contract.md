# Contract — deferred-inv · v1

facets: library
schema-touching: no

## Goal & scope
**Goal:** exercise the two `invariants()` destroying paths — the assert-tail split and the wholesale replacement of a DEFERRED invariant's own wording.

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
- **INV-DEFER (PROGRESS-TRUE) → DEFERRED TO v0.33 (see CARRY-FORWARD.md)** — original text retained for traceability: **(PROGRESS-TRUE) — progress is always visible and always true.** Zero shipped builds report a step count contradicting their receipts, and this sentence exists so the replacement has something real to discard. → *assert:* deferred, so nothing runs.
