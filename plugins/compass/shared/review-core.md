# Review Core — the shared adversarial-review engine

> Cited by `compass:review-contract` (light), `compass:review-plan` (full), `compass:review-build` (full).
> These three reviews differ in **lens, streams, and depth**; they share this **engine**.

## The engine (same in all three reviews)

1. **Fan out, don't read linearly.** Spawn specialized review streams in parallel (the streams list comes from the specific review skill). For the full reviews use Dynamic Workflows / multi-agent; the light review can be a single focused pass.
2. **Assume it fails.** For every finding, capture: what breaks · which existing feature/workflow/invariant it impacts · why · severity · concrete fix · the test/validation that proves the fix.
3. **One issue ledger.** Merge all stream outputs into a single append-only ledger (`review-ledger.md`):

   | Issue ID | Affected area | Failure mode | Impacted feature/workflow/invariant | Severity | Root cause | Concrete fix | Validation required | Owner stream | Status |

4. **Prove, don't vibe.** Every "it's correct / it's fixed" is backed by a real check — see `verify-ladder.md`. Agent agreement is **not** evidence. (At the *contract* and *plan* stages there is no code to test — there the proof is **grounding**: every claim verified against the real repo/data, or flagged as an explicit open risk.)
5. **No scope creep.** No broad refactors, renames, formatting-only or product-behavior changes unless required to fix a documented finding.

## The convergence loop

Repeat: **review → fix → re-validate → re-review.** After round 1's broad sweep, **rounds 2+ re-review only the surface the fixes touched** (diff-scoped) + re-run the real checks — do *not* re-run the full fleet every round.

**Stop only when:** two consecutive rounds surface no new material issue (**converged**), or the review's iteration cap is hit.

**Caps (ceiling, not target — most converge earlier):**
- `review-contract` → **2**
- `review-plan` → **3**
- `review-build` → **5**

**Hitting a cap WITHOUT convergence is never "converged."** It means: **stop, document remaining open risks, and escalate UP a level** —
- plan review stuck at cap → the **contract** is likely under-specified → bounce to `compass:contract`.
- build review stuck at cap → the **plan** likely has a design flaw → bounce to `compass:plan`.

## Grounding (the invariant)
If a `contract.md` exists, **read it first** and check the artifact against it — a deviation from the contract is itself a CRITICAL finding (the build/plan drifted from what was agreed). If no contract exists (standalone use), say so plainly: "ungrounded — no contract to check against," and offer to create one.

## Output
Feature-by-feature failure modes · regression risks · completeness gaps (vs contract) · security/RBAC/data-leakage · performance/OOM · DB/migration · missing tests · concrete fixes before merge · final sign-off criteria · per-iteration log (streams spawned · new issues · fixes · checks run · failures remaining · converged?).
