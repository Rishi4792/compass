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
const CLIP_PROPS = /(-webkit-line-clamp|text-overflow\s*:\s*ellipsis|display\s*:\s*none|visibility\s*:\s*hidden)/i;
function clippedClasses(html) {
  const out = new Set();
  for (const m of html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/gi)) {
    for (const rule of m[1].split('}')) {
      const i = rule.indexOf('{');
      if (i < 0) continue;
      if (!CLIP_PROPS.test(rule.slice(i))) continue;
      for (const c of rule.slice(0, i).matchAll(/\.([A-Za-z0-9_-]+)/g)) out.add(c[1]);
    }
  }
  return out;
}
// Drop an element and everything inside it, matching nesting of the same tag name.
function dropSubtree(html, startIdx, tag) {
  const openRe = new RegExp(`<${tag}\\b`, 'gi');
  const closeRe = new RegExp(`</${tag}\\s*>`, 'gi');
  let depth = 0, i = startIdx;
  while (i < html.length) {
    openRe.lastIndex = i; closeRe.lastIndex = i;
    const o = openRe.exec(html); const c = closeRe.exec(html);
    if (!c) return html.slice(0, startIdx);          // unclosed: drop the rest, never credit it
    if (o && o.index < c.index) { depth++; i = o.index + 1; continue; }
    depth--; i = c.index + 1;
    if (depth <= 0) return html.slice(0, startIdx) + html.slice(c.index + c[0].length);
  }
  return html.slice(0, startIdx);
}
function reachableText(html) {
  let h = html.replace(/<script[\s\S]*?<\/script>/gi, ' ').replace(/<style[\s\S]*?<\/style>/gi, ' ').replace(/<!--[\s\S]*?-->/g, ' ');
  const clipped = clippedClasses(html);
  for (let guard = 0; guard < 5000; guard++) {
    const m = /<([a-zA-Z][a-zA-Z0-9]*)\b([^>]*)>/.exec(h);
    let hit = null;
    for (const mm of h.matchAll(/<([a-zA-Z][a-zA-Z0-9]*)\b([^>]*)>/g)) {
      const attrs = mm[2] || '';
      const styleM = /style\s*=\s*"([^"]*)"/i.exec(attrs);
      const classM = /class\s*=\s*"([^"]*)"/i.exec(attrs);
      const inlineClip = styleM && CLIP_PROPS.test(styleM[1]);
      const classClip = classM && classM[1].split(/\s+/).some((c) => clipped.has(c));
      const attrHidden = /\bhidden\b/i.test(attrs) || /aria-hidden\s*=\s*"true"/i.test(attrs);
      if (inlineClip || classClip || attrHidden) { hit = mm; break; }
    }
    if (!hit) break;
    h = dropSubtree(h, hit.index, hit[1]);
  }
  return h.replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/\s+/g, ' ').trim();
}
// Which disclosure control, if any, holds a given probe — so cheat 4 can be caught.
function controlsFor(html) {
  const out = [];
  for (const m of html.matchAll(/<details\b[\s\S]*?<\/details>/gi)) out.push({ start: m.index, text: reachableText(m[0]) });
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
const byPath = {};
const examples = [];
for (const p of pages) {
  const rows = existsSync(p.trace)
    ? readFileSync(p.trace, 'utf8').split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean)
    : [];
  if (!rows.length) continue;
  const html = readFileSync(p.out, 'utf8');
  const text = reachableText(html);
  const ctrls = controlsFor(html);
  const evPerCtrl = new Map();                       // control index -> Set(ev)
  for (const r of rows) {
    unitsSeen += r.unitsDropped || 0;
    for (const probe of (r.probes || [])) {
      probesTotal++;
      const b = (byPath[r.site] ||= { probes: 0, reachable: 0, unreachable: 0 });
      b.probes++;
      const ci = ctrls.findIndex((c) => c.text.includes(probe));
      const inFlow = text.includes(probe);
      if (ci >= 0) {
        const set = evPerCtrl.get(ci) || new Set();
        set.add(r.ev); evPerCtrl.set(ci, set);
        // cheat 4: one control may speak for ONE row. Beyond that it is a dump.
        if (set.size > 1) { unreachable++; dumped++; b.unreachable++; continue; }
        reachable++; inControl++; b.reachable++; continue;
      }
      // Found in ordinary flow, NOT in a disclosure control. That is weaker evidence and is
      // reported apart: on an UNFIXED generator it usually means the same words happen to appear
      // somewhere else on the page, not that this row's remainder was disclosed. Folding it into
      // "reachable" would flatter the number in the one direction that matters.
      if (inFlow) { reachable++; inFlowOnly++; b.reachable++; continue; }
      unreachable++; b.unreachable++;
      if (examples.length < 5) examples.push({ dir: p.dir, view: p.view, site: r.site, probe: probe.slice(0, 70) });
    }
  }
}
try { rmSync(tmp, { recursive: true, force: true }); } catch { /* best effort */ }

const result = {
  corpus: corpusRoot, dirs: dirs.length, views: VIEWS,
  pagesRendered: rendered, pagesFailed: failures.length, failures,
  unitsDropped: unitsSeen, probes: probesTotal, unprobed: Math.max(0, unitsSeen - probesTotal),
  reachable, reachableInAControl: inControl, reachableInFlowOnly: inFlowOnly,
  unreachable, dumpedIntoAsharedControl: dumped,
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
  console.log(`  reachable            : ${reachable}  (${inControl} in a per-row disclosure control, ${inFlowOnly} merely present elsewhere in the flow)`);
  if (inFlowOnly && !inControl) {
    console.log(`                          NOTE: none of these sits in a disclosure control. On an`);
    console.log(`                          unfixed generator that is usually coincidence - the same`);
    console.log(`                          words appearing in another card - not a reader being given`);
    console.log(`                          this row's remainder. The honest range is ${unreachable} to ${unreachable + inFlowOnly}.`);
  }
  console.log(`  UNREACHABLE          : ${unreachable}${dumped ? `  (${dumped} of them sat in a control shared by several rows)` : ''}`);
  for (const k of Object.keys(byPath).sort((a, b) => byPath[b].unreachable - byPath[a].unreachable)) {
    const v = byPath[k];
    console.log(`    ${k.padEnd(30)} unreachable ${String(v.unreachable).padStart(5)} of ${v.probes}`);
  }
  for (const e of examples) console.log(`    e.g. ${e.dir}/${e.view} [${e.site}] "${e.probe}…"`);
}
if (failures.length) process.exit(1);
process.exit(unreachable > 0 ? 1 : 0);
