---
description: Start (or continue) the Compass contract-first build lifecycle — contract → review → plan → review → build → review → ship — with user-driven gates between every stage, real receipt-gated transitions, auto-pause when context runs low, and clean cross-session resume.
---

# /compass:start — the lifecycle orchestrator

Compass builds software **true to spec, with zero drift**. The contract is the invariant; every stage is checked against it. You sequence the skills, but **you never auto-advance** — each transition is a user-driven gate, AND each downstream stage runs a real script gate that blocks on missing proof.

> Namespaced invocations: `/compass:start`, `/compass:contract`, `/compass:review-contract`, `/compass:plan`, `/compass:review-plan`, `/compass:build`, `/compass:review-build`, `/compass:ship`. Resume with `/compass:resume`.

## State (file-based, resumable)
All in `.claude/builds/<slug>/`:
- `contract.md` — the versioned locked invariant (amendments bump the version + re-lock).
- `plan.md` — the step checklist; its checkboxes are the **authoritative** build-progress record.
- `review-ledger.md` — issues across all reviews (first review creates it).
- `progress.md` — the cursor: status ∈ `{draft, in-review (Rn), contract-LOCKED, plan-LOCKED, CLOSED, SHIPPED, ROLLED-BACK}`. Reviews set `in-review (Rn)` at their START.
- `receipts.md` — each stage's **receipt** (commands + outputs). **The teeth:** every downstream Step-0 runs `compass.sh gate <build-dir> <prior-stage>`, which exits non-zero — a hard, un-skippable error — if the prior receipt is absent, FAIL, has an unchecked `[ ]`, or is SUPERSEDED. Escalation/re-run calls `compass.sh supersede` to void downstream receipts so they must re-run.

**`.claude/builds/CURRENT`** = a non-authoritative *hint* of the last active slug (cleared on CLOSE). With parallel builds it can NOT disambiguate — resume derives identity from the worktree (see resume). **`.claude/builds/INDEX`** = every build (`slug · goal · status · facets · touches`). Plan rewrites `touches` with the real file list from Phase 0; before planning, if another in-flight build's `touches` overlap, **surface it and ask**.

> **State path:** skills resolve state via `compass.sh state-root` (returns the *main checkout's* `.claude/builds`), so a skill running inside a build's worktree still reaches the one canonical state. Never hardcode `.claude/builds` from inside a worktree.

## Parallel builds (worktree isolation — the keystone)
A repo may run **N builds at once** (incl. one unattended). The rule: **one git worktree per build**, so no two builds share a working directory (this is what stops one build's `git add -A` sweeping another's files). Auto-on when `compass.sh active-builds` shows another in-flight build (or `--parallel`); single-build runs stay in the main checkout unchanged.

On `start` in parallel mode:
1. `compass.sh gc` — sweep terminal-build worktrees first.
2. If another build is active **and still in the main checkout**, `compass.sh promote <that-slug>` BEFORE starting the new one (never leave the first build in the shared checkout on a prose warning).
3. **DB isolation gate:** if this build changes schema, the contract MUST declare `isolation.db_provision`/`db_teardown` (per-worktree DATABASE_URL). `compass.sh check-db-isolation <slug> <has-schema:0|1> <provision-declared:0|1>` REFUSES a schema-touching parallel build with no isolation — concurrent migrations on one dev DB corrupt it.
4. `compass.sh worktree <slug>` → its folder+branch (runs `db_provision` if declared); `compass.sh install-guard` (once); then `claim` at build start.
5. Tell the user the worktree path + the one-time `npm ci` / `source .env.compass` step, and that **all build work happens in that worktree** (`cd` there).

**Unattended runs** (`--unattended`): gates write the resume banner and `exit 0` instead of asking; a guard rejection writes a receipt **FAIL** and stops (never retries → no livelock). Only proceed when the prior stage receipt is PASS.

## The pipeline
```
① contract ─gate→ ② review-contract ─gate→ [contract-LOCKED]
   ─gate→ ③ plan ─gate→ ④ review-plan ─gate→ [plan-LOCKED]
   ─gate→ ⑤ build ─gate→ ⑥ review-build ─(human sign-off)→ [CLOSED]
   ─gate→ ⑦ ship (optional; skip if contract marks deploy out of scope) → [SHIPPED]
```
- Reviews converge first: **light = one clean pass; full = two clean rounds** (caps R1=2, R2=3, R3=5). Cap un-converged escalates UP (and supersedes) — plan→contract, build→plan, contract→user — never fakes done.
- **review-build requires a human sign-off** on the receipt's command+output evidence before CLOSED.

## The gate (between every stage — never auto-advance)
Present a short summary, then **AskUserQuestion** with five options:
1. **Approve & continue** — advance to the next stage.
2. **Revise** — re-run this stage with the user's change.
3. **Amend contract** — a *legitimate scope change* (not drift): bump the contract version + changelog, run a mini review-contract on the delta, `supersede` downstream, re-baseline. This is how Compass distinguishes scope-change (goes through amendment) from drift (blocked).
4. **Pause here** — stop cleanly; write the resume pointer.
5. **Show full artifact** — print the complete file, then ask again.

Only **Approve**/**Amend** advance. Every later stage reads `contract.md` as the invariant; on detected drift, STOP and surface.

## Standalone / budget
Each skill works alone and self-gates via `compass.sh gate` (missing proof = hard stop, never fabricated). If the contract set a **budget**, surface "approaching budget" and stop-with-summary rather than grinding to a cap.

## Clean stage transitions (never go quiet)
**A long build must never leave the user wondering where it is.** Every stage ends with a one-line **transition footer** before the gate, in this exact shape — what just passed, what's next, and the exact command:
```
✓ <stage> PASSED — <one-line proof>.  Next: <stage> · run `<exact command>`.
```
Then present the 5-option gate. After any pause/interrupt, `/compass:status` reprints this. Mid-build, surface step `k/n` after each step. Silence is a defect.

## Auto-pause
The pre-compact hook fires an *advisory* reminder only — it can't write for you and compaction can't be deferred. The real safety net is per-step discipline (progress.md fresh after each step; a box never checked before its verify passes; a build IN-PROGRESS receipt per step), so a lost compaction costs at most one step. On the hook OR **Pause**: write `progress.md` first, then print the **elegant hand-off — exactly one clean, copy-paste-ready fenced block and nothing interleaved** (the shell command to open the build, then the resume command):
```
cd "<abs PROJECT root, where .claude/ lives>" && claude
```
Then, on its own line, the command to run once Claude starts: `/compass:resume <slug>` — Stage `<stage>`, Next `<the single next action>`. Nothing else on those lines: the user copies the block clean into a new terminal.

## Bottom line
Read `CURRENT`, sequence the stages, gate every hop (script gate + the 5-option user gate), keep the contract as the invariant, prove every "done" with a recorded command, require the human sign-off before CLOSED, and hand off cleanly when context ends.
