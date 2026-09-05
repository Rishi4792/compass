---
name: start
description: The Compass lifecycle orchestrator — sequences contract → review → plan → review → build → review → ship with user-driven gates between every stage, real receipt-gated transitions, opt-in autonomous (--auto) mode with two human gates, parallel-build worktree isolation, auto-pause when context runs low, and clean cross-session resume. Invoked by /compass:go for a new build; not a user menu entry (user-invocable:false).
user-invocable: false
---

# compass:start — the lifecycle orchestrator

Compass builds software **true to spec, with zero drift**. The contract is the invariant; every stage is checked against it. This skill sequences the stage skills. It **never advances without being asked** — each transition is a user-driven gate — and since v0.35 an answer of **Approve** is acted on rather than described, so the build continues instead of stopping in silence. Each downstream stage still runs a real script gate that blocks on missing proof.

> The whole lifecycle is driven through the single front door **`/compass:go`**, which reads state and routes into each stage skill (`compass:contract`, `compass:review-contract`, `compass:plan`, `compass:review-plan`, `compass:build`, `compass:review-build`, `compass:ship`). Resume from a fresh terminal with **`/compass:resume`**. The per-stage skills are hidden from the `/` menu (`user-invocable: false`) but Compass invokes them for you — you never have to remember which one.

<!-- DOCTRINE:START -->
**Read these before you start.** They are the standards this stage is held to, and they
live in `plugins/compass/shared/` so they are the same for every stage that uses them:

- **`shared/engine.md`** — how the orchestrator paces a long run, and where it deliberately stops.

(A standard nobody loads is not a standard. `shared/MANIFEST` declares who reads each file and
`doctrine-wired-check.sh` proves it — `feynman.md` sat unread for three releases while its own
first line claimed three stages loaded it.)
<!-- DOCTRINE:END -->

## Compass is a graph

Compass's lifecycle is an explicit directed graph — drawn at design time, never improvised at runtime:

- **The org-graph (fixed):** contract → review-contract → plan → review-plan → build → review-build → ship. Nodes are stages; **edges are script gates** (`compass.sh gate`, exit codes) — the next stage is never chosen by a model.
- **Independent verifier nodes:** the adversarial reviews, the cold-critic (fresh subagent, cold screenshots only, 2 consecutive GOs on one tree sha), and the **post-ship critique loop** (v0.12.0) — a bounded cycle after ship: critique the LIVE system against the contract, loop back on material findings, terminate on N consecutive clean rounds or the cap, `SHIPPED` unwritable until `loop-converged` passes. A verifier that shares the builder's context shares its blind spots — Compass's critics get fresh context and on-disk evidence only.
- **Collapsibility rule:** every node must justify itself (a distinct specialty, a parallel fan-out, auditable branching, or independent verification) — a node you can't tie to a signal gets collapsed back into the loop it came from.
- **Bounded cycles, evidence-based stop rules:** every loop carries a cap, a convergence bound read from the contract header, stall/oscillation detection, and budget metering owned by the registration gate itself.

(Vocabulary kept Compass-native; the July-2026 "graph engineering" discourse this release coincided with is cited in the CHANGELOG.)

## State (file-based, resumable)
All in `.claude/builds/<slug>/`:
- `contract.md` — the versioned locked invariant (amendments bump the version + re-lock).
- `plan.md` — the step checklist; its checkboxes are the **authoritative** build-progress record.
- `review-ledger.md` — issues across all reviews (first review creates it).
- `progress.md` — the cursor: status ∈ `{draft, in-review (Rn), contract-LOCKED, plan-LOCKED, CLOSED, SHIPPED, ROLLED-BACK}`. Reviews set `in-review (Rn)` at their START.
- `receipts.md` — each stage's **receipt** (commands + outputs). **The teeth:** every downstream Step-0 runs `compass.sh gate <build-dir> <prior-stage>`, which exits non-zero — a hard, un-skippable error — if the prior receipt is absent, FAIL, has an unchecked `[ ]`, or is SUPERSEDED. Escalation/re-run calls `compass.sh supersede` to void downstream receipts so they must re-run.

**`.claude/builds/CURRENT`** = a non-authoritative *hint* of the last active slug (cleared on CLOSE). With parallel builds it can NOT disambiguate — resume derives identity from the worktree (see the resume command). **`.claude/builds/INDEX`** = every build (`slug · goal · status · facets · touches`). Plan rewrites `touches` with the real file list from Phase 0; before planning, if another in-flight build's `touches` overlap, **surface it and ask**.

> **State path:** skills resolve state via `compass.sh state-root` (returns the *main checkout's* `.claude/builds`), so a skill running inside a build's worktree still reaches the one canonical state. Never hardcode `.claude/builds` from inside a worktree.

## Parallel builds (worktree isolation — the keystone)
A repo may run **N builds at once** (incl. one unattended). The rule: **one git worktree per build**, so no two builds share a working directory (this is what stops one build's `git add -A` sweeping another's files). Auto-on when `compass.sh active-builds` shows another in-flight build (or `--parallel`); single-build runs stay in the main checkout unchanged.

On start in parallel mode:
1. `compass.sh gc` — sweep terminal-build worktrees first.
2. If another build is active **and still in the main checkout**, `compass.sh promote <that-slug>` BEFORE starting the new one (never leave the first build in the shared checkout on a prose warning).
3. **DB isolation gate:** if this build changes schema, the contract MUST declare `isolation.db_provision`/`db_teardown` (per-worktree DATABASE_URL). `compass.sh check-db-isolation <slug> <has-schema:0|1> <provision-declared:0|1>` REFUSES a schema-touching parallel build with no isolation — concurrent migrations on one dev DB corrupt it.
4. `compass.sh worktree <slug>` → its folder+branch (runs `db_provision` if declared); `compass.sh install-guard` (once); then `claim` at build start. **ALWAYS create worktrees this way — NEVER hand-roll `git worktree add`** (that scatters ad-hoc siblings the guard/GC/doctor don't track). Worktrees live in the centralized home `~/.compass/worktrees/<project-id>/<slug>` (v0.6.0) — out of the project's parent, so the project folder is never confused with a sibling.
5. Tell the user the worktree path + the one-time `npm ci` / `source .env.compass` step, and that **all build work happens in that worktree** (`cd` there).
6. **See what else is in flight:** `compass.sh builds` lists every parallel build on this repo. Run `compass.sh doctor` anytime to audit/clean worktrees. **If a sibling merges first, every other build must pass `compass.sh post-merge-check <slug>` (and ship's merged-recon) before it can ship** — base-advanced + blast-radius vs `origin/<base>`.

**Unattended runs** (`--unattended`): gates write the resume banner and `exit 0` instead of asking; a guard rejection writes a receipt **FAIL** and stops (never retries → no livelock). Only proceed when the prior stage receipt is PASS.

## Autonomous mode (`--auto`, v0.10.0; self-spawn v0.11.0) — opt-in, two human gates only
Autonomous mode runs the lifecycle WITHOUT the per-hop 4-button gate, stopping for a human at only **two** points (the rest auto-advance). It is mutually exclusive with `--unattended` (`compass.sh auto-precheck` refuses both; default = fully gated).

### Two ways to turn it on (v0.11.0)
1. **Interactive (default, discoverable):** on a plain new build (`/compass:go` → new build, no flag), the run-mode is chosen at **exactly one point — contract lock (G1)**: the contract skill asks **Gated or Autonomous?** via AskUserQuestion at the moment you lock (never earlier — you'd be choosing blind before the contract exists). If **Autonomous**, it also asks for the budget (wall-seconds / max-sessions / max-stages; defaults 3600 / 6 / 40), then runs the one-command setup below. If **Gated**, proceed exactly as today. (v0.24.0 INV-MODE-AT-LOCK: the pre-contract mode prompt was removed so this orchestrator and the contract skill agree on the single at-lock point.)
2. **Flag / one command:** passing `--auto` skips the prompt. Setup is a SINGLE command — **`compass.sh auto-start <dir> [--wall S --sessions N --stages N]`** — which runs `auto-precheck` + `budget-init` + `auto-init` and writes `.auto-mode` (refuses without a budget — **mandatory**, INV-3; refuses `--unattended`). (The old three-call setup still works but `auto-start` is the supported entry.)

The orchestrator loop in `--auto`:
1. **Per stage, Step-0:** `compass.sh budget-check <dir> --bump-stage`. Non-zero → `compass.sh fire-g2 <dir> budget-stop` and STOP (the measurable ceiling is the runaway guard — INV-4).
2. Run the stage. If a stage's verify/INVARIANT FAILS, or a review caps un-converged → `compass.sh fire-g2 <dir> <reason>` and STOP.
3. After the stage gate PASSES: `compass.sh can-advance <dir>`. If it passes, **auto-advance (treat as Approve) — do NOT present the 4-button gate.** If it reports a gate, STOP.
4. **G1 (the only upfront human stop):** right after the contract receipt is PASS, present ONE approval of the contract + design/product intent (Approve/Amend). On approval, append a `gate-cleared` event and continue the loop.
5. **G2 (event-triggered):** any `fire-g2` writes a `gate-wait-G2` banner to `progress.md` and STOPs (exit non-zero) — it NEVER auto-resolves, spawns, or hangs. A human resumes with `/compass:resume <slug>` choosing ship-despite-miss / relax / keep-trying / abort (after `g2_fires` ≥ 3, keep-trying is withdrawn).
6. **End of lifecycle:** review-build records `auto-closed: two clean adversarial rounds + all INVARIANTs green` (NOT a faked human signature — `lifecycle-audit` G-L2 accepts this marker); ship then runs its FULL real verification (prod recon + route smoke). Any ship/prod-verify FAIL → `fire-g2`.

**Continuation at a turn end (v0.35 — this replaced the self-spawn):** when the owning session tries to end a turn on an Autonomous build that still has work, the Stop hook (`compass.sh stop-guard`) does **not** let the turn end quietly. It refuses, and the reason names the next stage, `/compass:resume <slug>`, and two commands that stop it. Nine conditions must ALL hold: Autonomous · not suspended · not aborted · this session owns it · no gate-lock · `can-advance` passes · a successor exists · the successor is not `ship` · refusals remain. Any one absent and the turn ends normally. The refusal counter (`ceiling_refusals`, default 40) is the bound, and each refusal says how many are left.

**The Stop hook no longer starts a second session.** Until v0.34 it spawned a fresh `claude` running `/compass:resume <slug> --auto`, on a much weaker test — owned and continuable — so a build parked at a human gate, or sitting at the ship seam, got a new session started on it. Driving the build from this turn and starting another session are alternatives, never both. `compass.sh auto-spawn` still exists for anyone who wants the cross-session behaviour deliberately.

**Honesty on the boundary:** the budget — wall-clock + max-sessions + max-stages — is the **hard runaway ceiling**, proven (INV-HALT) to bind across *real separate spawned processes*, so the chain cannot exceed it regardless of what the spawn launches. The self-spawn launches `nohup claude -p "/compass:resume <slug> --auto"`; if that launcher can't start, it records `spawn-failed` and stops cleanly (INV-DEGRADE) — never a silent or faked continuation. A human is needed only at G1/G2.

**G1/G2 are real gates (v0.11):** `compass.sh fire-g1`/`fire-g2` take a gate-lock; the self-spawn refuses while either is held (no bypass). On human approval the orchestrator runs `compass.sh gate-clear <dir>` to release the lock and continue.

## The pipeline
```
① contract ─gate→ ② review-contract ─gate→ [contract-LOCKED]
   ─gate→ ③ plan ─gate→ ④ review-plan ─gate→ [plan-LOCKED]
   ─gate→ ⑤ build ─gate→ ⑥ review-build ─(human sign-off)→ [CLOSED]
   ─gate→ ⑦ ship (MANDATORY unless the contract carries `deploy: out-of-scope — <reason>`) → [SHIPPED]
```
- Reviews converge first: **light = one clean pass; full = two clean rounds** (caps R1=2, R2=3, R3=5). Cap un-converged escalates UP (and supersedes) — plan→contract, build→plan, contract→user — never fakes done.
- **review-build requires a human sign-off** on the receipt's command+output evidence before CLOSED.
- **Ship is mandatory (v0.7.0).** CLOSED is NOT a final resting state unless the contract waives deploy. The terminal-status guard (`compass.sh close` runs `lifecycle-audit CLOSED`; ship runs `lifecycle-audit SHIPPED`) and the **Stop hook** (`compass.sh stop-guard`, fires every time the agent tries to stop) block going quiet, skipping a gate, or forgetting ship while a build is mid-lifecycle. Enforcement is script + hook, not discretion.

## The gate (between every stage — owned by the stage; it ASKS, and acts on the answer)
**The gate is owned by each stage's skill.** Every stage skill ends by presenting the canonical 4-button gate (single source: `shared/gate.md`, smoke-enforced byte-identical across the 7 stage skills). As the orchestrator you **sequence** the stages and advance only when the user picks **Approve** or **Amend** — you do **not** present a second gate of your own. On detected drift from `contract.md`, STOP and surface. (The gate's transition footer now points the user at **`/compass:go`**, the one front door that reads state and routes on to the correct next stage.)

## Standalone / budget
Each stage skill works alone and self-gates via `compass.sh gate` (missing proof = hard stop, never fabricated). If the contract set a **budget**, surface "approaching budget" and stop-with-summary rather than grinding to a cap.

## Clean stage transitions (never go quiet)
**A long build must never leave the user wondering where it is.** Every stage ends with a one-line **transition footer** before the gate, in this exact shape — what just passed, what's next, and the exact command (`/compass:go`):
```
✓ <stage> PASSED — <one-line proof>.  Next: <stage> · run `/compass:go`.
```
The stage's own skill then presents the gate after this footer (the footer is the first line of the gate block). After any pause/interrupt, `/compass:status` reprints this. Mid-build, surface step `k/n` after each step. Silence is a defect.

## Auto-pause
The pre-compact hook fires an *advisory* reminder only — it can't write for you and compaction can't be deferred. The real safety net is per-step discipline (progress.md fresh after each step; a box never checked before its verify passes; a build IN-PROGRESS receipt per step), so a lost compaction costs at most one step. On the hook OR **Pause**: write `progress.md` first, then print the **elegant hand-off — exactly one clean, copy-paste-ready fenced block and nothing interleaved** (the shell command to open the build, then the resume command):
```
cd "<abs PROJECT root, where .claude/ lives>" && claude
```
Then, on its own line, the command to run once Claude starts: `/compass:resume <slug>` — Stage `<stage>`, Next `<the single next action>`. Nothing else on those lines: the user copies the block clean into a new terminal.

## Bottom line
Read `CURRENT`, sequence the stages, gate every hop (script gate + the stage-owned 4-button user gate), keep the contract as the invariant, prove every "done" with a recorded command, require the human sign-off before CLOSED, and hand off cleanly when context ends.
