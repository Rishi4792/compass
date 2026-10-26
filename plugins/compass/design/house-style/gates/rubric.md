# Craft rubric — the bar a mockup must clear (gate G3)

> "Premium" = plugin CRAFT − NOVELTY + identity. This rubric makes that testable.
> TWO tiers so nothing is a self-granted opinion:
>   • MEASURABLE — checked by SCRIPTS on the mockup HTML (objective, not agent-judged).
>   • GESTALT — judged by a FRESH INDEPENDENT agent vs `gallery/` (the builder never self-scores).
> A mockup PASSES only when every measurable script exits 0 AND every gestalt item is PASS.

## Tier 1 — MEASURABLE (script-checked on the mockup HTML/CSS)
| # | Item | Objective PASS condition | Checked by |
|---|------|--------------------------|------------|
| M1 | One accent family | exactly one accent hue-family in use (its tints/washes allowed); no second brand hue | `anti-drift-grep.mjs` (allowlist = theme tokens) |
| M2 | No off-theme tokens | every color + font is in the active theme's allowlist (hex/rgb/rgba/hsl normalized) | `anti-drift-grep.mjs` |
| M3 | ≤ 2 font families | the document uses at most 2 `font-family` stacks; the display face is the theme's | `anti-drift-grep.mjs` |
| M4 | Tabular figures | every numeric figure element carries `tabular-nums` (font-variant-numeric or the .tnum class) | `compose-check.mjs` |
| M5 | Table first-col left | every data table's first column is `text-align:left` (header + body) | `compose-check.mjs` |
| M6 | Card geometry | cards use the recipe: radius 12, padding 20–22, 1px hairline `line`, white surface | `compose-check.mjs` |
| M7 | Kicker form | a `.kicker` rule is 700-weight + uppercase (the recipe) | `compose-check.mjs` (implemented) |
| M8 | Token-composed | every color is a theme token, no raw off-theme literal | `anti-drift-grep.mjs` (this IS M8 — every color must be in the theme allowlist) |

## Tier 2 — GESTALT (independent agent, scored vs the gallery screenshots)
| # | Item | PASS condition (the agent must justify with evidence from the screenshot) |
|---|------|---------------------------------------------------------------------------|
| G_a | Focal hierarchy | one element is clearly the hero (largest, highest-contrast) and it's the most important thing; the eye lands there first — like the hero number in gallery/dashboard |
| G_b | Restraint | accent used sparingly (emphasis/active/links only); no random colors; calm, not busy — like the gallery |
| G_c | Intentional depth | layering via hairlines + soft shadow + surface tints (bg/surface/headBg), NOT heavy borders or flat gray boxes |
| G_d | Spacing & rhythm | generous, consistent whitespace; aligned columns; nothing cramped or overflowing; kickers label every block |
| G_e | Same-team feel | a designer would believe this shipped from the SAME team as the gallery screenshots (for a NEW product: same craft LEVEL, its own identity — gallery is the craft bar, not an identity target) |

## How the independent scorer runs (G3 — anti-theater, with its honest limits)
1. The builder produces `mockup.html` + a **full-page** `shot.png` (NOT a flattering crop) and runs the Tier-1 scripts (must all exit 0). Tier-1 is hard-enforced by scripts.
2. A **fresh sub-agent** (a separate Agent call — NOT the builder's own context) is spawned with ONLY: `shot.png`, the `gallery/` screenshots, and this rubric's Tier 2. It is told: "adversarially hunt for drift; score each gestalt item PASS/FAIL with specific evidence; default to FAIL if unsure." It writes its verdict to `score.md`.
3. **`score.md` is APPEND-ONLY** — never overwrite a prior round. Each scoring round is appended with a header, so a FAIL→iterate→PASS trail is permanently on the record (the evidence the gate is working). The builder iterates the mockup and re-scores until the LATEST round is all-PASS.
4. `node gates/g3-check.mjs <proof-dir>` validates the RECORD: full-page shot present, every item scored with evidence, latest round all-PASS (or a literal `owner-signed:` exception). Run it; it must exit 0.
5. An exception to all-PASS is valid ONLY with a literal `owner-signed: <reason>` line — the builder may NEVER self-grant it.

> **Honest limit (what a script can't do):** g3-check enforces the *format and the record*, and Tier-1 enforces the *objective craft*. But no script can prove the gestalt judgment was truly independent or that the screenshot was honest. The separate-agent step is an honor-system instruction; the **user is the final backstop** and should spot-check `score.md` against the live page. This tier is "strong advisory with a falsifiable record," not a cryptographic gate. That is the honest boundary — stated, not hidden.
