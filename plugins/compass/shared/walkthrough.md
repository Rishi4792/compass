# Teaching a build — the walkthrough standard

Loaded by the **explain** stage. It governs how Compass explains itself or a build to a person.

## Why this file exists

`/compass:explain` used to open by telling the model to invoke a skill called
`feynman-walkthrough`. Compass has never shipped that skill. It is a personal, user-level skill on
its author's machine, so on **every other installation the teaching surface pointed at nothing** —
with no fallback stated. Three releases shipped that way.

The method is not complicated and there is no reason it should live outside the plugin. It is here.

## The method

1. **Big picture before any part.** Say what the whole thing is for in one sentence before naming a
   single component. Someone who does not know why a machine exists cannot follow a tour of its
   parts.
2. **One idea per step, in the order a person meets them.** Not the order the code is organised in.
3. **A concrete instance before the general rule.** "Three shipped builds reported zero steps done,
   and two of them had finished" lands. "Progress counts can be inaccurate" does not.
4. **Plain word first, precise term second** — *"the number we check the result against — the
   gold"*. Never the term alone, and never the term before its plain version.
5. **An analogy must say where it breaks**, or it is decoration. *"A gate is a turnstile: it stops
   you until you show a ticket. Unlike a turnstile, this one can be left unlocked by the person
   walking through — which is the bug."*
6. **Check understanding at the end, not throughout.** Interrupting to quiz someone mid-explanation
   costs more than it finds. Ask afterwards where it went thin, and fix the explanation there.
7. **A breaking point is a gap in the explanation, never the listener's fault.** If it did not land,
   do not add a sentence explaining the sentence — decompose the step or find a better example.

## Pitch it to the person in front of you

- **"How does Compass work?"** → the mental model: a contract locked first, then an assembly line
  where nothing advances until a real command proves it matches that contract.
- **"Explain this build"** → read the build's own state and walk through what it is building, where
  it stands, what the reviews caught, and what happens next — pitched at an engineer or at someone
  who will never read the code, depending on who is asking.
- **60 seconds or an hour.** Match the depth to the ask. Teaching is the goal; it never changes
  build state and never advances a stage.

## The optional enhancement

If a richer walkthrough skill is installed at user level, use it — it produces a durable explainer a
person can revisit. **It is an enhancement, never a dependency.** When it is not installed, this
file is the method, and the explanation is just as good; what is lost is the saved artefact, not the
teaching.
