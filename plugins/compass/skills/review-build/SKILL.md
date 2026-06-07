---
name: review-build
description: Review-3 (FULL) — final adversarial review of the BUILT product via a multi-agent fan-out assuming every feature is broken until a re-run check proves it (reconciliation, design+a11y, exercised rollback, observability, idempotency, secrets). Ends with a human sign-off. Two clean rounds; cap 5. Trigger after compass:build, or on "review the build", "final review", "ready to ship".
---

# compass:review-build  (Review-3 · FULL)

Lens: **is the BUILT thing correct, complete vs the contract, and safe — proven, not vibed?**

## Step 0 — gate
Run `compass.sh gate .claude/builds/<slug> build`. **Non-zero → STOP** (build incomplete), offer the right earlier stage. Read `contract.md` + `plan.md`. Set `progress.md` = `in-review (R3)`. Check the product against the contract feature-by-feature.

## Engine
- **Ledger** (create if absent): same columns.
- **Material** = new Critical/Major. **Clean round** = zero new material AND the regression suite RE-RUNS green. **Proof-of-work footer:** `> Round N (R3): suite=\`<cmd>\` exit=0 passed=k/k; reconcile→PASS; new Crit/Maj=0. Clean? yes` — no command line = not clean. **Converged = two consecutive clean rounds.** Cap **5**.
- **Fan-out economy:** round 1 spawns all groups; **rounds 2+ spawn ONLY the groups the last round's fixes touched** — the full regression suite still re-runs every round (that, not re-spawning every agent, guards un-reviewed surfaces). A confirming clean round with no new fixes = just the suite re-run + footer. Closure = Validation command **re-run with fresh output**; agent agreement is not evidence.
- **Cap 5 un-converged** → plan flaw → `compass.sh supersede .claude/builds/<slug> plan`, escalate to `compass:plan` (or `contract` if the premise is false).

## Streams — fan out as 6 agents (assume each FAILS until proven; each emits one ledger row per check)
- **[A] Correctness & completeness:** feature failure modes (empty/huge data, concurrency, partial input, permission edges) · completeness vs contract (every requirement built AND demonstrated by a re-run check) · regression (run the repo's own suite).
- **[B] Numbers, data & integrity:** reconciliation — run the query then `compass.sh reconcile <actual> <gold> <tol>` (non-zero = CRITICAL, blocks CLOSED), re-check the dup/fan-out/source-table bug-classes, gold is the contract's independent figure · DB/migration integrity — **rollback ACTUALLY exercised on a copy** (forward+back, row-count + checksum identical) · idempotency — run twice, assert identical end-state, no double-write.
- **[C] UX & operability:** design + a11y (web) — exact: computed CSS vs tokens, contrast/focus-visible/keyboard; **design-intent fidelity: screenshot the live UI and read it back against the contract's captured DESIGN INTENT, naming any drift from what was imagined (layout, hierarchy, spacing, feel) — a Major finding if it drifts.** · performance/OOM/scale at the contract's volume + concurrency · observability — the contract's named metric/log actually EMITS (not prose).
- **[D] Security/RBAC/data-leakage** — *independent agent.*
- **[E] Secret-leak** — *independent agent:* `compass.sh secret-scan .` over the diff + every kept verify spec (any hit = CRITICAL, blocks CLOSED).
- **[F] Verification audit & coverage** — *independent agent:* every "works" backed by a real command + fresh output (screenshot-only proof of a number/token = a finding); every plan-promised test present and passing.

## Procedure → emit → human sign-off
Round 1: all 6 groups → ledger + fixes; re-validate by RE-RUNNING commands. Rounds 2+: only the groups the fixes touched, plus the full regression suite re-run + footer (a confirming round with no new fixes = suite re-run only). Two clean rounds → **EMIT RECEIPT** (one line per asserted thing, with command + output):
```
## RECEIPT — review-build · <slug> · PASS
- [x] gate: build receipt OK; all 6 groups run
- [x] INVARIANT <id>: `<cmd>` → <actual> vs <bound> PASS   (per invariant)
- [x] RECONCILE: `compass.sh reconcile <actual> <gold> <tol>` → PASS   (or N/A)
- [x] secret-scan: `compass.sh secret-scan .` → 0 hits
- [x] rollback exercised on a copy: `<cmd>` → row-count+checksum identical
- [x] observability emits: `<cmd>` → <signal seen>; idempotency test: run twice → identical
- [x] regression suite: `<cmd>` exit=0 passed=k/k
- [x] every plan-promised test present & passing
```
Self-check: `compass.sh scan-receipt .claude/builds/<slug> review-build`. **Then require a HUMAN sign-off** (AskUserQuestion): show the receipt's command+output lines (the falsifiable evidence, not a summary) and ask the user to Approve before CLOSED. On approve: `progress.md` = `CLOSED`; INDEX `status=closed`; run `compass.sh close .claude/builds/<slug> <slug>` (clears CURRENT). Then the build may proceed to `compass:ship` (or close if deploy is out of scope).
**Standalone STOP:** report the result; no further outward action.
