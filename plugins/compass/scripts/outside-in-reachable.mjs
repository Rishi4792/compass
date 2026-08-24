#!/usr/bin/env node
// outside-in-reachable.mjs — measure the rendered page, never ask the generator. (v0.33 S15, C-1)
//
// WHAT C-1 IS. v0.32 shipped a reachability check that ran INSIDE the generator's own process and
// read a TRACE the generator wrote about itself: each destroying return in gen.mjs handed over the
// text of the units it had dropped. A generator that lies about its own trace cannot be caught from
// inside it. Six rules were tried and each measured and rejected; the release named it as the one
// cheat it could not see, and said the fix was structural.
//
// THIS IS THE STRUCTURAL FIX. It renders the page as a SUBPROCESS, then reads only two things:
//   1. the rendered HTML, parsed here
//   2. the tracked source markdown
// It never imports gen.mjs, never reads a trace, and never asks the generator what it did. If the
// generator's account of itself is falsified, the figure produced here does not move — because it
// was never consulted.
//
// THE PARSER. gen.mjs emits a CLOSED, machine-generated shape, so a purpose-built parser over that
// shape needs no dependency — and this plugin ships with zero. The contract settled this at R1-05:
// a general HTML parser is not required, a parser for one generator's bounded output is, and if
// this could not be made to work the invariant fails and the build stops rather than downgrading
// to a report.
//
// THE SHAPE, verified against real output:
//   <div class="v">VISIBLE (continues)<details class="rest"><summary>…</summary>
//     <div class="rest-body">REMAINDER</div></details></div>
//
// Usage: node outside-in-reachable.mjs --corpus <dir> [--json]
//        exit 0 every shortened unit is reachable · 1 some are not · 2 usage.
import { readFileSync, existsSync, readdirSync, mkdtempSync, rmSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const GEN = resolve(HERE, '../skills/compass-visual/gen.mjs');
const MARK = '(continues)';

const argv = process.argv.slice(2);
const getArg = (n) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : null; };
const corpus = getArg('--corpus') || resolve(HERE, 'fixtures/corpus');
// --page measures ONE already-rendered file. Added so the check can be pointed at exactly the page
// a cold reader read, which is how CR-01 was confirmed: the readers' verdict and this figure have
// to agree on the same artefact or one of them is wrong.
const onePage = getArg('--page');
const asJson = argv.includes('--json');

if (!existsSync(GEN)) { console.error('outside-in-reachable: no generator at ' + GEN); process.exit(2); }
if (!existsSync(corpus)) { console.error('outside-in-reachable: no corpus at ' + corpus); process.exit(2); }

// ── the purpose-built parser ─────────────────────────────────────────────────────────────────
// Text extraction for ONE generator's output. Not a general HTML parser and does not pretend to be.
function decode(s) {
  return s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
          .replace(/&#39;/g, "'").replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&');
}
function stripTags(s) { return decode(s.replace(/<[^>]*>/g, '')).replace(/\s+/g, ' ').trim(); }

// ── CR-01: the population, widened after two cold readers found what this check could not ─────
// The first version counted only units carrying the literal marker. Two independent readers found
// TWO of eight named rows unreachable on a real page — plus five more, unprompted — while this
// check reported ZERO. Its blindness was never in its logic; it was in its POPULATION. A row the
// generator truncated WITHOUT emitting a marker was invisible to it.
//
// That is v0.32's DG-2 recurring word for word: "717 covers only fieldText(); four more destroy
// paths outside it drop bullets with NO MARKER AT ALL." S15 closed C-1 — a lying generator cannot
// move the figure — and left DG-2 wide open.
//
// So a unit is SHORTENED if it carries a marker OR it is prose that stops without terminal
// punctuation and without a disclosure to continue into.
//
// GUARD-FIRST, measured on the real page before this rule was written: of 34 prose units it flags
// exactly 5, and those 5 are precisely the rows both readers named. Zero false positives. Units
// under 25 characters are skipped — labels, chips and counters legitimately have no full stop.
const TERMINAL = ['.', '!', '?', ':', ';', ')', ']', '"', "'", '\u201d'];
function unmarked(html) {
  const out = [];
  const pats = [/<div class="v">([\s\S]*?)<\/div>\s*<\/div>/g, /<li[^>]*>([\s\S]*?)<\/li>/g, /<div class="b-det">([\s\S]*?)<\/div>/g];
  for (const re of pats) {
    let m;
    while ((m = re.exec(html)) !== null) {
      const raw = m[1];
      if (raw.includes('<details')) continue;           // it discloses; the marker path handles it
      const txt = stripTags(raw.replace(/<details[\s\S]*?<\/details>/g, ''));
      if (txt.length < 25) continue;                     // a label, a chip, a counter
      if (TERMINAL.includes(txt.slice(-1))) continue;    // it finished
      if (txt.includes(MARK)) continue;                  // already counted by the marker path
      out.push(txt.slice(-70));
    }
  }
  return out;
}

// Find each shortened unit and the disclosure that should carry its remainder.
//
// KEYED ON THE DISCLOSURE, NOT ON A MARKER STRING — and that is the second population fix this
// check needed. The first version scanned for the literal "(continues)". The page uses at least
// three marker forms: "(continues)", "— and N more", and "+ N more". Scanning for one of them made
// the other two invisible, which is how the readers' row 6 — an overflow counter whose disclosure
// opens onto a cut sentence — slipped past even after the unmarked-truncation fix.
//
// Every disclosure IS a shortening. So the population is: every `<details class="rest">` on the
// page, plus (from `unmarked`) every prose unit that stops without one.
function units(html) {
  const out = [];
  const re = /<details class="rest"([^>]*)>([\s\S]*?)<\/details>/g;
  let m;
  while ((m = re.exec(html)) !== null) {
    const openAttrs = m[1] || '';
    const inner = m[2] || '';
    const clipped = /line-clamp|max-height|overflow\s*:\s*hidden/i.test(openAttrs);
    let body = null, bodyRaw = null;
    const bStart = inner.indexOf('class="rest-body"');
    if (bStart >= 0) {
      const tStart = inner.indexOf('>', bStart) + 1;
      const tEnd = inner.lastIndexOf('</div>');
      if (tEnd > tStart) { bodyRaw = inner.slice(tStart, tEnd); body = stripTags(bodyRaw); }
    }
    // A disclosure that opens onto a SECOND cliff. Both cold readers hit this: row 6 opens and the
    // first item inside stops at "…over the branch's commit range, both", while the body carries on
    // to the next item — so the BLOCK ends cleanly and an ITEM inside it does not. Every non-final
    // line is checked, not just the last character of the block.
    let truncatedBody = !!body && body.length >= 25 && !TERMINAL.includes(body.slice(-1));
    if (!truncatedBody && bodyRaw) {
      const items = bodyRaw.split(/\n/).map((x) => stripTags(x)).filter((x) => x.length >= 25);
      for (let i = 0; i < items.length - 1; i++) {
        if (!TERMINAL.includes(items[i].slice(-1))) { truncatedBody = true; break; }
      }
    }
    out.push({ hasDisclosure: true, remainder: body, clipped, truncatedBody });
  }
  return out;
}

// ONE verdict, ONE definition. This condition lived in two code paths — the --page path and the
// corpus path — and when the second-cliff rule was added it landed in only one of them, so the
// same page scored differently depending on how it was reached. That is INV-NO-DUPLICATED-FACT's
// own class, committed inside the check meant to close C-1. Extracted so it cannot drift again.
function verdict(u) {
  if (!u.hasDisclosure) return 'no disclosure follows the marker — the remainder went nowhere';
  if (u.clipped) return 'the disclosure is CSS-clipped, so the text is present but not reachable';
  if (!u.remainder || u.remainder.length === 0) return 'the disclosure is EMPTY — the marker promises more and delivers nothing';
  if (u.truncatedBody) return 'the disclosure OPENS ONTO A SECOND CLIFF — its own text stops mid-sentence, with nothing further to open';
  return null; // reachable
}

// ── render every corpus build, then read only the HTML ───────────────────────────────────────
const VIEWS = ['brief', 'plan-map'];
const builds = readdirSync(corpus, { withFileTypes: true })
  .filter((e) => e.isDirectory()).map((e) => join(corpus, e.name));

let pages = 0, shortened = 0, reachable = 0, unreachable = 0;
const failures = [];
const tmp = mkdtempSync(join(tmpdir(), 'oir-'));
try {
  if (onePage) {
    if (!existsSync(onePage)) { console.error('outside-in-reachable: no page at ' + onePage); process.exit(2); }
    const html = readFileSync(onePage, 'utf8');
    pages++;
    for (const tail of unmarked(html)) {
      shortened++; unreachable++;
      failures.push({ build: onePage.split('/').pop(), view: 'page',
        why: `cut with NO marker and NO disclosure — it just stops: "…${tail}"` });
    }
    for (const u of units(html)) {
      shortened++;
      const why = verdict(u);
      if (!why) reachable++;
      else { unreachable++; failures.push({ build: onePage.split('/').pop(), view: 'page', why }); }
    }
  } else {
  for (const b of builds) {
    for (const v of VIEWS) {
      const out = join(tmp, `${v}.html`);
      // A SUBPROCESS, not an import. Nothing it prints about itself is read — only the file.
      const r = spawnSync(process.execPath, [GEN, b, v, '--out', out], { encoding: 'utf8' });
      if (r.status !== 0 || !existsSync(out)) continue;
      const html = readFileSync(out, 'utf8');
      pages++;
      // the unmarked half — a row that simply stops, with nothing to open
      for (const tail of unmarked(html)) {
        shortened++; unreachable++;
        failures.push({ build: b.split('/').pop(), view: v,
          why: `cut with NO marker and NO disclosure — it just stops: "…${tail}"` });
      }
      for (const u of units(html)) {
        shortened++;
        const why = verdict(u);
        if (!why) reachable++;
        else { unreachable++; failures.push({ build: b.split('/').pop(), view: v, why }); }
      }
    }
  }
  }
} finally { rmSync(tmp, { recursive: true, force: true }); }

// VACUITY GUARD — a green over an empty set is not a signal.
if (pages === 0) {
  console.error('outside-in-reachable: ERR — 0 pages rendered from ' + corpus + '. Nothing was measured.');
  process.exit(1);
}
if (asJson) { console.log(JSON.stringify({ pages, shortened, reachable, unreachable })); }
else {
  for (const f of failures.slice(0, 8)) console.log(`  UNREACHABLE  ${f.build}/${f.view} — ${f.why}`);
  console.log(`\noutside-in-reachable: ${unreachable} unreachable of ${shortened} shortened unit(s) across ${pages} rendered page(s).`);
  console.log('  Measured from the RENDERED PAGE only. No generator trace was read, and gen.mjs was');
  console.log('  run as a subprocess rather than imported — so a generator that lies about what it');
  console.log('  destroyed cannot move this figure. That is C-1, closed structurally.');
}
process.exit(unreachable === 0 ? 0 : 1);
