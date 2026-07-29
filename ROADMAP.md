# Compass — Roadmap

Compass is a contract-first build lifecycle (**contract → review → plan → review → build → review → ship**) that makes AI-assisted builds ship true to spec with zero drift.

This roadmap is a **three-phase program** to make every stage-agent world-class *and* make the whole tool legible to a first-time user — grounded in a multi-agent audit of all five stage-agents.

**Where we are:** **Phase 1 shipped (v0.15.x).** **Phase 2 contract 1 — "survive the cutover" — shipped (v0.16.0).** The rest of Phase 2 and all of Phase 3 are planned below.

**How it's delivered:** each phase is a set of **focused, independently-shippable contracts run sequentially** — never one mega build. A single contract with too many invariants can't converge in review (Compass's own `review-build` has a hard cap and a "split rather than grind" rule), so the roadmap is deliberately chunked; each build's regression tests raise the floor that protects the next.

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

## Phase 2 — Make a production cutover survivable

*The infrastructure and review method that make prod cutover safe. Each group below is its own contract.*

**Survive the cutover  ✅ Shipped (v0.16.0, contract 1)**
- Canary / progressive rollout — deploy to a slice, reconcile against it, promote only on green.
- Bake window — a required soak under load before the terminal SHIPPED write.
- Burn-rate auto-abort — metric thresholds that fire the rehearsed rollback automatically.
- Named watcher / on-call — or the auto-abort armed as its substitute.
- Abort sentinel — halt an autonomous build cleanly mid-flight, before any bulk mutation.

**Turn named review checks into methods**
- STRIDE + a role×resource RBAC matrix per view/endpoint + an IDOR probe.
- Boundary/edge checklist (null, zero, one, max, off-by-one, unicode, timezone + DST, month/year rollover).
- Concurrency / TOCTOU analysis — name the losing race, assert the guard.
- Perf budget pinned as a literal INVARIANT (p95 latency, peak memory, cost).
- Per-dependency FMEA — behavior when each external dependency is slow / down, plus mitigation.
- Perf anti-pattern hunt (N+1, paginationless, O(n²)) + observability SLO thresholds (a healthy range per signal).
- Compliance / PII plan gate — what's logged, retention, residency, no regulated field crossing into an out-of-scope view.
- Screenshot secret hygiene — extend the secret scan to images.

**Data & migration safety**
- Expand/contract migration phasing — destructive changes ship as a separate, later build after the additive one bakes.
- Backfill reconciliation — tie backfilled values to their source by count + checksum.
- Rollback forward-compat — prove old code can read data new code wrote before allowing a revert.
- Cross-table invariant enforcement — DB-constraint level (child sums to parent, no orphan FK, one active generation), not app-only.
- Green-CI merge gate; field-level schema pin at contract.

---

## Phase 3 — Make Compass self-improving

*Feedback loops, test rigor, and durability. Each group is its own contract.*

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

- **Rebuild the `compass-visual` Brief generator.** Its free-form-markdown parsing proved fragile during Phase 1's post-ship review (multiple fidelity bugs). Rebuild it on strict/structured input, or re-scope the *shareable* Brief to explicitly best-effort. (The local Brief the user locks against is faithful; the shareable-copy scrub is the weak part.)
