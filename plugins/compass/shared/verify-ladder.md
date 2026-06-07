# Verify Ladder — the shared "prove it" protocol

> Cited by `compass:build`, `compass:review-build`, and any skill that claims something works.
> **Rule: never claim correctness on LLM judgement or agent agreement. Back every claim with a real check.**

Pick the **cheapest rung that actually proves the claim.** Climb only if the cheaper rung can't.

| # | Rung | Proves | Cost | Cross-project safe? |
|---|------|--------|------|---------------------|
| 1 | **Typecheck / build** (`tsc --noEmit`, `next build`, compiler) | code is internally consistent, no type/signature breakage | cheap | yes |
| 2 | **DB query** (psql / prisma raw) | data-level truth — counts, sums, reconciliation, invariants hold | cheap | yes |
| 3 | **Page HTML via curl + auth cookie** | the page renders, returns 200, key markers present, no server error | cheap | yes |
| 4 | **API response** (curl the endpoint) | request/response contract, status, payload shape | cheap | yes |
| 5 | **Playwright flow + screenshot** | the *actual* user flow works — click through, assert DOM, screenshot key states; **Claude reads the screenshots back** to verify visually | medium | **yes** — spawns its own browser per run, no cross-project lock; the spec persists as a regression test |
| 6 | **Chrome MCP** (interactive) | exploratory/visual debugging where the flow isn't known yet to script | high | **NO** — single shared instance, locks across projects; **last resort only** |

## How to use

1. State the claim ("the Active list shows 533 groups with correct EMI").
2. Choose the lowest rung that genuinely proves it. Most data/logic claims stop at rung 1–2.
3. For "does this page/flow actually work" — the claim you can't fake by reading code — use **rung 5 (Playwright)**, not Chrome MCP. Write a short spec that logs in (prod cookie), clicks the real flow, screenshots each key state, asserts (element visible, no console error, count = N). Read the screenshots back for the visual check. **Keep the spec — it becomes a regression test, so coverage compounds.**
4. Use **rung 6 (Chrome MCP) only** when you genuinely don't yet know the flow to script, and you accept the cross-project lock. Never the default.

## Non-negotiables
- A claim with no passing check is **not** done — say so plainly.
- Record the exact command + its real output. "Looks right" is not evidence.
- Prefer the project's *own* test/lint/migration/perf scripts (discover them first) over inventing new ones.
