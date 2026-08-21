#!/usr/bin/env node
// ============================================================================================
// lossy-instrument.mjs — how many units of text does the generator destroy, and on which path?
//
// WHY THIS EXISTS. Three headline figures for this defect have been published — 340, then 340
// again, then 717 — and every one was wrong. Each was produced the same way: by searching the
// RENDERED page for a pattern. That method cannot see a path whose output it does not match, and
// it fails silently and plausibly, returning a confident number instead of an error. The first
// figure literally printed `'and N more' cuts: 0` for a path responsible for 377 units.
//
// So this does not read pages. It runs the real generator with `COMPASS_LOSSY_TRACE` set, and the
// generator reports from inside each destroying return statement. A path cannot hide from a counter
// placed within it. There is deliberately no second implementation of the parsing rules here — a
// re-implementation drifts, and then two numbers disagree with no way to say which is right.
//
// Usage:
//   node lossy-instrument.mjs <repo-root> [--json] [--corpus <dir>] [--views a,b]
//
// Exit: 0 measured · 2 usage · 3 the corpus is empty (an ERR, never a PASS — a corpus with no
//       pages measures nothing, and reporting 0 for it is how a clean clone would report "fixed").
// ============================================================================================

import { readFileSync, existsSync, readdirSync, mkdtempSync, rmSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';

const argv = process.argv.slice(2);
const root = argv[0] && !argv[0].startsWith('--') ? resolve(argv[0]) : '';
const asJson = argv.includes('--json');
const cIdx = argv.indexOf('--corpus');
const vIdx = argv.indexOf('--views');
if (!root) {
  console.error('usage: node lossy-instrument.mjs <repo-root> [--json] [--corpus <dir>] [--views brief,plan-map,...]');
  process.exit(2);
}

const GEN = join(root, 'plugins/compass/skills/compass-visual/gen.mjs');
if (!existsSync(GEN)) { console.error(`lossy-instrument: no gen.mjs at ${GEN}`); process.exit(2); }

// The four rendered views a build actually publishes. `brief-body` is a subset of `brief` and would
// double-count every field on it.
const VIEWS = (vIdx >= 0 ? argv[vIdx + 1] : 'brief,plan-map,release-card,review').split(',').filter(Boolean);

// THE PINNED CORPUS. This build's own two directories are excluded, so a build cannot measure
// itself into its own gold — the number must not move because this build wrote another ledger row.
const SELF = new Set(['user-invariants-v0-32', 'gate-soundness-v0-32']);
const corpusRoot = cIdx >= 0 ? resolve(argv[cIdx + 1]) : join(root, '.claude/builds');
const dirs = existsSync(corpusRoot)
  ? readdirSync(corpusRoot)
      .filter((d) => !SELF.has(d))
      .map((d) => join(corpusRoot, d))
      .filter((d) => { try { return statSync(d).isDirectory() && existsSync(join(d, 'contract.md')); } catch { return false; } })
      .sort()
  : [];

if (!dirs.length) {
  console.error(`lossy-instrument: ERR — the corpus at ${corpusRoot} has no build directories with a contract.md.`);
  console.error('  This is an ERR and never a PASS. A corpus with no pages measures nothing, and');
  console.error('  reporting 0 for it is indistinguishable from reporting that the defect is fixed.');
  console.error('  The live corpus is gitignored, so a clean clone lands here. Pass --corpus <fixtures>.');
  process.exit(3);
}

const trace = join(mkdtempSync(join(tmpdir(), 'lossy-')), 'trace.jsonl');
let rendered = 0; const failures = [];
for (const d of dirs) {
  for (const v of VIEWS) {
    const r = spawnSync(process.execPath, [GEN, d, v], {
      env: { ...process.env, COMPASS_LOSSY_TRACE: trace },
      encoding: 'utf8', maxBuffer: 1 << 28,
    });
    if (r.status === 0) rendered++;
    else failures.push({ dir: d.split('/').pop(), view: v, status: r.status, err: (r.stderr || '').trim().split('\n').pop() });
  }
}

const rows = existsSync(trace)
  ? readFileSync(trace, 'utf8').split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean)
  : [];
try { rmSync(join(trace, '..'), { recursive: true, force: true }); } catch { /* best effort */ }

// Contract section 9 enumerates SIX lossy call sites. Instrumenting the producer finds NINE.
// The mapping is printed rather than reconciled away, because collapsing paths is what produced
// the wrong figures in the first place.
const S9 = {
  'fieldText:and-N-more':        'section 9 — "the — and N more path"',
  'fieldText:continues-sentence':'section 9 — "the (continues) path" (1 of 2 returns)',
  'fieldText:continues-hardcut': 'section 9 — "the (continues) path" (2 of 2 returns)',
  'closedRows.slice':            'section 9 — closedRows.slice(0, CLOSED_SHOWN)',
  'bullets.slice8':              'section 9 — bullets(...).slice(0, 8)',
  'nowItems.slice6':             'section 9 — nowItems.slice(0, 6)',
  'firstPara':                   'section 9 — firstPara()',
  'firstBullet':                 'section 9 — firstBullet()',
  'lineMatching.cap6':           'NOT IN SECTION 9 — found by instrumenting the producer',
  // v0.32 S1-REOPEN. Four more paths, none in section 9 and none in this instrument's first
  // version. They were found by S2 — an independent census that read gen.mjs itself and never
  // touched this file — which is exactly the disagreement step S2 exists to produce. Between
  // them they destroy 235 more events than the first nine paths saw.
  'invariants.assertTail':       'NOT IN SECTION 9 — the command that proves each invariant, split off unmarked',
  'invariants.deferredReplaced': 'NOT IN SECTION 9 — a deferred invariant\'s own wording replaced wholesale',
  'doneMeans.goalSentence2':     'NOT IN SECTION 9 — "Done means" falls back to goal sentence two; 3+ vanish',
  'waiverReason.firstOnly':      'NOT IN SECTION 9 — the un-converged chip names only the first open finding',
};

const byPath = {};
for (const r of rows) {
  const b = (byPath[r.site] ||= { events: 0, unitsDropped: 0, charsDropped: 0, pages: new Set() });
  b.events++; b.unitsDropped += r.unitsDropped || 0; b.charsDropped += r.charsDropped || 0;
  b.pages.add(`${r.dir}|${r.view}`);
}
const out = {
  corpus: corpusRoot,
  dirs: dirs.length,
  views: VIEWS,
  pagesRendered: rendered,
  pagesFailed: failures.length,
  failures,
  paths: Object.fromEntries(Object.entries(byPath).map(([k, v]) => [k, {
    events: v.events, unitsDropped: v.unitsDropped, charsDropped: v.charsDropped,
    pagesAffected: v.pages.size, section9: S9[k] || 'UNMAPPED — a path no enumeration covers',
  }])),
  totals: {
    destroyingEvents: rows.length,
    unitsDropped: rows.reduce((a, r) => a + (r.unitsDropped || 0), 0),
    charsDropped: rows.reduce((a, r) => a + (r.charsDropped || 0), 0),
    pathsFiring: Object.keys(byPath).length,
    pathsInstrumented: Object.keys(S9).length,
  },
};

if (asJson) { console.log(JSON.stringify(out, null, 2)); process.exit(0); }

const pad = (s, n) => String(s).padEnd(n);
const num = (s, n) => String(s).padStart(n);
console.log(`\ncorpus: ${corpusRoot}`);
console.log(`${out.dirs} build dirs x ${VIEWS.length} views = ${out.dirs * VIEWS.length} pages · rendered ${rendered} · failed ${failures.length}\n`);
console.log(`${pad('destroying path', 30)}${num('events', 8)}${num('units', 8)}${num('chars', 10)}${num('pages', 7)}  section 9`);
console.log('─'.repeat(110));
for (const [k, v] of Object.entries(out.paths).sort((a, b) => b[1].unitsDropped - a[1].unitsDropped)) {
  console.log(`${pad(k, 30)}${num(v.events, 8)}${num(v.unitsDropped, 8)}${num(v.charsDropped, 10)}${num(v.pagesAffected, 7)}  ${v.section9}`);
}
console.log('─'.repeat(110));
console.log(`${pad('TOTAL', 30)}${num(out.totals.destroyingEvents, 8)}${num(out.totals.unitsDropped, 8)}${num(out.totals.charsDropped, 10)}`);
console.log(`\n${out.totals.pathsFiring} of ${out.totals.pathsInstrumented} instrumented paths fired.`);
if (failures.length) {
  console.log(`\n${failures.length} page(s) FAILED to render — their destruction is UNMEASURED, not zero:`);
  for (const f of failures.slice(0, 10)) console.log(`  ${f.dir} / ${f.view} — exit ${f.status} — ${f.err}`);
}
