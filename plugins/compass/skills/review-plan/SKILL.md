---
name: review-plan
description: Review-2 (FULL) — adversarially pressure-test the PLAN before build via a multi-agent fan-out (traceability, invariants, migration, deps, blast-radius, rollback, tests, reconciliation, perf, security, secrets). Two clean rounds; cap 3; un-converged escalates to the contract. Trigger after compass:plan, or on "review the plan", or the Compass orchestrator.
---

# compass:review-plan  (Review-2 · FULL)

Lens: **will this plan, built exactly as written, work — and break nothing else?**

## Step 0 — gate
Run `compass.sh gate .claude/builds/<slug> plan`. **Non-zero → STOP**, offer `compass:plan`. Read `contract.md` + `plan.md`. Set `progress.md` = `in-review (R2)`.

## Engine
- **Ledger** (create if absent): same columns as the other reviews.
- **Material** = new Critical/Major. **Clean round** = zero new material AND the deterministic checks re-ran green. **Proof-of-work:** the footer carries evidence or it doesn't count — `> Round N (R2): checks=\`<cmd>\` exit=0; new Crit/Maj=0. Clean? yes`. **Converged = two consecutive clean rounds.** Cap **3**.
<!-- BUGBAR:START -->
- **Severity bug-bar — every ledger `Severity` cell MUST cite one clause.** **CRITICAL** — data loss/corruption · a security or commercial leak · a wrong number that ships · an unassertable INVARIANT · an irreversible migration · prod-down. **MAJOR** — wrong behavior with a workaround · a drift-prone duplicated canonical set · a missing guard on a reachable path. **MINOR** — cosmetic / log-wording.
<!-- BUGBAR:END -->
- **Self-refutation (before a Critical/Major counts):** in the Root-cause cell, record that the triggering input is **reachable from a real entry point** AND that it is **not already guarded** (no existing guard handles it); an unreachable or already-guarded finding is downgraded or dropped — it never resets convergence.
- **Dedupe & rank:** collapse findings that share a root cause into ONE parent row; present **Critical-first**; the round footer names the **top blocker** (not just a count). Derive expected behavior from `contract.md` **before** reading `plan.md`'s implementation (**contract before** plan — the contract wins on any divergence).
- **Fan-out economy:** round 1 spawns all groups; **rounds 2+ spawn ONLY the agent groups whose surface the last round's fixes touched** — the full deterministic suite still re-runs every round (that, not re-spawning every agent, is what guards un-reviewed surfaces). A confirming clean round with no new fixes = just the suite re-run + footer. A fix is closed only when its Validation command is **re-run with fresh output**; agent agreement is not evidence.
- **Cap 3 un-converged = NOT converged** → contract likely under-specified → **`compass.sh supersede .claude/builds/<slug> contract` then STOP and escalate to `compass:contract`** with the open questions.

## Grounding
Plan delivers the WHOLE contract, nothing it forbids. Drifting step / un-stepped requirement = CRITICAL. **Every INVARIANT → a NON-deferred bound-asserting check** (missing/vague/deferred = CRITICAL).

## Streams — fan out as 6 agents (each emits ONE ledger row per check it covers; coverage = the checks, not the agent count)
- **[A] Spec coverage:** traceability (every requirement → step) · INVARIANT-assertion coverage (each → a non-deferred exact-bound check) · test plan (deterministic tests incl. reconciliation, web tokens + a11y, idempotency).
- **[B] Data & migration:** DB/migration safe, reversible, rolling-deploy-safe with a real dry-run-on-a-copy step · reconciliation feasibility — the query recomputes toward the **independent** gold (greenfield carve-out: no data yet → post-data acceptance check, don't bounce the plan).
- **[C] Interfaces & blast radius:** dependencies (installs/pins are explicit steps) · API back-compat + idempotency · blast-radius/regression — each risk has a guarding test.
- **[D] Operability:** rollback & rollout (undo without data loss) · performance/scale at the contract's volume + concurrency.
- **[E] Security/RBAC/cost** — *independent agent* (keep separate; the adversarial independence is load-bearing).
<!-- RBACSTRIDE:START -->
- **STRIDE + role×resource RBAC-matrix + IDOR method (F-RBACSTRIDE):** for every NEW view/endpoint the build adds, run this method — byte-inert (**N/A**) when the build adds **no new view/endpoint**:
  1. **Role×resource matrix** — build one (every role × the view/endpoint's resources+actions) and **assert each cell against the contract's role×view allow/deny matrix**; a cell the contract doesn't cover, or a matrix-vs-contract mismatch, is a finding.
  2. **Under-declared guard** — a new view/endpoint added while the contract's role×view is **N/A / absent** is itself a **CRITICAL** finding: build the matrix from the ACTUAL roles/resources you observe and challenge the N/A — **never trust a disprovable N/A** (the under-declared-surface / KAM-cross-visibility class).
  3. **STRIDE-walk** each surface — one line each for Spoofing / Tampering / Repudiation / Info-disclosure / DoS / Elevation.
  4. **IDOR probe** — as each LOWER role, fetch another tenant's / another owner's object id on the new endpoint and **assert 403 / empty** — never another tenant's data.
  5. **Consequence** — a deny cell that returns data, a non-403 on the IDOR probe, or any unasserted cell → a **CRITICAL that blocks CLOSED**.
  Wire the repo's **`permission-matrix`** skill as the matrix tool **when present** (optional — follow the method manually if it is not installed; never a hard dependency).
<!-- RBACSTRIDE:END -->
<!-- COMMSCAN:START -->
- **Commercial-sensitivity scan (F-COMMSCAN):** every business-facing view/API is scanned for **IRR / take-rate / gross-revenue% / COF** on a non-management surface — any hit is a **CRITICAL** that blocks CLOSED. Field set canonical to the `commercial-sensitivity-guard` skill; this delimited block is byte-identical across the review skills so the set can't silently drift.
<!-- COMMSCAN:END -->
- **[F] Secret-leak** — *independent agent*: no planned harness embeds a real cookie/JWT/key (`compass.sh secret-scan`).

## Procedure → emit
Round 1: all 6 groups → ledger + fixes applied to `plan.md`. Rounds 2+: only the groups the fixes touched, plus the full suite re-run + footer (a confirming round with no new fixes = suite re-run only). Two clean rounds → `progress.md` = `Plan LOCKED`. **EMIT RECEIPT**:
```
## RECEIPT — review-plan · <slug> · PASS
- [x] gate: plan receipt OK
- [x] all 6 groups run; every INVARIANT → non-deferred bound-asserting check
- [x] RBACSTRIDE: role×resource matrix asserted vs contract + IDOR probed (403/empty), or N/A — no new view/endpoint
- [x] migration dry-run-on-copy present; rollback path exists; deps are explicit steps
- [x] reconciliation feasible toward INDEPENDENT gold (or greenfield carve-out)
- [x] secret-scan of planned harness: `compass.sh secret-scan .` → 0 hits
- [x] converged in <n> rounds; progress.md = Plan LOCKED
```
Self-check: `compass.sh scan-receipt .claude/builds/<slug> review-plan`.

<!-- FEYNMAN -->
## In plain words — where we are and what's next
**What just happened.** A team of independent reviewers — security, database safety, back-compat, performance, secret-leaks — each starting fresh, tried to tear the plan apart.
**Why it matters.** Catching a design flaw now is far cheaper than mid-build. I loop until two clean rounds in a row, and the last round re-attacks the fixes themselves — agreement isn't evidence, a passing command is.
**Your options:**
- **Approve & continue** — move to build (execute the plan, one proof-gated step at a time).
- **Revise** — re-run the review with a change you name.
- **Amend** — a real scope change: bump the contract and re-review just the delta.
- **Pause** — stop cleanly; you resume exactly here, nothing lost.
**My recommendation.** Approve & continue once two clean rounds land.
Progress — ④ plan pressure-tested · next: ⑤ build.
<!-- CONFIDENCE -->
**The rigor I'm applying, so you can trust the machine:** "A team of independent reviewers — one each for security, database safety, back-compat, performance, and secret-leaks — tried to tear the plan apart, each starting fresh so they don't just agree with each other. I keep looping until two clean rounds in a row, and the last round re-attacks the fixes themselves. Agreement isn't evidence; a passing command is."

<!-- GATE:START -->
## Stage transition — the gate (fires on EVERY entry path)

This stage owns its own transition gate. Present it whether the stage was run standalone
(bare skill, e.g. `/build`), via the namespaced command (`/compass:build`), or sequenced by
`/compass:start`. The orchestrator does **not** present a second gate — the stage owns it.

1. First print the one-line **transition footer**, in exactly this shape:

   `✓ <this stage> PASSED — <one-line proof>.  Next: <next stage> · run \`/compass:<next stage>\`.`

   (For the terminal `ship` stage, Next is `done — build SHIPPED`.)

2. Then present the gate using **AskUserQuestion** with exactly these **4 options**
   (AskUserQuestion caps at 4; "Show full artifact" is offered via the auto-provided **Other**,
   or just print the artifact if the user asks):
   - **Approve & continue** — advance to the next stage.
   - **Revise** — re-run this stage with the user's change.
   - **Amend** — a legitimate scope change (not drift): bump the contract version + changelog,
     run a mini review-contract on the delta, `supersede` downstream, re-baseline.
   - **Pause here** — stop cleanly; write the resume pointer to `progress.md`.

Only **Approve** or **Amend** advances. **Never auto-invoke the next skill** — the gate ASKS;
it does not advance by itself. On any detected drift from `contract.md`, STOP and surface
instead of advancing.
<!-- GATE:END -->
