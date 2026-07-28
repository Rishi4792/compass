---
description: On-demand deep teaching — explains how Compass works, or walks you (or a stakeholder) through a specific build, at whatever depth you want. The "help me understand this" surface.
---

# /compass:explain

Teach, don't just answer. `/compass:explain` gives a genuine, plain-English walkthrough — big picture first, one piece at a time, an analogy and a concrete example before any jargon.

**Do this now:** invoke the **Skill** tool with `skill: feynman-walkthrough` — it owns the teaching method (feynman-walkthrough-grade: simple language, structured for real understanding, with an explainer you can revisit or hand to someone else). Frame the walkthrough to the request:

- **"How does Compass work?"** → teach the mental model: contract-first, then the assembly-line-with-gates (contract → review → plan → review → build → review → ship), why each gate is a real script check, and how nothing advances until it proves it matches the locked contract.
- **"Explain this build to me / to a stakeholder."** → read the active build's state (`compass.sh state-root` → its `contract.md` / `progress.md` / `plan.md` / `receipts.md` / `review-ledger.md`) and walk through what it's building, where it stands, what the reviews caught, and what's next — pitched at the audience (engineer vs. non-technical stakeholder). Offer to render the visual **Contract Brief** / **Cockpit** via `compass-visual` as the accompanying picture.

Match the depth to the ask: a 60-second orientation, or a full guided walkthrough. This command teaches; it never changes build state or advances a stage.
