# Compass Parallel-Builds Keystone — Design Spec v2 (post-adversarial-review)

> Status: LOCKED for implementation. v1 was red-teamed across 8 streams (73 raw → 22
> consolidated findings, 9 critical); v2 resolves every finding. Goal unchanged: N Compass
> builds in one repo at once (incl. one unattended) without contamination, resume ambiguity,
> unenforced overlap, or unsafe merges. The four problems from the 2026-06-09 retro:
>
> - **P1** Shared working dir → one build's `git add -A` swept the other's files.
> - **P2** Single global `CURRENT` → bare `/compass:resume` resumed the wrong build.
> - **P3** Cross-build coordination was prose, not an enforced lock.
> - **P4** Autonomous overnight run is the riskiest (unattended `git add -A`).

## Keystone

One **git worktree per build** (own folder, own branch, shared `.git`), plus an enforcement
layer in `compass.sh`. v2's key realization from the review: most of v1's complexity was
*self-inflicted*. The state-location problem dissolves — see D1.

## Locked decisions (resolve all 22 findings)

### D1 — State location (kills K-4/K-14/K-15)
`STATE_ROOT = dirname(abspath(git-common-dir))/.claude/builds` = **the main checkout's
`.claude/builds`, always**. Verified: from a worktree (where `.git` is a file) `git
rev-parse --git-common-dir` returns the main `.git`; its parent is the main root. So:
- **No move, no symlink, no migration.** Main checkout already has state there.
- Skills stop hardcoding `.claude/builds` and call `compass.sh state-root` (so a skill
  running *inside a worktree* reaches the one canonical state). `close()` uses `state-root`,
  not `cd "$dir/.."`.
- `migrate-state` is therefore unneeded; dropped. (K-15 moot.)

### D2 — Worktree path (K-17)
`WT = <parent>/<basename>.compass/<slug>` (sibling of the repo, *outside* it → never scanned
or committed). Every path quoted; file lists passed newline-delimited via files/stdin, never
space-split args. A spaces+parens test is part of the suite.

### D3 — DB isolation, hybrid B+C (kills the critical K-2/K-3)
Compass is stack-agnostic, so the project supplies the hook; Compass enforces the gate:
- Contract gains optional `isolation.db_provision` / `db_teardown` shell commands.
- `worktree <slug>` runs `db_provision` if present → a per-worktree `DATABASE_URL` written to
  `<WT>/.env.compass`; the DB/schema name recorded in LOCKS meta. `close` runs `db_teardown`.
- **Safe default (C):** `check-db-isolation <slug>` exits non-zero (parallel mode REFUSED)
  if the plan has schema changes AND no `db_provision` is declared AND another build is
  active. So a schema-touching build can only go parallel if it brings real DB isolation.

### D4 — One slug-agnostic guard (kills K-7/K-8)
A single `pre-commit` hook installed **once** at the common `.git/hooks/pre-commit` (chains
to any existing hook). At commit time it: resolves `git rev-parse --show-toplevel` → if it's a
`*.compass/<slug>` worktree, validates staged files against *that slug's* claim; if it's the
**main checkout**, blocks any staged file claimed by *any* active build (the main checkout
must not commit an in-flight build's files). `--no-verify` can't be stopped by a hook, so:
banned in build prose, plus `audit-staged`/post-merge `audit` catches bypasses after the
fact, plus unattended mode turns a guard rejection into a receipt **FAIL + stop** (no retry).

### D5 — Resume rewrite (kills K-5/K-20, fixes P2)
Delete the global-`CURRENT`-first read. Order: (1) if cwd's `show-toplevel` is a
`*.compass/<slug>` worktree → that slug (prefer the `compass/<slug>` branch name via
`symbolic-ref`); (2) else `active-builds`: 0 → nothing, 1 → resume, **>1 → REFUSE, list,
require explicit slug**. `CURRENT` demoted to a non-authoritative hint; resume never trusts
it to disambiguate. Per-repo isolation comes free from D1 (state is per-repo).

### D6 — LOCKS format + atomicity (kills K-10/K-22)
`STATE_ROOT/.locks/` directory, **one file per slug**: `<slug>.files` (newline-delimited
claimed paths) + `<slug>.meta` (worktree path · branch · db name · status) + a shared `acks`
file. All writes atomic (temp + `mv`); cross-process mutex via a portable **mkdir-lock**
(macOS has no `flock`). `check-overlap` = set-intersection of active slugs' `.files`. INDEX
writes also temp+rename.

### D7 — Glob→file expansion (kills K-12)
`claim <slug>` runs **in the worktree at build start**: `git ls-files -- <globs>` ∪ the plan's
machine-readable NEW-file list (`plan` must emit `touches.list`). Idempotent / re-runnable as
scope grows, so future-created files get claimed too.

### D8 — Post-merge gate + merge policy (kills K-9/K-13, closes P3)
- `merged-recon <slugA> <slugB> <base>`: create a throwaway worktree at the *merged* tree,
  re-run each build's stored reconciliation (receipts record `RECON-CMD:`), require PASS
  before the second build's PR merges. Wired into `ship`.
- Both builds **CLAIM `package-lock.json` and their migration dir** → `check-overlap` forces
  the conflict *early*. Policy: dep/migration changes serialize — first to merge wins, second
  rebases. A single global migration-timestamp convention is required of the project.

### D9 — Promote the first in-flight build (kills K-16, closes P1's gap)
On `start` with an active build NOT already in a worktree: `promote <slug>` moves it into a
worktree (and DB isolation) **before** the second build starts; if promotion isn't possible,
**refuse** to start the second build. No prose-only warnings.

### D10 — Worktree-cwd is a hard precondition (kills K-19)
`assert-worktree <slug>` exits non-zero unless cwd's `show-toplevel` is that slug's worktree.
`build` calls it at Step 0; `start` prints the `cd` instruction prominently and the build
refuses to run in the main checkout. (Belt-and-suspenders with D4's main-checkout block.)

### D11 — Orphan GC (kills K-18)
`close` always calls `worktree-rm`; escalation/abandon call `gc`. `gc` scans INDEX for
terminal builds and removes their worktrees + `compass/*` branches; `start` does a pre-flight
stale sweep.

### D12 — Unattended mode (kills K-21)
`--unattended`: gates become "write resume banner + `exit 0`"; a hook rejection writes a
receipt **FAIL** and stops (never retries → no livelock). Only allowed when the prior stage
receipt is PASS.

## compass.sh surface (all exit non-zero on failure)

`state-root` · `worktree <slug>` · `promote <slug>` · `worktree-rm <slug>` · `assert-worktree
<slug>` · `claim <slug> [globs|--from <list>]` · `check-overlap <slug>` · `check-db-isolation
<slug>` · `active-builds` · `install-guard` · `audit-staged <slug>` · `merged-recon <a> <b>
<base>` · `gc` — plus the existing `gate · scan-receipt · supersede · reconcile · secret-scan
· close`.

## Lifecycle
1. `start` (parallel on) → pre-flight `gc`; if another build is active & unpromoted →
   `promote` it; `worktree <slug>` (+ `db_provision`); `claim`; `install-guard`. Print the
   worktree path + the one-time `npm ci` / `source .env.compass` step.
2. `build` in the worktree → `assert-worktree`; `check-overlap` + `check-db-isolation` at
   start (hard gate; unattended → banner+stop on conflict); scoped commits; guard enforces.
3. `review-build` → human sign-off (unchanged).
4. `ship` → PR/merge from `compass/<slug>`; if a sibling merged first → `merged-recon` must
   PASS before this merge.
5. `close` → `db_teardown` + `worktree-rm` + drop LOCKS rows + clear CURRENT hint.

## Verdict this v2 targets
v1 left P1 PARTIAL, P2 RELOCATED, P3 PARTIAL, P4 PARTIAL. v2 aims: P1 SOLVED (promote + cwd
precondition + guard), P2 SOLVED (cwd/branch identity + refuse-to-guess, no global CURRENT),
P3 SOLVED (early file-level lock + post-merge recon gate + merge policy), P4 SOLVED (single
guard + main-checkout block + unattended FAIL-stop). DB isolation is the gating prerequisite:
no parallel schema-touching build without a project-supplied `db_provision`.
