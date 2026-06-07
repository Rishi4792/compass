---
name: review-build
description: Review-3 (FULL) — the final adversarial review of the BUILT product before close. Multi-agent fan-out that assumes every feature is broken until proven otherwise, grounds every claim with a real check (verify-ladder), and verifies reconciliation-to-the-gold-figure and design-token fidelity. Converges on two consecutive clean rounds; cap 5; cap-without-convergence escalates UP to the plan (or contract if the premise is false). Trigger after compass:build, or when the user says "review the build", "final review", "is this ready to ship", or invokes the Compass orchestrator.
---

# compass:review-build  (Review-3 · FULL)

Lens: **is the BUILT thing correct, complete vs the contract, and safe to ship — proven, not vibed?** The most comprehensive review: multi-agent fan-out, every claim backed by a real check.

## Prerequisite check (Step 0)
Read `.claude/builds/CURRENT` → slug → `contract.md` AND `plan.md`. **If there's no built product / no `plan.md`, STOP** and offer the right earlier stage. Check the built product against the contract feature-by-feature.

## Engine (inlined — canonical spec is `shared/review-core.md`)
- **Ledger:** create `review-ledger.md` if absent; append-only rows, `Status` in place; columns include `Review(R3) | Round#`; per-round footer `> Round N (R3): k new Critical/Major, m new Minor. Clean? y/n.`
- **Material** = new Critical or Major. **Clean round** = zero new material issues AND the regression suite RE-RUNS green (diff-scope what you review, but always re-run the full fleet before calling a round clean — a regression on an un-reviewed surface must not slip through). **Converged = two consecutive clean rounds.** Cap **5**.
- **A fix is "closed" only when its Validation command is RE-RUN with fresh output recorded.** Re-reading the diff or a subagent agreeing is NOT closure. **Agent agreement is not evidence.**
- **Cap 5 without convergence = NOT converged.** Don't fake a green. Persistent churn → a **plan-level design flaw → STOP and escalate to `compass:plan`** (or `compass:contract` if the build proved the contract's premise false).

## Grounding (first)
A feature that drifted from the contract, or a contract requirement not actually delivered, is CRITICAL. **Every contract INVARIANT must be demonstrated by a passing check that asserts its exact bound** — an INVARIANT with no such check is CRITICAL, no matter how good the code looks.

## Streams (fan out; assume each FAILS until proven)
1. **Feature-by-feature failure modes** — empty data, huge data, concurrent users, partial input, permission edges.
2. **Completeness vs contract** — every requirement built AND demonstrated with a real check.
3. **Reconciliation** — run the contract's reproducing query; the headline number must equal the gold figure within tolerance. Off by more than tolerance = CRITICAL (this is the flagship check — treat it like RBAC).
4. **Design fidelity** — assert computed CSS against the contract's tokens (color/type/spacing) via DOM checks; visual diff vs a reference if one exists. Specified tokens that aren't actually rendered = a finding.
5. **Regression** — did any existing feature/workflow the change touched break? Run the repo's own test suite.
6. **Security / RBAC / data-leakage** — can a user see/do what they shouldn't? Auth coupling, tenant isolation.
7. **Performance / OOM / scale** — at the contract's stated volume + concurrency: load time, memory, N+1, single-DB bottleneck. Use the repo's perf/load scripts.
8. **DB / migration integrity** — applied cleanly on prod-like data? Reversible? Data consistent post-migration?
9. **Verification audit** — is every "it works" claim backed by an actual command + fresh output, or asserted on faith? Faith = a finding. Screenshot-only "proof" of a number/token = a finding.
10. **Test coverage** — are the deterministic tests the plan promised present and passing?

## Procedure
1. Round 1: full fan-out → ledger with concrete fixes + each fix's validation command. 2. **Fix**, then **re-validate by RE-RUNNING the command** (Playwright for flows; prod = read-only). 3. Rounds 2+: diff-scoped re-review + re-run the full suite. 4. Two consecutive clean rounds → update `progress.md` (status = CLOSED) → ready to ship. 5. **Standalone STOP:** report the result; don't take further outward action. Under the orchestrator, hand to the final gate.

## Sign-off (all must hold, each PROVEN)
Every feature works under edge/scale/permission stress · contract fully delivered · every INVARIANT demonstrated by a bound-asserting check · reconciliation ties to the gold figure within tolerance · design tokens render as specified · no regression (suite green) · no RBAC/data leak · perf bar met at real scale · migration clean + reversible · every "works" claim has a recorded fresh check · promised tests present and passing. Only then is the build **closed**.
