---
name: review-build
description: Review-3 (FULL) — the final adversarial review of the BUILT product before close. Multi-agent fan-out that assumes every feature is broken until proven otherwise, grounds every claim with a real check (verify-ladder), and loops to convergence. Caps at 5 iterations; real stop is 2 consecutive clean rounds. Cap-without-convergence escalates UP to the plan. Trigger after compass:build, or when the user says "review the build", "final review", "is this ready to ship", or invokes /compass.
---

# compass:review-build  (Review-3 · FULL)

Lens: **is the BUILT thing correct, complete vs the contract, and safe to ship — proven, not vibed?** The most comprehensive review: multi-agent fan-out, every claim backed by a real check. Uses `../shared/review-core.md` and `../shared/verify-ladder.md`. Cap **5** iterations; real stop = **2 consecutive clean rounds**.

## Grounding (first)
Read `contract.md` (the invariant) and `plan.md`. Check the built product against the contract feature-by-feature. A feature that drifted from the contract, or a contract requirement not actually delivered, is a CRITICAL finding.

## Streams (fan out in parallel; assume each FAILS until proven)
1. **Feature-by-feature failure modes** — for every feature, how does it break? Empty data, huge data, concurrent users, partial input, permission edges.
2. **Completeness vs contract** — every contract requirement actually built AND demonstrated with a real check?
3. **Regression** — did any existing feature/workflow the change touched break? Run the repo's own test suite.
4. **Security / RBAC / data-leakage** — can a user see/do what they shouldn't? Auth coupling, tenant isolation.
5. **Performance / OOM / scale** — at real volume and concurrency: load time, memory, N+1, single-DB bottleneck. Use the repo's perf/load scripts if they exist.
6. **DB / migration integrity** — did the migration apply cleanly on prod-like data? Reversible? Data consistent post-migration?
7. **Verification audit** — is every "it works" claim backed by an actual command + output (verify-ladder), or is something asserted on faith? Faith = a finding.
8. **Test coverage** — are the deterministic tests the plan promised present and passing? Gaps = findings.

## Procedure (the convergence loop)
1. Round 1: full fan-out. Merge into `review-ledger.md` with concrete fixes + the validation each fix needs.
2. **Fix**, then **re-validate with a real check** (verify-ladder — Playwright for flows, not Chrome MCP).
3. Rounds 2+: diff-scoped re-review of only what the fixes touched + re-run checks.
4. **Stop when 2 consecutive rounds surface no new material issue** (converged) → ready to ship. Or at cap 5.
5. **Cap 5 without convergence = NOT converged.** Don't fake a green. Persistent churn means a **plan-level design flaw** → STOP and escalate UP to `compass:plan`.

## Sign-off (all must hold, each PROVEN)
Every feature works under edge/scale/permission stress · contract fully delivered · no regression (suite green) · no RBAC/data leak · perf bar met at real scale · migration clean + reversible · every "works" claim has a recorded real check · promised tests present and passing. Only then is the build **closed**.
