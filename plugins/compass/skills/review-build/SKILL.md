---
name: review-build
description: Review-3 (FULL) — the final adversarial review of the BUILT product before close. Multi-agent fan-out that assumes every feature is broken until proven, grounds every claim with a re-run check, and verifies reconciliation (hard PASS/FAIL), design-token fidelity, exercised rollback, wired observability, and no committed secret. Converges on two consecutive clean rounds; cap 5; cap-without-convergence escalates UP. Trigger after compass:build, or when the user says "review the build", "final review", "is this ready to ship", or invokes the Compass orchestrator.
---

# compass:review-build  (Review-3 · FULL)

Lens: **is the BUILT thing correct, complete vs the contract, and safe to ship — proven, not vibed?** The most comprehensive review; every claim backed by a re-run check.

## Step 0 — gate + status
Read `.claude/builds/CURRENT` → slug → `receipts.md`. **If the `build` receipt is absent or FAIL, STOP** and offer the right earlier stage. Read `contract.md` + `plan.md`. **Set `progress.md` status = `in-review (R3)` now.** Check the built product against the contract feature-by-feature.

## Engine (inlined; skill is authoritative)
- **Ledger:** create if absent; columns `Issue ID | Review (R1/R2/R3) | Round # | Affected area | Failure mode | Impacted invariant | Severity | Root cause | Fix | Validation | Owner stream | Status`.
- **Material** = new Critical/Major. **Clean round** = zero new material issues AND the regression suite RE-RUNS green. **Proof-of-work:** footer carries evidence or doesn't count — `> Round N (R3): suite=\`<cmd>\` exit=0 passed=<k>/<k>; reconcile=\`<query>\`→actual=<x> gold=<y> Δ=<%> PASS; new Crit/Maj=0. Clean? yes`. **Converged = two consecutive clean rounds.** Cap **5**.
- Diff-scope what you review, but **always re-run the full fleet** before calling a round clean. **A fix is closed only when its Validation command is RE-RUN with fresh output. Agent agreement is not evidence.**
- **Cap 5 un-converged = NOT converged.** Don't fake a green. Persistent churn → **plan-level flaw → escalate to `compass:plan`** (or `compass:contract` if the build proved the premise false).

## Grounding
A feature that drifted from the contract, or a requirement not delivered, is CRITICAL. **Every INVARIANT must be demonstrated by a passing check asserting its exact bound** — an INVARIANT with no such check is CRITICAL no matter how good the code looks.

## Streams (fan out; assume each FAILS until proven)
1. **Feature-by-feature failure modes** — empty/huge data, concurrency, partial input, permission edges.
2. **Completeness vs contract** — every requirement built AND demonstrated with a re-run check.
3. **Reconciliation (hard gate)** — run the reproducing query; emit `RECONCILE: actual gold tol PASS|FAIL`. **FAIL = CRITICAL and blocks CLOSED, no discretion.** This is the flagship check — treat it as the highest bar.
4. **Design fidelity (web)** — assert computed CSS vs the contract tokens (color/type/spacing); **visual diff vs the reference ONLY if the contract named a reference artifact** (else skip — don't claim a check that has no input).
5. **Regression** — did any existing feature/workflow the change touched break? Run the repo's own suite.
6. **Security / RBAC / data-leakage** — can a user see/do what they shouldn't? Auth coupling, tenant isolation.
7. **Secret-leak** — scan the diff + every kept verify spec for committed cookies/JWTs/keys/connection-strings/`*_SECRET`. **Any hit = CRITICAL, blocks CLOSED.** (Rishi's repeated burn — a named stream, not silence.)
8. **Performance / OOM / scale** — at the contract's stated volume + concurrency; use the repo's perf/load scripts.
9. **DB / migration integrity** — applied cleanly on prod-like data; **rollback ACTUALLY exercised** on a copy (forward+back, row-count + checksum identical), not just asserted reversible.
10. **Observability wired** — the exact metric/log the contract named actually exists and EMITS (don't accept a prose observability section as done).
11. **Verification audit** — every "it works" backed by a real command + fresh output? Faith = a finding. A screenshot-only "proof" of a number/token = a finding.
12. **Test coverage** — the deterministic tests the plan promised are present and passing.

## Procedure
1. Round 1 full fan-out → ledger + fixes + each fix's Validation command. 2. Fix, then **re-validate by RE-RUNNING the command** (Playwright for flows; prod = read-only). 3. Rounds 2+ diff-scoped + re-run the full suite. 4. Two consecutive clean rounds → `progress.md` = CLOSED; set the build's INDEX line `status=closed`. 5. **EMIT RECEIPT**:
   ```
   ## RECEIPT — review-build · <slug> · PASS (CLOSED)
   - [x] build receipt present; all 12 streams run
   - [x] every INVARIANT demonstrated at its exact bound
   - [x] RECONCILE PASS (actual=gold within exact tolerance)   or N/A
   - [x] no secret committed anywhere (diff + specs scanned)
   - [x] rollback exercised on a copy; observability emits
   - [x] regression suite re-ran green: <cmd> exit=0 passed=k/k
   - [x] converged in <n> rounds; progress.md = CLOSED
   ```
6. **Standalone STOP:** report the result; take no further outward action. Under the orchestrator, hand to the final gate.

## Sign-off (each PROVEN)
Every feature survives edge/scale/permission stress · contract fully delivered · every INVARIANT bound-asserted · **RECONCILE PASS** · design tokens render as specified · no regression (suite green) · no RBAC/data leak · **no committed secret** · rollback exercised · observability emits · perf bar met at scale · every "works" claim has a recorded fresh check · promised tests present and passing · receipt PASS. Only then is the build **closed**.
