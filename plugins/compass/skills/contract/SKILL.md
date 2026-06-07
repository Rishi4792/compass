---
name: contract
description: Define a build's CONTRACT — the single locked spec that becomes the invariant for the whole build. Runs as an interview (AskUserQuestion), refusing to finish until every required section for the project type is filled and unambiguous — data derivation, schema, scale, dependencies, reconciliation-to-a-goal (exact by default), acceptance INVARIANTs, and (web) auth + UI tokens. Trigger when starting any non-trivial feature/build, or when the user says "define the contract", "compass contract", "spec this out", or invokes the Compass orchestrator.
---

# compass:contract

The contract is the **single source of truth** — the invariant every later step is checked against. A vague contract guarantees drift. This skill **interviews** until the spec is airtight, then writes `contract.md`.

## Hard rule
**Do not finish until every required section for the project type is filled and unambiguous.** Push back on thin answers. An incomplete contract is a failed contract.

## Procedure
1. **Build folder & index.** Create `.claude/builds/<feature-slug>/`. Write the slug to `.claude/builds/CURRENT` (active build) AND append a line to `.claude/builds/INDEX` (`<slug> · <one-line goal> · status=draft · touches=<top-level paths it will change>`). If INDEX already lists a build whose `touches` overlaps this one, **surface it and ask** before continuing — two builds editing the same files can collide.

2. **Pick the Project Type** (it switches which sections are required): **web-app** · **data-pipeline / CLI** · **library**.

3. **Interview with AskUserQuestion.** Ask only what's missing; confirm sensible defaults rather than asking open-ended. **Each required section must be filled or explicitly `N/A` (silent omission = defect; explicit N/A = a decision).**
   - **All types:** Goal & scope · Data derivation · Schema/output shape · Scale (volume, concurrency) · Dependencies/integrations · Features (as behaviors "when X → Y") · Acceptance & accuracy goals (measurable; mark non-negotiables **INVARIANT**) · Idempotency/failure & retry · Rollback (what "revert" means, what must not be lost) · Observability (the exact metric/log that proves it's still correct in prod) · Non-goals/constraints.
   - **Reconciliation goal (REQUIRED whenever the build outputs any number; INVARIANT by default):** name the **gold source**, the **exact target figure**, the **reproducing query/command**, and the **tolerance — which DEFAULTS TO 0 (exact match).** A non-zero band is allowed ONLY with a written justification and is flagged for the user to sign off. "Close to actual" is not acceptable by default.
   - **web-app also requires:** Auth model (who logs in, session mechanism, how a test harness authenticates) · UI/UX (exact design tokens — colors/type/spacing; flow; empty/loading/error states; optionally a **reference artifact path** if a visual diff target exists). Tokens get VERIFIED later — they aren't decoration.
   - **data-pipeline/CLI also requires:** Input-data contract · Determinism (same input → identical output) · Output schema · Run reproducibility. (Auth/UI tokens → N/A.)

4. **Testability + deferred-flag cap.** Every requirement needs a concrete check. An item may be flagged "resolve in plan" ONLY if non-INVARIANT and non-acceptance AND it names who/when/how. **Zero deferred flags on INVARIANT or acceptance items** — they block the lock until pinned.

5. **Write `contract.md`** (mark INVARIANTs). **Update `progress.md`** (stage ① Contract draft, next = Review-1).

6. **EMIT RECEIPT** — append to `.claude/builds/<slug>/receipts.md`:
   ```
   ## RECEIPT — contract · <slug> · PASS
   - [x] project type: <web-app|data-pipeline|library>
   - [x] all required sections filled or explicit N/A
   - [x] reconciliation pinned (gold/figure/query/tolerance) or N/A (no numbers)
   - [x] tolerance = 0 exact  (or: band <t> justified, awaiting user sign-off)
   - [x] no deferred flag on any INVARIANT/acceptance item
   - [x] CURRENT + INDEX + progress.md written
   ```
   (Any box you cannot check → status FAIL, list what's missing, do not hand on.)

7. **Standalone STOP.** Suggest `compass:review-contract` and **STOP — do not invoke it yourself.** Under the orchestrator, hand to the gate.

## Done when
The receipt is PASS: every required section filled/N/A, reconciliation pinned at exact tolerance (or a justified band awaiting sign-off), no deferred flag on an INVARIANT, CURRENT/INDEX/progress.md/receipt written. Then it must pass `compass:review-contract` to become the locked invariant.
