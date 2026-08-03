# Compass — Roadmap

Compass is a contract-first build lifecycle (**contract → review → plan → review → build → review → ship**) that makes AI-assisted builds ship true to spec with zero drift.

This roadmap is a **three-phase program** to make every stage-agent world-class *and* make the whole tool legible to a first-time user — grounded in a multi-agent audit of all five stage-agents.

**Where we are:** **Phase 1 shipped (v0.15.x).** **Phase 2 is underway — 5 contracts shipped, v0.16.0 → v0.20.0** ("survive the cutover" · Brief-generator rebuild · STRIDE/RBAC method · boundary + TOCTOU method · per-dependency FMEA + anti-pattern method). The rest is consolidated into **just 2 contracts left**: **Contract 6** finishes Phase 2 (data, migration & compliance safety); **Contract 7** is all of Phase 3 (make Compass self-improving).

**How it's delivered:** each phase is a set of **focused, independently-shippable contracts run sequentially** — never one mega build. A single contract with too many invariants can't converge in review (Compass's own `review-build` has a hard cap and a "split rather than grind" rule), so the roadmap is chunked; each build's regression tests raise the floor that protects the next. The remaining work is consolidated into **2 larger contracts (6 and 7)** — deliberately fuller than the earlier ones; if either can't converge under review's cap, that same "split rather than grind" rule splits it at build time.

---

## Phase 1 — Trust backbone + clarity layer  ✅ Shipped (v0.15.x)

The "80% of the trust for 20% of the effort" slice.

**Trust backbone**
- **Severity bug-bar** — a Critical/Major/Minor rubric every review finding must cite (the convergence gate is no longer game-able).
- **Self-refutation** — a Critical/Major counts only once its trigger is proven *reachable from a real entry point* and *not already guarded*.
- **Dedupe + rank** — same-root-cause findings collapse; presented Critical-first; the round names the top blocker, not a count.
- **Prod-safety floor** — `restore-point` (no destructive migration without a confirmed snapshot) and `config-parity` (no deploy missing a prod env key), wired into ship as hard-stops.
- **Kill-switch / feature-flag spine** — pinned at contract, built flag-off-by-default, proven to disable in prod without a redeploy.
- **Security & data-sensitivity pin** at contract (per-field classification, never-show fields, role×view matrix, STRIDE-lite) + a **commercial-sensitivity scan** in review.

**Clarity / UX layer**
- **`/compass:go`** — a welcome that teaches the mental model (contract-first → an assembly line with gates).
- **Visual Contract Brief** the user explicitly locks, plus a progress **Cockpit**.
- A plain-English **clarity + confidence block** at every stage.
- **Auto-vs-human-gated mode choice** and **`/compass:explain`** for on-demand teaching.

---

## Phase 2 — Make a production cutover survivable  🔨 In progress (5 of 6 contracts shipped)

*The infrastructure and review method that make prod cutover safe. Each group below is its own contract.*

**Survive the cutover  ✅ Shipped (v0.16.0, contract 1)**
- Canary / progressive rollout — deploy to a slice, reconcile against it, promote only on green.
- Bake window — a required soak under load before the terminal SHIPPED write.
- Burn-rate auto-abort — metric thresholds that fire the rehearsed rollback automatically.
- Named watcher / on-call — or the auto-abort armed as its substitute.
- Abort sentinel — halt an autonomous build cleanly mid-flight, before any bulk mutation.

**Turn named review checks into methods**  *(each became its own contract; the review-method "island" pattern — one delimited block byte-identical across review-plan + review-build, smoke-enforced — is reused each time)*
- **STRIDE + a role×resource RBAC matrix per view/endpoint + an IDOR probe.**  ✅ Shipped (v0.18.0, contract 3)
- **Boundary/edge checklist** (null, zero, one, max, off-by-one, unicode, timezone + DST, month/year rollover) **+ concurrency / TOCTOU analysis** — name the losing race, assert the guard.  ✅ Shipped (v0.19.0, contract 4)
- **Per-dependency FMEA** (behavior when each external dependency is slow / down, plus mitigation) **+ perf anti-pattern hunt** (N+1, paginationless, O(n²)).  ✅ Shipped (v0.20.0, contract 5)
**Contract 6 — Data, migration & compliance safety**  ⬜ Planned · **next up** — the remaining Phase-2 hard gates, consolidated into one contract:
- **Data & migration safety** *(the largest piece — likely real new `compass.sh` gates, not just a review method)* — expand/contract migration phasing (destructive changes ship as a separate, later build after the additive one bakes) · backfill reconciliation (tie backfilled values to their source by count + checksum) · rollback forward-compat (prove old code can read data new code wrote before allowing a revert) · cross-table invariant enforcement at DB-constraint level (child sums to parent, no orphan FK, one active generation) · green-CI merge gate · field-level schema pin at contract.
- **Perf-budget pin + observability SLO thresholds** *(deferred out of v0.20)* — pin p95 latency / peak memory / cost as literal INVARIANTs; a healthy range per signal so monitoring is pass/fail.
- **Compliance / PII plan gate** — what's logged, retention, residency, no regulated field crossing into an out-of-scope view.
- **Screenshot secret hygiene** — extend the secret scan to images.

---

## Phase 3 — Make Compass self-improving  ⬜ Planned · Contract 7 (the whole phase, one contract)

*Feedback loops, test rigor, and durability — the three groups below ship as a single contract (Contract 7).*

**Test & correctness rigor**
- Mutation testing — a test that still passes after the implementation is deliberately broken is a fake, and gets flagged.
- Tests-first (red-green) ordering; hermetic web tests (pinned clock/tz, stubbed network, deterministic).

**Operability & feedback**
- DORA ledger on every terminal exit (deploy frequency, lead time, change-failure rate).
- Opt-in drift monitor.
- Cell/region staging + a consumer-contract validator.
- **Program-continuity ledger.** A program-level layer *above* a single build. Today Compass tracks a build (contract → ship) but not the program around it, so a fresh session knows the build and not what comes after it. This adds:
  - a **program ledger** — the phases/builds, the vision, current position, and what's next after each ships;
  - a contract header — `program: <name> · phase K/N` — so a build knows its place and what's a non-goal *this* phase;
  - **ship advances the ledger** on SHIPPED (marks this build done, points to the next);
  - a **program-aware `/compass:go` and resume** — a fresh session reads the ledger and offers *"Phase K shipped → start Phase K+1?"* instead of *"nothing to resume."*

  *(Marked a pull-forward candidate: high value for anyone running a multi-phase program, and the fix for "a fresh terminal knows the build but not the program.")*

**Durability**
- Glossary, problem/context, ADR alternatives, one-way-door vs two-way-door labels, RACI owner.

---

## Debt from shipping Phase 1

- **Rebuild the `compass-visual` Brief generator.**  ✅ Shipped (v0.17.0, contract 2). The fragile free-form-markdown parsing was rebuilt on a structured `compass-brief-data` fence — declared values, and every numeric-locale reformatting of them, now scrub with certainty; absent input is labeled best-effort; malformed input fails closed. The local Brief the user locks against stays faithful and full.
