# Compass — Adversarial Review Findings (v0.1.0)

> Three independent agents reviewed Compass end-to-end (mechanical / architecture / methodology) on 2026-06-07.
> Status: OPEN → FIXED as each is resolved. Severity: 🔴 Critical · 🟠 Major · 🟡 Minor.

## Mechanical corrections (confirmed against current Claude Code docs)
- Hooks via `hooks/hooks.json` auto-discovery is VALID; `PreCompact` + `systemMessage` are real → original "hooks broken" finding was wrong. **No fix needed.**
- `author` object, relative marketplace `source`, and auto-discovery of `skills/`/`commands/` are all VALID. **No fix needed.**

---

## 🔴 CRITICAL

| # | Area | Problem | Fix | Status |
|---|------|---------|-----|--------|
| F1 | All skills | `../shared/*.md` cross-refs don't resolve at runtime (`${CLAUDE_PLUGIN_ROOT}` works in JSON only, not skill markdown; cwd is unknown). Shared engine is a dead reference. | Make every skill self-contained — inline the engine rules it needs. Keep `shared/*.md` as the canonical human-readable spec the README points to. | FIXED |
| F2 | `commands/compass.md`, README | Plugin commands are always namespaced → `/compass` actually registers as `/compass:compass`; `/compass resume` won't exist. | Split into two clean commands: `/compass:start` (orchestrator) and `/compass:resume`. Update all docs to real invocations (`/compass:contract`, etc.). | FIXED |
| F3 | resume, `commands`, `contract` | The build `<slug>` is recorded nowhere → on resume the orchestrator can't tell which `.claude/builds/<slug>/` is current; with two builds it guesses. | Add a fixed pointer file `.claude/builds/CURRENT` holding the active slug. Contract writes it; orchestrator updates it at every gate; resume reads it first. | FIXED |
| F4 | `review-core.md`, reviews | No skill creates `review-ledger.md`; ledger schema has no Review/Round columns → "2 clean rounds" can't be audited from the file. | review-core OWNS ledger creation ("create if absent"); add `Review (R1/R2/R3)` + `Round #` columns + a per-round footer line so convergence is computable, not vibes. | FIXED |
| F5 | `review-core.md`, `review-contract` | Stop rule self-contradicts: "2 consecutive clean rounds" vs contract cap 2 vs review-contract's "one clean pass." Unreachable for the light review. | Define once, numerically. Light review converges on **1 clean pass**; full reviews on **2 consecutive clean rounds**. State explicitly in both files. | FIXED |
| F6 | `review-core.md`, `review-contract` | "Escalate UP a level" has no level above contract → contract review at cap is an unhandled dead end. | Define the terminal case: contract review at cap → hand back to the USER with the open questions (there is no higher level). | FIXED |
| F7 | `progress.md` lifecycle | Only `contract` + `plan` update `progress.md`; reviews + build don't → after a standalone build the resume cursor lies. No skill owns the LOCKED status flip. | Every skill updates `progress.md` as its last action (build after each step). Declare precedence: `plan.md` checkboxes are authoritative for build progress; `progress.md` is a pointer. Reviews flip status to LOCKED on sign-off. | FIXED |
| F8 | `verify-ladder.md`, `build` | Playwright (rung 5) is a stub: no install guidance, auth is one word ("prod cookie"), and it would drive PROD for steps that WRITE data — a data-integrity landmine. | Add a "Rung 5 prerequisites" block: toolchain install; concrete auth recipe + "how to tell auth failed" first-line assertion; hard rule **prod = read-only asserts only, write-flows run against local/staging**. | FIXED |
| F9 | `verify-ladder.md` | "Claude reads the screenshots back" = the LLM-eyeballing the ladder bans one line earlier. Can't tell ₹12.4 from ₹12.7Cr or one hex from another. | Demote screenshot to layout/rendering sanity only. Numbers → assert exact DOM text vs a rung-2 value. Tokens → assert computed CSS. Screenshot is supporting evidence, never the proof. | FIXED |
| F10 | `contract`, `review-build`, `plan` | Reconcile-to-a-goal (the flagship need) is one optional bullet — no required field, no review stream, no build gate. | Make reconciliation first-class: required contract field (*gold source · exact figure · tolerance · reproducing query*), INVARIANT by default for any numeric build; add a **Reconciliation** stream to review-build + plan feasibility. | FIXED |
| F11 | all stages | "Drift = STOP" is self-graded prose; nothing forces a contract INVARIANT (±1%, <2s, RBAC) to become an actual verify assertion. Build can mark "done" while violating the number. | Plan must turn every INVARIANT into a named verify command asserting its exact bound; review-build FAILS if any INVARIANT lacks a passing assertion of its specific bound. | FIXED |

## 🟠 MAJOR

| # | Area | Problem | Fix | Status |
|---|------|---------|-----|--------|
| F12 | all skills | Standalone skills have NO prerequisite check — `build` with no `plan.md` will improvise (the exact drift Compass exists to prevent). Promise lives only in the orchestrator. | Add a Step-0 prerequisite check to every skill: if the required input file is absent, STOP, name what's missing, offer the right earlier stage. Never fabricate it. | FIXED |
| F13 | all skills | Standalone skills can auto-advance — the "stop and ask" gate exists only in the orchestrator; skills "suggest the next stage" and a helpful model chains straight through. | Each skill's standalone hand-off says "STOP here. Do not invoke the next skill yourself — tell the user to run it." | FIXED |
| F14 | `review-core.md` | Diff-scoped rounds 2+ can hide a regression on an un-reviewed surface → two locally-clean rounds ≠ globally clean → false green. | A round counts as clean only if the deterministic test fleet (regression suite) RE-RUNS green — diff-scope what you *review*, but always re-run the full checks before counting a round clean. | FIXED |
| F15 | `review-core.md` | "Material issue" is undefined and self-assessed by the model trying to finish → it can downgrade issues to converge ("fakes done"). | Tie "material" to severity: a round is clean iff it surfaces zero new **Critical or Major** issues. Remove the discretion. | FIXED |
| F16 | `build`, hooks, `commands` | Auto-pause can fire mid-verify (compaction is non-deferrable); progress.md isn't guaranteed fresh; a step's box may be checked before its verify passes. | Hook handler writes progress.md FIRST. Rule: never check a step's box until its verify fully passes and proof is recorded → an interrupted verify always resumes as "pending." | FIXED |
| F17 | `review-build`, `contract` | Design aesthetics are specified then never verified — no design stream in any review while functionality has several. | Add a **Design-fidelity** stream to review-build: assert computed CSS vs the contract's tokens (color/type/spacing) + visual diff vs reference if one exists. Add to sign-off. | FIXED |
| F18 | `contract` | Required-section list misses known drift sources: data volume/scale, auth model, external dependencies, idempotency/retry, rollback meaning, observability. | Add these as required-or-explicitly-N/A sections ("N/A" must be stated, not silently absent). | FIXED |
| F19 | `contract`, `review-contract` | Testability has an escape hatch: hard items get "flagged & deferred to plan," and the capped review converges on a contract full of "assumption: TBD." Drift with a permission slip. | Cap deferred flags: ZERO on INVARIANT/acceptance items; any deferred item must name who/when/how it resolves, else lock is blocked. | FIXED |
| F20 | `plan`, `build` | Forcing "each step has its own verify command" manufactures fake/placeholder verifies for steps that can't be cheaply checked (8M-row backfill, cron, flag). | Allow a step's verify to be **"deferred — proven by step N / post-deploy check X"**, explicitly. "Deferred without a named later proof" is itself a review finding. | FIXED |
| F21 | `review-core.md` | Rounds 2+ "re-validate" often degrades to a subagent re-reading the fix and agreeing — not re-running the command. (His documented "patch reported fixed but wasn't" failure.) | In the loop: a fix is "closed" only when its named Validation command is RE-RUN and its FRESH output recorded. Re-reading the diff is not closure. | FIXED |
| F22 | `build` | No partial-failure story (steps 1–5 shipped, step 6 unrecoverable → what state?); escalation only goes build→plan, but the nasty case is the build revealing the CONTRACT was wrong. | Add: on irrecoverable mid-build failure, leave committed work in a known-good revertible state + record the cursor. Add a build→contract escalation branch for contract-level falsehoods. | FIXED |

## 🟡 MINOR

| # | Area | Problem | Fix | Status |
|---|------|---------|-----|--------|
| F23 | `plan` | "Scan the live prod codebase first" is a STRICT prerequisite with no path for a greenfield (new) project — it'll stall or fabricate. | Add a greenfield branch: if no existing codebase, Phase 0 inventories the chosen stack/conventions/scaffolding instead, and says so. | FIXED |
| F24 | `verify-ladder.md` | Ladder is web-app-shaped (DB/cookie/HTTP); for a CLI/library/pipeline rungs 2–5 don't map. And rung 2 (DB) proves data, not that the UI shows it. | State the real rule is "any deterministic check"; the six rungs are the web-app instance. Add: rung 2 proves data at source, not display — UI/number/token claims cannot stop below rung 5. | FIXED |
| F25 | `review-core.md` | "Append-only ledger" contradicts "apply fixes / mark closed." | Clarify: rows are append-only; the Status cell is updated in place. | FIXED |
| F26 | `commands` | Resume tells user to `cd` to "build root," but `.claude/builds/` is relative to the PROJECT root where `.claude/` lives. | Resume block says `cd` to the project root (where `.claude/` lives), not the build folder. | FIXED |
