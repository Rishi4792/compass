# Verify Ladder — the shared "prove it" protocol (illustrative reference)

<!-- Agents: do NOT read at runtime — the skills are self-contained. This is a human/maintainer overview only. -->


> **The SKILLS are authoritative.** Each skill that verifies inlines the essentials; this file is a
> human-readable overview. If it disagrees with a skill, the skill wins.
>
> **The real rule: prove every claim with a deterministic check; never on LLM judgement or agent agreement.**
> The rungs below are the **web-app** instance. Pick a project type first, then the matching rungs.

## Project-type rungs (choose by the contract's Project Type)
**web-app:**
| # | Rung | Proves | X-project safe? |
|---|------|--------|------|
| 1 | Typecheck / build | code consistent | yes |
| 2 | DB query | data truth at SOURCE (counts, sums, reconciliation) | yes |
| 3 | Page HTML via curl+cookie | renders, 200, markers present | yes |
| 4 | API response | request/response contract | yes |
| 5 | **Playwright** — assert DOM text / computed CSS, + screenshot read-back vs the captured design intent | the *actual* user flow + what the user sees + whether it matches the imagined design | **yes** (own browser/run; persists as regression test) |
| 6 | Chrome MCP | exploratory only | **NO** — locks across projects; last resort |

**data-pipeline / CLI:** exit code → **golden-file diff** of output → unit/`pytest` asserts → **numeric reconciliation to tolerance** → determinism check (same input twice → identical output) → idempotent re-run.
**library:** typecheck → unit asserts → public-API contract test → property/fuzz test where it fits.

## Critical rules (all project types)
- **Rung 2 (data at source) does NOT prove the UI/output shows it.** Any claim about a number/page/token a user reads cannot stop below the UI rung (web: rung 5).
- **Two kinds of UI check — use both, don't substitute one for the other:**
  - *Exact things* (a number, a hex, a spacing value) → an **exact assertion**, never a screenshot. A model can't tell ₹12.4 from ₹12.7Cr or `#0A84FF` from `#0A7AFF`. Numbers → assert DOM text vs the rung-2 value. Tokens → assert computed CSS (`getComputedStyle(el).color === 'rgb(10,132,255)'`).
  - *Design-intent fidelity* (layout, hierarchy, spacing rhythm, "does it match what we imagined") → a **screenshot read-back vs the design intent captured in the contract** (a mockup image, reference URL, or described visual). Claude views the screenshot, compares it to the reference, and **names any drift from intent** — this is the gestalt judgment an exact assertion cannot make, and it is a REQUIRED check for any web build, not optional. (If there's no captured design intent, that's a contract gap → flag it.)
- **An INVARIANT's assertion may NOT be deferred** — it must run and assert its exact bound before the step's box is checked.

## Rung 5 (Playwright) — the hard parts, handled
1. **Toolchain:** ensure `@playwright/test` + `npx playwright install chromium`. Non-JS repo → use the project's own e2e tool; don't pretend Playwright exists.
2. **Auth — discover, don't guess:** grep the repo for the session mechanism (NextAuth/JWT + secret, Devise, session middleware) and mint from THAT. **If you can't determine it, STOP and ask the user — never fall through and skip rung 5.** Read the token from an env var at runtime; **never commit a real cookie/JWT into the spec** (that's a secret leak).
3. **Detect failed auth POSITIVELY:** assert a known **authed-only DOM element with real data** is present. A blank/near-empty 200 shell (SPA pre-auth) is a **FAIL**, not a pass — "didn't hit /login" is insufficient.
4. **Environment safety:** **PROD = read-only assertions only.** A write-flow runs against local/staging; if none exists (prod-only project), verify it with a **reversible probe on a test-tagged disposable record (create → assert → delete in one spec, teardown in `finally` even on failure)**, or explicitly mark the write-flow **UNVERIFIED — no non-prod env** and surface it as an owned risk. Never let "no staging" silently mean "no verification."

## How to use
State the claim → pick the lowest rung that genuinely proves it (UI/number/token → the UI rung) → record the exact command + fresh output → keep the spec (it becomes a regression test, with the token read from env, not embedded). A claim with no passing check is **not** done — say so. Prefer the project's own test/lint/migration/perf scripts over inventing new ones.
