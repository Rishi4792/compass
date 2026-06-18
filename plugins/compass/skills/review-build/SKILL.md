---
name: review-build
description: Review-3 (FULL) — final adversarial review of the BUILT product via a multi-agent fan-out assuming every feature is broken until a re-run check proves it (reconciliation, design+a11y, exercised rollback, observability, idempotency, secrets). Ends with a human sign-off. Two clean rounds; cap 5. Trigger after compass:build, or on "review the build", "final review", "ready to ship".
---

# compass:review-build  (Review-3 · FULL)

Lens: **is the BUILT thing correct, complete vs the contract, and safe — proven, not vibed?**

## Step 0 — gate
Run `compass.sh gate .claude/builds/<slug> build`. **Non-zero → STOP** (build incomplete), offer the right earlier stage. Read `contract.md` + `plan.md`. Set `progress.md` = `in-review (R3)`. Check the product against the contract feature-by-feature.

## Engine
- **Ledger** (create if absent): same columns.
- **Material** = new Critical/Major. **Clean round** = zero new material AND the regression suite RE-RUNS green. **Proof-of-work footer:** `> Round N (R3): suite=\`<cmd>\` exit=0 passed=k/k; reconcile→PASS; new Crit/Maj=0. Clean? yes` — no command line = not clean. **Converged = two consecutive clean rounds.** Cap **5**.
- **Fan-out economy:** round 1 spawns all groups; **rounds 2+ spawn the groups the last round's fixes touched** — the full regression suite still re-runs every round. Closure = Validation command **re-run with fresh output**; agent agreement is not evidence.
- **A FIX IS NEW CODE — re-attack it (the rule that catches self-introduced defects).** A fix can introduce a *new* defect, including the exact class it fixed (a pagination fix that opens an IDOR; a redaction fix that misses a field). So: **any round that applied a fix is NOT clean by definition.** The next round MUST adversarially re-attack the fix surface, and the **independent agents [D] Security/RBAC, [E] Secret-leak, and [F] Verification-audit ALWAYS re-spawn on any fix diff — regardless of which group the fix nominally belonged to** (a "functional" fix routinely opens a security hole). **Convergence requires the final clean round to be a genuine *verify-the-fixes* round** where [D]/[E]/[F] re-attacked the latest fix diff and found nothing — never declare clean on a round that merely re-ran the suite after a fix. (Two consecutive clean rounds, last one a fix-surface re-attack; cap 5.)
- **Cap 5 un-converged** → plan flaw → `compass.sh supersede .claude/builds/<slug> plan`, escalate to `compass:plan` (or `contract` if the premise is false).
- **A clean round is not clean until `compass.sh converge-gate <build-dir>` exits 0** — it blocks unless BOTH the correctness ledger (no open Critical/Major) AND the design-drift ledger (`design-ledger.md`) are clean. Cite the command + exit in the footer.

## ⛔ Design fidelity — BRUTAL & NON-NEGOTIABLE (any web build)
The build is done on design ONLY when it is **indistinguishable from the mockup**. This is **NON-NEGOTIABLE** and the bar is **identical** whether the mockup is an HTML file or a flat image — only the technique differs.
- **Maintain `design-ledger.md`** (same table columns). Render the built UI vs the mockup **at every viewport AND every state** (empty/loading/error/overflow/long-text/hover/focus). Read them **side by side, element by element** across these drift dimensions: **layout · spacing · typography · color/token · hierarchy · every state**. Each difference = one OPEN row. **ONE open row = FAIL — loop and fix until the ledger has zero open rows**, then add the `<!-- design-review: complete -->` marker. **The marker is an attestation — it MUST list the viewports + states actually examined** (e.g. `complete — desktop/tablet/mobile × empty/loading/error/populated`); a bare marker with no rows and no coverage list is not a review, it's a forgery. `compass.sh design-drift-gate` enforces ledger discipline (missing/empty ledger on a web build = FAIL — design review not done ≠ clean).
- **HTML mockup:** also run exact checks — `compass.sh design-style-diff <mockup> <built> <token>` per token + computed-CSS assertions. **These are necessary but NOT sufficient** — a passing token diff does NOT mean design verified; layout/spacing/hierarchy/state drift still require the element-by-element reading above. Never "token diff passed → design done."
- **Image mockup:** the identical bar, enforced by the disciplined side-by-side reading that populates the ledger (no bash differ possible — that does not lower the bar).

## Non-ceremonial verify (the rule that ends ceremony)
- **Review-build does not re-run the build's own checks** and call it a review. Independently **render the live product on real/representative data** and adversarially read the actual values + pixels a user would see.
- **Every check must be falsifiable** — it must be able to FAIL if the thing were broken. A check that cannot fail (a tautology, a screenshot-only "looks right", a grep for prose) is deleted, not counted.

## Streams — fan out as 6 agents (assume each FAILS until proven; each emits one ledger row per check)
- **[A] Correctness & completeness:** feature failure modes (empty/huge data, concurrency, partial input, permission edges) · completeness vs contract (every requirement built AND demonstrated by a re-run check) · regression (run the repo's own suite).
- **[B] Numbers, data & integrity:** reconciliation — run the query then `compass.sh reconcile <actual> <gold> <tol>` (non-zero = CRITICAL, blocks CLOSED), re-check the dup/fan-out/source-table bug-classes, gold is the contract's independent figure · **migration delivery (v0.7.0, schema builds): `compass.sh migration-gate .claude/builds/<slug>` MUST be PASS (non-zero = CRITICAL, blocks CLOSED)** — a real migration in the canonical deploy dir reproduces the schema on a fresh DB (STRICT); `db execute`/hand-apply, a stray non-canonical migration dir, or fresh-apply failure = CRITICAL · DB/migration integrity — **rollback ACTUALLY exercised on a copy** (forward+back, row-count + checksum identical) · idempotency — run twice, assert identical end-state, no double-write.
- **[C] UX & operability:** **design fidelity — run the BRUTAL non-negotiable gate above (`design-ledger.md` → zero open rows, `converge-gate` passes); any drift from the mockup is a finding, not a "feel" note.** a11y (web) — exact: computed CSS vs tokens, contrast/focus-visible/keyboard · performance/OOM/scale at the contract's volume + concurrency · observability — the contract's named metric/log actually EMITS (not prose).
- **[D] Security/RBAC/data-leakage** — *independent agent.*
- **[E] Secret-leak** — *independent agent:* `compass.sh secret-scan .` over the diff + every kept verify spec (any hit = CRITICAL, blocks CLOSED).
- **[F] Verification audit & coverage** — *independent agent:* every "works" backed by a real command + fresh output (screenshot-only proof of a number/token = a finding); every plan-promised test present and passing. **Coverage, not sample:** a fix passing its test ≠ complete. When a fix is defined relative to a canonical set/list/enum (sensitive/commercial fields, roles, allowed values, secret patterns, redaction targets), assert the implementation is **driven by the canonical source itself** (imported/enumerated) — a hand-maintained copy/regex that duplicates a canonical set is a **Major finding** (it WILL drift, e.g. a redaction regex that misses real field keys), and the test must exercise the **full set** (or a property derived from it), not a hand-picked sample.

## Procedure → emit → human sign-off
Round 1: all 6 groups → ledger + fixes; re-validate by RE-RUNNING commands. Rounds 2+: the groups the fixes touched **PLUS the independent [D]/[E]/[F] agents on the fix diff**, + the full regression suite re-run + footer. **Converge only when the final clean round was a genuine verify-the-fixes round** ([D]/[E]/[F] re-attacked the latest fix diff and found nothing) — two consecutive clean rounds, the last a fix-surface re-attack. Then **EMIT RECEIPT** (one line per asserted thing, with command + output):
```
## RECEIPT — review-build · <slug> · PASS
- [x] gate: build receipt OK; all 6 groups run
- [x] INVARIANT <id>: `<cmd>` → <actual> vs <bound> PASS   (per invariant)
- [x] RECONCILE: `compass.sh reconcile <actual> <gold> <tol>` → PASS   (or N/A)
- [x] secret-scan: `compass.sh secret-scan .` → 0 hits
- [x] rollback exercised on a copy: `<cmd>` → row-count+checksum identical
- [x] observability emits: `<cmd>` → <signal seen>; idempotency test: run twice → identical
- [x] regression suite: `<cmd>` exit=0 passed=k/k
- [x] every plan-promised test present & passing
- [x] final round was a verify-the-fixes round: [D]/[E]/[F] re-attacked the last fix diff → 0 new material
- [x] set-based fixes driven by the canonical source (not a drift-prone copy); test covers the full set
```
Self-check: `compass.sh scan-receipt .claude/builds/<slug> review-build`. **Then require a HUMAN sign-off** (AskUserQuestion): show the receipt's command+output lines (the falsifiable evidence, not a summary) and ask the user to Approve before CLOSED. On approve: `progress.md` = `CLOSED`; INDEX `status=closed`; run `compass.sh close .claude/builds/<slug> <slug>` (clears CURRENT). Then the build may proceed to `compass:ship` (or close if deploy is out of scope).
**Standalone STOP:** report the result; no further outward action.
