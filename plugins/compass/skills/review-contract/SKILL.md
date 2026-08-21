---
name: review-contract
user-invocable: false
description: Review-1 (LIGHT) — adversarially pressure-test a CONTRACT before it locks — completeness, ambiguity, testability, reconciliation pinned/independent/exact, consistency, edge states, feasibility. One clean pass; cap 2. Trigger after compass:contract, or on "review the contract", "pressure-test this spec", or the Compass orchestrator.
---

# compass:review-contract  (Review-1 · LIGHT)

Lens: **is the WHAT airtight?** One focused pass; loop only if gaps.

## Step 0 — gate (real, not prose)
Run `compass.sh gate .claude/builds/<slug> contract` (slug from `.claude/builds/CURRENT`). **Non-zero exit → STOP**, offer `compass:contract`. Read `contract.md`. Set `progress.md` status = `in-review (R1)`.

## Engine
- **Ledger:** create `.claude/builds/<slug>/review-ledger.md` if absent. Append-only rows, `Status` in place. Columns: `Issue ID | Review (R1/R2/R3) | Round # | Affected area | Failure mode | Impacted invariant | Severity | Root cause | Fix | Validation | Owner stream | Status`.
- **Material** = new Critical/Major. **Converged = ONE clean pass** (zero new material). Cap **2**. Footer per round: `> Round N (R1): new Crit/Maj=0. Clean? yes`.
<!-- BUGBAR:START -->
- **Severity bug-bar — every ledger `Severity` cell MUST cite one clause.** **CRITICAL** — data loss/corruption · a security or commercial leak · a wrong number that ships · an unassertable INVARIANT · an irreversible migration · prod-down. **MAJOR** — wrong behavior with a workaround · a drift-prone duplicated canonical set · a missing guard on a reachable path. **MINOR** — cosmetic / log-wording.
<!-- BUGBAR:END -->
- **Self-refutation (before a Critical/Major counts):** in the Root-cause cell, record that the triggering input is **reachable from a real entry point** AND that it is **not already guarded** (no existing guard handles it); an unreachable or already-guarded finding is downgraded or dropped — it never resets convergence.
- **Dedupe & rank:** collapse findings that share a root cause into ONE parent row; present **Critical-first**; the round footer names the **top blocker** (not just a count). Derive expected behavior from `contract.md` **before** reading `plan.md`'s implementation (**contract before** plan — the contract wins on any divergence).
- Proof here = **grounding** (checked against real schema/data, or flagged as an owned risk — a flag is not a pass). **Agent agreement is not evidence.**
- Cap without convergence → **no level above the contract → STOP, hand to the USER** with the open questions.

## Streams (one pass)

<!-- COMPASS-STREAMS:START -->
`streams: completeness ambiguity testability reconciliation internal-consistency edge-states feasibility-vs-data co-construction-sketch-audit`
<!-- COMPASS-STREAMS:END -->

<!-- The list above is the DENOMINATOR, and it is machine-read. Contract §4: a stream id is "derived,
     never a hardcoded letter range" — the [A]..[F] labels below are a reading aid for humans, not the
     count. `compass.sh review-streams review-contract` prints these ids, and the review-evidence gate
     requires one evidence file per id at `agents/review-contract-r<round>-<id>.md`. Taking the denominator
     from the receipt's own claim is what let twenty builds record "all streams run" with zero
     evidence files on disk. Editing this line changes what the gate demands — that is the point. -->

1. **Completeness** for the chosen facets — every required section substantive (incl. scale, deps, reconciliation, idempotency, rollback, observability; web: auth + tokens + a11y; pipeline: input-contract + determinism + output-schema + reproducibility).
2. **Ambiguity** — every term defined; name any phrase readable two ways.
3. **Testability** — every requirement measurable. **A deferred flag on an INVARIANT/acceptance item = CRITICAL.**
4. **Reconciliation — pinned, INDEPENDENT, exact.** Grep `contract.md` and assert: gold is a **literal with published provenance, NOT self-computed** (self-computed gold = CRITICAL); tolerance = displayed precision (a looser band must carry justification + user sign-off); the known-bug-class checklist (dup / fan-out / source-table) is present. Quote the matched lines in the ledger — don't just re-state the contract's own claim.
5. **Internal consistency** — no two requirements conflict.
6. **Edge states** — empty/loading/error/scale/permission specified.
7. **Feasibility-vs-data** — real source data supports the derivation/goal (cheap check, else flag — never flag an INVARIANT).
8. **Co-construction & sketch audit (v0.13.0, when `intake: co-construct-v1` / sketch artifacts exist):** `compass.sh intake-gate` and `compass.sh sketch-gate` exit 0 (quoted — they also ride the Step-0 gate); every `SCOPE NOW:` item traces to a numbered requirement; every `SCOPE NEVER:` item appears in Non-goals; every premortem-NOW item maps to an INVARIANT, a `CRITIQUE-TARGET:` line, or an explicit accepted-risk; sketch↔spec parity — every visible mockup element/state has a Design Spec line (web) / every Mermaid edge maps to a "when X → Y" behavior (non-web); waiver lines (`sketch: out-of-scope`, `post-ship-loop: off`, `cold-critic: off`) each carry a real reason with user sign-off; **anti-fabrication — if the contract was authored by an --auto/headless session, it must declare `intake: classic` and intake.md must NOT exist; `intake: co-construct-v1` with auto-era authorship = CRITICAL (a fabricated interview). WHAT THE EVIDENCE ACTUALLY SUPPORTS, corrected in v0.32.0 S22-25: this clause used to cite `session-chain.log` as establishing authorship. It does not. `compass.sh check-session-chain` validates that log's SHAPE — seven fields per line, a known event, a known stage, numeric counters — and nothing more; it never reads who wrote the contract. The log is also written by the same party it would police, which is the same limit contract §4 states about independence. So authorship is a JUDGEMENT this stream makes from the receipts and the contract's own wording, and the reviewer must say which evidence they used. Do not cite the chain log as proof of it.**

## Procedure → emit
Run the streams; log + apply fixes (surface intent questions, don't guess). One more pass if a new material gap (cap 2). Converged → `progress.md` = `Contract LOCKED`. **EMIT RECEIPT**:
```
## RECEIPT — review-contract · <slug> · PASS
- [x] gate: contract receipt OK (compass.sh gate → PASS)
- [x] all streams run; ledger updated
- [x] streams: review-contract r<round> -> <present> of <declared> (denominator from `compass.sh review-streams review-contract`, never from this receipt)
- [x] this review was NOT independently verified — independence cannot be proven in this environment (contract §4); the same sentence is printed on the review page
- [x] reconciliation independent+exact: grep `contract.md` → gold=<literal> provenance=<artifact>; tol=<…>
- [x] 0 open Critical/Major; progress.md = Contract LOCKED
```
Self-check: `compass.sh scan-receipt .claude/builds/<slug> review-contract`.

<!-- FEYNMAN -->
## In plain words — where we are and what's next
**What just happened.** Independent reviewers tried to break the contract before it costs anything — every term defined, every requirement testable, the reconciliation number real and exact, the edge cases handled.
**Why it matters.** Fixing a spec now is nearly free; fixing it after the build is expensive. A finding only counts if it's proven really reachable — no crying wolf.
**Your options:**
- **Approve & continue** — move to plan (turn the locked contract into a step-by-step build plan).
- **Revise** — re-run the review with a change you name.
- **Amend** — a real scope change: bump the contract and re-review just the delta.
- **Pause** — stop cleanly; you resume exactly here, nothing lost.
**My recommendation.** Approve & continue once the review is clean.
Progress — ② contract pressure-tested · next: ③ plan.
<!-- CONFIDENCE -->
**The rigor I'm applying, so you can trust the machine:** "I just tried to break the spec before it costs anything — every term defined, every requirement testable, the reconciliation number real and exact, every edge case (empty, huge, permission-denied) handled. If I flag a blocker, I first prove it's really reachable — no crying wolf."

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
