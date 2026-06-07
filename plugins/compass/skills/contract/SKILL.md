---
name: contract
description: Define a build's CONTRACT — the single locked spec that becomes the invariant for the whole build. Runs as an interview (AskUserQuestion), refusing to finish until every required section is filled and unambiguous — data derivation, schema, scale, auth, dependencies, UI/UX design tokens, features, reconciliation-to-a-goal, AND measurable acceptance/accuracy goals. Trigger when starting any non-trivial feature/build, or when the user says "define the contract", "compass contract", "spec this out", or invokes the Compass orchestrator.
---

# compass:contract

The contract is the **single source of truth** for what gets built — the invariant every later step is checked against. A vague contract guarantees drift. This skill **interviews** the user until the spec is airtight, then writes `contract.md`.

## Hard rule
**Do not finish until every required section below is filled and unambiguous.** If the user leaves one thin, *push back* — ask the specific question that closes the gap. An incomplete contract is a failed contract.

## Procedure

1. **Locate the build folder.** `.claude/builds/<feature-slug>/` (create it). Write the contract to `.claude/builds/<feature-slug>/contract.md`. **Also write the slug to the fixed pointer `.claude/builds/CURRENT`** (one line: the slug) so any later session / the orchestrator knows which build is active — never rely on globbing the folder.

2. **Interview, section by section, using AskUserQuestion.** Ask only what's missing; infer sensible defaults and *confirm* them rather than asking open-ended. **Required sections — each must be filled or explicitly marked `N/A` (a silent omission is a defect, an explicit N/A is a decision):**
   - **Goal & scope** — what this build does, who it's for, what's explicitly OUT of scope.
   - **Data derivation** — where every number/field comes from, the exact rule (source table → transform → output).
   - **Reconciliation goal** — *if the build outputs any number*, this is REQUIRED and an INVARIANT by default: name the **gold source**, the **exact target figure**, the **tolerance** (e.g. ±1%), and the **query that reproduces it**. "The numbers add up to X" must be pinned, not implied.
   - **Schema** — tables/models/columns touched or added; relationships; what's authoritative.
   - **Scale** — expected row counts, request volume, concurrency. (The plan checks against real volume — without a stated target there's no bar.)
   - **Auth model** — who logs in, session mechanism, how a test harness authenticates (needed for the verify step later).
   - **Dependencies / integrations** — third-party APIs, DB ids, rate limits, anything external.
   - **UI/UX** — design tokens (exact colors, type scale, spacing), components/elements, the user flow, empty/loading/error states. (These tokens get VERIFIED in review-build — they are not decoration.)
   - **Features** — each feature stated as a behavior ("when X, the user sees Y").
   - **Acceptance & accuracy goals** — the *measurable* bar (reconciliation ±X%, page <2s, RBAC: L3 sees only their branches). Mark non-negotiables as **INVARIANT**.
   - **Idempotency / failure & retry** — what must be safe to re-run; behaviour on partial failure.
   - **Rollback** — what "revert" means to the user; what must NOT be lost.
   - **Observability** — how we'll know in prod it's still correct.
   - **Non-goals / constraints** — what must NOT change; performance/security/cost invariants.

3. **Every requirement must be testable.** For each feature/goal, ensure a concrete way to verify it. **Deferred-flag cap:** an item may be flagged "resolve in plan" ONLY if it is non-INVARIANT and non-acceptance, AND it names who/when/how it resolves. **Zero deferred flags are allowed on INVARIANT or acceptance items** — those block the lock until pinned. A contract full of "assumption: TBD" is not "complete."

4. **Write `contract.md`** using the structure below. Mark INVARIANT items clearly.

5. **Update `progress.md`** (create if absent): stage = ① Contract (draft), status = draft, next = Review-1.

6. **Standalone STOP.** If run on its own (not under the orchestrator): tell the user the contract is drafted, suggest `compass:review-contract`, and **STOP — do not invoke the next skill yourself.** Under the orchestrator, hand to the gate.

## contract.md structure
```markdown
# Contract — <feature>
> Locked: <date>. THE INVARIANT. Every Compass step checks against this; deviation = STOP.

## Goal & Scope     ## Data Derivation   ## Reconciliation Goal (gold source · figure · tolerance · query)
## Schema           ## Scale             ## Auth Model        ## Dependencies / Integrations
## UI / UX (exact design tokens)          ## Features          ## Acceptance & Accuracy Goals (mark INVARIANT)
## Idempotency / Failure & Retry          ## Rollback          ## Observability
## Non-Goals / Constraints
```

## Done when
Every section is filled or explicitly N/A, every requirement is testable, reconciliation (if any numbers) is pinned, INVARIANTs are marked, no deferred flag sits on an INVARIANT/acceptance item, `CURRENT` + `progress.md` are written, and `contract.md` exists. Then it must pass `compass:review-contract` before becoming the locked invariant.
