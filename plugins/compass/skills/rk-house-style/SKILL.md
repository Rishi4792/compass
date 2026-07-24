---
name: rk-house-style
description: The ENFORCED house design system — one premium look for every frontend, with gates that stop drift (not just advice). Triggers on building or editing a page, component, view, dashboard, screen, form, table, chart, or any UI surface ("build a page", "create a component", "design a dashboard", "make a form", "add a table", "redesign the UI", "build the frontend"). Does NOT trigger on backend/API/route logic, data/SQL/pipeline, schema/migration, CLI/scripts, test-only, or docs. Applies the active theme's pinned tokens + component recipes, and a self-critique gate that scores the work BEFORE the user sees it. The single design skill at user level (the generic novelty-biased ones were removed).
version: 1.0.0
---

# House Style — enforced, not advisory

**The lesson this skill exists for:** a prior 24 KB prose design skill already described the target look in full — and the build STILL drifted to a serif/parchment
aesthetic. **Prose drifts. Gates don't.** This skill is the gates.

The formula: **plugin CRAFT − NOVELTY + pinned tokens/components + a self-critique gate that moves the quality filter off the user.**

## Companion files (read before building)
```
SYSTEM.md   ← token STRUCTURE (9 groups) + 14 component recipes + provenance
gates/rubric.md      ← the craft rubric (Tier-1 MEASURABLE scripts · Tier-2 GESTALT independent scorer)
gates/anti-drift-grep.mjs   ← G1: 0 off-theme colors/fonts (normalizes hex/rgb/hsl)
gates/compose-check.mjs     ← G2: kit composition (first-col-left, tnum, card geometry)
seeds-to-tokens.mjs  ← 4 seeds → a full coherent theme (for a NEW product)
themes/neutral-indigo.json  ← the DEFAULT theme (applies everywhere)
themes/warm-fintech.json    ← example generated theme
gallery/*.png        ← the neutral reference gold (dashboard/form/table) the GESTALT scorer compares against
```

## Active theme
Default = **`neutral-indigo`** for ALL projects. A product gets its OWN identity ONLY by an explicit
opt-in: choose 4 seeds (accent · neutral temperature · headline font · density/radius) →
`node seeds-to-tokens.mjs '<seeds>' > themes/<product>.json` → use that. Everyday work = the default.

## The single design skill (no collisions)
This is the **ONE** design-aesthetic system Compass ships. Do NOT layer a generic "be novel /
be distinctive / use a non-system font" design skill on top — that is the exact bias that causes
the parchment/serif drift away from the system. **Do NOT reintroduce a generic "be novel" design
skill.** A theme is always active (neutral-indigo is the default); identity = the theme's tokens,
never overridden.

## The build process — FOUR GATES, none skippable

**1 · Ground (find the closest existing page).** Identify the active theme + the nearest gallery
pattern(s). Compose from the SYSTEM.md recipes — never invent a card/table/pill from scratch.

**2 · Build the MOCKUP first (G4).** Produce a static HTML mockup composed from the recipes using
the theme tokens. NO React / production component code yet.

**3 · Self-critique — the anti-theater gate (G1 + G2 + G3). You do NOT score your own gestalt.**
   - **G1** `node gates/anti-drift-grep.mjs mockup.html themes/<active>.json` → must print "0 off-theme tokens" (exit 0). Catches off-theme hex/rgb/hsl/named colors + off-theme fonts. Hard-enforced.
   - **G2** `node gates/compose-check.mjs mockup.html` → must pass (first-col-left, tnum, card geometry, kicker form). Hard-enforced.
   - **G3** take a **FULL-PAGE** screenshot (not a flattering crop), then **spawn a FRESH independent sub-agent** (a separate Agent call — never your own context) given ONLY the screenshot + `gallery/` + `gates/rubric.md` Tier-2, told: *"adversarially hunt for drift; score each gestalt item PASS/FAIL with evidence; default FAIL if unsure."* It APPENDS its verdict to `score.md` (**append-only — never overwrite a prior round**, so the FAIL→PASS trail stays on record). Then `node gates/g3-check.mjs <proof-dir>` must exit 0 (validates: full-page shot, every item scored, latest round all-PASS). **Iterate until G1+G2 green AND the independent latest score.md round is all-PASS.** Exception to all-PASS needs a literal `owner-signed:` line — never self-granted.
   > **Honest boundary:** G1/G2/g3-check are scripts (hard). The gestalt *judgment* is an independent-agent honor step a script can't force — so the **user is the final backstop** and should glance at `score.md` vs the page. This tier is strong-advisory-with-a-record, not cryptographic. Stated, not hidden — because pretending otherwise is the exact "prose drifts" trap this skill exists to kill.

**4 · Show the user the mockup, get approval, THEN write React** — porting the mockup 1:1 to the
theme tokens. On the real build, re-run G1/G2 against the component (G1 also forbids the legacy
literals); keep entrance motion once-on-mount + `prefers-reduced-motion`.

## Why this one-shots
Identity is pinned (no guessing) · craft is composed from recipes (no blank page) · the gestalt is
judged by an independent agent against your real pages (no rubber stamp). The iterations still
happen — they happen on the gates' side, before you ever look.
