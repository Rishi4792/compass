#!/usr/bin/env node
// ============================================================================================
// reachable-argument.mjs — of the text this generator destroys, how much can a reader still GET TO?
//
// The gold this build is graded by is not "how much is cut". It is "how many rows a reader cannot
// finish". Those are different questions, and every wrong figure this project published answered
// the first while claiming the second.
//
// METHOD, and why it is not the one that failed three times. It does not search the page for a
// marker. Each destroying return inside gen.mjs hands over the TEXT of the units it dropped
// (`lossy(..., () => droppedUnits)`), the page is rendered, and each dropped unit is looked for in
// the page's REACHABLE text. Keyed to the source, per unit. Renaming a marker changes nothing here,
// because no marker is read.
//
// THE FIVE CHEATS contract section 9 enumerates, and how each is defeated:
//   1. rename the marker        — no marker is read at all.
//   2. hide the rows            — the dropped rows' own text is the probe; hiding them leaves the
//                                 probes unfindable, which is exactly what it should report.
//   3. an EMPTY control         — the control must contain THIS unit's text, not merely exist.
//   4. one control per page     — a control holding probes from more than one destroying EVENT is a
//                                 dump; only one of them is credited, the rest count as unreachable.
//   5. CSS-clipped full text    — text inside a clipped element is PRESENT but not REACHABLE, and
//                                 this strips it before looking. Clipping is detected both inline
//                                 and by class, from the page's own <style> rules.
//
// Exit: 0 every dropped unit reachable · 1 some are not · 2 usage · 3 the corpus is empty (an ERR,
//       never a PASS — a corpus with no pages measures nothing, and reporting 0 for it is
//       indistinguishable from reporting the defect fixed).
//
// COMPASS_V32_STRICT is deliberately NOT read. Contract section 12: the kill switch may silence a
// reporting gate, never the measurement.
// ============================================================================================

import { readFileSync, existsSync, readdirSync, mkdtempSync, rmSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';

const argv = process.argv.slice(2);
const root = argv[0] && !argv[0].startsWith('--') ? resolve(argv[0]) : '';
const asJson = argv.includes('--json');
const cIdx = argv.indexOf('--corpus');
const eIdx = argv.indexOf('--explain');
const explainSite = eIdx >= 0 ? argv[eIdx + 1] : '';
if (!root) { console.error('usage: node reachable-argument.mjs <repo-root> [--json] [--corpus <dir>]'); process.exit(2); }

const GEN = join(root, 'plugins/compass/skills/compass-visual/gen.mjs');
if (!existsSync(GEN)) { console.error(`reachable-argument: no gen.mjs at ${GEN}`); process.exit(2); }

const VIEWS = ['brief', 'plan-map', 'release-card', 'review'];
const SELF = new Set(['user-invariants-v0-32', 'gate-soundness-v0-32']);
const corpusRoot = cIdx >= 0 ? resolve(argv[cIdx + 1]) : join(root, '.claude/builds');
const dirs = existsSync(corpusRoot)
  ? readdirSync(corpusRoot).filter((d) => !SELF.has(d)).map((d) => join(corpusRoot, d))
      .filter((d) => { try { return statSync(d).isDirectory() && existsSync(join(d, 'contract.md')); } catch { return false; } }).sort()
  : [];

if (!dirs.length) {
  console.error(`reachable-argument: ERR — the corpus at ${corpusRoot} has no build directories with a contract.md.`);
  console.error('  This is an ERR and never a PASS. The live corpus is gitignored, so a clean clone');
  console.error('  lands here; point --corpus at the tracked fixtures to regression-test the check.');
  process.exit(3);
}

// ── reachability ────────────────────────────────────────────────────────────────────────────
// Classes whose own CSS clips their content. Read from the page's <style>, so a cheat that moves
// the clipping out of an inline style and into a rule is still seen.
// v0.32 S4b — REWRITTEN after an independent reviewer drove the old version to
// `COMPASS-GATE: PASS` with every row still unreadable. Four things were wrong and all four are
// reproduced as corpus entries or assertions:
//   1. the stripper ran a bounded loop (5000 full-document rescans) and FAILED OPEN when the budget
//      ran out. 5,001 empty `display:none` decoys ate it, then the real remainders clipped freely:
//      live corpus 2,181 -> 99, gate PASS. It is a SINGLE PASS now, with no budget to exhaust.
//   2. `<template>` content is inert in every browser and was never stripped: 2,181 -> 435.
//   3. CLIP_PROPS covered four properties, and the selector scraper read only `.class` before the
//      first `{` — so `@media all{.x{display:none}}` and `[data-x]{display:none}` both slipped past.
//   4. probes were RAW MARKDOWN and pages are RENDERED markdown, so half of them could never match
//      no matter how honestly the text was disclosed. Both sides are normalised the same way now.
const CLIP_PROPS = new RegExp([
  '-webkit-line-clamp', 'text-overflow\\s*:\\s*ellipsis',
  'display\\s*:\\s*none', 'visibility\\s*:\\s*hidden',
  'opacity\\s*:\\s*0(?![.\\d])', 'font-size\\s*:\\s*0(?![.\\d])',
  'color\\s*:\\s*transparent', '-webkit-text-fill-color\\s*:\\s*transparent',
  'clip-path\\s*:\\s*inset\\(\\s*100%', 'clip\\s*:\\s*rect\\(\\s*0',
  'max-height\\s*:\\s*0(?![.\\d])', 'text-indent\\s*:\\s*-\\s*\\d{3,}',
  'left\\s*:\\s*-\\s*\\d{3,}', 'top\\s*:\\s*-\\s*\\d{3,}',
  '(?:width|height)\\s*:\\s*0(?![.\\d])',
].join('|'), 'i');

// Classes whose own CSS clips their content. Read from EVERY rule in the page's <style>, including
// nested at-rules, and from the whole selector rather than only a leading `.class`.
function clippedClasses(html) {
  const out = new Set();
  for (const m of html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/gi)) {
    const css = m[1];
    // flatten at-rules (@media, @supports, @layer) so their inner rules are read like any other
    const flat = css.replace(/@[a-zA-Z-]+[^{]*\{/g, ' ');
    for (const rule of flat.split('}')) {
      const i = rule.indexOf('{');
      if (i < 0) continue;
      if (!CLIP_PROPS.test(rule.slice(i))) continue;
      for (const c of rule.slice(0, i).matchAll(/\.([A-Za-z0-9_-]+)/g)) out.add(c[1]);
    }
  }
  return out;
}

// Elements whose content a browser never renders, whatever the CSS says.
const INERT_TAGS = new Set(['script', 'style', 'template', 'noscript', 'head', 'title']);
const VOID_TAGS = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr']);

function isClipped(tag, attrs, clipped) {
  if (INERT_TAGS.has(tag)) return true;
  const styleM = /style\s*=\s*"([^"]*)"/i.exec(attrs) || /style\s*=\s*'([^']*)'/i.exec(attrs);
  if (styleM && CLIP_PROPS.test(styleM[1])) return true;
  const classM = /class\s*=\s*"([^"]*)"/i.exec(attrs) || /class\s*=\s*'([^']*)'/i.exec(attrs);
  if (classM && classM[1].split(/\s+/).some((c) => clipped.has(c))) return true;
  // `hidden` as a bare attribute, not as part of some id. `/\bhidden\b/` matched id="hidden-panel".
  if (/(^|\s)hidden(\s|=|$)/i.test(attrs)) return true;
  if (/aria-hidden\s*=\s*["']?true/i.test(attrs)) return true;
  return false;
}

// ONE PASS. No budget, so nothing can exhaust it. While inside a clipped element we skip text and
// track nesting by tag name; a void element never opens a subtree.
function reachableText(html, clippedIn) {
  const clipped = clippedIn || clippedClasses(html);
  const h = html.replace(/<!--[\s\S]*?-->/g, ' ');
  let out = '';
  let skipTag = null, skipDepth = 0, last = 0;
  const re = /<\/?([a-zA-Z][a-zA-Z0-9]*)\b([^>]*)>/g;
  let m;
  while ((m = re.exec(h)) !== null) {
    if (!skipTag) out += h.slice(last, m.index);
    last = re.lastIndex;
    const closing = m[0][1] === '/';
    const tag = m[1].toLowerCase();
    const attrs = m[2] || '';
    const selfClosing = /\/\s*$/.test(attrs) || VOID_TAGS.has(tag);
    if (skipTag) {
      if (tag !== skipTag || selfClosing) continue;
      if (closing) { skipDepth--; if (skipDepth <= 0) { skipTag = null; skipDepth = 0; } }
      else skipDepth++;
      continue;
    }
    if (!closing && !selfClosing && isClipped(tag, attrs, clipped)) { skipTag = tag; skipDepth = 1; }
  }
  if (!skipTag) out += h.slice(last);
  // An UNCLOSED clipped element swallows the rest of the document — that is the fail-CLOSED
  // direction, and it is deliberate: crediting text after a clip we could not close is how a
  // malformed page would score better than a well-formed one.
  return normalise(out);
}

// ── the normal form, applied to BOTH sides ───────────────────────────────────────────────────
// Probes come from the SOURCE (markdown); pages carry RENDERED markdown. Comparing them raw meant
// 1,114 of 2,215 probes could never match however honestly the text was disclosed — so the check
// scored an honest fix WORSE than a cheat. Everything below is applied to the page text and to
// every probe alike.
function normalise(t) {
  return t
    .replace(/&nbsp;|&#160;/gi, ' ')
    .replace(/&amp;|&#0*38;/gi, '&').replace(/&lt;|&#0*60;/gi, '<').replace(/&gt;|&#0*62;/gi, '>')
    .replace(/&quot;|&#0*34;/gi, '"').replace(/&#0*39;|&apos;|&#x27;/gi, "'")
    .replace(/&#8217;|&rsquo;|&#x2019;/gi, "'").replace(/&#8216;|&lsquo;/gi, "'")
    .replace(/&#8220;|&ldquo;|&#8221;|&rdquo;/gi, '"')
    .replace(/&#8212;|&mdash;/gi, '—').replace(/&#8211;|&ndash;/gi, '–')
    .replace(/&#(\d+);/g, (_, d) => { try { return String.fromCodePoint(+d); } catch { return ' '; } })
    .replace(/&#x([0-9a-f]+);/gi, (_, x) => { try { return String.fromCodePoint(parseInt(x, 16)); } catch { return ' '; } })
    .replace(/[​‌‍﻿]/g, '')     // breakColors() injects a zero-width space after every #
    // Everything that is not a letter or a digit goes. Stripping markdown SYNTAX one construct at a
    // time kept losing: gen.mjs collapses a source block's newlines into spaces before the probe is
    // built, so a list marker arrives mid-string where no `^`-anchored rule can see it, and the
    // page renders it as a list with no marker at all. A signature of letters and digits is immune
    // to every such difference, and 12 of them is still distinctive enough to find. It is also the
    // conservative direction for cheat detection: hiding text or clipping it defeats this exactly
    // as it defeated the stricter form.
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// Which disclosure control, if any, holds a given probe — so cheat 4 can be caught.
// Each control, with the reachable text that PRECEDES it — back to the end of the previous control.
// That preceding slice is what ties a control to a row: an honest control sits directly after the
// shortened text it discloses, and an aggregation sits after everything, with no row's shown text
// immediately before it.
// v0.32 S7b — FIX from the independent review of S6, and it was a CRITICAL. A control used to be
// judged from its OWN substring, so a CLIPPED ANCESTOR was invisible to it: wrapping every control
// in `<div style="display:none">` scored exactly the same as leaving them openable, and wrapping
// the WHOLE PAGE BODY in one `display:none` still credited 66 of 83 remainders as reachable on a
// page that renders nothing at all.
// Blank every clipped subtree ONCE over the whole document, keeping byte offsets so `before`
// windows and control positions still line up, and read the controls out of the blanked copy.
function visibleHtml(html, clippedIn) {
  const clipped = clippedIn || clippedClasses(html);
  const h = html.replace(/<!--[\s\S]*?-->/g, ' ');
  const chars = h.split('');
  let skipTag = null, skipDepth = 0, skipFrom = 0;
  const re = /<\/?([a-zA-Z][a-zA-Z0-9]*)\b([^>]*)>/g;
  let m;
  while ((m = re.exec(h)) !== null) {
    const closing = m[0][1] === '/';
    const tag = m[1].toLowerCase();
    const attrs = m[2] || '';
    const selfClosing = /\/\s*$/.test(attrs) || VOID_TAGS.has(tag);
    if (skipTag) {
      if (tag !== skipTag || selfClosing) continue;
      if (closing) { skipDepth--; if (skipDepth <= 0) { for (let i = skipFrom; i < re.lastIndex; i++) chars[i] = ' '; skipTag = null; skipDepth = 0; } }
      else skipDepth++;
      continue;
    }
    if (!closing && !selfClosing && isClipped(tag, attrs, clipped)) { skipTag = tag; skipDepth = 1; skipFrom = m.index; }
  }
  // an UNCLOSED clipped element swallows the rest — the same fail-CLOSED direction as reachableText
  if (skipTag) for (let i = skipFrom; i < chars.length; i++) chars[i] = ' ';
  return chars.join('');
}
function controlsFor(rawHtml, clipped) {
  const html = visibleHtml(rawHtml, clipped);
  const out = [];
  let prevEnd = 0;
  for (const m of html.matchAll(/<details\b[\s\S]*?<\/details>/gi)) {
    const before = reachableText(html.slice(prevEnd, m.index), clipped);
    out.push({ start: m.index, text: reachableText(m[0], clipped), before: before.slice(-600) });
    prevEnd = m.index + m[0].length;
  }
  return out;
}

// ── render every page with the trace on, keeping the HTML ───────────────────────────────────
const tmp = mkdtempSync(join(tmpdir(), 'reach-'));
let rendered = 0; const failures = [];
const pages = [];
for (const d of dirs) {
  for (const v of VIEWS) {
    const trace = join(tmp, `t.${dirs.indexOf(d)}.${v}.jsonl`);
    const out = join(tmp, `p.${dirs.indexOf(d)}.${v}.html`);
    const r = spawnSync(process.execPath, [GEN, d, v, '--out', out], {
      env: { ...process.env, COMPASS_LOSSY_TRACE: trace }, encoding: 'utf8', maxBuffer: 1 << 28,
    });
    if (r.status === 0 && existsSync(out)) { rendered++; pages.push({ dir: d.split('/').pop(), view: v, out, trace }); }
    else failures.push({ dir: d.split('/').pop(), view: v, status: r.status, err: (r.stderr || '').trim().split('\n').pop() });
  }
}

let probesTotal = 0, unreachable = 0, reachable = 0, dumped = 0, unitsSeen = 0, inControl = 0, inFlowOnly = 0;
const unbindable = new Set();
const nrPaths = new Set();
let notRendered = 0;
// ── the SECOND measure, and the reason it exists ─────────────────────────────────────────────
// The probe measure above is keyed to what the generator REPORTS dropping. That denominator moves:
// hide a whole ledger row and the field truncations inside it never happen, so the count FALLS
// while the reader loses more. The behaviour corpus caught exactly that — `hide-rows` took the
// figure 159 -> 130 without a line being fixed.
// So: a second measure whose denominator is the SOURCE and cannot move. Take every distinctive
// line of the build's own markdown and ask whether a reader can find it on any of that build's
// pages. Hiding a row lowers this. Renaming a marker does not touch it. Clipping lowers it.
// This is the contract's unit stated literally: a row of source a reader cannot finish.
const srcPages = new Map();                       // dir -> [reachable text of each of its pages]
const SRC_MIN = 40;                               // shorter lines are not distinctive enough to find
const byPath = {};
const examples = [];
for (const p of pages) {
  const rows = existsSync(p.trace)
    ? readFileSync(p.trace, 'utf8').split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean)
    : [];
  if (!rows.length) continue;
  const html = readFileSync(p.out, 'utf8');
  const clipped = clippedClasses(html);
  const text = reachableText(html, clipped);
  const ctrls = controlsFor(html, clipped);
  // TWO PASSES, because cheat 4 can only be judged once every probe has been placed. Crediting a
  // control as soon as its FIRST event is found let the dump keep whichever event happened to be
  // seen first — 33 probes, and the cheat took the figure 159 -> 126. A control that ends up
  // speaking for more than one destroying event credits NONE of them: it is a dump, retroactively.
  (srcPages.get(p.dir) || srcPages.set(p.dir, []).get(p.dir)).push(text);
  const placed = [];
  const evPerCtrl = new Map();
  // v0.32 S4b: assign each EVENT to a DISTINCT control, greedily. `findIndex` returned the first
  // control containing the text, so two rows whose remainders read the same collapsed onto one
  // control and the anti-dump rule then killed both — 106 of 172 fixture probes, 62%, even when
  // every row had its own control. That is why an honest fix scored WORSE than a cheat.
  const claimed = new Map();
  const evShown = new Map();
  // how much THIS ROW lost in total, across every destroying path that touched it
  const rowChars = new Map();
  for (const r of rows) {
    const sh = normalise(r.shownProbe || '').slice(0, 30);
    if (sh.length >= 12) rowChars.set(sh, (rowChars.get(sh) || 0) + (r.charsDropped || 0));
  }                       // control index -> ev that owns it
  for (const r of rows) {
    unitsSeen += r.unitsDropped || 0;
    // A PREFIX, because a shown half is often shortened AGAIN downstream: `invariants()` hands over
    // the summary, and `fieldParts` may then cut it to forty characters, so the full sixty would
    // never appear on the page. Thirty characters survive that and are still far too specific for an
    // aggregation to satisfy by accident — it would have to reproduce every row's opening line
    // immediately before itself, which is no longer an aggregation.
    const shown = normalise(r.shownProbe || '').slice(0, 30);
    // A shown half needs the SAME minimum distinctiveness a probe does. It had none, so a generator
    // could pass `() => 'the'`, put nothing beside the row, pile every control at the page foot each
    // preceded by the word "the", and score byte-identically to an honest build. Found by the
    // independent review of S6.
    if (shown.length < 12) unbindable.add(r.site);
    for (const raw of (r.probes || [])) {
      const probe = normalise(raw);
      probesTotal++;
      const b = (byPath[r.site] ||= { probes: 0, reachable: 0, unreachable: 0 });
      b.probes++;
      if (probe.length < 12) { placed.push({ r, probe, ci: -1, inFlow: false, b }); continue; }
      // NOT RENDERED. A destroying path can fire for a field this page never shows — `invariants()`
      // runs on the plan-map purely to COUNT invariants, and the plan-map has no invariant table.
      // Nothing was shortened for a reader there, because there is no row. Such events are reported
      // in their own bucket and counted in NEITHER column, exactly like a unit too short to probe.
      // The escape hatch is closed by the SOURCE measure: hide a row's shown half to make it "not
      // rendered" and its source lines stop being findable, which raises SOURCE UNREACHABLE.
      if (shown && shown.length >= 20 && !text.includes(shown)) { notRendered++; nrPaths.add(r.site); probesTotal--; b.probes--; continue; }
      // v0.32 S6b: ONE control speaks for ONE event, and an event is credited only if it CLAIMS a
      // control of its own. The earlier version fell back to a control another event already owned,
      // which let contract §9's cheat 4 — every remainder dumped into one control — credit 8 probes
      // it should not have (76 -> 68 on the fixture corpus, with nothing fixed). No fallback now:
      // no free control containing this remainder means this row has no control of its own.
      // A control is this ROW's control only if it is PROPORTIONATE to the one remainder it holds.
      // Text-matching alone cannot tell an honest control from a dump — the dump contains every
      // remainder, so it matches every probe. But the trace already carries how many characters
      // THIS event dropped, and a control holding one row's remainder is about that long, while a
      // control holding seventy of them is not. That is contract §9's cheat 4 measured rather than
      // asserted, and it needs no new data and no label the generator could forge.
      // ONE objective test, and it needs no label the generator could forge. A control that speaks
      // for ONE row is about as long as that row's remainder — the trace already records how many
      // characters this event dropped. A control holding every remainder on the page is not, and
      // the hard ceiling matters as much as the ratio: an event that dropped 9,000 characters would
      // otherwise licence a 13,000-character dump. No realistic single row needs 2,000.
      //
      // Said plainly, because it is a limit and not a triumph: this cannot PROVE a control belongs
      // to its row. Proving that needs the row's own position, which would mean carrying the SHOWN
      // text through the trace as well. What it does is make an aggregation measurably different
      // from a disclosure, which is what contract §9's cheat 4 is about.
      // FAIL CLOSED when a path does not carry its shown half. Without it there is no way to tie a
      // control to a row, and crediting one anyway is precisely how the dump cheat kept winning:
      // ten of the thirteen paths are not wired yet (that is S7), and their probes were matching
      // the dump and passing on size alone. A path that cannot be bound is reported as UNBINDABLE
      // and counted UNREACHABLE — never credited on a maybe.

      // NOT INDEPENDENTLY PINNED, and said so rather than dressed up. Deleting this test changes no
      // assertion and no corpus entry: the POSITIONAL rule already refuses everything it refuses,
      // and on an honest tree it fires against nothing at all — an honest control is proportionate
      // to its row by construction. Two attempts to build a cheat that only this test catches both
      // failed, because the padded control is caught positionally first. It is kept as a second
      // line of defence, and it does still reject ONE probe on the live corpus. What is NOT claimed
      // is that it is tested; an untested rule that looks like protection is this build's own
      // subject, and the honest move is to name it, not to manufacture a test that fits it.
      //
      // Budgeted against what THIS ROW lost, summed across every path that dropped text from it —
      // one row's control legitimately holds all of them. No absolute cap: a flat 2,000-character
      // ceiling punished six honestly-disclosed long remainders on the live corpus, calling them
      // unreachable because the text they disclose is long. The ratio is what separates a
      // disclosure from an aggregation; an absolute number just penalises verbose rows.
      const budget = (rowChars.get(shown) || r.charsDropped || probe.length) * 1.5 + 400;
      // `--explain <site>` says WHY a probe was refused, gate by gate. Added because one probe of
      // seven refused to move through three targeted fixes, and guessing which rule rejected it is
      // how you write a fourth fix for the wrong cause.
      const why = [];
      let ci = -1;
      for (let i = 0; i < ctrls.length; i++) {
        if (!ctrls[i].text.includes(probe)) { why.push(`c${i}: does not contain the remainder`); continue; }
        if (ctrls[i].text.length > budget) { why.push(`c${i}: ${ctrls[i].text.length} chars vs budget ${Math.round(budget)}`); continue; }
        // POSITION is what actually ties a control to its row. The row's SHOWN half must appear in
        // the text immediately before the control. A page that dumps every remainder into one box
        // at the end fails this for every row but at most one, whatever the box's size.
        if (shown.length < 12) { why.push(`shown half too short (${shown.length} < 12): UNBINDABLE`); continue; }
        if (!ctrls[i].before.includes(shown)) { why.push(`c${i}: this row's shown text is not in the ${ctrls[i].before.length} chars before it`); continue; }
        // Ownership is keyed to the ROW — the shown half — not to the event. One row can lose text
        // on SEVERAL paths at once (a field shortened AND its invariant's assert recipe split off),
        // and the honest fix puts everything that row lost into ONE control. Keying by event made
        // the second path unable to claim its own row's control. Two DIFFERENT rows still cannot
        // share one, which is the property cheat 4 attacks.
        const owner = claimed.get(i);
        if (owner === undefined || owner === shown) { ci = i; claimed.set(i, shown); break; }
      }
      if (explainSite && r.site === explainSite && ci < 0) {
        console.error(`explain [${p.dir}/${p.view}] ${r.site} ev=${r.ev}`);
        console.error(`  shown : ${JSON.stringify(shown)}`);
        console.error(`  probe : ${JSON.stringify(probe.slice(0, 70))}`);
        console.error(`  controls on the page: ${ctrls.length}`);
        for (const w of why.slice(0, 8)) console.error(`    ${w}`);
      }
      evShown.set(r.ev, shown);
      if (ci >= 0) { const m = evPerCtrl.get(ci) || new Map(); m.set(r.ev, probe); evPerCtrl.set(ci, m); }
      placed.push({ r, probe, ci, inFlow: text.includes(probe), b });
    }
  }
  // v0.32 S6: a control holding several events is only a DUMP if those events' remainders are
  // genuinely different text. One remainder frequently CONTAINS another — a field's dropped tail and
  // a paragraph dropped from the same section overlap by construction — and treating that as a dump
  // punished honest per-row controls, which is how the first migration made the figure go UP.
  // Overlap (one probe a substring of another) is the honest case; two remainders that share
  // nothing are an aggregation, which is contract §9's cheat 4 and still caught.
  // With exclusive claiming, a control can only ever hold ONE event, so the dump case is now
  // expressed by what a dump cannot do: give every row a control of its own.
  // A dump is a control speaking for more than one ROW. Several events from the SAME row sharing
  // one control is the honest shape, not an aggregation.
  const isDump = (ci) => new Set([...(evPerCtrl.get(ci) || new Map()).keys()].map((ev) => evShown.get(ev))).size > 1;
  for (const q of placed) {
    if (q.ci >= 0 && !isDump(q.ci)) { reachable++; inControl++; q.b.reachable++; continue; }
    if (q.ci >= 0) { unreachable++; dumped++; q.b.unreachable++; continue; }
    // v0.32 S6b — PRESENT SOMEWHERE IS NOT REACHABLE FOR THIS ROW, and counting it as reachable
    // was a hole big enough to drive contract §9's cheat 4 straight through: dumping every
    // remainder into one control puts all of them into the page's flow text, and 65 of 170 probes
    // were then credited as "reachable" with the figure going to 0 and the gate reporting PASS.
    // A row's remainder is reachable when THAT ROW has a control holding it. Text that merely
    // appears elsewhere on the page is counted UNREACHABLE and reported on its own line, because
    // it is real information — a reader might stumble on it — but it is not disclosure.
    if (q.inFlow) { unreachable++; inFlowOnly++; q.b.unreachable++; continue; }
    unreachable++; q.b.unreachable++;
    if (examples.length < 5) examples.push({ dir: p.dir, view: p.view, site: q.r.site, probe: q.probe.slice(0, 70) });
  }
}
// ── source coverage: a line of the build's own markdown a reader cannot find on its pages ───
let srcLines = 0, srcReachable = 0;
for (const d of dirs) {
  const slug = d.split('/').pop();
  const texts = srcPages.get(slug) || [];
  if (!texts.length) continue;
  const joined = texts.join(' \u0001 ');
  const seen = new Set();
  // v0.32 S4b, M-5. This walked EVERY .md in the build dir, so `receipts.md` (27.9% of the live
  // denominator), `progress.md`, `intake.md`, a superseded plan and a spawn log all counted as
  // "lines a reader cannot find". They are build exhaust and were never meant to be on a page.
  // The reader-facing documents are the three the views are rendered FROM.
  const READER_DOCS = new Set(['contract.md', 'plan.md', 'review-ledger.md']);
  for (const f of readdirSync(d)) {
    if (!READER_DOCS.has(f)) continue;
    let body = '';
    try { body = readFileSync(join(d, f), 'utf8'); } catch { continue; }
    let fenced = false;
    for (const raw of body.split('\n')) {
      if (/^\s*```/.test(raw)) { fenced = !fenced; continue; }
      if (fenced) continue;                        // a fenced block is code, not prose a reader hunts for
      // v0.32 S4b: the SOURCE side must go through the SAME normal form as the page, or the two
      // are never comparable. When the page side became an alphanumeric signature and this did not,
      // the measure read 0 of 6,417 reachable — a figure so bad it was obviously the measure, not
      // the pages. Both sides, one function, always.
      const line = normalise(raw);
      if (line.length < SRC_MIN) continue;
      const key = line.slice(0, 120);
      if (seen.has(key)) continue;                 // count a repeated line once
      seen.add(key);
      srcLines++;
      if (joined.includes(key)) srcReachable++;
    }
  }
}
const srcUnreachable = srcLines - srcReachable;
try { rmSync(tmp, { recursive: true, force: true }); } catch { /* best effort */ }

const result = {
  corpus: corpusRoot, dirs: dirs.length, views: VIEWS,
  pagesRendered: rendered, pagesFailed: failures.length, failures,
  unitsDropped: unitsSeen, probes: probesTotal, unprobed: Math.max(0, unitsSeen - probesTotal),
  reachable, reachableInAControl: inControl, reachableInFlowOnly: inFlowOnly,
  unbindablePaths: [...unbindable].sort(), notRendered, notRenderedPaths: [...nrPaths].sort(),
  unreachable, dumpedIntoAsharedControl: dumped,
  sourceLines: srcLines, sourceReachable: srcReachable, sourceUnreachable: srcUnreachable,
  byPath, examples,
};
if (asJson) { console.log(JSON.stringify(result, null, 2)); }
else {
  console.log(`reachable-argument: ${rendered} pages rendered, ${failures.length} failed, over ${dirs.length} build dirs.`);
  console.log(`  dropped units        : ${unitsSeen}`);
  console.log(`  ...probed            : ${probesTotal}`);
  if (unitsSeen > probesTotal) {
    console.log(`  ...NOT PROBED        : ${unitsSeen - probesTotal}  — shorter than 12 characters, so not distinctive`);
    console.log(`                          enough to find on a page without false hits. Reported as`);
    console.log(`                          UNMEASURED, never folded into either column.`);
  }
  const bindUnreach = Object.keys(byPath).filter((k) => !unbindable.has(k)).reduce((a, k) => a + byPath[k].unreachable, 0);
  if (notRendered) {
    console.log(`  ...NOT RENDERED       : ${notRendered}  — the field's shown half is nowhere on this page, so`);
    console.log(`                          the page never showed this row and nothing was shortened for`);
    console.log(`                          a reader. Counted in NEITHER column. Paths: ${[...nrPaths].sort().join(', ')}`);
  }
  console.log(`  REACHABLE            : ${reachable}  — each in a control holding THAT row's remainder`);
  console.log(`  UNREACHABLE (bindable): ${bindUnreach}  — counting only the paths that carry their shown half,`);
  console.log(`                          i.e. the ones an honest fix can currently drive to zero.`);
  if (unbindable.size) {
    console.log(`  UNBINDABLE PATHS      : ${unbindable.size} of ${Object.keys(byPath).length} — ${[...unbindable].sort().join(', ')}`);
    console.log(`                          These do not carry the shown half yet, so no control can be`);
    console.log(`                          tied to their rows. Counted UNREACHABLE, never credited on`);
    console.log(`                          a maybe. Wiring them is step S7.`);
  }
  if (inFlowOnly) {
    console.log(`  ...merely present     : ${inFlowOnly}  — the words appear somewhere on the page but not in`);
    console.log(`                          a control for this row. Counted UNREACHABLE: presence is`);
    console.log(`                          not reachability, and crediting it let a page dump every`);
    console.log(`                          remainder into one box and score a perfect zero.`);
  }
  console.log(`  UNREACHABLE          : ${unreachable}${dumped ? `  (${dumped} of them sat in a control shared by several rows)` : ''}`);
  console.log(`  SOURCE LINES         : ${srcLines} distinctive lines in the corpus's own markdown`);
  console.log(`  ...a reader can find  : ${srcReachable}`);
  console.log(`  SOURCE UNREACHABLE   : ${srcUnreachable}   — the denominator here is the SOURCE, so hiding`);
  console.log(`                          a row raises this instead of lowering it.`);
  for (const k of Object.keys(byPath).sort((a, b) => byPath[b].unreachable - byPath[a].unreachable)) {
    const v = byPath[k];
    console.log(`    ${k.padEnd(30)} unreachable ${String(v.unreachable).padStart(5)} of ${v.probes}`);
  }
  for (const e of examples) console.log(`    e.g. ${e.dir}/${e.view} [${e.site}] "${e.probe}…"`);
}
if (failures.length) process.exit(1);
process.exit(unreachable > 0 ? 1 : 0);
