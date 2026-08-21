---
name: review-build
user-invocable: false
description: Review-3 (FULL) — final adversarial review of the BUILT product via a multi-agent fan-out assuming every feature is broken until a re-run check proves it (reconciliation, design+a11y, exercised rollback, observability, idempotency, secrets). Ends with a human sign-off. Two clean rounds; cap 5. Trigger after compass:build, or on "review the build", "final review", "ready to ship".
---

# compass:review-build  (Review-3 · FULL)

Lens: **is the BUILT thing correct, complete vs the contract, and safe — proven, not vibed?**

## Step 0 — gate
Run `compass.sh gate .claude/builds/<slug> build`. **Non-zero → STOP** (build incomplete), offer the right earlier stage. Read `contract.md` + `plan.md`. Set `progress.md` = `in-review (R3)`. Check the product against the contract feature-by-feature.

## Engine
- **Ledger** (create if absent): same columns.
- **Material** = new Critical/Major. **Clean round** = zero new material AND the regression suite RE-RUNS green. **Proof-of-work footer:** `> Round N (R3): suite=\`<cmd>\` exit=0 passed=k/k; reconcile→PASS; new Crit/Maj=0. Clean? yes` — no command line = not clean. **Converged = two consecutive clean rounds.** Cap **5**.
<!-- BUGBAR:START -->
- **Severity bug-bar — every ledger `Severity` cell MUST cite one clause.** **CRITICAL** — data loss/corruption · a security or commercial leak · a wrong number that ships · an unassertable INVARIANT · an irreversible migration · prod-down. **MAJOR** — wrong behavior with a workaround · a drift-prone duplicated canonical set · a missing guard on a reachable path. **MINOR** — cosmetic / log-wording.
<!-- BUGBAR:END -->
- **Self-refutation (before a Critical/Major counts):** in the Root-cause cell, record that the triggering input is **reachable from a real entry point** AND that it is **not already guarded** (no existing guard handles it); an unreachable or already-guarded finding is downgraded or dropped — it never resets convergence.
- **Dedupe & rank:** collapse findings that share a root cause into ONE parent row; present **Critical-first**; the round footer names the **top blocker** (not just a count). Derive expected behavior from `contract.md` **before** reading `plan.md`'s implementation (**contract before** plan — the contract wins on any divergence).
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

<!-- COMPASS-STREAMS:START -->
`streams: correctness-completeness numbers-data-integrity ux-operability security-rbac-data-leakage secret-leak verification-audit-coverage`
<!-- COMPASS-STREAMS:END -->

<!-- The list above is the DENOMINATOR, and it is machine-read. Contract §4: a stream id is "derived,
     never a hardcoded letter range" — the [A]..[F] labels below are a reading aid for humans, not the
     count. `compass.sh review-streams review-build` prints these ids, and the review-evidence gate
     requires one evidence file per id at `agents/review-build-r<round>-<id>.md`. Taking the denominator
     from the receipt's own claim is what let twenty builds record "all streams run" with zero
     evidence files on disk. Editing this line changes what the gate demands — that is the point. -->

- **[A] Correctness & completeness:** feature failure modes (empty/huge data, concurrency, partial input, permission edges) · completeness vs contract (every requirement built AND demonstrated by a re-run check) · regression (run the repo's own suite). · **test-rigor (v0.22.0, INV-REDGREEN / INV-MUTATION): RE-RUN `compass.sh mutation-check .claude/builds/<slug>`** — a declared `mutation:` recipe MUST bite (a decorative or broken-control recipe blocks CLOSED) — and **re-challenge the `red-green:` evidence** (`compass.sh redgreen-check` + READ the actual test): a present-but-hollow red-green that names no real failing-first assertion is a MAJOR (the build's honor gate passes it; the review does not).
<!-- EDGERACE:START -->
- **Boundary/edge + concurrency/TOCTOU method (F-EDGERACE):** run for every build that handles numeric/temporal/index input or a read-modify-write — byte-inert (**N/A**) when the build has **no boundary or read-modify-write surface**:
  1. **Boundary/edge checklist** — for each numeric/temporal/index input on a reachable path, enumerate: null · empty · zero · one · max · negative · **off-by-one** · unicode · **timezone**+DST · month/year rollover. Each unhandled boundary on a reachable path is a finding.
  2. **Concurrency/TOCTOU** — for every read-modify-write, name the **losing interleaving** and **assert the guard** (row lock / unique constraint / atomic upsert); flag long transactions that hold locks across I/O.
  3. **Challenge a disprovable N/A** — a boundary/RMW surface present while the review claims N/A is itself a finding; never wave off a boundary or race you can see; build the checklist from the inputs you actually observe.
  An unhandled boundary on a reachable path, or an unguarded read-modify-write, is a finding under the bug-bar (a missing guard on a reachable path = MAJOR; a data-loss/corruption race = CRITICAL) that **blocks CLOSED**.
<!-- EDGERACE:END -->

<!-- HERMETIC:START -->
- **Hermetic-test method (F-HERMETIC, v0.23.0)** — run for every build whose tests touch TIME or the NETWORK; byte-inert (**N/A**) for a build with no time/network/web test surface:
  1. **Clock/timezone** — the tests must **pin the clock** and timezone (inject a fixed epoch + `TZ`); asserting on a live wall-clock value flakes across the date line / DST.
  2. **Network** — the tests must **stub the network** (no live external call; every dependency stubbed/recorded); a real-endpoint call flakes + silently leaks a dependency.
  3. **Determinism** — **run twice** and assert byte-identical results (no order-dependence, no unseeded randomness).
  - **Challenge the disprovable N/A:** **never wave off** a time or network dependency you can SEE in the diff (a `new Date()`, a `fetch`/`http` call, a `sleep`) — a claimed N/A over a visible clock/network read is a finding.
  - **Consequence:** a web/time/network build whose tests are non-hermetic **blocks CLOSED** (MAJOR — a flaky-by-design suite is not a passing suite).
<!-- HERMETIC:END -->
- **[B] Numbers, data & integrity:** reconciliation — run the query then `compass.sh reconcile <actual> <gold> <tol>` (non-zero = CRITICAL, blocks CLOSED), re-check the dup/fan-out/source-table bug-classes, gold is the contract's independent figure · **migration delivery (v0.7.0, schema builds): `compass.sh migration-gate .claude/builds/<slug>` MUST be PASS (non-zero = CRITICAL, blocks CLOSED)** — a real migration in the canonical deploy dir reproduces the schema on a fresh DB (STRICT); `db execute`/hand-apply, a stray non-canonical migration dir, or fresh-apply failure = CRITICAL · DB/migration integrity — **rollback ACTUALLY exercised on a copy** (forward+back, row-count + checksum identical) · idempotency — run twice, assert identical end-state, no double-write. · **rollback forward-compat (v0.21, INV-ROLLBACK-FWDCOMPAT): re-challenge the recorded rollback data-safety line (`old-code reads new-version writes → OK`) against the plan/diff — a fabricated line passes the ship gate, so NEVER treat it as independent proof (honor-level; blocks CLOSED if the recorded claim can't be substantiated).** · **green-CI merge gate (v0.21, INV-GREEN-CI): when the contract declares `ci: yes`, re-challenge the recorded green-ci merge-proof line against the actual CI/merge state — a fabricated proof passes the gate, so NEVER treat it as independent proof (honor-level; blocks CLOSED).**
<!-- CROSSTAB:START -->
- **Cross-table invariant enforcement method (F-CROSSTAB):** run for every build that touches **≥2 related tables** (parent/child, foreign key, or a versioned/generational set) — byte-inert (**N/A**) when the build has **no ≥2-related-table surface**:
  1. **Enumerate the cross-table invariants** — name each rule that must hold ACROSS rows/tables for the tables the build touches: **child-sums-to-parent** (a child aggregate ties to the parent's stored total), **no orphan FK** (every child references a live parent), **one active generation** (exactly one row is the live version where the schema implies it).
  2. **Assert DB-level enforcement, not app-only** — each invariant is held by a **DB-constraint** / **trigger** / unique-partial-index, NOT merely app code a second writer bypasses; and a **zero-violators** pre-flight query returns empty on real data before the change is CLOSED.
  3. **Challenge a disprovable N/A** — you must **challenge the disprovable N/A for schema/migration/PII**: a build that plainly touches ≥2 related tables (or a visible schema/migration/PII surface) while the review claims N/A is itself a finding; **never wave off** a multi-table surface you can see; build the invariant list from the tables you actually observe.
  An unenforced cross-table invariant (app-only, or no zero-violators pre-flight) on a reachable path is a finding under the bug-bar (a missing guard on a reachable path = MAJOR; a cross-table data-corruption break = CRITICAL) that **blocks CLOSED**.
<!-- CROSSTAB:END -->
- **[C] UX & operability:** **design fidelity — run the BRUTAL non-negotiable gate above (`design-ledger.md` → zero open rows, `converge-gate` passes); any drift from the mockup is a finding, not a "feel" note.** **Sketch leak re-check (v0.13.0): `compass.sh sketch-gate <build-dir>` rides this stage's gate mechanically — a LINE-1 `COMPASS-MOCK` marker in any tracked product file is a CRITICAL (the throwaway wireframe shipped).** **Cold-critic convergence (v0.12.0): when the contract declares `cold-critic: on`, `compass.sh coldgo-gate <build-dir>` MUST exit 0 (2 consecutive cold GOs on the IDENTICAL tree sha == current HEAD, clean trees — any commit between or after the GOs mechanically resets; or one gated HUMAN-GO with the declared fallback). Non-zero = CRITICAL, blocks CLOSED.** a11y (web) — exact: computed CSS vs tokens, contrast/focus-visible/keyboard · performance/OOM/scale at the contract's volume + concurrency · observability — the contract's named metric/log actually EMITS (not prose). · **blast-radius page-load (v0.8.0, when the plan declares `## Affected routes`): `compass.sh route-coverage .claude/builds/<slug>` MUST be PASS (non-zero = CRITICAL, blocks CLOSED)** AND **independently RE-LOAD each declared route yourself** (actually GET/Playwright it on the migration-built schema, assert 200-with-content) — do NOT trust the build receipt's recorded line (it's honor-level; a fake `→ 200` passes the script). A page/route step proven by typecheck alone = CRITICAL.
<!-- PERFFMEA:START -->
- **Per-dependency FMEA + anti-pattern-hunt method (F-PERFFMEA):** run for every build with an external dependency or a data-volume-sensitive loop — byte-inert (**N/A**) when the build has **no external dependency or data-volume-sensitive loop**:
  1. **Per-dependency FMEA** — for each external dependency (DB / API / cron / queue / third-party), state behavior when **slow and when down** + the mitigation (timeout / retry-backoff / fallback); **no dependency called with no timeout**.
  2. **Anti-pattern hunt** — hunt **N+1** queries, **paginationless** / unbounded fetches, O(n²) loops; **assert the query count** and peak memory at the contract's row count, not a toy set.
  3. **Challenge a disprovable N/A** — a real external dependency or a data-volume-sensitive loop present while the review claims N/A is itself a finding; **never wave off a dependency or volume-sensitive loop you can see**; build the FMEA from the dependencies you actually observe.
  An unmitigated dependency (a call with no timeout / no fallback), or an unbounded anti-pattern at the contract's scale, is a finding under the bug-bar (a missing guard on a reachable path = MAJOR; a data-loss / OOM at the contract's volume = CRITICAL) that **blocks CLOSED**.
<!-- PERFFMEA:END -->
- **[D] Security/RBAC/data-leakage** — *independent agent.*
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
- **[E] Secret-leak** — *independent agent:* `compass.sh secret-scan --commits <base>..HEAD` over the build's COMMITTED patches (a secret committed mid-build must not survive to ship just because the tree is now clean) + `compass.sh secret-scan <build-dir>` over the per-build text artifacts (any hit = CRITICAL, blocks CLOSED).
- **[F] Verification audit & coverage** — *independent agent:* every "works" backed by a real command + fresh output (screenshot-only proof of a number/token = a finding); every plan-promised test present and passing. **Coverage, not sample:** a fix passing its test ≠ complete. When a fix is defined relative to a canonical set/list/enum (sensitive/commercial fields, roles, allowed values, secret patterns, redaction targets), assert the implementation is **driven by the canonical source itself** (imported/enumerated) — a hand-maintained copy/regex that duplicates a canonical set is a **Major finding** (it WILL drift, e.g. a redaction regex that misses real field keys), and the test must exercise the **full set** (or a property derived from it), not a hand-picked sample.


### Write the artefact-data block (v0.31, INV-DECLARED)

Compass's pages state numbers. Until v0.31 every one of them was worked out by reading hand-written
markdown with ~90 ad-hoc regular expressions, and when that guessing was wrong the page stated the
wrong number with exactly as much confidence as when it was right. A `compass-artefact-data` fence in
this build's state files ends the guessing for the fields it names: the generator states them
verbatim and marks them `declared`, and `compass.sh gold-numbers-gate` cross-checks each one against
the file it describes and FAILS on a disagreement.

**Only declare a field with an EXACT, mechanically checkable source.** A plan checkbox and a bolded
`INV-` id are syntax Compass itself writes, so counting them is not a heuristic. Do NOT declare
`findings.*`: those come from classifying free text in a ledger, which is precisely the guessing this
removed — and a declared number carries no caveat, so a wrong one reads as verified.

A field you do not write is counted by reading and disclosed to the reader as such: a worse but
honest outcome. Write what you actually know, and nothing you do not.

At THIS stage the block already exists — the contract, plan and build stages wrote it. Your job is to
confirm it still agrees with the files, because the build stage has been ticking boxes since it was
written:

```bash
compass.sh gold-numbers-gate .claude/builds/<slug>     # exit 0, and it audits THIS dir, not 28 others
```

A non-zero exit means a declared number now contradicts its source file. Fix the number, never the
gate. (Until v0.31 this gate ran the corpus measurement and never looked at the dir it was handed, so
a build could declare 999 steps over a 16-checkbox plan and be told it was clean.)

## Procedure → emit → human sign-off
Round 1: all 6 groups → ledger + fixes; re-validate by RE-RUNNING commands. Rounds 2+: the groups the fixes touched **PLUS the independent [D]/[E]/[F] agents on the fix diff**, + the full regression suite re-run + footer. **Converge only when the final clean round was a genuine verify-the-fixes round** ([D]/[E]/[F] re-attacked the latest fix diff and found nothing) — two consecutive clean rounds, the last a fix-surface re-attack. Then **EMIT RECEIPT** (one line per asserted thing, with command + output):
```
## RECEIPT — review-build · <slug> · PASS
- [x] streams: review-build r<round> -> <present> of <declared> (denominator from `compass.sh review-streams review-build`, never from this receipt)
- [x] gate: build receipt OK; all 6 groups run
- [x] RBACSTRIDE: role×resource matrix asserted vs contract + IDOR probed (403/empty), or N/A — no new view/endpoint
- [x] EDGERACE: boundary checklist + concurrency/TOCTOU applied (losing interleaving named, guard asserted), or N/A — no boundary or read-modify-write surface
- [x] PERFFMEA: per-dependency FMEA + anti-pattern hunt applied (no call without a timeout; query count + peak mem asserted at the row count), or N/A — no external dependency or data-volume-sensitive loop
- [x] HERMETIC: pin-clock/stub-network/run-twice applied for a time/network test build, or N/A — no time/network/web test surface
- [x] CROSSTAB: cross-table invariants enumerated + DB-constraint/trigger enforcement + zero-violators pre-flight applied, or N/A — no ≥2-related-table surface
- [x] INVARIANT <id>: `<cmd>` → <actual> vs <bound> PASS   (per invariant)
- [x] RECONCILE: `compass.sh reconcile <actual> <gold> <tol>` → PASS   (or N/A)
- [x] secret-scan: `compass.sh secret-scan <build-dir>` (per-build text artifacts) + `compass.sh secret-scan --commits <base>..HEAD` (committed patches) → 0 hits
- [x] rollback exercised on a copy: `<cmd>` → row-count+checksum identical
- [x] observability emits: `<cmd>` → <signal seen>; idempotency test: run twice → identical
- [x] regression suite: `<cmd>` exit=0 passed=k/k
- [x] every plan-promised test present & passing
- [x] final round was a verify-the-fixes round: [D]/[E]/[F] re-attacked the last fix diff → 0 new material
- [x] set-based fixes driven by the canonical source (not a drift-prone copy); test covers the full set
```
Self-check: `compass.sh scan-receipt .claude/builds/<slug> review-build`. **Then require a HUMAN sign-off** — show the receipt's command+output lines (the falsifiable evidence, not a summary) as the transition proof, then present the gate below. On **Approve**: `progress.md` = `CLOSED`; INDEX `status=closed`; run `compass.sh close .claude/builds/<slug> <slug>` (clears CURRENT); Approve advances to `compass:ship` (or stays CLOSED if the contract waives deploy).


## Review artefact (v0.30 — before the receipt)
The reviews produce the one artefact that says what was actually wrong and whether anyone fixed it.
Generate, gate, publish — in that order, and STOP on any non-zero:

`node skills/compass-visual/gen.mjs <dir> review --out <dir>/review.html`
→ `compass.sh artefact-gate <dir>/review.html --copy --source <dir>/contract.md`
→ the cold read runs as `node scripts/insight-gate.mjs --artefact <dir>/review.html --intent <dir>/coldread-intent.txt --grader <grader-verdict.json> --control <control-verdict.json> < <reader-verdict.json>` (INV-1: a fresh separate-context reader whose verdict arrives on **stdin**, a second grader that never sees the page, and a control read of the known-bad page that VOIDs the round if the reader passes it too). All three are FILES except the reader's, which is piped — run it without the pipe and it waits on stdin forever.
→ `compass.sh artefact-publish <dir>/review.html --url <the published URL>`
→ `compass.sh rail <dir> --artefact review --url <that URL>` and SHOW it.

Record: `- [x] MILESTONE: review-artefact render=review.html artifact=<URL OR N/A — reason>`

> The contract ranks this above the Release Card on purpose: a shipping certificate says a thing
> shipped; this says what was wrong with it and whether it got fixed.

<!-- FEYNMAN -->
## In plain words — where we are and what's next
**What just happened.** Final adversarial pass: I assumed every feature was broken until a re-run proved otherwise — re-loading pages, re-running the reconciliation, exercising the rollback on a copy, confirming the monitoring signal fires, checking nothing sensitive leaked.
**Why it matters.** This is the last gate before real deployment. Findings are ranked worst-first, and it ends with your sign-off. CLOSED means proven on representative data — not yet prod.
**Your options:**
- **Approve & continue** — sign off, then move to ship (deploy + prove in prod).
- **Revise** — re-run the review with a change you name.
- **Amend** — a real scope change: bump the contract and re-review just the delta.
- **Pause** — stop cleanly; you resume exactly here, nothing lost.
**My recommendation.** Approve & sign off, then ship.
Progress — ⑥ build proven + human sign-off · next: ⑦ ship.
<!-- CONFIDENCE -->
**The rigor I'm applying, so you can trust the machine:** "Final adversarial pass: I assume every feature is broken until a re-run proves otherwise. I re-load every page myself, re-run the reconciliation, actually exercise the rollback on a copy, confirm the monitoring signal really fires, and check nothing sensitive leaked into a screenshot. Findings are ranked worst-first, and it ends with your sign-off. CLOSED means proven on representative data — not yet prod."

<!-- GATE:START -->
## Stage transition — the gate (fires on EVERY entry path)

This stage owns its own transition gate. Present it whether this stage was invoked on its own
(the `compass:build` skill) or sequenced by the `compass:start` orchestrator. The orchestrator
does **not** present a second gate — the stage owns it.

1. First print the one-line **transition footer**, in exactly this shape:

   `✓ <this stage> PASSED — <one-line proof>.  Next: <next stage> · run \`/compass:go\`.`

   (For the terminal `ship` stage, Next is `done — build SHIPPED`.)

   Then PUSH the RAIL when this stage produced an artefact — run
   `compass.sh rail <build-dir> --artefact <view> --url <the published URL>` (or `--local <path>`
   when nothing could publish it) and show it, so the link is in front of the user beside the
   buttons rather than described in prose. (v0.30: the rail existed and nothing called it — a
   surface nobody invokes is not a surface, the same defect this build was raised to fix.)

   Then PUSH the cockpit — run `compass.sh cockpit <build-dir>` and show it — so the user always
   sees where they are (the 7-stage strip · step k/n · next; plus program phases + contracts when
   in a program) with **zero typing** (v0.24.0 INV-PUSH-STAGE). Silence between stages is a defect.

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
