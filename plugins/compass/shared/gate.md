# Compass — canonical stage-transition gate

This is the **single source of truth** for the stage-transition gate. The block between the
`GATE:START` / `GATE:END` markers below is inlined **verbatim** into every stage skill
(`skills/*/SKILL.md`). A smoke assertion (`compass.smoke.sh`)
fails the build if any copy drifts from this one — so the gate can never silently diverge
across entry paths (invoked as a stage skill, or sequenced by the `compass:start` orchestrator).

Editing the gate? Edit the block here, then re-run `bash plugins/compass/scripts/compass.smoke.sh`
and propagate the identical block to every consumer until the assertion passes.

<!-- GATE:START -->
## Stage transition — the gate (fires on EVERY entry path)

This stage owns its own transition gate. Present it whether this stage was invoked on its own
(the `compass:build` skill) or sequenced by the `compass:start` orchestrator. The orchestrator
does **not** present a second gate — the stage owns it.

1. First print the one-line **transition footer**, in exactly this shape:

   `✓ <this stage> PASSED — <one-line proof>.  Next: <next stage> · run \`/compass:go\`.`

   That footer line is for the READER: it names where they are and the door they can take if they
   want to steer. It is not your instruction — yours is the Approve branch at the end of this block.

   `<next stage>` is not guessed. Run `compass.sh next-stage <build-dir>` and branch on its EXIT
   CODE, never on its output, because two different states both print nothing:
   **0** → the stage it named · **3** → every stage has passed, so Next is `done — build SHIPPED` ·
   **anything else** → the build state could not be read; say exactly that and stop, rather than
   guessing a stage or reporting the build finished.

   Then PUSH the RAIL when this stage produced an artefact — run
   `compass.sh rail <build-dir> --artefact <view> --url <the published URL>` (or `--local <path>`
   when nothing could publish it) and show it, so the link is in front of the user beside the
   buttons rather than described in prose. (v0.30: the rail existed and nothing called it — a
   surface nobody invokes is not a surface, the same defect this build was raised to fix.)

   Then PUSH the cockpit — run `compass.sh cockpit <build-dir>` and show it — so the user always
   sees where they are (the 7-stage strip · step k/n · next; plus program phases + contracts when
   in a program) with **zero typing** (v0.24.0 INV-PUSH-STAGE). Silence between stages is a defect.

   Then RUN the stage-end gate on what you just printed — `compass.sh cockpit-gate <build-dir>`.
   It checks the four elements a reader needs are actually there (what happened · where you are ·
   what is next · the options, each naming a real command). v0.32 built it and NOTHING invoked it,
   so it never ran on a single installation; v0.33.3 wires it here, which is its only correct home
   because it validates a block the model PRINTS rather than a file on disk. Non-zero → fix the
   block and print it again before presenting the gate.

2. Then present the gate using **AskUserQuestion** with exactly these **4 options**
   (AskUserQuestion caps at 4; "Show full artifact" is offered via the auto-provided **Other**,
   or just print the artifact if the user asks):
   - **Approve & continue** — advance to the next stage.
   - **Revise** — re-run this stage with the user's change.
   - **Amend** — a legitimate scope change (not drift): bump the contract version + changelog,
     run a mini review-contract on the delta, `supersede` downstream, re-baseline.
   - **Pause here** — stop cleanly; write the resume pointer to `progress.md`.

Only **Approve** or **Amend** advances — and on **Approve** you CONTINUE, you do not stop to ask a
second time. Run `compass.sh next-stage <build-dir>` — the build directory is the one this stage has
been working in — and on exit 0 **invoke the named stage with the Skill tool**, whose skill name is
`compass:` followed by that stage, exactly the way this stage was invoked. On exit 3 the build is
finished; on any other code, say the state could not be read and stop. The user has already said
yes; the silence after that yes is the stall this gate exists to end.

The seven stage skills are hidden from the `/` menu, and that is not an obstacle — it is a division
of labour. A person types **`/compass:resume`**; a model uses the Skill tool. Both reach the same
stage. What nobody has is a `/compass:` slash command named after a stage, so never print one: it
sends the reader to a door that is not there.

On **Revise**, re-run this stage with the change. On **Pause**, stop cleanly. On any detected drift
from `contract.md`, STOP and surface instead of advancing.

*(Until v0.35 this paragraph forbade invoking the next skill at all. It told the reader what would
NOT happen and never what would, so an approved stage ended in silence and the build waited for a
human to remember the next command. The old sentence is not quoted here, because the check that
proves it is gone greps for it — a note about a banned string that contains the banned string keeps
the defect alive in the file that fixed it. The gate still ASKS. What changed is that an answer of
Approve is now acted on rather than described.)*
<!-- GATE:END -->
