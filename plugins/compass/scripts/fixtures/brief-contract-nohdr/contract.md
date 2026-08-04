# Contract — sec-goal-coverage-fixture  (v1, LOCKED)

This fixture has **NO `**Goal:**` inline header** — the goal lives in a `## Goal & scope` section placed AFTER `## Non-goals`. That forces `briefBody`'s `hdr('Goal') || firstPara(sec('Goal') || sec('Goal & scope'))` to fall through to **`sec('Goal')`**, so the anchored-`sec()` fix is actually EXERCISED. With the old buggy `.includes('goal')`, `sec('Goal')` returns the `Non-goals` body (its first key containing "goal"), so the hero would render `GOALSEC-DECOY-QQ`; the fix makes it render `GOALSEC-REAL-PP`.

## Machine headers
- **facets:** pipeline
- **deploy:** in scope

## 1. Problem / context
The goal is stated in a section, not an inline header — this is a valid legacy contract shape the generator must still render correctly.

## Non-goals
GOALSEC-DECOY-QQ — this Non-goals sentinel must NEVER appear in the goal/hero region. (Placed BEFORE the Goal section on purpose, so a buggy substring `sec()` would grab it.) Also: no live dashboard, no currency conversion.

## Goal & scope
GOALSEC-REAL-PP — the real goal: aggregate widget events into a daily rollup table so the team stops hand-counting. This is the true goal sentence the hero must show.

## 2. Scope ladder

### NOW — the walking skeleton
1. Aggregate events into a daily table.
2. Backfill history idempotently.

### LATER (deferred)
- An hourly refresh.

### NEVER — Non-goals
- A live dashboard.

## 3. INVARIANTs
- **INV-SEC-COVERAGE:** the hero renders the Goal-section text, not the Non-goals section — proving `sec('Goal')` resolves correctly. Biting: grep the hero region.

## 4. Security / data-sensitivity
- N/A — no sensitive surface (a test fixture).

## Reconciliation gold
- N/A — no numeric gold (this fixture targets the sec() path, not the leak gate).
