#!/usr/bin/env node
// artefact-gate — v0.29.0 INV-STRUCTURE.
// Verifies a generated artefact WITHOUT a browser. Every defect this release was raised
// for is invisible to a screenshot and exact in text: a placeholder token, a count that
// disagrees with its source, a missing diagram, a missing band, text cut mid-word, a page
// older than the file it claims to render. So the gate reads the HTML, not the pixels.
//
// Usage: node artefact-gate.mjs <html-file> [--source <md-file>] [--steps N] [--json]
// Exit 0 = clean. Exit 1 = a specific, named failure.

import { readFileSync, statSync, existsSync } from 'node:fs';

const argv = process.argv.slice(2);
const file = argv[0];
if (!file || !existsSync(file)) {
  console.error('artefact-gate: usage: artefact-gate <html-file> [--source <md>] [--steps N]');
  process.exit(2);
}
const arg = (n) => { const i = argv.indexOf(n); return i > -1 ? argv[i + 1] : ''; };
const source = arg('--source');
const wantSteps = arg('--steps');
const html = readFileSync(file, 'utf8');

const fails = [];
const pass = [];
const check = (name, ok, detail) => (ok ? pass.push(name) : fails.push(`${name} — ${detail}`));

// 1 ── no unresolved placeholder reached the reader.
// Only the generator's own sentinel counts: a contract may legitimately QUOTE a token
// while discussing it, and refusing to render that would be a false positive.
const sentinels = [...html.matchAll(/⟪\s*missing:([a-z0-9 _-]+)⟫/gi)].map((m) => m[1]);
check('no-unresolved-token', sentinels.length === 0, `${sentinels.length} unresolved field(s): ${[...new Set(sentinels)].join(', ')}`);

// 2 ── the four bands, in order. Band 3 is ALWAYS the diagram — that is the product
// decision the contract pins, so it is asserted positionally, not merely by presence.
const order = [];
for (const m of html.matchAll(/class="(b-decide|b-facts|b-flow|b-sec|b-step)"/g)) {
  const c = m[1];
  if (!order.length || order[order.length - 1] !== c) order.push(c);
}
const firstIdx = (c) => order.indexOf(c);
// The contract pins the four bands for the two DECISION artefacts — "the diagram is band 3
// on both" means the Brief and the Plan Map. The Release Card and Program Cockpit are
// different surfaces (a shipped summary, a program timeline); they must carry a logic block
// and be self-contained, but a facts row would be inventing a decision they do not ask for.
// So the full band order is asserted with --bands, and everything else is asserted always.
const bandsRequired = argv.includes('--bands');
if (bandsRequired) {
  check('band-decision-first', firstIdx('b-decide') === 0, `bands appeared as: ${order.slice(0, 5).join(' → ') || '(none)'}`);
  check('band-facts-second', firstIdx('b-facts') > firstIdx('b-decide'), 'the facts row must follow the decision');
  check('band-flow-third', firstIdx('b-flow') > firstIdx('b-facts'), 'the logic block must follow the facts row');
}
// Bands 1-3 are fixed for every view; band 4 is free-form per view (the Cockpit's
// timeline and the Release Card's hero are legitimately different shapes), so this
// asserts only that detail FOLLOWS the flow — not that it wears a particular class.
const flowEnd = html.indexOf('class="b-flow"');
const detailAfter = flowEnd > -1 && /class="(b-sec|b-step|card)"/.test(html.slice(flowEnd + 1));
check('band-detail-last', detailAfter, 'no detail content follows the logic block');

// 3 ── the logic block is a real diagram, not an icon. Counted structurally so
// "decorative diagram" is a failing number rather than a matter of taste.
const svg = (html.match(/<svg[\s>][\s\S]*?<\/svg>/g) || []).join('');
const n = (re) => (svg.match(re) || []).length;
check('logic-block-present', svg.length > 0, 'no <svg> in the artefact');
check('logic-block-real', n(/<rect/g) >= 3 && n(/<path/g) >= 2 && n(/<text/g) >= 3,
  `rect=${n(/<rect/g)} path=${n(/<path/g)} text=${n(/<text/g)} — need >=3 / >=2 / >=3`);

// 4 ── the page makes no outbound request. Attributes only: the same characters in
// escaped prose (a VERIFY command that greps for 'src=') are text, not a resource load.
const extAttrs = (html.match(/<[a-zA-Z][^>]*?\s(?:src|href|xlink:href|data|poster)\s*=\s*["']?\s*(?:https?:|\/\/)/g) || []).length;
const scripts = (html.match(/<script\b/g) || []).length;
check('self-contained', extAttrs === 0 && scripts === 0, `${extAttrs} external reference(s), ${scripts} script tag(s)`);

// 5 ── counts shown match the source they claim to render.
if (wantSteps) {
  const rendered = (html.match(/class="b-step"/g) || []).length;
  const header = (html.match(/<b>(\d+)<\/b>\s*steps?/) || [, ''])[1];
  check('counts-match', String(rendered) === String(wantSteps) && String(header) === String(wantSteps),
    `header says ${header || '?'}, body renders ${rendered}, source has ${wantSteps}`);
}

// 6 ── nothing was cut mid-word. A hard character slice leaves a word fragment at the
// boundary; a real split lands on a word or sentence edge.
const cutMarks = (html.match(/[a-z]\u2026(?=\s*<)|[a-z]\.\.\.(?=\s*<)/gi) || []).length;
check('no-truncation', cutMarks === 0, `${cutMarks} text node(s) end in an ellipsis cut`);

// 7 ── the artefact is not older than the source it renders.
if (source && existsSync(source)) {
  const a = statSync(file).mtimeMs;
  const b = statSync(source).mtimeMs;
  check('fresh', a >= b, `artefact is ${Math.round((b - a) / 1000)}s older than ${source} — regenerate it`);
}

if (argv.includes('--json')) {
  console.log(JSON.stringify({ file, pass, fails }, null, 2));
} else if (fails.length) {
  console.error(`COMPASS-GATE: FAIL — artefact-gate: ${fails.length} problem(s) in ${file}`);
  for (const f of fails) console.error(`  ${f}`);
} else {
  console.log(`COMPASS-GATE: PASS — artefact-gate: ${file} (${pass.length} checks)`);
}
process.exit(fails.length ? 1 : 0);
