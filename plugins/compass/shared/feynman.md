# The writing standard for reader-facing copy

Loaded by the contract, plan and ship stages before they write the **reader-copy block** that
`gen.mjs` lays out. It governs the words on an artefact, not the words in `contract.md` — a contract
may be as precise and jargon-dense as it needs to be. The artefact is where a person decides.

Extracted from the `feynman-walkthrough` skill so installers get it with the plugin and do not
depend on that skill being present.

## Why this file exists

The pre-change Contract Brief was scored by a fresh reader who had never seen the project. Their
verdict: *"I could tell you what button to press; I could not tell you whether pressing it is a
good idea."* Roughly a third of the visible words were undecodable — `Gold`, `Blast Radius`,
`emits a body fragment`, `invariants`, `cold reader`. The page was not badly laid out. It was
written for someone who already knew the answer.

## The bar

A **fresh reader**, given only the rendered page, can state — unhedged — its **one message** and
what that message **implies**. If they hedge, reconstruct a different message, or ask for more,
**the page failed and the fix is in the page**. Never in prose wrapped around it, and never in a
briefing given to the reader first.

## The six rules

1. **Plain words first, the precise term second.** Introduce the plain version, then name it:
   *"the number we check the result against — the gold"*. Never the reverse, and never the term
   alone. A term used before it is introduced is a term the reader skips.
2. **The most prominent element states the message, not the topic.** A heading that says
   `Reconciliation` names a subject. A heading that says `This number is checked against an audited
   figure, not against itself` states the point. Emphasis is structure, not decoration.
3. **Concrete before abstract.** One worked instance before any generalisation. "3 of 24 shipped
   builds report zero steps done, and two of them shipped at 16/17" lands; "progress counts can be
   inaccurate" does not.
4. **An analogy must state where it breaks**, or it is decoration. *"A gate is a turnstile — it
   stops you until you show the ticket. Unlike a turnstile, this one can be left unlocked by the
   person walking through, which is the bug."*
5. **No internal code on a reader-facing surface.** No `INV-*`, no `cmd_*`, no bare file path, no
   invented compound (`N/A-pass`, `guard-first`) without its plain gloss in the same sentence.
   Names of things the reader will click or type are fine — those are theirs, not ours.
6. **A breaking point is a gap in the explanation, never the reader's fault.** If the cold read
   fails, do not add a sentence explaining the sentence. Decompose the step, find a concrete
   example, or change what the prominent element says.

## What this is not

It is not a request to be vague. Precision and plainness are the same move: *"the buckets are
analyst-coded and cannot be reproduced"* is both plainer and more precise than *"the gold has
provenance issues"*. If a plain sentence loses information, the sentence is wrong, not the rule.

## How it is enforced

- `compass.sh copy-gate` reads **only** the reader-copy block and fails on rule 5, the one rule
  that is mechanically checkable. It never inspects quoted contract text, the invariant table, or
  code shown as code — a gate that fires on correct work gets disabled within a week.
- Rules 1–4 and 6 are not mechanically checkable, and pretending otherwise would be its own kind of
  decoration. They are enforced by the **cold read** (`node scripts/insight-gate.mjs --artefact <f> --intent <f> --grader <f>`), which measures the
  only thing that matters: whether a stranger can state the message and its implication.
