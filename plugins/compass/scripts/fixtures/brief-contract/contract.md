# Contract — nightly-revenue-rollup-fixture  (v1, LOCKED)

**Goal:** Build a nightly job that rolls up per-order revenue into a daily `revenue_daily` table so finance stops hand-totalling spreadsheets; the rollup must tie to the audited month-end figure of 1234567 to the rupee. (Fixture for INV-GEN-PARSE / INV-BRIEF-IA / INV-BRIEF-SHAREABLE — a GENERIC non-menu contract.)

## Machine headers
- **facets:** pipeline
- **schema-touching:** yes
- **deploy:** in scope — the nightly cron
- **before→after:** finance hand-totals orders in a spreadsheet each morning || a `revenue_daily` table is ready before 6am, tied to the audited figure

## 1. Problem / context
Finance currently exports the orders table and hand-totals revenue in a spreadsheet every morning — slow, error-prone, and impossible to audit. The audited month-end revenue figure is 1234567 rupees, and nothing today reconciles the daily numbers back to it. The internal S&P_score field must never appear in a shareable copy (a declared never-show value with an HTML metachar — the RB-v0.26 leak-regression case).

## 2. Scope ladder

### NOW — the walking skeleton
1. A nightly job that aggregates `orders` → `revenue_daily` (date, gross, net, order_count).
2. Backfill 90 days of history idempotently.
3. Reconcile the month's sum to the audited figure, exact to the rupee.

### LATER (deferred)
- Hourly incremental refresh instead of a nightly full rebuild.
- A per-region breakdown.

### NEVER — Non-goals
- A live dashboard (finance reads the table directly).
- Currency conversion — single-currency only.

## 3. INVARIANTs
- **INV-RECON-TIE:** the month's `SUM(gross)` from `revenue_daily` equals the audited figure 1234567 exactly (0 tolerance). Biting: a reconcile query vs the pinned literal.
- **INV-IDEMPOTENT:** re-running the backfill produces byte-identical `revenue_daily` rows (no double-count). Biting: run twice, diff the table.
- **INV-FRESH-BY-6AM:** the job completes and writes a freshness marker before 06:00. Biting: assert the marker timestamp.

## 4. Security / data-sensitivity
- Per-field classification: revenue figures are **commercial-sensitive**; `revenue_daily` is management-only. never-show: gross_revenue_pct.
- The rollup reads `orders` (contains customer_id) but writes only aggregates — no PII in `revenue_daily`.

FOLD-LEAK-SENTINEL — role×view: only the finance-admin role may read `revenue_daily`; the analyst role sees a masked view. STRIDE-lite: no new external input; the cron auth is a service account. (This paragraph is intentionally a SEPARATE paragraph so `firstPara` drops it on `--shareable` — the fold-vacuity test.)

## Reconciliation gold
- gold = 1234567 (rupees), provenance = the audited month-end statement (human-signed, NOT the rollup's own query); tol = exact to the rupee.

## 5. Kill-switch / rollback
- Flag `revenue_rollup_enabled` (default off); disable = flip the flag; rollback = drop `revenue_daily` + revert the migration. one-way-door: none.

## Non-goals
- NONGOAL-SENTINEL-ZZ — this fixture's Non-goals carry a unique sentinel so a region-scoped test can prove the Goal region never renders Non-goals text. Also: no live dashboard, no currency conversion (see §2 NEVER).

```compass-brief-data
gold: 1234567
never-show: gross_revenue_pct, S&P_score
```
