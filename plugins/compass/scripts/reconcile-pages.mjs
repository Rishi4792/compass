#!/usr/bin/env node
// reconcile.mjs — every gold figure in contract v2, with the population AND the pattern set it was
// counted over, printed as `figure = value  ·  set: <what>  ·  cmd: <how>`.
//
// WHY THIS FILE EXISTS. Contract v1 published ten figures and an independent reconciliation stream
// reproduced three. The cause was never arithmetic. Five times it was the same thing: a figure
// stated without the set or the pattern that produced it.
//   · "brief-body and review have no files anywhere"  <- a scan that searched three filenames
//   · "1,301 internal codes"                          <- three patterns invented and never declared,
//                                                        and ~530 tokens matched by two of them and
//                                                        counted twice
//   · "165 contracts across 6 projects"               <- 168 across 11; the PAGE set's project count
//   · "82 pages"                                      <- a one-level glob missing nested folders
//   · "0 of 161 outside the Compass repo"             <- a set DEFINED as having no block, so 0 is
//                                                        true by construction
// So the figures now come from ONE script that declares its own populations, and the contract quotes
// this script's output rather than restating it. Run it and diff.
//
// Usage: node reconcile.mjs [--json]
import { readFileSync, existsSync, statSync, readdirSync } from 'node:fs';
import { join, basename, sep } from 'node:path';

// ROOT IS NEVER HARDCODED. The first committed version of this file carried the author's own
// absolute home path — `<a user's home directory>` — in a script that SHIPS in a public plugin.
// An independent reviewer caught it before the branch was pushed. A path that names one machine's
// owner is a leak in source, and it also makes the script useless to everyone else: NOW-12 promises
// the gold "stays re-derivable after release", and a hardcoded root means only its author can
// re-derive anything.
//
// Resolution order, all relative or supplied: --root <dir> · COMPASS_PAGES_ROOT · the parent of the
// repo this script lives in (scripts/ -> compass/ -> plugins/ -> repo -> its parent).
import { fileURLToPath } from 'node:url';
function resolveRoot() {
  const i = process.argv.indexOf('--root');
  if (i !== -1 && process.argv[i + 1]) return process.argv[i + 1];
  if (process.env.COMPASS_PAGES_ROOT) return process.env.COMPASS_PAGES_ROOT;
  const here = fileURLToPath(new URL('.', import.meta.url));   // .../plugins/compass/scripts/
  return join(here, '..', '..', '..', '..');                    // the directory holding the repo
}
const ROOT = resolveRoot();
// Printed as a LABEL, never as an absolute path: a run log is pasted into issues and pull requests.
const ROOT_LABEL = basename(ROOT) || '(root)';
const JSON_OUT = process.argv.includes('--json');

// ── POPULATIONS, each declared before it is used ────────────────────────────────────────────────
// walk(): full recursive descent. v1 used a one-level glob and lost a nested build folder; a
// figure whose population depends on how deep the author happened to look is not reproducible.
function walk(dir, out = [], depth = 0) {
  if (depth > 8) return out;
  let ents;
  try { ents = readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of ents) {
    if (e.name === 'node_modules' || e.name === '.git') continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out, depth + 1);
    else out.push(p);
  }
  return out;
}

// The five views gen.mjs actually serves. v1 searched three of these five and then reported that
// the other two "have no files anywhere on this machine" — a claim of absence from a search that
// never looked. All five are named here, in one place.
const VIEWS = ['brief', 'brief-body', 'plan-map', 'release-card', 'review'];
const VIEW_FILES = new Set(VIEWS.map(v => `${v}.html`));

const ALL = walk(ROOT);
// EXCLUDED, and said out loud: worktrees are checkouts of a build that is also counted at its own
// path, so counting both double-counts the same page.
const inWorktree = p => p.includes(`${sep}.compass${sep}worktrees${sep}`);
const underBuilds = p => p.includes(`${sep}.claude${sep}builds${sep}`);

const PAGES     = ALL.filter(p => underBuilds(p) && VIEW_FILES.has(basename(p)) && !inWorktree(p));
const CONTRACTS = ALL.filter(p => underBuilds(p) && basename(p) === 'contract.md' && !inWorktree(p));
const PLANS     = ALL.filter(p => underBuilds(p) && basename(p) === 'plan.md' && !inWorktree(p));
const projectOf = p => p.slice(ROOT.length + 1).split(sep)[0];
const inCompassRepo = p => projectOf(p) === 'compass';

// ── VISIBLE TEXT, defined once, both readings reported ──────────────────────────────────────────
// An independent reviewer showed the definition DECIDES the verdict: excluding <style> and collapsed
// <details> flips three of four views across the zero/non-zero line. So this returns both, and the
// contract must say which one an invariant binds rather than leaving it to whoever writes the check.
//   open   = everything a reader can reach, including text inside a collapsed <details>
//   shown  = only what is visible without clicking anything
const INLINE = 'span|b|i|em|strong|a|code|small|sup|sub|u|abbr';
function visible(html, { includeDetails }) {
  let s = html;
  // script/style/svg CONTENT is never read as prose. svg is dropped for text counting and measured
  // separately for INV-PICTURE — v1 conflated the two and manufactured phantom words
  // ("writtenfor", "paragraphsrendered") out of SVG line breaks.
  s = s.replace(/<(script|style|svg)\b[^>]*>[\s\S]*?<\/\1>/gi, ' ');
  if (!includeDetails) s = s.replace(/<details\b[^>]*>[\s\S]*?<\/details>/gi, ' ');
  // inline tags vanish with NO space — they do not break a word on screen. Replacing them with a
  // space is what invented "off" + "each" -> a defect that was not there.
  s = s.replace(new RegExp(`</?(?:${INLINE})\\b[^>]*>`, 'gi'), '');
  s = s.replace(/<[^>]+>/g, ' ');
  s = s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
       .replace(/&#39;/g, "'").replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&');
  return s.replace(/\s+/g, ' ').trim();
}

// ── THE PATTERN SET, declared, and counted as DISTINCT SPANS ────────────────────────────────────
// v1 summed per-pattern match counts. ~530 INV- tokens matched two patterns and were counted twice,
// which is most of the gap between the published 1,301 and the real figure. Distinct character
// spans cannot double-count by construction.
const JARGON_PATH = join(ROOT, 'compass/plugins/compass/scripts/fixtures/copy/jargon.txt');
const SHIPPED = readFileSync(JARGON_PATH, 'utf8').split('\n').map(l => l.trim()).filter(Boolean);
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

// ── FIGURES ─────────────────────────────────────────────────────────────────────────────────────
const F = [];
const fig = (id, value, set, cmd) => { F.push({ id, value, set, cmd }); };

fig('contracts.total', CONTRACTS.length,
    `every contract.md under */.claude/builds/ below the resolved root, full recursive descent, worktrees excluded`,
    'CONTRACTS.length');
fig('contracts.projects', new Set(CONTRACTS.map(projectOf)).size,
    'distinct top-level project directories represented in contracts.total',
    'new Set(CONTRACTS.map(projectOf)).size');
const withBlock = CONTRACTS.filter(p => readFileSync(p, 'utf8').includes('```compass-reader-copy'));
fig('contracts.with_reader_copy', withBlock.length, 'contracts.total carrying a real fenced block', 'grep -c "```compass-reader-copy"');
fig('contracts.with_reader_copy.outside_compass', withBlock.filter(p => !inCompassRepo(p)).length,
    `contracts NOT in the compass repo (${CONTRACTS.filter(p => !inCompassRepo(p)).length} of them) carrying a block`,
    'withBlock.filter(not compass).length');
fig('contracts.outside_compass', CONTRACTS.filter(p => !inCompassRepo(p)).length,
    'contracts.total minus those in the compass repo — the HONEST denominator; v1 said "161", a set defined as having no block, so its 0 was true by construction',
    'CONTRACTS.filter(not compass).length');
fig('plans.total', PLANS.length, 'every plan.md under */.claude/builds/, same walk', 'PLANS.length');
fig('plans.with_reader_copy', PLANS.filter(p => readFileSync(p, 'utf8').includes('```compass-reader-copy')).length,
    'plans.total carrying a block — the surface INV-COPY-REQUIRED would extend to', 'grep over PLANS');

fig('pages.total', PAGES.length,
    `every ${VIEWS.join('/')}.html under */.claude/builds/, ALL FIVE views, worktrees excluded`,
    'PAGES.length');
for (const v of VIEWS) {
  fig(`pages.${v}`, PAGES.filter(p => basename(p) === `${v}.html`).length,
      `pages.total whose filename is ${v}.html`, `basename === "${v}.html"`);
}

// codes, both readings, distinct spans, SHIPPED pattern set only
for (const mode of [{ k: 'shown', includeDetails: false }, { k: 'open', includeDetails: true }]) {
  let occ = 0, pages = 0;
  for (const p of PAGES) {
    const t = visible(readFileSync(p, 'utf8'), mode);
    const n = distinctSpans(t, SHIPPED);
    occ += n; if (n) pages++;
  }
  fig(`codes.occurrences.${mode.k}`, occ,
      `distinct spans matching the SHIPPED jargon.txt (${SHIPPED.length} patterns, no additions) over pages.total, ${mode.k === 'open' ? 'INCLUDING' : 'EXCLUDING'} text inside collapsed <details>`,
      `distinctSpans(visible(html,{includeDetails:${mode.includeDetails}}), SHIPPED)`);
  fig(`codes.pages.${mode.k}`, pages, `pages.total with >=1 such span (${mode.k})`, 'count of pages with n>0');
}

// truncation controls
const CUT = /\(continues\)|—\s*and\s+\d+\s+more|\+\s*\d+\s+more/g;
// ── v0.34 S14 — THE PRODUCER NOW AGREES WITH THE GLOSSARY ─────────────────────────────────────
// This counted a cut as bad unless the text before it ended in `. ! ? : ;` — a rule of the
// producer's own invention, which the contract's glossary never states. An independent
// re-derivation from the glossary got a different number, and the contract's own blocking rule
// ("any figure the reviewer cannot reproduce blocks the lock") fired on exactly this figure.
//
// TWO CORRECTIONS, and the first is the one that matters:
//   1. THE MARKER NAMES THE BOUNDARY KIND. `— and N more` and `+ N more` mean a LIST was shortened
//      at an item boundary; that is clean by construction, and demanding a full stop there fails
//      every correct list. Only `(continues)` — shortened prose — can land mid-clause.
//   2. A boundary is a sentence end or a closing bracket/brace. `:` and `;` were the producer's
//      additions and appear in the glossary nowhere. Zero real cuts are preceded by either, so
//      removing them changes no verdict — but a rule nobody can re-derive is not a measurement.
let cuts = 0, mid = 0, listCuts = 0;
for (const p of PAGES) {
  const t = visible(readFileSync(p, 'utf8'), { includeDetails: true });
  for (const m of t.matchAll(CUT)) {
    cuts++;
    if (!/\(continues\)/.test(m[0])) { listCuts++; continue; }
    const before = t.slice(Math.max(0, m.index - 90), m.index).trimEnd();
    if (!/[.!?]$|[)\]}]$/.test(before)) mid++;
  }
}
fig('cuts.total', cuts, 'every truncation control in open visible text over pages.total: (continues), — and N more, + N more', 'CUT regex');
fig('cuts.list_boundary', listCuts, 'cuts.total that shortened a LIST at an item boundary — clean by construction, and excluded from mid_clause', 'the marker names the kind');
fig('cuts.mid_clause', mid, 'the (continues) cuts whose preceding 90 chars end at neither a sentence end (. ! ?) nor a closing bracket ()  ]  }) — the glossary definition, not the producer\'s own', 'the same pass');

// markup leaks — the tag set is DECLARED, because v1 published "9" with no reproducible population
const LEAK = /&lt;(?:span|div|details|summary|svg|rect|text|style|script|html|p|ul|li)\b/g;
const LEAK_NARROW = /&lt;(?:span|div|details)\b/g;
// A tag name QUOTED INSIDE <code> is correct escaping, not a leak: a ledger row that writes
// `&lt;span data-prov=…&gt;` is DESCRIBING the bug, not committing it. An independent reviewer showed
// 17 of 34 occurrences are exactly that, across 3 of the 8 pages this used to count. A rule that
// fires on a page for correctly quoting a tag name is a rule somebody switches off within a week.
const inCode = (raw, i) => { const before = raw.slice(Math.max(0, i - 200), i);
  return before.lastIndexOf('<code') > before.lastIndexOf('</code>'); };
let leakN = 0, leakW = 0, leakOcc = 0, leakQuoted = 0;
for (const p of PAGES) {
  const raw = readFileSync(p, 'utf8');
  let n = 0;
  for (const m of raw.matchAll(new RegExp(LEAK.source, 'g'))) {
    if (inCode(raw, m.index)) { leakQuoted++; continue; }
    n++; leakOcc++;
  }
  if (n) leakW++;
  let nn = 0;
  for (const m of raw.matchAll(new RegExp(LEAK_NARROW.source, 'g'))) if (!inCode(raw, m.index)) nn++;
  if (nn) leakN++;
}
fig('leaks.pages.narrow', leakN, 'pages.total with >=1 escaped span|div|details OUTSIDE a <code> element', 'LEAK_NARROW minus code-quoted');
fig('leaks.pages.wide', leakW, 'pages.total with >=1 escaped opening tag from the 13-tag set, OUTSIDE a <code> element — a tag name quoted inside <code> is CORRECT escaping, not a leak', 'LEAK minus code-quoted');
fig('leaks.occurrences', leakOcc, 'real leak occurrences over pages.total, code-quoted excluded', 'the same pass');
fig('leaks.correctly_quoted', leakQuoted, 'occurrences INSIDE <code> and therefore CORRECT — counted so the exclusion is visible rather than silent', 'the same pass');

// pictures — presence only. Whether any picture EXPLAINS anything is NOT a figure this script can
// produce, and saying so is the point: v1 pre-committed a step to defining "picture" against a
// population that turned out to be one hardcoded diagram repeated.
let svgPages = 0;
for (const p of PAGES) if (/<svg\b|<canvas\b/i.test(readFileSync(p, 'utf8'))) svgPages++;
fig('pictures.pages_with_svg', svgPages, 'pages.total containing an <svg> or <canvas> element — PRESENCE ONLY, not whether it explains anything', '/<svg|<canvas/i');

// reader-copy reach — the figure that decides the build's shape
const GEN = join(ROOT, 'compass/plugins/compass/skills/compass-visual/gen.mjs');
const gen = readFileSync(GEN, 'utf8');
for (const fn of ['briefBody', 'releaseCard', 'planMap', 'reviewArtefact']) {
  const m = gen.match(new RegExp(`function ${fn}\\b[\\s\\S]*?\\n\\}`, ''));
  const n = m ? (m[0].match(/\brc\(|\brcList\(/g) || []).length : -1;
  fig(`reach.${fn}`, n, `rc()/rcList() call sites inside function ${fn} in gen.mjs — how much of that view reader copy can reach at all`, `count rc( in function ${fn}`);
}

// ── v0.34 S15 — THE CORPUS FIGURES, WHICH DO NOT DRIFT ────────────────────────────────────────
// Everything above walks a LIVE tree that this build itself keeps changing: it writes contracts and
// renders pages while it runs, so ten of the contract's published figures had already moved by the
// time a reviewer re-derived them. A figure that changes while you are checking it cannot be
// reconciled by anyone, and the contract's own rule — "any figure the reviewer cannot reproduce
// blocks the lock" — has no way to be satisfied against a moving population.
//
// So the MEASURED gold is the fixture corpus: ten authored folders, fixed on disk, rendered fresh.
// Two runs an hour apart print identical figures because nothing in that population can move
// unless someone edits a fixture, and the MANIFEST pins each fixture's sha so that is visible.
// The live-tree figures above stay, because they are what makes the case for the build — but they
// are a DATED SNAPSHOT, not a gate.
const CORPUS = join(ROOT, 'compass/plugins/compass/scripts/fixtures/pages');
if (existsSync(CORPUS)) {
  const slugs = readdirSync(CORPUS, { withFileTypes: true })
    .filter((e) => e.isDirectory()).map((e) => e.name).sort();
  fig('corpus.fixtures', slugs.length, `authored fixture folders under fixtures/pages — a FIXED population, unlike everything above it`, 'readdir');
  fig('corpus.controls', slugs.filter((x) => x.startsWith('ctl-')).length,
      'fixtures asserted to FAIL their class; they are the CONTROL set and are never counted in a measured figure', 'slug prefix');
  // the sha of the corpus itself, so a figure and the population it came from travel together
  let h = 0;
  for (const sl of slugs) {
    for (const f of readdirSync(join(CORPUS, sl)).sort()) {
      const t = readFileSync(join(CORPUS, sl, f), 'utf8');
      for (let i = 0; i < t.length; i++) { h = (h * 31 + t.charCodeAt(i)) >>> 0; }
    }
  }
  fig('corpus.sha', h.toString(16).padStart(8, '0'),
      'a digest of every fixture file — quote it beside any corpus figure so the figure and its population travel together', 'rolling hash over the sorted corpus');
}

// ── OUTPUT ──────────────────────────────────────────────────────────────────────────────────────
if (JSON_OUT) { console.log(JSON.stringify(F, null, 2)); process.exit(0); }
const w = Math.max(...F.map(f => f.id.length));
console.log(`reconcile.mjs — ${F.length} figures, measured ${new Date().toISOString().slice(0, 10)}`);
console.log(`root: ${ROOT_LABEL}/ (resolved relative to this script; override with --root or COMPASS_PAGES_ROOT)`);
console.log(`jargon pattern set: plugins/compass/scripts/fixtures/copy/jargon.txt (${SHIPPED.length} patterns, UNMODIFIED)\n`);
for (const f of F) {
  console.log(`${f.id.padEnd(w)} = ${String(f.value).padStart(6)}`);
  console.log(`${' '.repeat(w)}   set: ${f.set}`);
}
console.log(`\nEvery figure above is produced by this file. The contract quotes it; it does not restate it.`);
