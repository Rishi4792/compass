#!/usr/bin/env node
// readable-pages-measure.mjs — measures ONE rendered page and prints one line per metric.
//
// Called by readable-pages-check.sh, which owns the corpus walk and the verdict. This file owns
// only "given this HTML, what are the figures, and over what population".
//
// EVERY LINE CARRIES ITS POPULATION. A figure without the set it was counted over is not
// reproducible — that rule was broken five times while this build's contract was being written
// (a search that never looked for two of five filenames; three undeclared patterns; a set
// descriptor carried across from a different measurement; a one-level glob; a circular denominator).
//
// EVERY LINE DECLARES MEASURE OR REPORT. A check that fires on correct work gets switched off
// within a week, and this build demoted every count to REPORT after twenty-four independent
// reviewers showed each zero-target either fires on correct work or is green on day one.
//
// Usage: node readable-pages-measure.mjs <page.html> <page-label> [--metric NAME]
// Exit:  0 always — the CALLER decides the verdict. This file reports; it never gates.

import { readFileSync } from 'node:fs';

const [, , file, label, ...rest] = process.argv;
if (!file || !label) {
  console.error('usage: readable-pages-measure.mjs <page.html> <page-label> [--metric NAME]');
  process.exit(2);
}
const only = rest.includes('--metric') ? rest[rest.indexOf('--metric') + 1] : '';

let raw;
try { raw = readFileSync(file, 'utf8'); }
catch { console.log(`${label}\tERR\tunreadable\t0\tthe page could not be read`); process.exit(0); }

// ── visible text, defined once, both readings ───────────────────────────────────────────────────
// Inline elements are removed with NO space: replacing them with a space invents word boundaries
// that are not on the screen, which produced two false findings during this build's gold and both
// were discarded. `shown` excludes text inside a collapsed <details>; `open` includes it, because
// text a reader can reach by clicking is text they can read.
const INLINE = 'span|b|i|em|strong|a|code|small|sup|sub|u|abbr';
function visible(html, { includeDetails }) {
  let s = html.replace(/<(script|style|svg)\b[^>]*>[\s\S]*?<\/\1>/gi, ' ');
  if (!includeDetails) s = s.replace(/<details\b[^>]*>[\s\S]*?<\/details>/gi, ' ');
  s = s.replace(new RegExp(`</?(?:${INLINE})\\b[^>]*>`, 'gi'), '');
  s = s.replace(/<[^>]+>/g, ' ');
  s = s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
       .replace(/&#39;/g, "'").replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&');
  return s.replace(/\s+/g, ' ').trim();
}

// ── the reader-facing region is a STAMP, never a description ────────────────────────────────────
// Three independent reviewers killed the prose version of this definition in one round: its clauses
// were disjoint on one view, the band it excluded could not be identified in the output at all, and
// under one reading the check read CLEAN on a page showing the reader fifteen internal codes.
// A region a checker cannot identify is not a definition. So: the generator stamps it, and this
// reads the stamp. Until the stamp exists the region is EMPTY, and an empty population is an ERR,
// never a pass.
function readerRegion(html) {
  const out = [];
  const re = /<([a-z]+)\b[^>]*\bdata-reader-region\s*=\s*"1"[^>]*>/gi;
  let m;
  while ((m = re.exec(html))) {
    const tag = m[1];
    // balanced scan from the open tag, so a nested element of the same name does not close it early
    let i = re.lastIndex, depth = 1;
    const open = new RegExp(`<${tag}\\b`, 'gi'), close = new RegExp(`</${tag}\\s*>`, 'gi');
    while (depth > 0 && i < html.length) {
      open.lastIndex = i; close.lastIndex = i;
      const o = open.exec(html), c = close.exec(html);
      if (!c) break;
      if (o && o.index < c.index) { depth++; i = o.index + 1; } else { depth--; i = c.index + c[0].length; }
    }
    out.push(html.slice(m.index, i));
  }
  return out;
}

const JARGON = readFileSync(new URL('./fixtures/copy/jargon.txt', import.meta.url), 'utf8')
  .split('\n').map((l) => l.trim()).filter(Boolean);

// DISTINCT SPANS, never a sum of per-pattern counts: summing double-counts any token two patterns
// both match, which is most of the gap between this build's first published figure and the truth.
function distinctSpans(text, patterns) {
  const marks = [];
  for (const p of patterns) {
    let re; try { re = new RegExp(p, 'g'); } catch { continue; }
    for (const m of text.matchAll(re)) if (m[0]) marks.push([m.index, m.index + m[0].length]);
  }
  marks.sort((a, b) => a[0] - b[0] || b[1] - a[1]);
  let n = 0, end = -1;
  for (const [s, e] of marks) { if (s >= end) { n++; end = e; } else if (e > end) end = e; }
  return n;
}

// A tag name quoted inside <code> is CORRECT escaping, not a leak: a ledger row that writes
// `&lt;span&gt;` is describing the bug, not committing it. Seventeen of thirty-four occurrences on
// this machine were exactly that, and counting them made the published figure wrong by three pages.
const LEAK = /&lt;(?:span|div|details|summary|svg|rect|text|style|script|html|p|ul|li)\b/g;
const inCode = (s, i) => {
  const before = s.slice(Math.max(0, i - 200), i);
  return before.lastIndexOf('<code') > before.lastIndexOf('</code>');
};

const CUT = /\(continues\)|—\s*and\s+\d+\s+more|\+\s*\d+\s+more/g;

// ── the metrics ─────────────────────────────────────────────────────────────────────────────────
// line format:  <label>\t<metric>\t<verdict>\t<figure>\t<population and what it means>
const lines = [];
const emit = (metric, verdict, figure, population) => {
  if (!only || only === metric) lines.push(`${label}\t${metric}\t${verdict}\t${figure}\t${population}`);
};

// codes — over the STAMPED region only, in the `open` reading
const region = readerRegion(raw);
if (region.length === 0) {
  emit('codes', 'ERR', 0, 'no element carries data-reader-region="1" — the region is unstamped, so there is nothing to measure. An empty population is not a pass.');
} else {
  const text = region.map((h) => visible(h, { includeDetails: true })).join(' ');
  emit('codes', 'REPORT', distinctSpans(text, JARGON),
       `distinct spans matching the ${JARGON.length} shipped jargon patterns, over ${region.length} stamped element(s), open reading`);
}

// cuts — a truncation control that does not sit at a unit boundary
const openText = visible(raw, { includeDetails: true });
const cuts = [...openText.matchAll(CUT)];
if (cuts.length === 0) {
  emit('cuts', 'ERR', 0, 'this page renders no truncation control, so there is nothing to inspect. Reported as ERR rather than as a pass — a green over an empty set is not a signal.');
} else {
  let bad = 0;
  for (const m of cuts) {
    // THE MARKER NAMES THE BOUNDARY KIND, so the rule must too. The generator has three cut paths
    // and only one of them can land mid-clause:
    //   `— and N more` / `+ N more`  a LIST was shortened at an item boundary. Clean by
    //                                construction — the text before it ends on the last item, and
    //                                requiring a full stop there would fail every correct list.
    //                                An earlier draft of this rule did exactly that and would have
    //                                flagged 63 of 208 correct cuts.
    //   `(continues)`                prose was shortened. This one has to land on a sentence end or
    //                                the close of a bracketed run, and is the only one worth counting.
    if (!/\(continues\)/.test(m[0])) continue;
    const before = openText.slice(Math.max(0, m.index - 90), m.index).trimEnd();
    if (!/[.!?]$|[)\]}]$/.test(before)) bad++;
  }
  emit('cuts', 'REPORT', bad, `of ${cuts.length} truncation control(s) on this page, not at a sentence end or a closing bracket`);
}

// decision — does the page state the decision it is asking for?
//
// THE EXPECTED LINE IS DECLARED, not read back out of the generator. An earlier draft asserted the
// rendered string against `gen.mjs`'s own literal, which compares the generator with itself — the
// vacuous class `vacuous-assert-check.sh` exists to catch.
//
// `release-card` is DELIBERATELY ABSENT from this map, and finding out why is the useful part: its
// hero kicker reads "Shipped". It is a RECORD of a decision already taken, not a page asking for
// one, so demanding a question of it would be demanding the page be something else. The contract's
// own table declared "Ship this release?" for it and the contract was wrong — corrected there.
const DECISION = {
  'brief': 'Lock this contract?',
  'brief-body': 'Lock this contract?',
  'plan-map': 'Approve this plan?',
};
const view = String(label).split('/').pop();
if (view in DECISION) {
  const h1 = (raw.match(/<h1[^>]*>([\s\S]*?)<\/h1>/) || [, ''])[1].replace(/<[^>]*>/g, '').trim();
  const want = DECISION[view];
  emit('decision', h1 === want ? 'REPORT' : 'REPORT', h1 === want ? 0 : 1,
       h1 === want ? `the page asks "${want}", which is what the contract declares for this view`
                   : `the page asks "${h1}" where the contract declares "${want}"`);
} else {
  emit('decision', 'ERR', 0, `no decision is declared for the ${view} view — it records a decision already taken rather than asking for one, so there is nothing to compare. Stated rather than passed silently.`);
}

// leaks — escaped markup a reader sees as text, excluding correct <code> quotations
let leaks = 0, quoted = 0;
for (const m of raw.matchAll(LEAK)) { if (inCode(raw, m.index)) quoted++; else leaks++; }
emit('leaks', 'REPORT', leaks,
     `escaped opening tag(s) outside a <code> element${quoted ? `; ${quoted} more are correctly quoted inside <code> and are excluded` : ''}`);

// pictures — does every image describe itself for a reader who cannot see it?
//
// REPORT, never MEASURE, and the reason is worth keeping. This started as a MEASURE bound to the
// one image on this machine lacking a text equivalent — and a reviewer found that image lives in
// `cover()`, a function with ZERO call sites, which no render of any view can reach. A bar whose
// entire population is unreachable code is green on day one and proves nothing.
//
// What it reports instead is the real thing: of the images a page actually renders, how many carry
// a text equivalent. Today that is all of them, and saying so plainly is more useful than a rule
// that could never fire.
const svgs = [...raw.matchAll(/<svg\b[^>]*>/gi)].map((m) => m[0]);
if (svgs.length === 0) {
  emit('picture', 'ERR', 0, 'this page renders no picture, so there is nothing to describe. An empty population is not a pass — and note the contract asks every reader-facing view to carry one.');
} else {
  const bare = svgs.filter((t) => !/role="img"/.test(t) && !/aria-hidden="true"/.test(t)).length;
  emit('picture', 'REPORT', bare,
       `of ${svgs.length} image(s) on this page, carrying neither a text equivalent (role="img") nor a marker saying they are decorative (aria-hidden)`);
}

process.stdout.write(lines.join('\n') + (lines.length ? '\n' : ''));
