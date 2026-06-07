# Verify Ladder — the shared "prove it" protocol (canonical spec)

> The full reference for how any Compass skill proves a claim. **Runtime note:** the skills that
> need it (`build`, `review-build`, `review-plan`) INLINE the essentials — a plugin skill cannot
> reliably read this sibling file at runtime. This file is the human-readable source of truth.
>
> **The real rule is: prove every claim with a deterministic check; never on LLM judgement or agent agreement.**
> The six rungs below are the **web-app instance** of that rule. For a CLI, library, or data
> pipeline, the rungs differ (exit code + golden-file diff, unit asserts, etc.) — keep the rule,
> swap the rungs. Pick the **cheapest rung that genuinely proves the claim**; climb only if it can't.

| # | Rung | Proves | Cost | Cross-project safe? |
|---|------|--------|------|---------------------|
| 1 | **Typecheck / build** (`tsc --noEmit`, `next build`) | code is internally consistent, no type/signature break | cheap | yes |
| 2 | **DB query** (psql / prisma raw) | data-level truth at the SOURCE — counts, sums, reconciliation, invariants | cheap | yes |
| 3 | **Page HTML via curl + auth cookie** | the page renders, 200, key markers present, no server error | cheap | yes |
| 4 | **API response** (curl the endpoint) | request/response contract, status, payload shape | cheap | yes |
| 5 | **Playwright flow + assertions** | the *actual* user flow works — click through, **assert DOM text / computed CSS**, screenshot for layout sanity | medium | **yes** — own browser per run, no cross-project lock; the spec persists as a regression test |
| 6 | **Chrome MCP** (interactive) | exploratory/visual debugging where the flow isn't known yet to script | high | **NO** — single shared instance, locks across projects; **last resort only** |

## Critical rules

- **Rung 2 proves the data is right at the source — NOT that the UI shows it.** A number can be correct in Postgres and wrong on the page (bad join in the API, formatting, caching). For "the user sees the right number" you must ALSO assert the rendered DOM (rung 5).
- **Any claim that mentions a page, a screen, a number a user reads, or a design token cannot stop below rung 5.** The "most claims stop at 1–2" nudge is for pure logic/data, not for UI.
- **Screenshots are layout/rendering sanity ONLY — never a numeric or token check.** A model eyeballing a PNG cannot reliably tell ₹12.4Cr from ₹12.7Cr or `#0A84FF` from `#0A7AFF`. That is the LLM-judgement this ladder bans.
  - Numbers on a page → assert exact DOM text against a value computed by rung 2: `expect(page.getByTestId('total')).toHaveText('₹1,208 Cr')`.
  - Design tokens → assert computed CSS: `getComputedStyle(el).color === 'rgb(10,132,255)'`. The screenshot is supporting evidence, not the proof.

## Rung 5 (Playwright) — prerequisites the step MUST handle
1. **Toolchain:** ensure `@playwright/test` is installed + `npx playwright install chromium` (downloads the browser binary). If the repo is non-JS (Python, etc.), note it and use the project's own e2e tool instead — don't pretend Playwright is present.
2. **Auth (the hard part — never hand-wave "prod cookie"):** obtain/inject the real session (e.g. mint a session cookie via the app's secret, or a stored login state). Document how to refresh it when it expires. The spec's **first assertion must fail loudly if it was redirected to a login page** — so a bad/expired cookie can never masquerade as a pass.
3. **Environment safety — non-negotiable:** **PROD = read-only assertions ONLY.** Any flow that WRITES (creates/edits/deletes state) runs against a **local or staging** instance, never production. State which environment the spec targets at the top of the spec.

## How to use
1. State the claim ("the Active list shows 533 groups, and the headline disbursement = ₹1,208 Cr").
2. Pick the lowest rung that genuinely proves it (UI/number/token → rung 5, see above).
3. Write the Playwright spec, keep it — it becomes a regression test, so coverage compounds.
4. Use rung 6 (Chrome MCP) ONLY when you genuinely don't yet know the flow to script and accept the cross-project lock. Never the default.

## Non-negotiables
- A claim with no passing check is **not** done — say so plainly.
- Record the exact command + its real, fresh output. "Looks right" is not evidence.
- Prefer the project's own test/lint/migration/perf scripts (discover them first) over inventing new ones.
