# Compass — canonical stage-transition gate

This is the **single source of truth** for the stage-transition gate. The block between the
`GATE:START` / `GATE:END` markers below is inlined **verbatim** into every stage skill
(`skills/*/SKILL.md`) and into `commands/start.md`. A smoke assertion (`compass.smoke.sh`)
fails the build if any copy drifts from this one — so the gate can never silently diverge
across entry paths (standalone skill, namespaced `/compass:<stage>` command, or `/compass:start`).

Editing the gate? Edit the block here, then re-run `bash plugins/compass/scripts/compass.smoke.sh`
and propagate the identical block to every consumer until the assertion passes.

<!-- GATE:START -->
## Stage transition — the gate (fires on EVERY entry path)

This stage owns its own transition gate. Present it whether the stage was run standalone
(bare skill, e.g. `/build`), via the namespaced command (`/compass:build`), or sequenced by
`/compass:start`. The orchestrator does **not** present a second gate — the stage owns it.

1. First print the one-line **transition footer**, in exactly this shape:

   `✓ <this stage> PASSED — <one-line proof>.  Next: <next stage> · run \`/compass:<next stage>\`.`

   (For the terminal `ship` stage, Next is `done — build SHIPPED`.)

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
