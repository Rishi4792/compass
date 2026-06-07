---
name: contract
description: Define a build's CONTRACT — the single locked spec that becomes the invariant for the whole build. Runs as an interview (AskUserQuestion), refusing to finish until every required section is filled — how data is derived, schema, UI/UX design tokens, elements, features, AND measurable acceptance/accuracy goals. Trigger when starting any non-trivial feature/build, or when the user says "define the contract", "compass contract", "spec this out", or invokes /compass.
---

# compass:contract

The contract is the **single source of truth** for what gets built — the invariant every later step is checked against. A vague contract guarantees drift. This skill **interviews** the user until the spec is airtight, then writes `contract.md`.

## Hard rule
**Do not finish until every required section below is filled and unambiguous.** If the user leaves one thin, *push back* — ask the specific question that closes the gap. An incomplete contract is a failed contract.

## Procedure

1. **Locate the build folder.** `.claude/builds/<feature-slug>/` (create it). The contract is written to `.claude/builds/<feature-slug>/contract.md`.

2. **Interview, section by section, using AskUserQuestion.** Ask only what's missing; infer sensible defaults and *confirm* them rather than asking open-ended. Required sections:
   - **Goal & scope** — what this build does, who it's for, what's explicitly OUT of scope.
   - **Data derivation** — where every number/field comes from, the exact rule (source table → transform → output). If it reconciles to something, name it.
   - **Schema** — tables/models/columns touched or added; relationships; what's authoritative.
   - **UI/UX** — design tokens (colors, type, spacing), components/elements, the user flow, empty/loading/error states.
   - **Features** — each feature, stated as a behavior ("when X, the user sees Y").
   - **Acceptance & accuracy goals** — the *measurable* bar (e.g. "disbursements reconcile to ₹X ±1%", "page loads <2s", "RBAC: L3 sees only their branches"). Mark any the user calls non-negotiable as **INVARIANT**.
   - **Non-goals / constraints** — what must NOT change; performance/security/cost invariants.

3. **Every requirement must be testable.** For each feature/goal, ensure there's a concrete way to verify it. If a requirement can't be checked, rewrite it until it can — or flag it.

4. **Write `contract.md`** in the build folder using the structure below. Mark INVARIANT items clearly.

5. **Update `progress.md`**: stage = ① Contract (draft), next = Review-1.

6. **Hand to the gate** (the orchestrator presents Approve / Revise / Pause / Show full artifact). Standalone, just tell the user the contract is drafted and suggest `compass:review-contract`.

## contract.md structure
```markdown
# Contract — <feature>
> Locked: <date>. THE INVARIANT. Every Compass step checks against this; deviation = STOP.

## Goal & Scope        ## Data Derivation     ## Schema
## UI / UX             ## Features            ## Acceptance & Accuracy Goals (mark INVARIANT)
## Non-Goals / Constraints
```

## Done when
Every section is filled, every requirement is testable, INVARIANTs are marked, and `contract.md` is written. Then it must pass `compass:review-contract` before becoming the locked invariant.
