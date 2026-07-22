# Compass — Five Improvements: Research, Feasibility, Designs
**Date:** 2026-07-21 · **Method:** 22-agent workflow (usage audit of 12 real builds + 10 deep web-research agents + Claude-Code feasibility red-team per point + design synthesis per point). ~2.4M tokens, 602 tool calls, all findings source-cited.

---

## TL;DR

- **Points 1 + 2 + 3 converge on ONE build (v0.12):** the post-ship critique loop, with eyes, framed as a verifier node in Compass's graph. The research for all three lands on the same spine: *critique only works when grounded in observed external evidence; loops need bounded, evidence-based stop rules; the verifier belongs in its own node.*
- **Points 4 + 5 converge on a SECOND build (v0.13):** the contract interview becomes a co-construction protocol (scan → frame → expand → converge → clarify → lock) with a live sketch loop (HTML wireframe for UI, Mermaid logic map otherwise) rendering while you decide.
- Both are M-sized (2–3 sessions each). `jarvis-sniper-obs` is entering post-ship round 1 right now — the perfect dogfood target for v0.12.

---

## What the usage audit found (12 builds read end-to-end)

1. **You already hand-write the post-ship loop.** Your last 3 Jarvis contracts carry a §8 "post-ship critique" + `INV-POSTSHIP-LOOP`: critique the LIVE system, loop back to plan on material findings, terminate on **2 consecutive clean rounds or 5 iterations**, fire-g2 at cap. It ran for real and earned its keep:
   - `jarvis-cos`: converged 3/5; round 1 caught noisy "Needs your eye" triage.
   - `jarvis-biz-digest`: ran the full 5; round 1 caught a missing spec section; round 3 caught a spec gap AND a 109s perf regression introduced by its own round-1 fix ("a fix is new code" proven live).
2. **Eyes exist but are ad-hoc.** `jarvis-hud-ui` used screenshots as receipts + a human GOLD-DESIGN sign-off ("Looks great."). `gq-brain-agent-ux-revamp` is the flagship: cold screenshots → fresh-context critic → **2 consecutive cold GOs, any code change resets the counter** — and its post-deploy loop caught a prod data bug (EMI table vs card summary reading different sources) that no test suite would find. Counter-case: GQ CRM builds couldn't screenshot (OAuth-gated) and deferred to your eyeball — the design must handle blindness explicitly.
3. **Critic pathology is real:** gq-brain's loop burned ~1.8M critic tokens ending in critic-vs-critic contradictions and "rotating taste nits" — the anti-nit stop rule below is mandatory, not optional.
4. **Screenshots get dumped anywhere** (jarvis-google's GCP screenshots live in jarvis-tg-hud's folder) — needs a canonical `evidence/` convention.
5. **Contracts already read as co-design** (numbered "decisions locked" blocks), but the expansion depends on session mood — nothing enforces that alternatives were explored.

---

## Point 1 — Post-ship critique loop (works better in loops)

### Research spine (cited)
- **Intrinsic self-critique fails.** Huang et al. (ICLR 2024): accuracy DROPS after self-correction without external signal (GSM8K 75.9→74.7; CommonSenseQA 75.8→38.1). Stechly et al.: GPT-4 self-critique collapsed graph-coloring 16%→2%, while the same loop with a sound external verifier hit 38–44% and improved monotonically. **The loop is only as good as its verifier; verifier error rate is the ceiling** (Reflexion's flaky self-generated tests made looping worse than no loop).
- **Gains concentrate early.** Self-Refine got most improvement in iteration 1, capped at 4; aider hardcodes 3 reflections; Anthropic: always set a max-iteration stop. Your 2-clean/5-cap numbers are exactly in the evidence range.
- **Practitioner loop shape (Ralph pattern, Anthropic long-running-agent harness, AlphaEvolve, autoresearch):** dumb outer loop, **fresh context per iteration, all state on disk**, one unit of work per iteration, machine-checkable verifier as the only stop signal, convergence = streak of clean passes (never one lucky pass), and **all three ceilings** (iterations + cost + wall-clock) because they fail differently.
- **Post-ship specifically:** the proven industrial loop is the SRE canary cycle — observe pre-declared metrics on the live system, pause/rollback on breach.

### Design (merged with Point 2 — see reconciliation)
- Contract header `post-ship-loop: on (clean 2 / cap 5) | off — <reason>` — **default ON for every shipping build** (waiver mirrors `deploy: out-of-scope`). Optional `post-ship-check: <cmd>` lines pin domain checks ("reconcile every number vs Metabase") as commands, not prose.
- **No verifier → no loop** (INV-PS9): a pre-flight check requires at least one external signal (RECON-CMD, declared routes, or post-ship-check lines) — the loop refuses to run on model self-critique alone; blindness fires G2 for your eyeball.
- Per round: fresh-context critic subagent (in-session — never headless spawn, honoring your stall memory), inputs = contract + live evidence ONLY. **Reproduce-to-count:** a Crit/Maj finding exists only when reproduced by a re-run command; else it's a note.
- Loop state in line-oriented `loop.log` + `PS-<round>-<k>` rows in the existing review-ledger. Anti-pathology teeth: **no-progress detection** (MATERIAL with unchanged git sha) and **ping-pong detection** (A,B,A,B sha alternation) both hard-fail to G2.
- Convergence gate = script exit code wired into `lifecycle-audit SHIPPED`: **SHIPPED becomes mechanically unwritable** until converged / waived / user-accepted-at-cap. Cap with open findings → fire-g2, never fake done.
- In `--auto`, every round runs `budget-check --bump-stage` — the existing wall/session/stage ceilings bound the loop with zero new budget machinery.
- The loop primitive is phase-parameterized (`loop-round <dir> <phase>`), so review stages can adopt the same rail later — the "make Compass work in loops" foundation.

---

## Point 2 — Eyes (AI is better at critique than building)

### Research spine (cited)
- **The generator–verifier gap is real and large** — Weaver: 37-point gap between what a model can generate at pass@100 vs select; the gap GROWS with scale ("Mind the Gap"); OpenAI's CriticGPT catches more code bugs than paid human reviewers. **But** SELF-[IN]CORRECT shows models are NOT reliably better at judging their own outputs — the gap only pays out when the critique is **grounded in an observed artifact**: execution feedback (Self-Debugging), tool feedback (CRITIC), rendered screenshots (Design2Code; Anthropic's official guidance: mock → implement → screenshot → compare → iterate, "typically much better after 2–3 iterations").
- **Tooling economics:** MCP browser loops are token-heavy (~114K per 10-step task; a base64 full-page screenshot can exceed 200K tokens). **One-shot headless Playwright capture to disk is ~4× cheaper**; resize to ≤1568px long edge ≈ 1,500 tokens per image. Pixel-diff (Playwright toHaveScreenshot/Backstop/Percy) for stable baselines in CI; **semantic vision critique for "is this good?"** judgments — Compass wants the latter.
- **Rubric quality matters:** decomposed dimensions (layout · spacing · typography · tokens · hierarchy · states · numbers-vs-contract), region-anchored findings ("name the element"), difference-listing vs the spec — never 1–10 scores.

### Design (the "eyes" half of v0.12)
- **Observation channel declared at CONTRACT time** so ship never discovers blindness late: web → prod URL + env-supplied auth + states/viewports; pipeline → digest command (≤50 key lines, never raw log dumps); library → suite + one real consumer invocation.
- Evidence lands in canonical **`<build-dir>/evidence/round-<n>/`** (fixes the scattered-PNG mess). A round without on-disk evidence does not count: the gate checks file existence, PNG magic bytes, ≥20KB floor (your own jarvis INV-CARD anti-blank heuristic).
- **Anti-nit stop rule (INV-EYES-4):** a material finding must cite the contract line/INVARIANT it violates; uncited findings are FUTURE rows — logged, fed to the next contract, never blocking. This is the scripted fix for the 1.8M-token taste-nit spiral.
- **Blocked channel never silently skips:** OAuth/air-gapped → your quoted eyeball (`HUMAN-OBSERVED: "Looks great."` — the hud GOLD-DESIGN pattern) counts as that round's evidence, or the explicit waiver line. No fallback + no screenshots = hard fail surfaced.
- **Cold-critic gate for web builds (institutionalizes your 2×cold-GO memory):** fresh subagent, ONLY cold screenshots + design spec (no builder reasoning — breaks echo-checking); receipts carry `tree=<git sha>`; `coldgo-gate` passes only when the last 2 GOs carry the IDENTICAL sha — **any commit between GOs mechanically resets the streak.** Fallback=human-eyeball for un-screenshotable apps.

---

## Point 3 — "Graphs" (what the buzz actually is + how it applies)

### What happened (dated, verified)
- **The trend is "graph engineering,"** crystallized **Jul 18, 2026** by Peter Steinberger's tweet "Are we still talking loops or did we shift to graphs yet?" (~575K views in hours) — the same person who triggered June's "loop engineering" wave. Within hours: Carlos E. Perez's "From Loop Engineering to Graph Engineering?" essay; @svpino's "Loop Engineering is dead. Long live Graph Engineering!"; backlash from @PawelHuryn ("I call BS") and @DavidKPiano ("it's just state machines"). Explainer wave Jul 19–20 (HN, AI Builder Club, Towards AI, substacks).
- **The concept:** wire agents into an explicit directed graph — nodes = agents each running their own observe-act-verify loop; edges = designed hand-offs; **verifiers split into independent nodes** to break "echo checking" (two systems sharing a blind spot agree on it with total confidence); cycles bounded by evidence-based stop rules. The stack meme: prompt → context → harness → loop → **graph**.
- **Consensus: a naming event, not new tech** (LangGraph 1.0 shipped Oct 2025; AutoGen GraphFlow, Google ADK predate it). The practical core (AI Builder Club, Jul 20): default to a loop; a node is justified only by one of **five signals** — distinct specialty · parallel fan-out · different model per node · auditable branching · overloaded verifier. "The smallest honest graph is worker + independent verifier." Keep graphs **collapsible** — delete any node you can't tie to a signal.
- **Rival threads (older, not this week's spike):** "context graphs" (Foundation Capital, Dec 2025 — decision-trace memory) and temporal knowledge-graph memory (Graphiti/Zep). Don't build the wrong one.

### How it applies to Compass
1. **Compass already IS the thing being named.** contract→reviews→plan→build→ship with script-enforced edges and adversarial fan-outs is a textbook org-graph with verifier nodes and hard-coded (never LLM-chosen) edges — the trend validates the architecture. This is a marketing gift: a README/start.md block ("Compass is a graph: 7 fixed org-graph stages, per-build work-graph nodes, edges are exit codes") timed to the discourse.
2. **The one real topology hole is post-ship** — the graph ends at SHIPPED while you hand-draw the missing verifier node into every contract. v0.12 (points 1+2) IS the on-trend move: adding the bounded post-ship verifier cycle + the independent cold-critic node.
3. **Later (v0.14+ candidates, from the applied-graphs research):** flat-file typed-edge graphs emitted deterministically at receipt gates (never LLM-extracted, never a graph DB): invariant→check traceability (gate = reachability query), and a cross-build knowledge graph ("what did past builds learn about this file" injected at plan time — the aider repo-map pattern). Park these; they're real but not this month.

---

## Point 4 — Contract co-construction (clarify + expand, AskUserQuestion-first)

### Research spine (cited)
- **Structured interviews are the best-evidenced elicitation technique** (Dieste & Juristo, aggregation of 30 empirical studies). LLM interviewers left alone elicit **under half** of implicit requirements and ask their best questions too late (ReqElicitGym). Decision failure is **4× likelier when the first idea is embraced** (Nutt) — alternatives must be generated, and the client won't generate them.
- **The 2025–26 tool consensus** (GitHub Spec Kit `/clarify`, AWS Kiro): scan the codebase FIRST and never ask what code can answer; a 9-category ambiguity taxonomy; **hard question caps** (Spec Kit: max 5, one at a time); every question a 2–5 option menu with a labeled, reasoned "(Recommended)" default; every answer written into the spec immediately. ClarifyGPT: targeted clarification lifted Pass@1 70.96→80.80.
- **Expansion generators with evidence:** premortem (+30% reason identification via prospective hindsight), constraint relaxation, 10× reframing, adjacent use-cases — presented as concrete menus (closed options beat open questions on response quality). **Anchoring is the risk:** shown options steer roughly as strongly as the user's own estimate — mitigate with a deliberate "recommend AGAINST" option and recommendation-withholding on pure-taste calls.

### Design — "Intake Protocol v1" (6 phases, all decisions via AskUserQuestion)
- **Phase 0 SCAN** (zero questions): read repo + request, fill a COVERAGE line across the 9-category taxonomy, pre-answer everything resolvable. One mode question: Full / Light.
- **Phase 1 FRAME:** why + success-anchor menus (anchored in a specific past event, never "would you use X?").
- **Phase 2 EXPAND (the new muscle):** 4 multiSelect menus, one per generator — premortem ("it shipped and FAILED; here are the 4 likeliest post-mortems"), constraint relaxation, 10×, adjacent use-cases. You react to concrete possibilities; you're never asked "anything else?". Premortem items you accept become `CRITIQUE-TARGET:` lines — **feeding the v0.12 post-ship critic's FOCUS automatically** (intake wires the loop).
- **Phase 3 CONVERGE:** scope ladder (NOW = walking skeleton / LATER / NEVER→Non-goals), ASCII sketch first for web (your standing rule), lock via menu.
- **Phase 4 CLARIFY:** ≤4 questions, impact×uncertainty-ranked, recommended defaults — EXCEPT flagged OPEN-CALLs (irreversible/taste) where the recommendation is deliberately withheld to prevent rubber-stamping.
- **Phase 5 LOCK:** contract v1 + `## Scope ladder`; existing gate unchanged.
- **Teeth — `intake-gate` (exit code):** append-only `intake.md` ledger; every generated option must terminate in NOW|LATER|NEVER (nothing silently dropped); **"expansion was real" invariant: at least one LATER/NEVER must exist** (an all-NOW ledger = sycophancy or scope balloon, both defects); question budget enforced; ladder counts must match contract; ≥1 human answer required (a headless --auto session structurally cannot fake the interview).

---

## Point 5 — Render while contracting (see it as we decide)

### Research spine (cited)
- **Showing beats describing is one of the oldest replicated results in SE:** Boehm 1984 — prototyping teams delivered equivalent systems ~40% smaller with ~45% less effort; IKIWISI ("I'll know it when I see it": users can't specify a UI in advance but recognize it on sight).
- **Fidelity matters:** rough artifacts elicit more and franker structural feedback; polished single designs get inflated ratings (Schumann 1996; Tohidi 2006). **GenAI broke the polish-effort signal** (Hundhausen, ACM Interactions Jul–Aug 2026): hi-fi is now free but reluctance-to-criticize-polish persists → deliberately grayscale wireframes + explicit "this took 2 minutes — tear it apart" framing. CHIWORK 2026 (22 product-team members on v0/Lovable/Bolt): "the prototype becomes the spec."
- **Logic diagrams:** Mermaid is the only diagram-as-code dialect natively rendered on GitHub AND in Claude artifacts (not in the terminal — open issue). Embed the fence in the spec file itself so diagram and spec version together (the documented drift-killer). Co-drawing surfaces missing branches: Wiegers found two missing requirements "immediately" on drawing a state-transition diagram; Cherubini CHI'07; EventStorming. C4 guidance: one feature-scoped component view + at most one behavior view.
- **The classic pitfall:** the polished throwaway gets shipped — must be prevented by construction.

### Design — "Sketch Loop" (runs inside Intake phases 1–3)
- Web facet → self-contained **grayscale HTML wireframe** `sketch/mock-v<N>.html` (tokens in one `:root{}` block so the final render's tokens copy verbatim into the Design Spec); non-web → **Mermaid logic map** (one node per stage, edges labeled with data shape, failure paths dashed, INVARIANTs annotated).
- **Render early** (after the first 1–2 answers), re-render per structural decision; **contested decisions render 2–3 labeled alternatives side-by-side (A/B/C) BEFORE the question** — the sanctioned anti-fixation move; AskUserQuestion options A/B/C/merge.
- Delivery ladder: Artifact URL (same file → same URL, live-updates across the interview) → local `open` → ASCII in terminal; mode recorded per render in a `sketch/LEDGER`.
- Lock: one final render flips to pinned house tokens; extraction into the binding `## Design Spec` (web, `mockup: sketch/mock-vN.html (ACCEPTED)`) or `## Logic Map` (mermaid embedded in contract.md).
- **Teeth — `sketch-gate` (exit code)** + the elegant bit: the `<!-- COMPASS-MOCK -->` marker doubles as a **leak tracer** — `git grep` for it in tracked product source = hard FAIL at review-build, so "the throwaway got shipped" is mechanically impossible while the mockup persists in `sketch/` as the design-drift reference.

---

## Reconciliation & roadmap

**v0.12 — "The loop with eyes" (points 1+2+3-vocabulary, ONE build, M, 2–3 sessions):**
merge of the three designs — contract-header loop declaration (P1's policy + state model: `loop.log`, PS- ledger rows, no-progress/ping-pong teeth) + P2's observation machinery (evidence/ folders, observation channel at contract time, anti-nit contract-citation rule, HUMAN-OBSERVED fallback, coldgo-gate with tree-sha reset) + P3's framing (docs "Compass is a graph" block; postship node = the trend's overloaded-verifier signal). Skip P3's `graph.md` topology file for now — three designers converged on the same loop; the declarative NODE file is ceremony the contract header already covers. Dogfood on `jarvis-sniper-obs` (in post-ship round 1 today).

**v0.13 — "Co-construct + sketch" (points 4+5, ONE build, M, 2–3 sessions):**
Intake Protocol v1 + Sketch Loop, which naturally interleave (sketches render inside phases 1–3; alternatives render before contested menus). Premortem NOW items auto-become the v0.12 critic's FOCUS — the two releases wire together.

**Parked (v0.14+):** cross-build knowledge graph + invariant-traceability graph (flat-file edges emitted at receipt gates).

### Taste decisions for Rishi (resolve in the v0.12/v0.13 contract interviews)
1. Post-ship loop default in GATED mode too (recommended: yes, waiver to opt out) or auto-only?
2. Gated-mode mid-loop redeploys: 4-button gate before every redeploy (recommended) or only for Critical fixes?
3. Critic scope: contract-cited findings only, taste → FUTURE rows (recommended), or a `strict-design` mode where design drift is material without a cite?
4. Cold-critic auto-ON for every web build (recommended — it's your standard) or opt-in per contract?
5. Terminal wording: keep `SHIPPED (post-ship CONVERGED n/5)` (smallest blast radius, recommended) or a new CONVERGED terminal status?
6. Intake G-I3 "something must be rejected": hard FAIL (recommended) or warning?
7. Kill the "no mockup → name a design standard" escape for web builds (recommended: yes; only the explicit waiver line remains)?
8. Brand the README with "graph engineering" vocabulary now (timely, may age) or keep Compass-native wording + a CHANGELOG nod (recommended)?

---

*Full agent outputs (research JSON with all citations, feasibility verdicts, raw designs) preserved in the session scratchpad; this doc is the distilled record. Not committed — Rishi decides what ships.*
