# Contract — view-fixture-build  (v1, LOCKED)

**Goal:** Roll widget events into a daily table so the team stops hand-counting. Ships as v9.9.9.

## Machine headers
- **facets:** pipeline
- **program:** view-demo

## 2. Scope ladder

### NOW — the walking skeleton
1. Aggregate events into a daily table.
2. Backfill history idempotently.
3. Reconcile the totals.

### LATER (deferred)
- LATER-SENTINEL — an hourly refresh (must NOT show as shipped).

### NEVER — Non-goals
- NEVER-SENTINEL — a live dashboard (must NOT show as shipped).
