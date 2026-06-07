# Review Core — the shared adversarial-review engine (canonical spec)

> The full reference for the convergence engine used by `compass:review-contract` (light),
> `compass:review-plan` (full), and `compass:review-build` (full).
> **Runtime note:** each review skill INLINES the rules it needs (a plugin skill cannot reliably
> read a sibling file at runtime). This file is the human-readable source of truth; if you change
> the engine, change it here AND in the three review skills.

## The engine (same in all three reviews)

1. **Fan out, don't read linearly.** Spawn specialized review streams in parallel (the stream list comes from the specific review skill). Full reviews use multi-agent fan-out; the light review can be a single focused pass.
2. **Assume it fails.** For every finding capture: what breaks · which existing feature/workflow/invariant it impacts · why · severity · concrete fix · the test/validation that PROVES the fix.
3. **Prove, don't vibe.** Every "it's correct / it's fixed" is backed by a real check (see the verify-ladder). **Agent agreement is NOT evidence — restate this every round, not just once.** At the contract/plan stages there is no code to run; there the proof is **grounding** — every claim checked against the real repo/data, or flagged as an explicit, owned open risk (a flag is not a pass).

## The one issue ledger (`review-ledger.md`)

**The review skill CREATES `.claude/builds/<slug>/review-ledger.md` if it is absent** (it spans all three reviews). Rows are **append-only**; only the `Status` cell is updated in place (open → closed).

Columns:

| Issue ID | Review (R1/R2/R3) | Round # | Affected area | Failure mode | Impacted invariant | Severity (Critical/Major/Minor) | Root cause | Concrete fix | Validation command | Owner stream | Status |

After every round, append a footer line so convergence is computable from the file, not from memory:
`> Round N (Rx): <k> new Critical/Major, <m> new Minor. Clean? yes/no.`

## Definitions (numeric — no discretion)

- **Material issue** = a NEW **Critical or Major** finding. (Minor/cosmetic findings are logged but do NOT reset convergence.)
- **Clean round** = a round that surfaces **zero new material issues** AND (for full reviews) the deterministic test fleet / regression suite RE-RUNS green. Diff-scope what you *review*, but always re-run the full checks before calling a round clean — two locally-clean rounds on different surfaces are not global cleanliness.
- **Closed issue** = its `Validation command` has been **RE-RUN and its FRESH output recorded**. Re-reading the diff or a subagent agreeing it looks fixed is NOT closure.
- **Converged:**
  - **Light review (review-contract):** **one clean pass.**
  - **Full reviews (review-plan, review-build):** **two consecutive clean rounds.**

## The convergence loop

Repeat: **review → fix → re-validate (re-run the command) → re-review.** Round 1 is a broad sweep; rounds 2+ re-review only the surface the fixes touched (diff-scoped) BUT still re-run the full deterministic checks before counting the round clean.

**Stop when converged (above) OR the iteration cap is hit.** Caps (ceiling, not target — most converge earlier):
- `review-contract` → **2**
- `review-plan` → **3**
- `review-build` → **5**

**Hitting a cap WITHOUT convergence is never "converged."** Do not downgrade issues to fake a green. It means **stop, document remaining open risks, and escalate UP a level:**
- plan review stuck at cap → the **contract** is likely under-specified → bounce to `compass:contract`.
- build review stuck at cap → the **plan** likely has a design flaw → bounce to `compass:plan`.
- **contract review stuck at cap → there is no level above. Hand back to the USER** with the open questions listed — the spec needs their decisions. Never silently "lock."

## Grounding (the invariant)
Read `contract.md` FIRST and check the artifact against it — a deviation from the contract is itself a CRITICAL finding. **Every contract INVARIANT must trace to a passing assertion of its specific bound** (the ±1%, the <2s, the RBAC rule); an INVARIANT with no real check that asserts its exact bound is a CRITICAL gap. If no contract exists (standalone use), say so plainly: "ungrounded — no contract to check against," and offer to create one.

## Output
Feature-by-feature failure modes · regression risks · completeness gaps vs contract · INVARIANT-assertion coverage · security/RBAC/data-leakage · performance/OOM · DB/migration · reconciliation (numbers tie to the gold figure within tolerance) · design fidelity vs tokens · missing tests · concrete fixes · final sign-off criteria · the per-round footer log.
