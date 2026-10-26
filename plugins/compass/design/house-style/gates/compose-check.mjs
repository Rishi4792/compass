#!/usr/bin/env node
// compose-check — GATE G2 (house-style). Heuristic (RP6: token-use + obvious fidelity,
// not a perfect detector; the rubric + independent scorer are the backstop). Checks the
// objective MEASURABLE rubric items that live in the markup:
//   M5 table first column text-align:left   ·   M4 figures use tabular-nums when tables exist
//   M6 card geometry: white cards use a theme radius (8 or 12), not an ad-hoc value
// Exit 0 = pass; exit 1 = a hand-rolled / off-recipe surface found.
//
// Usage: node compose-check.mjs <file>

import { readFileSync } from 'node:fs';
const file = process.argv[2];
if (!file) { console.error('usage: compose-check <file>'); process.exit(2); }
const src = readFileSync(file, 'utf8');
const fails = [];

// M6 — card radius: any border-radius:Npx that is NOT a theme radius (8/12/99/6/5/7/9/inset) is a hand-roll.
// micro/decorative radii (0–4: legend ticks, chart caps) + the theme radii (chip 6 … card 12) + pill 99.
// Ad-hoc CARD radii (11,13–18,20,24 …) are NOT allowed — those are the hand-roll smell.
const ALLOWED_RADII = new Set([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 99]);
for (const m of src.matchAll(/border-radius\s*:\s*(\d+)px/gi)) {
  const r = +m[1];
  if (!ALLOWED_RADII.has(r)) fails.push(`M6 card geometry: off-recipe border-radius:${r}px (use a theme radius — card 12, chip 6, inset 8)`);
}

// M7 — kicker form: if a `.kicker` rule exists, it must be 700-weight + uppercase
// (the recipe). A kicker that isn't bold-uppercase is off-recipe. (RB-05: real check.)
for (const m of src.matchAll(/\.[\w-]*kicker[\w-]*\s*\{([^}]*)\}/gi)) {
  const body = m[1];
  const okWeight = /font-weight\s*:\s*(700|600)/.test(body);
  const okUpper = /text-transform\s*:\s*uppercase/.test(body);
  if (!okWeight || !okUpper) fails.push(`M7 kicker form: a .kicker rule must be font-weight:700 + text-transform:uppercase (got weight:${okWeight}, uppercase:${okUpper})`);
}

// tables present?
const hasTable = /<table[\s>]/i.test(src);
if (hasTable) {
  // M5 — first column left-aligned (a td:first-child text-align:left rule OR inline on first cells)
  const m5 = /first-child\s*\{[^}]*text-align\s*:\s*left/i.test(src) || /td:first-child[^{]*\{[^}]*left/i.test(src);
  if (!m5) fails.push('M5 table first-col: no `td:first-child { … text-align:left }` rule found — first column must be left-aligned');
  // M4 — tabular figures somewhere in the table context
  const m4 = /tabular-nums|font-variant-numeric|\btnum\b/i.test(src);
  if (!m4) fails.push('M4 figures: table present but no `tabular-nums` — numeric columns must use tabular figures');
}

if (fails.length === 0) { console.log(`compose-check: composed from the kit (${file})`); process.exit(0); }
console.error(`compose-check: ${fails.length} issue(s) in ${file}:`);
for (const f of fails) console.error('  - ' + f);
process.exit(1);
