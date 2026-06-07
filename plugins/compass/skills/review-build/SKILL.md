---
name: review-build
description: Review-3 (FULL) — the final adversarial review of the BUILT product. Multi-agent fan-out that assumes every feature is broken until proven, grounds every claim with a re-run check, and enforces reconciliation (script PASS/FAIL vs independent gold), design+a11y fidelity, exercised rollback, wired observability, idempotency, and no committed secret. Ends with a required human sign-off. Converges on two consecutive clean rounds; cap 5. Trigger after compass:build or when the user says "review the build", "final review", "is this ready to ship".
---

# compass:review-build  (Review-3 · FULL)

Lens: **is the BUILT thing correct, complete vs the contract, and safe — proven, not vibed?**

## Step 0 — gate
Run `compass.sh gate .claude/builds/<slug> build`. **Non-zero → STOP** (build incomplete), offer the right earlier stage. Read `contract.md` + `plan.md`. Set `progress.md` = `in-review (R3)`. Check the product against the contract feature-by-feature.

## Engine
- **Ledger** (create if absent): same columns.
- **Material** = new Critical/Major. **Clean round** = zero new material AND the regression suite RE-RUNS green. **Proof-of-work footer:** `> Round N (R3): suite=\`<cmd>\` exit=0 passed=k/k; reconcile→PASS; new Crit/Maj=0. Clean? yes` — no command line = not clean. **Converged = two consecutive clean rounds.** Cap **5**.
- Diff-scope what you review but **always re-run the full fleet** before calling a round clean. Closure = Validation command **re-run with fresh output.** **Agent agreement is not evidence.**
- **Cap 5 un-converged** → plan flaw → `compass.sh supersede .claude/builds/<slug> plan`, escalate to `compass:plan` (or `contract` if the premise is false).

## Streams (assume each FAILS until proven)
1. **Feature failure modes** — empty/huge data, concurrency, partial input, permission edges.
2. **Completeness vs contract** — every requirement built AND demonstrated with a re-run check.
3. **Reconciliation (script gate)** — run the query, then `compass.sh reconcile <actual> <gold> <tol>`. **Non-zero = CRITICAL, blocks CLOSED.** Re-check the dup / fan-out / source-table bug-classes. Gold is the contract's independent published figure.
4. **Design + a11y (web)** — assert computed CSS vs tokens; contrast/focus-visible/keyboard reachability; **visual diff vs reference ONLY if the contract named one.**
5. **Regression** — run the repo's own suite.
6. **Security/RBAC/data-leakage.**
7. **Secret-leak** — `compass.sh secret-scan .` over the diff + every kept verify spec. **Any hit = CRITICAL, blocks CLOSED.**
8. **Performance/OOM/scale** at the contract's volume + concurrency.
9. **DB/migration integrity** — **rollback ACTUALLY exercised on a copy** (forward+back, row-count + checksum identical), not just asserted.
10. **Observability wired** — the contract's named metric/log actually EMITS (don't accept prose).
11. **Idempotency** — run the job/request twice; assert identical end-state, no double-write.
12. **Verification audit** — every "works" backed by a real command + fresh output; screenshot-only proof of a number/token = a finding. · **Test coverage** — every plan-promised test present and passing (not just the repo suite).

## Procedure → emit → human sign-off
Round 1 fan-out → ledger + fixes; re-validate by RE-RUNNING commands; rounds 2+ diff-scoped + re-run full suite. Two clean rounds → **EMIT RECEIPT** (one line per asserted thing, with command + output):
```
## RECEIPT — review-build · <slug> · PASS
- [x] gate: build receipt OK; 12 streams run
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
