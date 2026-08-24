---
name: explain
description: On-demand deep teaching — explains how Compass works, or walks you (or a stakeholder) through a specific build, at whatever depth you want. The "help me understand this" surface. Invoked when the user asks to understand Compass or a build; not a user menu entry (user-invocable:false).
user-invocable: false
---

# compass:explain

Teach, don't just answer. This skill gives a genuine, plain-English walkthrough — big picture first, one piece at a time, an analogy and a concrete example before any jargon.

**Do this now:** read **`plugins/compass/shared/walkthrough.md`** — it owns the teaching method, and it ships with this plugin so it is present on every install. Then frame the walkthrough to the request:

**Optional enhancement, with a fallback:** if a richer walkthrough skill is installed at user level, you may also invoke the **Skill** tool with `skill: feynman-walkthrough` to produce a durable explainer the person can revisit. **If it is not installed, do not stop and do not mention it** — `shared/walkthrough.md` is the method and the explanation is just as good; what is lost is the saved artefact, not the teaching. Compass does not ship that skill, and for three releases this stage pointed at it with no fallback, which meant the teaching surface worked only on its author's machine.

- **"How does Compass work?"** → teach the mental model: contract-first, then the assembly-line-with-gates (contract → review → plan → review → build → review → ship), why each gate is a real script check, and how nothing advances until it proves it matches the locked contract.
- **"Explain this build to me / to a stakeholder."** → read the active build's state (`compass.sh state-root` → its `contract.md` / `progress.md` / `plan.md` / `receipts.md` / `review-ledger.md`) and walk through what it's building, where it stands, what the reviews caught, and what's next — pitched at the audience (engineer vs. non-technical stakeholder). Offer to render the visual **Contract Brief** / **Cockpit** via `compass-visual` as the accompanying picture.

Match the depth to the ask: a 60-second orientation, or a full guided walkthrough. This teaches; it never changes build state or advances a stage.
