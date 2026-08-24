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

// Find each shortened unit and the disclosure that should carry its remainder.
function units(html) {
  const out = [];
  let from = 0;
  for (;;) {
    const at = html.indexOf(MARK, from);
    if (at < 0) break;
    from = at + MARK.length;
    const after = html.slice(at + MARK.length, at + MARK.length + 4000);
    const d = after.indexOf('<details');
    // A disclosure must follow IMMEDIATELY. Anything else means the remainder went nowhere.
    const immediate = d >= 0 && stripTags(after.slice(0, d)) === '';
    let body = null, clipped = false;
    if (immediate) {
      const openTag = after.slice(d, after.indexOf('>', d) + 1);
      clipped = /line-clamp|max-height|overflow\s*:\s*hidden/i.test(openTag);
      const bStart = after.indexOf('class="rest-body"', d);
      if (bStart >= 0) {
        const tStart = after.indexOf('>', bStart) + 1;
        const tEnd = after.indexOf('</div>', tStart);
        if (tEnd > tStart) body = stripTags(after.slice(tStart, tEnd));
      }
    }
    out.push({ hasDisclosure: immediate, remainder: body, clipped });
  }
  return out;
}

// ── render every corpus build, then read only the HTML ───────────────────────────────────────
const VIEWS = ['brief', 'plan-map'];
const builds = readdirSync(corpus, { withFileTypes: true })
  .filter((e) => e.isDirectory()).map((e) => join(corpus, e.name));

let pages = 0, shortened = 0, reachable = 0, unreachable = 0;
const failures = [];
const tmp = mkdtempSync(join(tmpdir(), 'oir-'));
try {
  for (const b of builds) {
    for (const v of VIEWS) {
      const out = join(tmp, `${v}.html`);
      // A SUBPROCESS, not an import. Nothing it prints about itself is read — only the file.
      const r = spawnSync(process.execPath, [GEN, b, v, '--out', out], { encoding: 'utf8' });
      if (r.status !== 0 || !existsSync(out)) continue;
      const html = readFileSync(out, 'utf8');
      pages++;
      for (const u of units(html)) {
        shortened++;
        const ok = u.hasDisclosure && u.remainder && u.remainder.length > 0 && !u.clipped;
        if (ok) reachable++;
        else {
          unreachable++;
          failures.push({ build: b.split('/').pop(), view: v,
            why: !u.hasDisclosure ? 'no disclosure follows the marker — the remainder went nowhere'
               : u.clipped ? 'the disclosure is CSS-clipped, so the text is present but not reachable'
               : 'the disclosure is EMPTY — the marker promises more and delivers nothing' });
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
