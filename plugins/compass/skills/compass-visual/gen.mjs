#!/usr/bin/env node
// ============================================================================================
// compass-visual/gen.mjs — the Contract Brief + progress Cockpit generator.
//
// A PURE FUNCTION of a build's on-disk state files: same state → byte-identical HTML. No clock,
// no randomness (Date/Math.random are never called), so an idempotency diff of two runs is exact.
//
// Usage:
//   node gen.mjs <build-dir> <view> [--shareable] [--out <file>]
//     view ∈ brief | brief-body | cockpit
//       brief       full page: cinematic-hero cover (its OWN accent + grade) + rk-house-style body.
//       brief-body  ONLY the house-style body region — the artifact the house gates run on
//                   (the cinematic cover is off-theme BY DESIGN and is excluded from the gate).
//       cockpit     the "where it stands" progress view (house-style), from progress/plan/receipts/ledger.
//     --shareable   Brief for sharing: the reconciliation-GOLD literal + every never-show field VALUE
//                   are redacted to a "gold pinned ✓" badge (classification LABELS still render), then a
//                   LEAK GATE scans the output (secret classes + commercial VALUES + redaction residue)
//                   and HARD-STOPs (exit 3) on any hit. Never a soft pass.
//     --out <file>  write to <file> (default: stdout, so `diff <(gen) <(gen)` is exact).
//
// Exit: 0 ok · 2 usage/missing-state OR a MALFORMED brief-data fence on --shareable · 3 leak gate HARD-STOP.
// The first line of every generated asset is `<!doctype html>` — NEVER a `<!-- COMPASS-MOCK` marker.
// ============================================================================================

import { readFileSync, writeFileSync, existsSync, readdirSync, appendFileSync } from 'node:fs';
import { join } from 'node:path';
import { extractReaderCopy, parseReaderCopy } from '../../scripts/reader-copy.mjs';

// ── args ──────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
const dir = argv[0];
const view = argv[1];
const shareable = argv.includes('--shareable');
const outIdx = argv.indexOf('--out');
const outFile = outIdx >= 0 ? argv[outIdx + 1] : null;
// v0.30: the canonical view list, in ONE place. `cockpit` (an orphan HTML view nothing ever
// invoked) and `program-cockpit` are deleted; `review` is added. Smoke reads this line rather
// than re-typing the set, which is why deleting a view used to mean finding six copies.
export const VIEWS = ['brief', 'brief-body', 'plan-map', 'release-card', 'review'];
if (!dir || !VIEWS.includes(view || '')) {
  console.error(`usage: node gen.mjs <build-dir> <${VIEWS.join('|')}> [--shareable] [--out <file>]`);
  process.exit(2);
}

// ── v0.32 lossy instrumentation — INERT unless COMPASS_LOSSY_TRACE is set ─────────────────────
// The lesson this build was raised on: a count derived by grepping rendered output silently
// misses every path whose output the grep cannot match. Three headline figures were published
// this way (340, then 340 again, then 717) and every one was wrong — the first missed an entire
// destroying path because its count sits inside markup a text search cannot see.
//
// So the count is taken HERE, at the return statement that destroys the text. A path cannot hide
// from a counter placed inside it. Cost when the env var is unset: one falsy check per call, no
// allocation and no I/O, so the shipped generator is unchanged in behaviour and effectively in
// speed. It is deliberately NOT a separate re-implementation of the parsing rules — a second
// implementation drifts from the first, and then two numbers disagree with no way to say which
// is right.
const LOSSY_TRACE = process.env.COMPASS_LOSSY_TRACE || '';
const LOSSY_ROWS = [];
function lossy(site, keptChars, fullChars, unitsDropped, droppedUnitsFn, shownFn) {
  if (!LOSSY_TRACE) return;
  // The dropped text arrives as a THUNK, never a value. Passing it eagerly meant every render
  // computed it whether or not anything was tracing — which cost time on the shipped path and,
  // when one call site named the wrong variable, crashed all 116 pages. A measurement must not be
  // able to break the thing it measures, so it is computed only inside this guard and any throw
  // inside it is swallowed: a probe that cannot be built is one missing probe, never a dead render.
  let droppedUnits = [];
  try { droppedUnits = typeof droppedUnitsFn === 'function' ? droppedUnitsFn() : droppedUnitsFn; }
  catch { droppedUnits = []; }
  // v0.32.0 S4. Counting units tells us HOW MUCH is destroyed. It cannot tell us whether a reader
  // can still REACH it, and reachability is what the gold actually grades. So each destroying return
  // now hands over the TEXT of the units it dropped, and the check looks for that text on the
  // rendered page. Keyed to the SOURCE — never to a marker the implementation can rename, which is
  // how three published figures went wrong. Probes are normalised and capped: carrying whole
  // remainders would make the trace enormous, and a distinctive slice is enough to find one.
  const probes = (Array.isArray(droppedUnits) ? droppedUnits : (droppedUnits == null ? [] : [droppedUnits]))
    .map((u) => String(u == null ? '' : u).replace(/\s+/g, ' ').trim())
    .filter((u) => u.length >= 12)
    .map((u) => u.slice(0, 120));
  // `ev` identifies ONE destroying event — one row's field. It is what lets the check enforce the
  // per-row rule: a disclosure control holding the remainders of many rows at once is a dump, not a
  // control, and contract section 9 lists that as cheat 4.
  // v0.32.0 S6b — the SHOWN half, so a control can be tied to the ROW it belongs to.
  // Everything before this tied them by TEXT alone, and text cannot do it: a control holding every
  // remainder on the page contains each row's text too, so it matched every row. Size could not
  // separate them either — on a small page a dump is small. What does separate them is POSITION:
  // an honest control sits immediately after the shortened text it belongs to, and an aggregation
  // sits after everything. That needs the shown half, and here it is.
  let shownProbe = '';
  try {
    const sh = typeof shownFn === 'function' ? shownFn() : shownFn;
    // 60, not 120. A path whose shown half is later shortened AGAIN by another path — firstPara
    // feeding fieldText is the common case — only keeps its opening on the page. Sixty characters
    // survive that and are still far too specific for a dump to satisfy by accident: an aggregation
    // would have to reproduce every row's opening line immediately before itself.
    shownProbe = String(sh == null ? '' : sh).replace(/\s+/g, ' ').trim().slice(0, 60);
  } catch { shownProbe = ''; }
  LOSSY_ROWS.push({ ev: LOSSY_ROWS.length, site, view, dir, keptChars, fullChars,
                    charsDropped: Math.max(0, fullChars - keptChars), unitsDropped, probes, shownProbe });
}
if (LOSSY_TRACE) {
  // Flush on exit so an early process.exit (usage 2, leak gate 3, sentinel 5) still reports what
  // it destroyed before it stopped. A trace that only survives the happy path would under-count
  // exactly the pages that went wrong.
  process.on('exit', () => {
    try {
      appendFileSync(LOSSY_TRACE, LOSSY_ROWS.map((r) => JSON.stringify(r)).join('\n') + (LOSSY_ROWS.length ? '\n' : ''));
    } catch { /* never let instrumentation break a render */ }
  });
}

const read = (name) => (existsSync(join(dir, name)) ? readFileSync(join(dir, name), 'utf8') : '');
const contract = read('contract.md');
if (!contract) { console.error(`gen: no contract.md in ${dir}`); process.exit(2); }

// ── v0.29.0 INV-FENCE-BLIND — a drawing is not data ────────────────────────────
// A fenced code block holds ASCII mockups, examples and diagrams. It NEVER holds
// contract fields. Before v0.29 the field parser scanned raw markdown, so
// `Goal: <goal from INDEX>` inside the Design Spec's ASCII mockup was read as the
// contract's goal and printed to the user four times. Blank the fenced lines
// (keeping line COUNT, so any line-based logic stays aligned) and parse that.
// The raw text is still available for anything that genuinely needs the fences.
// THE fence rule, used by every reader here. A fence closes only on a run of the SAME character
// at least as long as the opener, so a 3-backtick sample nested in a 4-backtick mockup does not
// end the block. Three readers held three copies; two were fixed and this one — the one every
// contract and plan field passes through — was not. That is v0.29's INV-FENCE-BLIND defect back.
function fenceScanner() {
  let ch = '', len = 0;
  return (line) => {
    const m = String(line).match(/^ {0,3}(`{3,}|~{3,})/);
    if (!m) return { fence: false, inside: !!ch };
    if (!ch) { ch = m[1][0]; len = m[1].length; return { fence: true, inside: true }; }
    if (m[1][0] === ch && m[1].length >= len) { ch = ''; len = 0; }
    return { fence: true, inside: true };
  };
}
function stripFences(md) {
  const out = [];
  const scan = fenceScanner();
  for (const ln of String(md).split('\n')) {
    const st = scan(ln);
    out.push(st.fence || st.inside ? '' : ln);
  }
  return out.join('\n');
}

// ── markdown: split into `## ` sections, find by fuzzy header, pull structured bits ──
function sections(md) {
  const out = {}; let cur = '__pre__'; out[cur] = [];
  for (const ln of md.split('\n')) {
    const m = ln.match(/^##\s+(.+?)\s*$/);
    if (m) { cur = m[1]; out[cur] = []; } else out[cur].push(ln);
  }
  const joined = {}; for (const k of Object.keys(out)) joined[k] = out[k].join('\n').trim();
  return joined;
}
// EVERY field/section read goes through the fence-blind copy (INV-FENCE-BLIND).
const contractFields = stripFences(contract);

// ── v0.30 INV-9: the READER-COPY BLOCK ────────────────────────────────────────────────────────
// The model writes plain-language copy into a declared fence; gen.mjs lays it out and NEVER
// invents it. Before this, every reader-facing field was scraped out of contract markdown, which
// is why "INV-ORIENT: a front-door invocation with a Compass state-root" reached a page whose job
// was to ask "Lock this contract?". A contract may be as jargon-dense as it needs to be — the
// artefact is where a person decides, and the two are now different texts.
// Guard-first: a contract with no block keeps the pre-v0.30 scraping behaviour byte-identically,
// so all 27 existing builds still render.
// ── v0.31: the DECLARED data block ────────────────────────────────────────────────────────────
//
// The whole point of this build. When a state file carries a `compass-artefact-data` fence, the
// MODEL has written the numbers down and the generator's job is to lay them out — not to work them
// out and hope. A field present here is stated verbatim and marked `declared`, and the gate holds
// the page to it. A field absent falls back to counting, which is marked `counted` and disclosed.
//
// Guard-first: a build with no block behaves exactly as before, so all 27 legacy builds are
// byte-identical through this path.
// The canonical file list. `proven-numbers.sh` globs the same set; keeping the order written down in
// one place is what stops the two readers drifting apart again.
const ARTEFACT_DATA_FILES = (() => {
  try {
    return readdirSync(dir).filter((f) => f.endsWith('.md')).sort();
  } catch { return ['contract.md', 'plan.md', 'progress.md', 'receipts.md', 'review-ledger.md']; }
})();

const ARTEFACT_DATA = (() => {
  const FENCE = /^ {0,3}`{3,}compass-artefact-data[ \t]*\r?$/;
  // ONE search order, shared with the gold by being written down in both: every `*.md` in the dir,
  // alphabetically. Two readers with different orders meant a block in a file one of them never
  // opened satisfied the gate while the page declared nothing.
  for (const f of ARTEFACT_DATA_FILES) {
    let body = '';
    try { body = readFileSync(join(dir, f), 'utf8'); } catch { continue; }
    const lines = body.split('\n');
    const open = lines.findIndex((l) => FENCE.test(l));
    if (open === -1) continue;
    const close = lines.findIndex((l, i) => i > open && /^ {0,3}`{3,}[ \t]*\r?$/.test(l));
    if (close === -1) {
      console.error(`gen: ${f} opens a compass-artefact-data fence that is never closed`);
      process.exit(4);
    }
    const raw = lines.slice(open + 1, close).join('\n');
    // A duplicate key silently took the last value: `{"steps.total":3,"steps.total":999}` rendered
    // 999 while the author read the first line and believed 3.
    const _dupes = (() => {
      const seen = new Set(), dup = [];
      for (const m of raw.matchAll(/"([^"]+)"\s*:/g)) { if (seen.has(m[1])) dup.push(m[1]); seen.add(m[1]); }
      return dup;
    })();
    if (_dupes.length) {
      console.error(`gen: ${f} declares ${_dupes.map((d) => JSON.stringify(d)).join(', ')} more than once. JSON keeps the LAST value silently; say it once.`);
      process.exit(4);
    }
    let parsed;
    try { parsed = JSON.parse(raw); } catch (e) {
      // Never fall back to counting. A block the author WROTE and this cannot read is a defect to
      // surface, not a licence to guess — the same rule the reader-copy block already follows.
      console.error(`gen: ${f} has a compass-artefact-data block that is not valid JSON — ${e.message}`);
      process.exit(4);
    }
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed) || !Object.keys(parsed).length) {
      console.error(`gen: ${f} declares a compass-artefact-data block with no fields`);
      process.exit(4);
    }
    // The block is FLAT dotted keys. A nested object is the natural thing to write, and silently
    // falling back to counting would be the exact "never guess" failure this block exists to stop.
    for (const [k, v] of Object.entries(parsed)) {
      // A key with no dot is not a field name — `{"steps": 3}` was silently ignored while the author
      // believed they had declared `steps.total`, and the page counted instead. Silence there is the
      // "never guess" failure this block exists to prevent.
      if (!k.includes('.')) {
        console.error(`gen: ${f} declares "${k}", which is not a field name. Fields are dotted — did you mean "${k}.total"?`);
        process.exit(4);
      }
      if (v !== null && typeof v === 'object') {
        console.error(`gen: ${f} declares "${k}" as a nested object. The block is flat dotted keys — write "${k}.total", not {"${k}": {"total": …}}.`);
        process.exit(4);
      }
      if (typeof v === 'number' && (!Number.isInteger(v) || v < 0 || v >= 1e6)) {
        console.error(`gen: ${f} declares "${k}" as ${v}. A count is a non-negative whole number under a million — a page reading "-3 steps" or "2.5 invariants" is not a page anyone can act on.`);
        process.exit(4);
      }
    }
    return parsed;
  }
  return null;
})();

// State a field: the block's value marked `declared` when the model wrote it, otherwise the counted
// fallback. One call site per number, so "declared or counted" is never decided by hand.
function nF(field, fallback) {
  if (ARTEFACT_DATA && Object.prototype.hasOwnProperty.call(ARTEFACT_DATA, field)) {
    const v = ARTEFACT_DATA[field];
    if (typeof v === 'number' && Number.isFinite(v)) {
      // v0.32.0 S19 (§17-6). A DECLARED number used to win SILENTLY over the computed one, so the
      // Brief's header could read "12 invariants" while the panel directly below it read "this
      // contract pins no INVARIANTs" — one page, one set, two answers. Observed live on this
      // build's own Brief. The page cannot know which figure is right, so it now refuses to print
      // either rather than picking one and looking certain.
      // Measured BEFORE this became a refusal, over all 30 build folders x 4 views: exactly ONE
      // build disagreed (this one), so no historical build is newly refused.
      // v0.32.0 S19b, after an independent reviewer showed the first form turned a WRONG page into
      // a DEAD one. A computed 0 does not mean "there are none" — it means THIS PARSER COULD NOT
      // READ THEM, which is a different statement and must not be treated as a contradiction.
      // Refuse only when the page computed a real, non-zero figure that disagrees; when it computed
      // nothing, render and DISCLOSE that it could not read them (see the invariant card below).
      // That is this contract's own doctrine: where you cannot verify, disclose.
      if (typeof fallback === 'number' && Number.isFinite(fallback) && fallback > 0 && v !== fallback) {
        console.error(`gen: '${field}' disagrees with itself — the compass-artefact-data block ` +
          `declares ${v}, this page computes ${fallback}. Fix whichever is wrong (the block lives ` +
          `in progress.md). A page may not state a number it contradicts elsewhere on itself.`);
        process.exit(4);
      }
      return nD(v, field);
    }
    console.error(`gen: compass-artefact-data field ${field} is not a finite number`);
    process.exit(4);
  }
  return nC(fallback);
}

const READER_COPY = (() => {
  // ONE extractor, shared with `compass.sh copy-gate` (scripts/reader-copy.mjs). This used to be a
  // second, subtly different regex living here: it required the fence line to end immediately in a
  // newline while copy-gate accepted a prefix match. One trailing space on the fence and this
  // parser still rendered the block onto the page while the GATE reported "no block to check".
  // Two parsers for one format is a drift bug waiting on a keystroke.
  const r = extractReaderCopy(contract);
  if (r.status === 'malformed') {
    // Never silently fall back to scraping: a block the author WROTE and this cannot read is a
    // defect to surface, not a reason to render unreviewed contract prose at a reader.
    console.error(`gen: ${r.why}`);
    process.exit(4);
  }
  if (r.status !== 'ok') return null;
  const out = parseReaderCopy(r.body);
  return Object.keys(out).length ? out : null;
})();
// rc('build-what', <fallback>) — the block wins where it speaks, the old path fills the rest.
const rc = (key, fallback) => {
  const v = READER_COPY && READER_COPY[key];
  return (Array.isArray(v) ? v[0] : v) || fallback;
};
// rcList('now', fallback) — the block's plain-language list where it speaks, the contract's own
// scope ladder where it does not. Guard-first, exactly like rc().
const rcList = (key, fallback) => {
  const v = READER_COPY && READER_COPY[key];
  if (!v) return fallback;
  return [].concat(v);
};
const secs = sections(contractFields);
// anchored-at-start (after an optional `N.` numeric prefix), NOT a loose substring —
// so `Goal` no longer matches `Non-goals`, and `## 4. Security …` / `## 2. Scope ladder` still resolve.
const sec = (needle) => {
  const nd = needle.toLowerCase();
  const norm = (x) => x.toLowerCase().replace(/^\d+\.\s*/, '');
  const k = Object.keys(secs).find((x) => { const n = norm(x); return n === nd || n.startsWith(nd); });
  return k ? secs[k] : '';
};
const hdr = (key) => {
  const m = contractFields.match(new RegExp('^\\s*\\*{0,2}' + key.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&') + '\\*{0,2}\\s*:\\s*(.+)$', 'im'));
  return m ? m[1].replace(/\*/g, '').trim() : '';
};
// INV-NO-TOKEN: wrap a REQUIRED field. A resolved value passes through; an unresolved
// one becomes a sentinel that the write seam refuses on, naming the field.
const req = (name, value) => {
  const v = (value === null || value === undefined) ? '' : String(value).trim();
  return v ? v : `\u27ea missing:${name}\u27eb`;
};

const title = (contract.match(/^#\s+(.+)$/m) || [, dir.split('/').pop()])[1].trim();
const slug = (hdr('slug') || dir.replace(/\/+$/, '').split('/').pop());

// ── sanitize injected prose: HTML-escape AND break any color literal so an off-theme token
//    quoted in the contract (e.g. the cinematic accent) can never trip the house anti-drift grep. ──
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const breakColors = (s) => String(s)
  .replace(/#([0-9a-fA-F]{3,8})/g, '#​$1')     // #7C74FF → # + zero-width + hex (renders identically)
  .replace(/(rgba?|hsla?)(\()/gi, '$1​$2');    // rgb(/hsl( → rgb + zero-width + (
// convert the contract's inline markdown to HTML AFTER escaping (so **/* /` never render literally)
const mdInline = (s) => {
  let out = String(s)
    .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
    .replace(/(?<![\w*])\*([^*\n]+)\*(?![\w*])/g, '<em>$1</em>')
    .replace(/`([^`]+)`/g, '<code>$1</code>');
  // An ODD number of asterisks leaves an orphan: pairing consumes the opener of the next span and
  // the closer arrives on the page as literal punctuation — three shipped Briefs ended a sentence
  // "…own shareable Brief.)*". Markdown syntax is never something a reader should meet, so drop
  // what is left over — but never inside a code span, where an asterisk is content.
  out = out.split(/(<code>[\s\S]*?<\/code>)/).map((seg, i) => (i % 2 ? seg : seg.replace(/\*/g, ''))).join('');
  return out;
};
// `txtAttr` is the attribute-safe form: escaped, but with no markup added. Used where the result
// lands inside a quoted attribute value (an aria-label), where a <span> would corrupt the HTML.
// v0.31 round 3, findings 1+2. A number the GENERATOR computes — the `and N more` of a truncated
// field, a step number invented because the plan line had none — used to flow through this path and
// come out `data-prov="quoted"`, i.e. "copied from what someone wrote in the build's files". Nobody
// wrote them. 248 invented step numbers across 21 of 28 builds, plus every truncation count, and one
// real page carried the sentence "No number on this page was worked out by this page" over four
// numbers the page had worked out itself. The sentence was false, on unmodified pages, with the gold
// at exit 0.
//
// A string cannot carry a marker through `esc()`, so the generator marks the RUN with a sentinel at
// the moment it computes it, and `markQuoted` honours that declaration instead of guessing. The
// sentinel is private-use, never appears in source prose, and is stripped from attribute text (an
// aria-label carries no markup, so it carries no marker either).
const CNT_A = '\uE000', CNT_B = '\uE001';
const nCt = (v) => CNT_A + String(v) + CNT_B;   // "this run is COUNTED", inside a text string
const stripCnt = (s) => String(s).replace(/[\uE000\uE001]/g, '');
const CNT_A_RE = /[\uE000\uE001]/;
const txtAttrRaw = (s) => mdInline(esc(breakColors(String(s))));
const txtAttr = (s) => stripCnt(txtAttrRaw(s));

// `txt` is the HTML form, and it marks every number it passes through as QUOTED.
//
// This is where the bulk of a page's numbers come from: text quoted out of contract.md, plan.md and
// review-ledger.md — a step title, a finding's wording, a version string. The generator does not
// COMPUTE any of them; it is passing along what the model wrote. `literal` says exactly that: this
// number makes no claim about this build's data, from me.
//
// Marking them here rather than at 59 call sites is deliberate. The alternative is remembering to
// wrap each one, and "did I remember everywhere?" is the question this whole build exists to stop
// asking — a containment rule is only worth having if the thing it checks is structural.
//
// If one of these numbers turns out to move when the build's data moves, it was not a literal, and
// the gate's `mislabelled` cross-check says so by name. That is the intended feedback loop: quoted
// text that is secretly derived gets found, rather than assumed either way.
// Matches ANY Unicode numeric character, not just ASCII `\d`. Compass's own docs use circled digits
// (\u2460 \u2461 \u2462 for the lifecycle stages) and superscripts, and the auditor NFKC-normalises
// before it counts — so an ASCII-only pattern here marked nothing while the gate saw plain digits.
// That accounted for every one of the last 25 unmarked numbers: the generator and the checker were
// reading different alphabets. Close the shape, not the instance.
//
// The class includes `,` so a thousands separator stays INSIDE one marker. Without it `1,051` became
// two spans with a comma between them, which broke 34 smoke assertions that grep the formatted gold
// figure out of a rendered Brief — the marker must not change the string a reader (or a test) sees.
const QUOTE_RUN = /[\w.,\-\/\p{Nd}\p{No}]*[\p{Nd}\p{No}][\w.,\-\/\p{Nd}\p{No}]*/gu;
const markQuoted = (h) => String(h)
  .split(/(<[^>]+>)/g)
  .map((part, i) => {
    if (i % 2 === 1) return part;
    // A sentinel-wrapped run was computed by this file, so it is `counted`, not `quoted`. Everything
    // between the sentinels is emitted as ONE marker — never re-scanned, so no marker nests.
    return part.split(/(\uE000[\s\S]*?\uE001)/g).map((seg) => {
      if (seg.startsWith(CNT_A) && seg.endsWith(CNT_B)) {
        return `<span data-prov="counted">${seg.slice(1, -1)}</span>`;
      }
      return stripCnt(seg).replace(QUOTE_RUN, (t) => `<span data-prov="quoted">${t}</span>`);
    }).join('');
  })
  .join('');
const txt = (s) => markQuoted(txtAttrRaw(s));

// ── v0.31: ONE function every number on a page goes through ─────────────────────────────────────
//
// Five review rounds were spent trying to work out, from outside this file, which numbers on a
// rendered page are claims about the build's data. Two rules were built and measured and thrown
// away: a number sitting next to a counting noun (12.5% recall, 6.8% false demands — it wanted a
// "counted by reading" label on `v0.28.0`), and a number that moves when a mutated twin is rendered
// (35.6% recall, 19% false demands from an environment artefact). A heuristic at the sink cannot be
// made exact.
//
// This file already knows. `num()` makes it say so, once, at the point of emission:
//
//   num(207, 'counted')                  worked out by reading; may be wrong, and the page says so
//   num(207, 'declared', 'findings.total') came from the build's data block; must equal that field
//   num('v0.28.0', 'literal')            a version, a date, an id — a number that claims nothing
//
// The gate then performs a containment test — every digit run a reader sees sits inside a marker —
// which needs no vocabulary, no second render and no alignment. `literal` is what makes that honest
// rather than merely convenient: without it a version string would have to be mislabelled a count
// just to satisfy the rule.
const NUM_KINDS = new Set(['counted', 'declared', 'literal', 'quoted']);
function num(value, kind, field) {
  if (!NUM_KINDS.has(kind)) throw new Error(`num(): unknown kind ${JSON.stringify(kind)}`);
  const shown = esc(String(value));
  if (kind === 'declared') {
    if (!field) throw new Error('num(): a declared number must name its block field');
    return `<span data-count="${esc(field)}" data-prov="declared">${shown}</span>`;
  }
  return `<span data-prov="${kind}">${shown}</span>`;
}
// Shorthands, so a call site stays readable at the point it already was.
const nC = (v) => num(v, 'counted');           // counted by reading this build's files
const nL = (v) => num(v, 'literal');           // claims nothing about this build's data
const nQ = (v) => num(v, 'quoted');            // the model's own words, reproduced verbatim
const nD = (v, f) => num(v, 'declared', f);    // from the data block, and must equal it

// The words a page carrying `counted` numbers owes its reader. Pinned by the contract; the gate
// matches it apostrophe- and whitespace-insensitively, so this may be typeset normally.
const COUNTED_NOTE = "counted by reading this build's files";


// ── first paragraph of a section (skips leading blank/bold-label lines) ──
function firstPara(body) {
  const paras = body.split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
  const first = paras[0] || '';
  // A paragraph ending in a COLON is a label, and its content is whatever follows. Returning the
  // label alone silently dropped the content on 24 fields across 22 pages — including the Brief's
  // "Proof" card on two builds, where the label survived and all four pinned gold figures (the
  // numbers the build is checked against) did not. Nothing could see it: the text ends in a colon,
  // which both the truncator and the cut check accept as a terminator.
  if (/:$/.test(first) && paras[1]) {
    // Skip a markdown TABLE's scaffolding. The card that exists to show the gold figure printed
    // `| Figure | Value | Source |; |---|---|---|` — the header and the separator row — and then
    // dropped the second figure. A reader should see the numbers, not the table's plumbing.
    const rest = paras[1].split('\n')
      .filter((l) => !/^\s*\|?\s*:?-{2,}/.test(l))
      .map((l) => l.replace(/^\s*[-*]\s*/, '').replace(/^\s*\|\s*/, '').replace(/\s*\|\s*$/, '').replace(/\s*\|\s*/g, ' — ').trim())
      .filter(Boolean);
    if (rest.length) {
      // P7a. The colon-label path consumed paragraphs one and two; anything past those is gone.
      const out = `${first} ${rest.join('; ')}`;
      if (paras.length > 2) lossy('firstPara', out.length, paras.join('\n\n').length, paras.length - 2, () => paras.slice(2));
      return out;
    }
  }
  // P7b. The ordinary path returns paragraph one and drops every other paragraph in the section,
  // printing nothing at all to say so. One of the three paths that leave no trace — which is why
  // no amount of searching a rendered page could ever have found it.
  if (paras.length > 1) lossy('firstPara', first.length, paras.join('\n\n').length, paras.length - 1, () => paras.slice(1));
  return first;
}
// ── render a FULL section body as paragraphs (blank-line separated; lines joined by <br>) — used on the
//    LOCAL Brief so the reconciliation figure/tolerance and the F-SECPIN role×view matrix + STRIDE-lite are
//    NOT dropped from the lock surface (post-ship PS-1r4-B). The shareable path stays firstPara + redaction. ──
function bodyHtml(body) {
  return String(body || '').split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean)
    .map((p) => `<p>${p.split('\n').map((ln) => txt(ln.trim())).filter(Boolean).join('<br>')}</p>`).join('') || '<p>—</p>';
}
// ── bullet lines from a section matching a prefix predicate ──
function bullets(body, re) {
  return body.split('\n').map((l) => l.trim()).filter((l) => re.test(l));
}

// ── INVARIANTs: name + short summary (drop the "→ assert" tail) ──
function invariants() {
  const body = sec('INVARIANT') || sec('Acceptance');
  const rows = [];
  for (const l of body.split('\n')) {
    // v0.32.0 S19 (§17-6): TWO shapes, not one. A contract may write its invariants as bullets
    // OR as a table, and this parser only knew bullets — so a contract with a 12-row invariant
    // table rendered "this contract pins no INVARIANTs" in the panel while the header, fed from
    // the DECLARED artefact-data block, said 12. Same page, same contract, two answers.
    // Observed live on this build's own Brief; it is §17 entry 6.
    const m = l.match(/^-\s+\*\*(INV-[A-Za-z0-9][A-Za-z0-9-]*)[^*]*\*\*:?\s*(.*)$/)
           || l.match(/^\|\s*\*\*(INV-[A-Za-z0-9][A-Za-z0-9-]*)[^*]*\*\*\s*\|\s*([^|]*)/);
    if (!m) continue;
    // drop ONLY the "→ *assert:*" recipe tail — NOT every internal arrow, or binding text is lost
    // (INV-COMMSCAN's "→ CRITICAL", INV-SUITES' full "→ 0 … → PASS" chain, INV-NO-LEAK) (R3-M2).
    // P10. NOT ENUMERATED IN CONTRACT SECTION 9, found by S2's independent census. This is the
    // largest UNMARKED destroying path in the file by event count: the command that PROVES each
    // invariant is split off here and reaches no rendered page, with nothing saying it was removed.
    const _invParts = m[2].split(/→\s*\*?\s*assert/i);
    let summary = _invParts[0].replace(/\*/g, '').replace(/[:\s]+$/, '').trim();
    // v0.32.0 S7: the assert recipe is carried OUT on the row so the invariant table can disclose
    // it. The shown half is the summary — what the page actually prints for this row — so the check
    // can tie the control to it. Dropping the command that PROVES an invariant, unmarked, was the
    // largest unmarked destroying path in this file.
    let _dropped = '';
    if (_invParts.length > 1) {
      _dropped = 'assert:' + _invParts.slice(1).join(' ');
      lossy('invariants.assertTail', _invParts[0].length, m[2].length, 1, () => [_invParts.slice(1).join(' ')], () => summary);
    }
    if (summary && !/[.!?)]$/.test(summary)) summary += '.';
    // A deferred INVARIANT carries a bookkeeping marker ("— original text retained …"); render
    // the deferral plainly instead of leaking the marker as if it were the assertion.
    // the marker sits inside the BOLD NAME, not the summary, so match the whole line
    const defer = l.match(/DEFERRED TO ([A-Za-z0-9.]+)/);
    if (defer) {
      // Name WHAT is deferred. One canned sentence for every deferral printed the identical line
      // twice on the Brief — a reader saw the same words in two rows and could not tell what
      // differed, which is the duplication the copy gate now catches. The contract keeps the
      // original wording under "original text retained"; that clause is the plain answer.
      const kept = l.match(/original text retained[^:]*:\s*\*\*\([^)]*\)\s*—\s*([^*]+)\*\*/);
      const what = kept ? kept[1].replace(/[.\s]+$/, '') : '';
      // ONE sentence, not two: a shared closing sentence is itself a repeated 40-char line, and
      // the copy gate counts sentences, not rows. Folding the clause in keeps each row unique.
      // P11. NOT ENUMERATED IN SECTION 9. The page says "Not in this release" but never says the
      // invariant's own wording was discarded to say it — a partial marker, not a full one.
      // The invariant's ORIGINAL wording, replaced wholesale by the deferral sentence. Carried out
      // the same way; its shown half is the sentence that replaced it.
      const _origSummary = summary;
      lossy('invariants.deferredReplaced', 0, summary.length, 1, () => [_origSummary],
            () => (what ? `Not in this release — ${what}` : 'Not in this release'));
      _dropped = _dropped ? `${_origSummary}\n\n${_dropped}` : _origSummary;
      summary = what
        ? `Not in this release — ${what}; it ships with the work it governs, in ${defer[1]}.`
        : `Not in this release; it ships with the work it governs, in ${defer[1]}.`;
    }
    rows.push({ name: m[1], summary, dropped: _dropped });
  }
  return rows;
}
// ── scope ladder NOW / LATER / NEVER ──
function scope() {
  // real contracts write `### NOW —` headings + numbered/bullet items; parse those first, then
  // fall back to the old `- NOW:` inline-bullet form (item filter accepts BOTH `N.` and `-`/`*`).
  const grab = (kw) => {
    const m = contractFields.match(new RegExp('###\\s*' + kw + '[^\\n]*\\n([\\s\\S]*?)(?=\\n###|\\n##\\s|$)', 'i'));
    if (m) {
      const items = m[1].split('\n').map((l) => l.trim())
        .filter((l) => /^(\d+\.|[-*])\s+/.test(l))
        .map((l) => l.replace(/^(\d+\.|[-*])\s+/, '').replace(/\*/g, '').trim())
        .filter(Boolean);
      if (items.length) return items;
    }
    const body = sec('Scope ladder') || sec('scope');
    return bullets(body, new RegExp('^-\\s+\\**\\s*' + kw + '\\b', 'i'))
      .map((l) => l.replace(new RegExp('^-\\s+' + kw + '\\s*:?\\s*', 'i'), '').replace(/\*/g, '').trim());
  };
  return { now: grab('NOW'), later: grab('LATER'), never: grab('NEVER') };
}
// ── security & data-sensitivity: present? genuine N/A? never-show values? ──
function security() {
  const body = sec('Security') || sec('data-sensitivity');
  if (!body) return { present: false };
  // Collect never-show field tokens in EVERY supported format so the shareable scrub (which iterates this
  // list) actually redacts them — inline `never-show: a, b`, a `Never-show fields:` bullet list, and a
  // per-field row ending in a `never-show` label. A list-format never-show that isn't collected here would
  // ship the field names in a "blessed" (exit 0) shareable copy — a soft-pass (post-ship PS-1 round 4).
  const neverShow = [];
  const addTok = (s) => { for (const t of String(s).split(/[,;\s]+/)) { const c = t.replace(/[.,;]+$/, '').trim(); if (c) neverShow.push(c); } };
  let inNsList = false;
  for (const raw of body.split('\n')) {
    const l = raw.trim();
    const inline = l.match(/never-show\s*:\s*(\S.*?)\s*$/i);
    if (inline) { addTok(inline[1]); inNsList = false; continue; }
    if (/never-show\b[^:]*:\s*$/i.test(l)) { inNsList = true; continue; }   // "Never-show fields:" header
    if (inNsList) {
      const b = l.match(/^[-*]\s*([A-Za-z0-9_.\-]+)/);
      if (b) { neverShow.push(b[1]); continue; }
      if (l) inNsList = false;
    }
    const perField = l.match(/^[-*]\s*([A-Za-z0-9_.\-]+)\b.*\bnever[-\s]?show\b/i);
    if (perField) neverShow.push(perField[1]);
  }
  // "N/A" ONLY when the block LEADS with it (the whole block is N/A) AND declares no real sensitive surface.
  // An "N/A" buried in a STRIDE line ("Repudiation — N/A") or a role×view cell ("guest → N/A") must NOT flip
  // a PII / never-show block to a false green "no sensitive surface" badge that hides the binding classification
  // a user locks against (post-ship PS-2-1 / CRITIQUE-TARGET #3).
  const lead = /^\s*\**\s*N\/A\b\s*[—-]?\s*(.*)/i.exec(firstPara(body));
  // "declares a sensitive surface" catches never-show in ANY format (inline `never-show:` OR a
  // "Never-show fields:" list) + the common sensitivity vocabulary — so a block that LEADS with N/A but
  // still classifies fields can't flip to a false green "no sensitive surface" badge (post-ship PS-2-1 /
  // PS-3 / PS-3b). "sensitive" alone is intentionally NOT a trigger (a genuine "no sensitive surface" N/A).
  const declaresSensitive = neverShow.length > 0 || /\bnever-show\b/i.test(body)
    || /\b(PII|PHI|commercial-sensitive|confidential|restricted)\b/i.test(body);
  const na = !!lead && !declaresSensitive;
  return { present: true, na, naReason: na ? (lead[1] || '').trim() : '', body, neverShow };
}
// ── reconciliation gold literal (the section body) ──
const goldBody = sec('Reconciliation');
// ── reconciliation-gold FIGURE tokens: currency / ≥3-digit numbers / percentages / multiples that
//    appear in the gold section — the confidential VALUES a shareable Brief must NEVER carry (a figure
//    restated in the Goal or touches would otherwise ship at exit 0). Empty for an N/A / non-numeric
//    gold (this build), so it never over-redacts a library build. Value-based, not an alpha prefix. ──
function goldFigures() {
  // Extract every confidential FIGURE token FROM THE GOLD SECTION only, then scrub each globally. No "N/A
  // skip": a figure-less gold (this library build's "Numeric N/A") naturally yields [] here, so it is never
  // over-redacted — while a gold that SAYS "N/A" but still carries a figure is NOT let through (R3-R2-D2 →
  // R3-R3-D1: the N/A-skip was a bypass). Value-based, never an alpha prefix.
  const g = goldBody || '';
  const out = new Set();
  const add = (re) => { for (const m of g.matchAll(re)) { const t = m[0].trim(); if (t) out.add(t); } };
  add(/[$₹€£]\s?\d[\d,]*(?:\.\d+)?/g);                                     // currency ($9,999,999.00)
  add(/\b\d+(?:\.\d+)?\s?%/g);                                             // percentages (18.5%)
  add(/\b\d+(?:\.\d+)?\s?x\b/gi);                                          // multiples (1.8x)
  add(/\b\d[\d,]*(?:\.\d+)?\s?(?:crores?|lakhs?|bps|rupees|cr|mn|bn|k)\b/gi); // number + unit word (42 crore, 88 bps)
  add(/\b\d+\.\d+/g);                                                      // decimals, ANY digit count (1.5, 2.5) — R3-R3-D3
  add(/\b\d[\d,]{1,}(?:\.\d+)?/g);                                         // bare integers ≥2 digits (42, 349)
  add(/\b(?=[A-Za-z]*\d)(?=\d*[A-Za-z])[A-Za-z0-9]{6,}\b/g);               // id-like alnum ≥6 w/ letters+digits (DEADBEEF42)
  return [...out];
}

// ============================================================================================
// THEME — neutral-indigo tokens inlined so the asset is self-contained (matches themes/neutral-indigo.json).
// Only these colors + structural neutrals appear in the house body → anti-drift-grep passes.
// ============================================================================================
// ── v0.29.0 INV-HOUSE — the palette is READ, never re-typed ────────────────────
// These literals used to be hand-copied from the theme. They happened to match, but a
// theme edit would have silently drifted the artefacts out of the house system while
// the anti-drift gate kept passing against the OLD values. Read the theme file and emit
// the custom properties from it, so drift is impossible by construction.
// v0.30: the PINNED artefact design system. rk-house-style/neutral-indigo stays the system for the
// PRODUCT UIs Compass builds for users — two systems, two audiences, decided at contract time.
const THEME = JSON.parse(readFileSync(new URL('./themes/compass-artefact.json', import.meta.url), 'utf8'));
const THEME_VARS = Object.entries(THEME)
  .filter(([k, v]) => !k.startsWith('_') && typeof v === 'string' && !k.startsWith('font'))
  .map(([k, v]) => `--${k}:${v};`)
  .join(' ');
const DARK_VARS = Object.entries(THEME._dark || {})
  .filter(([k]) => !k.startsWith('_'))
  .map(([k, v]) => `--${k}:${v};`)
  .join(' ');
const HOUSE_CSS = `
  /* v0.32.0 S6 — the disclosure control. NO line-clamp, NO ellipsis, NO max-height: clipped text is
     not reachable text, and this build's own check strips clipped subtrees before it looks. */
  .rest{margin-top:6px}
  .rest>summary{cursor:pointer;font-size:11px;color:var(--mut2);list-style:revert}
  .rest>summary:hover{color:var(--ink)}
  .rest .rest-body{margin-top:4px;font-size:12px;line-height:1.5;color:var(--ink);white-space:pre-wrap}

  /* v0.30: all three theme states, defined at TOKEN level only. Components are styled through
     the tokens and never inside a media or [data-theme] block — a colour whose only definition
     sits behind [data-theme] never applies in the un-stamped "system" state, which is the
     classic unreadable-artifact bug. */
  :root{
    ${THEME_VARS}
  }
  @media (prefers-color-scheme: dark){
    :root:not([data-theme="light"]){ ${DARK_VARS} }
  }
  :root[data-theme="dark"]{ ${DARK_VARS} }
  /* The host paints its own ground in ITS theme, so a transparent body borrows the wrong one.
     body carries an explicit background from a token. */
  body{background:var(--bg);color:var(--ink);margin:0}
  *{box-sizing:border-box;margin:0}
  .cv-body{background:var(--bg);color:var(--ink);
    font-family:${THEME.fontSans};
    font-variant-numeric:tabular-nums;-webkit-font-smoothing:antialiased;padding:34px}
  .cv-body .wrap{max-width:1120px;margin:0 auto}
  .cv-body .kicker{font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--kicker)}
  .cv-body h1{font-size:23px;font-weight:700;letter-spacing:-.01em;margin-top:4px}
  .cv-body .lede{font-size:14px;color:var(--mut);margin-top:8px;line-height:1.55;max-width:80ch}
  .cv-body .lede b{color:var(--ink);font-weight:600}
  /* ── v0.29.0 the four bands — identical order on every view (INV-BANDS) ── */
  .cv-body .b-decide{background:var(--surface);border:1px solid var(--line);border-left:5px solid var(--accent);
    border-radius:12px;padding:20px 22px;box-shadow:0 1px 2px ${THEME.shadow};margin-bottom:16px}
  .cv-body .b-decide .ask{color:var(--accent);font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;margin-bottom:8px}
  .cv-body .b-decide h1{font-size:26px;letter-spacing:-.015em;line-height:1.2;margin-top:0}
  .cv-body .b-id{color:var(--mut);margin-top:8px;font-size:13.5px}
  .cv-body .b-id b{color:var(--ink);font-weight:600}
  .cv-body .b-label{font-size:10px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--kicker);margin-bottom:10px}
  .cv-body .b-facts{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:16px}
  .cv-body .b-fact{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:14px 16px}
  .cv-body .b-fact .k{font-size:10px;font-weight:700;letter-spacing:.11em;text-transform:uppercase;color:var(--kicker);margin-bottom:7px}
  .cv-body .b-fact .v{font-size:14px;color:var(--mut);line-height:1.45}
  .cv-body .b-fact .v b{color:var(--ink)}
  .cv-body .b-flow{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:20px 22px;margin-bottom:16px;overflow-x:auto}
  .cv-body .b-flow svg{display:block;margin:0 auto;max-width:100%;height:auto}
  .cv-body .b-purpose{color:var(--mut);font-size:12.5px;margin:-2px 0 14px}
  .cv-body .b-legend{display:flex;gap:20px;flex-wrap:wrap;justify-content:center;color:var(--mut);font-size:12.5px;margin-top:12px}
  .cv-body .b-sec{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:20px 22px;margin-bottom:16px}
  .cv-body .b-sec h2{font-size:15px;color:var(--ink);margin:0 0 2px}
  .cv-body .b-cols{display:grid;grid-template-columns:1fr 1fr;gap:16px;align-items:start}
  .cv-body .b-na{background:var(--chipBg);color:var(--chipFg);border-radius:8px;padding:10px 12px;font-size:13px}
  .cv-body .b-step{display:grid;grid-template-columns:34px 1fr 300px;gap:12px;padding:11px 0;border-top:1px solid var(--line);align-items:start}
  .cv-body .b-step:first-of-type{border-top:0}
  .cv-body .b-num{color:var(--kicker);font-size:12.5px;font-weight:700;padding-top:2px}
  .cv-body .b-ttl{color:var(--ink);font-size:14px;font-weight:600}
  .cv-body .b-det{color:var(--mut);font-size:12.5px;margin-top:3px}
  .cv-body .verify{background:var(--grid);border:1px solid var(--line);border-radius:8px;padding:7px 9px;color:var(--chipFg);font-size:12px;line-height:1.4;font-family:${THEME.fontMono}}
  .cv-body .verify b{color:var(--greenFg);font-weight:700;font-size:10px;letter-spacing:.08em;text-transform:uppercase;display:block;margin-bottom:3px;font-family:${THEME.fontSans}}
  .cv-body ul.pl{list-style:none;display:grid;gap:8px;padding:0;margin:0}
  .cv-body ul.pl li{display:grid;grid-template-columns:auto 1fr;gap:10px;align-items:start;color:var(--mut);font-size:13.5px;line-height:1.45}
  .cv-body ul.pl li b{color:var(--ink)}
  .cv-body .pill{font-size:10px;line-height:1.7;font-weight:700;letter-spacing:.06em;text-transform:uppercase;padding:0 8px;border-radius:99px;white-space:nowrap}
  .cv-body .pill.now{background:var(--greenBg);color:var(--greenFg)}
  .cv-body .pill.later{background:var(--amberBg);color:var(--amberFg)}
  .cv-body .pill.never{background:var(--redBg);color:var(--redFg)}
  .cv-body table.t{width:100%;border-collapse:collapse;font-size:13px}
  .cv-body table.t th{text-align:left;font-size:10px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--kicker);padding:0 18px 8px 0}
  .cv-body table.t th:last-child{padding-right:0}
  .cv-body table.t td{padding:8px 18px 8px 0;border-top:1px solid var(--line);color:var(--mut);vertical-align:top;text-align:left}
  .cv-body table.t td:last-child{padding-right:0}
  .cv-body table.t td.k{color:var(--ink);white-space:nowrap;font-weight:600;font-size:12px}
  .cv-body .foot{color:var(--kicker);font-size:12px;text-align:center;padding-top:4px}
  @media (max-width:900px){
    .cv-body .b-facts{grid-template-columns:repeat(2,1fr)}
    .cv-body .b-cols{grid-template-columns:1fr}
    .cv-body .b-step{grid-template-columns:30px 1fr}
    .cv-body .verify{grid-column:2}
  }
  .cv-body .card{background:var(--surface);border:1px solid var(--line);border-radius:12px;
    box-shadow:0 1px 2px ${THEME.shadow};padding:18px 20px;margin-top:16px}
  .cv-body .card>.kicker{margin-bottom:8px;font-weight:700;text-transform:uppercase}
  .cv-body .grid2{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-top:16px}
  .cv-body .grid3{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-top:16px}
  .cv-body p{font-size:13px;color:var(--mut);line-height:1.55}
  .cv-body p b{color:var(--ink);font-weight:600}
  .cv-body code{font-family:${THEME.fontMono};font-size:12px;background:var(--chipBg);color:var(--ink);padding:1px 5px;border-radius:5px}
  .cv-body ul{list-style:none;margin-top:6px}
  .cv-body li{font-size:13px;color:var(--ink);line-height:1.5;padding:5px 0 5px 16px;position:relative;border-top:1px solid var(--line)}
  .cv-body li:first-child{border-top:0}
  .cv-body li::before{content:"";position:absolute;left:0;top:12px;width:6px;height:6px;border-radius:99px;background:var(--accent)}
  .cv-body .chip{display:inline-flex;align-items:center;gap:6px;font-size:11px;font-weight:600;
    padding:3px 10px;border-radius:99px;color:var(--chipFg);background:var(--chipBg)}
  .cv-body .badge{display:inline-flex;align-items:center;gap:6px;font-size:12px;font-weight:700;
    padding:4px 12px;border-radius:99px;color:var(--greenFg);background:var(--greenBg)}
  .cv-body .badge.warn{color:var(--amberFg);background:var(--amberBg)}
  .cv-body table{width:100%;border-collapse:collapse;margin-top:6px}
  .cv-body th{font-size:10px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--kicker);
    text-align:right;padding:8px 10px;border-bottom:1px solid var(--line)}
  .cv-body th:first-child,.cv-body td:first-child{text-align:left}
  .cv-body td{font-size:13px;color:var(--ink);padding:9px 10px;border-bottom:1px solid var(--line);vertical-align:top;text-align:right}
  .cv-body td .n{font-weight:700;color:var(--accent)}
  .cv-body tr:last-child td{border-bottom:0}
  .cv-body .cols{display:grid;grid-template-columns:repeat(3,1fr);gap:1px;background:var(--line);
    border:1px solid var(--line);border-radius:8px;overflow:hidden}
  .cv-body .col{background:var(--surface);padding:14px 16px}
  .cv-body .col .hd{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;margin-bottom:8px}
  .cv-body .col.now .hd{color:var(--greenFg)} .cv-body .col.later .hd{color:var(--amberFg)} .cv-body .col.never .hd{color:var(--redFg)}
  .cv-body .foot{margin-top:20px;font-size:11px;color:var(--mut2);border-top:1px solid var(--line);padding-top:12px}
  .cv-body .ba{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:12px}
  .cv-body .ba .panel{border:1px solid var(--line);border-radius:8px;padding:12px}
  .cv-body .ba .panel.to{border-color:var(--accent);background:var(--chipBg)}
  .cv-body .ba .panel .t{font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:var(--kicker);margin-bottom:6px}
  .cv-body .ba .panel p{font-size:12px;color:var(--ink);line-height:1.45}
  .cv-body .done{background:var(--accent);color:var(--surface);border-radius:12px;padding:18px 20px;margin-top:16px}
  .cv-body .done .k{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;opacity:.85}
  .cv-body .done .big{font-size:16px;font-weight:700;margin-top:6px;line-height:1.35}
  .cv-body .proofrow{display:flex;flex-wrap:wrap;gap:8px;margin-top:8px}
  .cv-body .stat{flex:1;min-width:110px;border:1px solid var(--line);border-radius:8px;padding:10px 12px;background:var(--surface)}
  .cv-body .stat .sk{font-size:10px;color:var(--kicker);font-weight:700;text-transform:uppercase;letter-spacing:.05em}
  .cv-body .stat .sv{font-size:15px;font-weight:700;color:var(--ink);margin-top:3px}
  .cv-body .flow{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:6px}
  .cv-body .step{border:1px solid var(--line);border-radius:8px;padding:12px}
  .cv-body .step .si{font-size:11px;font-weight:700;color:var(--accent);background:var(--chipBg);width:20px;height:20px;border-radius:6px;display:inline-flex;align-items:center;justify-content:center}
  .cv-body .step .st{font-size:12px;color:var(--ink);margin-top:6px;line-height:1.4}
  .cv-body .won{border:1px solid var(--line);border-radius:12px;padding:16px 18px;background:var(--redBg);margin-top:16px}
  .cv-body .won .hd{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.05em;color:var(--redFg);margin-bottom:8px}
  .cv-body .won li::before{background:var(--redFg)}
  .cv-body details{margin-top:16px;border:1px solid var(--line);border-radius:12px;background:var(--surface)}
  .cv-body details>summary{cursor:pointer;padding:14px 18px;font-size:12px;font-weight:700;color:var(--ink)}
  .cv-body details .db{padding:0 18px 14px}
`;

// ── house-style Brief body (returns inner markup; used standalone AND inside the full brief) ──
// ── v0.29.0 the four bands (INV-BANDS) ────────────────────────────────────────
// EVERY view composes from these, in this order: the decision, the facts needed to
// make it, the logic block, then detail. The order is the product decision — a reader
// should never hunt for what they are being asked, and band 3 is always the diagram.
// ── v0.29.0 INV-LOGIC-BLOCK — the diagram, drawn not decorated ────────────────
// Inline SVG, generated here: no runtime library, no network, works offline forever,
// and assertable as text (a "decorative diagram" becomes a failing count, not a matter
// of taste). Nodes/edges come from the contract's `## Logic Map` mermaid fence when it
// has one, else from the build's own stage structure — so it always says something true
// about THIS build rather than being generic boxes.
function parseMermaid(md) {
  const m = String(md).match(/```mermaid\s*\n([\s\S]*?)```/);
  if (!m) return null;
  const nodes = new Map();
  const edges = [];
  const label = (raw) => String(raw).replace(/<br\s*\/?>/gi, ' ').replace(/&lt;|&gt;|["'\[\]{}()]/g, '').trim();
  for (const ln of m[1].split('\n')) {
    const e = ln.match(/^\s*([A-Za-z0-9_]+)\s*(\[[^\]]*\]|\{[^}]*\}|\([^)]*\))?\s*(-\.->|-->|---)\s*(?:\|([^|]*)\|)?\s*([A-Za-z0-9_]+)\s*(\[[^\]]*\]|\{[^}]*\}|\([^)]*\))?/);
    if (!e) continue;
    const [, a, aL, arrow, edgeL, b, bL] = e;
    if (aL && !nodes.has(a)) nodes.set(a, label(aL));
    if (bL && !nodes.has(b)) nodes.set(b, label(bL));
    if (!nodes.has(a)) nodes.set(a, a);
    if (!nodes.has(b)) nodes.set(b, b);
    edges.push({ a, b, dashed: arrow === '-.->', label: label(edgeL || '') });
  }
  return nodes.size >= 3 && edges.length >= 2 ? { nodes, edges } : null;
}
// Lay the graph out in reading order as a snake, so it reads left-to-right then back —
// the shape a person scans, not a force-directed tangle.
function logicBlock(graph, ariaLead) {
  const ids = [...graph.nodes.keys()];
  const W = 210, H = 54, GX = 30, GY = 54, PAD = 8, MAXCOL = 4;

  // ── LAYERED layout, computed from the graph ────────────────────────────────────────────────
  // The old layout placed nodes in DECLARATION order across a 4-column snake: row 1 ran
  // left-to-right, row 2 right-to-left, row 3 left-to-right. A cold reader put it plainly —
  // "I had to reverse direction mid-read". Arrows were then drawn between whatever grid cells
  // the nodes happened to land in, so the picture looked structured and read as noise.
  // Depth is now the longest path along SOLID edges (a dashed edge is a refusal, not flow), so
  // every row reads the same direction and an arrow always points forward.
  // Depth over ALL edges, not just solid ones. Using solid-only put every refusal TARGET at
  // depth 0 — "STOP, fix the page" floated to the top row, above the step that refuses into it —
  // and collapsed the chain into one narrow column with the page half empty. A refusal is still
  // a successor: it happens after the thing that refuses.
  const depth = new Map(ids.map((id) => [id, 0]));
  for (let pass = 0; pass < ids.length; pass++) {
    let moved = false;
    for (const e of graph.edges) {
      if (!depth.has(e.a) || !depth.has(e.b)) continue;
      if (depth.get(e.b) < depth.get(e.a) + 1) { depth.set(e.b, depth.get(e.a) + 1); moved = true; }
    }
    if (!moved) break;
  }
  // Reading order = depth, ties broken by declaration. Wrap at MAXCOL, ALWAYS left-to-right —
  // the snake reversed every other row and a cold reader said so: "I had to reverse direction
  // mid-read."
  // A REFUSAL TERMINAL is a node reached only by a dashed edge with nothing leaving it — "STOP,
  // fix the page", "fallback: local path + reason". Depth ordering legitimately placed these
  // inline on the main track, and a cold reader could not tell whether the happy path routed
  // THROUGH a stop. They get their own band below the flow: still connected, visibly not the
  // main track.
  const outDeg = new Map(ids.map((id) => [id, 0]));
  const inSolid = new Map(ids.map((id) => [id, 0]));
  const inDashed = new Map(ids.map((id) => [id, 0]));
  for (const e of graph.edges) {
    if (outDeg.has(e.a)) outDeg.set(e.a, outDeg.get(e.a) + 1);
    if (e.dashed) { if (inDashed.has(e.b)) inDashed.set(e.b, inDashed.get(e.b) + 1); }
    else if (inSolid.has(e.b)) inSolid.set(e.b, inSolid.get(e.b) + 1);
  }
  const isTerminal = (id) => outDeg.get(id) === 0 && inDashed.get(id) > 0 && inSolid.get(id) === 0;
  const byDepth = (a, b) => (depth.get(a) - depth.get(b)) || (ids.indexOf(a) - ids.indexOf(b));
  const flow = ids.filter((id) => !isTerminal(id)).sort(byDepth);
  const terms = ids.filter(isTerminal).sort(byDepth);

  const pos = new Map();
  flow.forEach((id, i) => {
    const row = Math.floor(i / MAXCOL), col = i % MAXCOL;
    pos.set(id, { x: PAD + col * (W + GX), y: PAD + row * (H + GY), row });
  });
  const flowRows = Math.ceil(flow.length / MAXCOL);
  // one blank row of separation, so the band reads as a different kind of thing
  const termRow0 = flowRows + (terms.length ? 1 : 0);
  terms.forEach((id, i) => {
    const row = termRow0 + Math.floor(i / MAXCOL), col = i % MAXCOL;
    pos.set(id, { x: PAD + col * (W + GX), y: PAD + row * (H + GY), row });
  });
  const rows = termRow0 + Math.ceil(terms.length / MAXCOL);
  const vw = PAD * 2 + MAXCOL * W + (MAXCOL - 1) * GX;
  const vh = PAD * 2 + rows * H + (rows - 1) * GY;

  const _svgRest = [];
  const boxes = ids.map((id) => {
    const p = pos.get(id);
    const { lead, rest } = splitLead(graph.nodes.get(id), 30);
    const t1 = `<text x="${p.x + W / 2}" y="${p.y + (rest ? 22 : 31)}" text-anchor="middle" fill="${THEME.ink}" font-weight="600" font-size="12.5">${txt(lead)}</text>`;
    // A sub-label is a deliberate second line, not an accident: same colour family, clearly
    // smaller, and set on its own baseline. The old treatment read as a rendering fault.
    // v0.32.0 S6, the one call site with no generic answer. A `<details>` is illegal inside an
    // `<svg>`, and NOT shortening overflows a fixed-width box — which is contract §9's own css-clip
    // cheat wearing a different hat. So: shorten to what fits, keep the full text in the node's
    // accessible name (the aria-label below already carries it), AND emit it in a reachable element
    // OUTSIDE the svg. All three, because any two of them still leave a sighted reader short.
    const _sub = fieldParts(rest, 34);
    if (_sub.rest) _svgRest.push(`${lead} — ${rest}`);
    const t2 = rest ? `<text x="${p.x + W / 2}" y="${p.y + 39}" text-anchor="middle" fill="${THEME.mut}" font-size="11" font-style="italic">${txt(_sub.shown)}</text>` : '';
    return `<rect x="${p.x}" y="${p.y}" width="${W}" height="${H}" rx="8" fill="${THEME.surface}" stroke="${THEME.line}"/>${t1}${t2}`;
  }).join('');

  const arrows = graph.edges.map((e) => {
    const a = pos.get(e.a), b = pos.get(e.b);
    if (!a || !b) return '';
    const stroke = e.dashed ? THEME.redFg : THEME.mut;
    const dash = e.dashed ? ' stroke-dasharray="5 4"' : '';
    const mk = e.dashed ? 'arR' : 'arN';
    let d, lx, ly;
    if (a.row === b.row) {
      const fwd = a.x < b.x;
      d = fwd ? `M${a.x + W},${a.y + H / 2} H${b.x - 4}` : `M${a.x},${a.y + H / 2} H${b.x + W + 4}`;
      lx = (a.x + b.x) / 2 + W / 2; ly = a.y + H / 2 - 7;
    } else {
      const midY = Math.min(a.y, b.y) + H + GY / 2;
      d = `M${a.x + W / 2},${a.y + H} V${midY} H${b.x + W / 2} V${b.y - 4}`;
      lx = (a.x + b.x) / 2 + W / 2; ly = midY - 6;
    }
    // Every dashed edge says WHAT refused. "Dashed = refuses and stops" told the reader a line
    // was a refusal but never which check refused or why — they had to guess the source.
    // Stagger: three refusals converging on nearby midpoints printed one on top of another,
    // which is how the first attempt at this fix failed.
    const slot = graph.edges.filter((x) => x.label).indexOf(e);
    const label = e.label
      ? `<text x="${lx}" y="${ly - (slot % 2) * 13}" text-anchor="middle" fill="${stroke}" font-size="10.5" font-weight="600">${txt(e.label)}</text>`
      : '';
    return `<path d="${d}" fill="none" stroke="${stroke}" stroke-width="1.6"${dash} marker-end="url(#${mk})"/>${label}`;
  }).join('');

  return `<svg viewBox="0 0 ${vw} ${vh}" role="img" aria-label="${txtAttr(ariaLead || 'How this build flows')}: ${txtAttr(ids.map((i) => graph.nodes.get(i)).join(', then '))}">` +
    `<defs>` +
    `<marker id="arN" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="${THEME.mut}"/></marker>` +
    `<marker id="arR" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="${THEME.redFg}"/></marker>` +
    `</defs>${arrows}${boxes}</svg>` +
    // OUTSIDE the svg, where a control is legal and a reader can actually open it.
    (_svgRest.length
      ? `<details class="rest"><summary>Show each box's full label</summary><div class="rest-body">${
          _svgRest.map((t) => `<div>${txt(t)}</div>`).join('')}</div></details>`
      : '');
}

// A finding's own lifecycle. The review page captioned its diagram "How a finding travels: raised,
// proven reachable, fixed, then re-attacked" and then drew whatever mermaid graph the CONTRACT
// happened to contain — a picture of the build's data flow under a caption about findings. 14 of
// the 28 existing builds carry a contract mermaid, so on half of them the page said one thing and
// showed another. A kind with its own graph now keeps it.
const KIND_GRAPHS = {
  review: {
    aria: 'How a finding travels',
    nodes: new Map([
      ['a', 'a reviewer raises it'], ['b', 'proven reachable'], ['c', 'fixed'],
      ['d', 're-attacked, still fixed'], ['e', 'dropped — not reachable'],
    ]),
    edges: [
      { a: 'a', b: 'b' }, { a: 'b', b: 'c' }, { a: 'c', b: 'd' },
      { a: 'b', b: 'e', dashed: true, label: 'already guarded' },
      { a: 'd', b: 'c', dashed: true, label: 'broke again' },
    ],
  },
};
// Which graph the last call actually drew. The captions used to assert what the picture showed
// while `logicBlockFor` ignored its `kind` and drew the contract's mermaid whenever one existed —
// so the Release Card captioned a data-flow diagram "every box a real gate it had to pass", and
// the Plan Map captioned the same picture "the shape of the work". Three of five views said one
// thing and showed another. A caption is now derived from what was drawn.
let LAST_GRAPH_SOURCE = '';
function logicBlockFor(kind) {
  if (KIND_GRAPHS[kind]) { LAST_GRAPH_SOURCE = 'kind'; return logicBlock(KIND_GRAPHS[kind], KIND_GRAPHS[kind].aria); }
  const g = parseMermaid(contract);
  if (g) { LAST_GRAPH_SOURCE = 'contract'; return logicBlock(g); }
  LAST_GRAPH_SOURCE = 'lifecycle';
  const nodes = new Map([
    ['c', 'contract locked'], ['p', 'plan locked'], ['b', 'build, step by step'],
    ['r', 'adversarial review'], ['s', 'ship'], ['x', 'a gate refuses'],
  ]);
  const edges = [
    { a: 'c', b: 'p' }, { a: 'p', b: 'b' }, { a: 'b', b: 'r' }, { a: 'r', b: 's' },
    { a: 'b', b: 'x', dashed: true, label: 'proof missing' },
  ];
  return logicBlock({ nodes, edges });
}

// Call AFTER logicBlockFor (argument order guarantees it): returns the caller's caption only when
// the caller's own graph was drawn, and otherwise names what the reader is actually looking at.
function flowCaption(own) {
  if (LAST_GRAPH_SOURCE === 'contract') return 'Drawn from this contract\u2019s own logic map \u2014 every box is a real check, not a stage name.';
  if (LAST_GRAPH_SOURCE === 'lifecycle') return 'The Compass lifecycle this build passes through \u2014 this contract carries no diagram of its own.';
  return own;
}
const firstNonEmpty = (xs) => (xs.find((x) => x && String(x).trim()) || '').toString().trim();
const firstBullet = (body) => {
  const all = String(body || '').split('\n').filter((l) => /^\s*-\s+\S/.test(l));
  const m = all[0];
  const out = m ? m.replace(/^\s*-\s+/, '').replace(/\*\*/g, '').trim() : '';
  // P8. Returns bullet one and drops the rest of the list silently — no marker, no count.
  if (all.length > 1) lossy('firstBullet', out.length, all.join('\n').length, all.length - 1, () => all.slice(1));
  return out;
};
const lineMatching = (body, re) => {
  const lines = String(body || '').split('\n');
  const i = lines.findIndex((l) => re.test(l) && /\S/.test(l));
  if (i < 0) return '';
  const clean = (l) => l.replace(/^\s*[-*]\s+/, '').replace(/\*\*/g, '').trim();
  const first = clean(lines[i]);
  // The SAME colon rule firstPara got in round 2, which this sibling never received: a line ending
  // in a colon is a label and its content is what follows. The Brief's "Proof" card is fed from
  // here, so on six pages it printed `Gold figures (literal, pinned):` and dropped the figures —
  // the very numbers that card exists to show.
  if (/:$/.test(first)) {
    const rest = [];
    for (let j = i + 1; j < lines.length && rest.length < 6; j++) {
      if (/^\s*\|?\s*:?-{2,}/.test(lines[j])) continue;   // a table's separator row is not content
      const t = clean(lines[j]).replace(/^\s*\|\s*/, '').replace(/\s*\|\s*$/, '').replace(/\s*\|\s*/g, ' — ');
      if (!t) { if (rest.length) break; else continue; }
      if (/^#/.test(lines[j])) break;
      rest.push(t);
    }
    if (rest.length) {
      // P9. NOT ENUMERATED IN CONTRACT SECTION 9. The loop above stops at six collected lines
      // (`rest.length < 6`), so a label with more than six content lines loses the remainder with
      // no marker. Found by instrumenting the producer, exactly as the durable lesson says: the
      // enumeration in the contract was itself derived from reading, and reading missed one.
      let more = 0, moreChars = 0; const moreText = [];
      for (let j = i + 1 + rest.length; j < lines.length; j++) {
        if (/^#/.test(lines[j])) break;
        const _c = clean(lines[j]).trim();
        if (_c) { more++; moreChars += _c.length; moreText.push(_c); }
      }
      if (rest.length >= 6 && more > 0) {
        // v0.32 S1-REOPEN. The `full` argument was `lines.slice(i).join('\n').length`, which counts
        // the LABEL LINE and the six KEPT lines as if they were dropped, and compares a '; '-joined
        // cleaned kept string against a '\n'-joined RAW one. Three ways wrong in one call, and it
        // over-reported by exactly the 295 chars S2's independent census disagreed about. Chars
        // dropped is now the dropped lines themselves. Events and units were always right.
        lossy('lineMatching.cap6', 0, moreChars, more, () => moreText);
      }
      return `${first} ${rest.join('; ')}`;
    }
  }
  return first;
};
// `touches` lives on the INDEX row, not in contract.md — read it there rather than
// showing the reader a vague fallback.
const indexTouches = () => {
  try {
    const idx = readFileSync(join(dir, '..', 'INDEX'), 'utf8');
    const row = idx.split('\n').find((l) => l.startsWith(slug + ' · '));
    const m = row && row.match(/·\s*touches=(.+)$/);
    return m ? m[1].trim() : '';
  } catch { return ''; }
};

function band1Decision(ask, question, idParts) {
  return `<div class="b-decide"><div class="ask">${txt(ask)}</div><h1>${txt(question)}</h1>` +
         `<div class="b-id">${idParts.filter(Boolean).join(' &nbsp;·&nbsp; ')}</div></div>`;
}
function band2Facts(label, facts) {
  const cards = facts.map((f) => `<div class="b-fact"><div class="k">${txt(f.k)}</div><div class="v">${f.v}</div></div>`).join('');
  return `<div class="b-label">${txt(label)}</div><div class="b-facts">${cards}</div>`;
}
function band3Flow(svg, purpose, legend) {
  return `<div class="b-flow"><div class="b-label">How it flows</div>` +
         (purpose ? `<div class="b-purpose">${txt(purpose)}</div>` : '') + svg +
         (legend ? `<div class="b-legend">${legend.map((l) => `<span>${txt(l)}</span>`).join('')}</div>` : '') + `</div>`;
}
function bandSection(title, purpose, inner, raw = false) {
  // `raw` = the caller has already rendered its own HTML (because it contains provenance markers).
  // Escaping it here printed the markup to the reader on every plan map.
  const T = raw ? title : txt(title);
  const P = raw ? purpose : txt(purpose);
  return `<div class="b-sec"><h2>${T}</h2>` +
         (purpose ? `<div class="b-purpose">${P}</div>` : '') + inner + `</div>`;
}
// INV-COMPLETE-PLAN: a section with nothing in the source says so, in the reader's
// words, rather than vanishing. A missing section a reader cannot see is indistinguishable
// from a section that was never required.
function bandNA(title, reason) {
  return bandSection(title, '', `<div class="b-na"><b>N/A</b> — ${txt(reason)}</div>`);
}
// INV-NO-TRUNCATION: split long prose at a sentence/word boundary into a lead and the
// rest. NEVER a character slice — a title cut mid-word reads as a bug, because it is one.
// v0.30 defect 7 + 2: an honest field. splitLead() cuts at a word boundary and DISCARDS the rest,
// which produced "…and so the class" and a Blast-radius list ending on a dangling separator — both
// read as "there is more, silently dropped". This trims a trailing separator and, when a list IS
// shortened, SAYS SO with a count instead of implying it.
// NOTE (v0.30, review-3 round 2): an attempt to mechanically strip addresses out of scraped
// engineering prose was tried here and REVERTED. Deleting "(contract.md:3349, receipts.md:3356)"
// from "flip its three early returns (missing contract.md:3349, missing receipts.md:3356, empty
// block:3358)" leaves "(missing, missing, empty block:3358" — jargon traded for gibberish, which is
// worse for the reader, not better. Prose written for engineers cannot be machine-translated into
// prose written for a decision-maker; that is precisely why the architecture is "the model writes
// the reader copy into the state file, gen.mjs only lays it out". Where reader copy is absent the
// page shows the plan's own words and SAYS they are the plan's own words.
// Markdown emphasis markers are SOURCE syntax; a reader should never meet one. Stray `*` and `**`
// were reaching pages — a Brief ended a sentence `…own shareable Brief.)*` — because prose is
// scraped from markdown and only paired markers were being stripped upstream.
function demd(x) {
  return String(x || '')
    .replace(/\*\*(.+?)\*\*/g, '$1')
    .replace(/(^|\s)\*(\S[^*]*?)\*(?=\s|$|[.,;:)])/g, '$1$2')
    .replace(/\*+/g, '')
    .replace(/\s{2,}/g, ' ')
    .trim();
}
// v0.32.0 S6 — `fieldText` used to return a STRING, so a caller had no way to render the half it
// dropped. `fieldParts` is the same function with the same rules, returning BOTH halves; the old
// name is kept as a thin wrapper returning `shown`, so every call site that has not been migrated
// yet behaves byte-for-byte as before and the migration can be proven one site at a time.
//
// Why not just return markup from here. `fieldText` has 22 call sites and NINETEEN of them wrap the
// result in an escaping helper, so a returned `<details>` renders as literal angle brackets on 120
// pages. And EIGHT of those contexts cannot legally hold one at all — an SVG `<text>`, a `<p>`,
// several `<span>`s. The shape has to change, not the string.
function fieldText(v, max = 150) { return fieldParts(v, max).shown; }

// v0.32.0 S6 — THE DISCLOSURE CONTROL. One per shortened field, holding THAT field's own remainder.
// Not a marker: contract §9's cheats 3 and 4 are an empty control and one control per page, so it
// must contain this row's text and no other row's. Deliberately plain CSS — no line-clamp, no
// ellipsis, no max-height — because `reachable-argument.mjs` strips clipped subtrees before it
// looks, and rightly: text present but clipped is not text a person can reach.
// `<details>` is FLOW content. It is legal inside <td>, <li> and <div>, and ILLEGAL inside <p> and
// <span>. Callers in phrasing contexts render it as a SIBLING after the element; see each site.
function disclose(rest, label = 'Show the rest') {
  if (!rest) return '';
  return `<details class="rest"><summary>${esc(label)}</summary><div class="rest-body">${txt(rest)}</div></details>`;
}
// The one-liner for the common case: a field in a flow context, shown short with its remainder
// reachable directly beneath it.
function fieldDisclosed(v, max = 150, label = 'Show the rest') {
  const p = fieldParts(v, max);
  return txt(p.shown) + disclose(p.rest, label);
}
function fieldParts(v, max = 150) {
  const full = demd(String(v || '').trim());
  if (full.length <= max) return { shown: full.replace(/[;,]\s*$/, ''), rest: '' };
  const parts = full.split(/;\s*/).filter(Boolean);
  if (parts.length > 1) {
    const kept = [];
    let n = 0;
    for (const part of parts) {
      if (n + part.length > max && kept.length) break;
      kept.push(part); n += part.length + 2;
    }
    const hidden = parts.length - kept.length;
    const joined = kept.join('; ');
    // P1. THE PATH THE FIRST TWO GOLD FIGURES MISSED. `nCt()` wraps the count in a
    // `<span data-prov="counted">`, so a plain text search of the rendered page returns 0 for this
    // path and reports it as absent rather than as unmeasured.
    if (hidden > 0) lossy('fieldText:and-N-more', joined.length, full.length, hidden, () => parts.slice(kept.length), () => joined);
    return { shown: joined + (hidden > 0 ? ` — and ${nCt(hidden)} more` : ''),
             rest: hidden > 0 ? parts.slice(kept.length).join('; ') : '' };
  }
  // Prefer a sentence boundary, so a shortened field ends where a thought ends. A bare ellipsis
  // is still a cut — the artefact gate is right to flag it — so when there is no clean boundary,
  // SAY the field continues instead of trailing off.
  // Ending on a sentence boundary is right; ending there SILENTLY is not. This path dropped the
  // rest of the field on 43 of 140 pages with nothing to show it had — this build's own Brief kept
  // "a stranger could not do that" and dropped "Target: none of them, and the stranger answers both
  // questions plainly", which is the half that says what success looks like. And because the text
  // ends in a full stop, the cut check cannot see it either.
  const sentence = full.slice(0, max + 60).match(/^[\s\S]*?[.!?](?=\s)/);
  if (sentence && sentence[0].length >= max * 0.5) {
    const kept = sentence[0].trim();
    // P2. Contract section 9 calls this "the (continues) path", singular. It is two separate return
    // statements — this one and P3 below — that happen to print the same word. Counted apart,
    // because a figure that fuses two code paths is how the earlier ones went wrong.
    if (kept.length < full.trim().length) lossy('fieldText:continues-sentence', kept.length, full.trim().length, 1, () => [full.trim().slice(kept.length)], () => kept);
    return { shown: kept.length < full.trim().length ? `${kept} (continues)` : kept,
             rest: kept.length < full.trim().length ? full.trim().slice(kept.length).trim() : '' };
  }
  const cut = splitLead(full, max);
  const lead = cut.lead.replace(/[;,]\s*$/, '');
  // P3. The second half of section 9's single "(continues) path".
  if (cut.rest) lossy('fieldText:continues-hardcut', lead.length, full.length, 1, () => [cut.rest], () => lead);
  return { shown: cut.rest ? `${lead} (continues)` : lead, rest: cut.rest || '' };
}

function splitLead(text, softMax = 92) {
  const t = String(text || '').trim();
  if (t.length <= softMax) return { lead: t, rest: '' };
  const dot = t.slice(0, softMax + 40).search(/[.!?](\s|$)/);
  if (dot > 20) return { lead: t.slice(0, dot + 1).trim(), rest: t.slice(dot + 1).trim() };
  // NOTE: do NOT add a "(continues)" marker or a synthetic full stop here. `lead` and `rest` are
  // rendered adjacently (title then detail), so nothing is lost and the text must stay contiguous —
  // INV-NO-TRUNCATION asserts a 363-character title survives WHOLE, and inserting a marker between
  // the halves breaks exactly that. A marker belongs where content is DROPPED, which is fieldText,
  // not here. (Tried and reverted in review-3 round 2.)
  // A comma-joined path list has no spaces, so `lastIndexOf(' ')` found nothing and the fallback
  // was `t.length` — "do not cut at all". Downstream the field was still clipped, and it landed
  // mid-filename ("…CHANGELOG.md,RE") with nothing to say it continued. Fall back to a comma or a
  // slash before giving up, and always hand back the remainder so the caller can mark it.
  const sp = t.lastIndexOf(' ', softMax);
  const cm = Math.max(t.lastIndexOf(',', softMax), t.lastIndexOf(';', softMax));
  const cut = sp > 20 ? sp : (cm > 20 ? cm + 1 : (softMax > 20 ? softMax : t.length));
  return { lead: t.slice(0, cut).trim(), rest: t.slice(cut).trim() };
}

function briefBody() {
  // ── v0.29.0 — the four bands: decision → facts → flow → detail (INV-BANDS) ──
  const goal = req('goal', hdr('Goal') || firstPara(sec('Goal') || sec('Goal & scope')));
  const inv = invariants();
  const sc = scope();
  const security_ = security();
  const facets = hdr('Facets') || hdr('facets') || 'library';
  // v0.32.0 S19 (§17-12). The fallback here was a hardcoded 'v1', so EVERY Brief whose title
  // carries no version suffix told its reader the contract was v1 — including the Brief published
  // for v2, v3 and v4 of this build, which is the very page the gold is read from. A version the
  // page cannot derive is now SAID to be underivable rather than invented.
  const version = (() => {
    const t = title.match(/·\s*(v[\d.]+)\s*$/);
    if (t) return t[1];
    const d = contract.match(/^Ships as v[\d.]+\s*\(\*\*(v[\d.]+)\*\*/m);
    if (d) return d[1];
    return 'contract version not stated';
  })();
  // v0.32.0 S6 (§17-14): `const doneSentence = fieldText(goal, 120)` stood here, assigned and
  // never read — a truncation running on every Brief with its result discarded. Found by S2's
  // independent census. Deleted rather than left as a comment about itself.
  // v0.30: the reader-copy block now covers the scope ladder too. It previously covered only the
  // four decision cards, so the ladder rendered contract prose verbatim — which is where the cold
  // reader hit six words of insider shorthand in a row and got nothing from it.
  const nowItems = rcList('now', sc.now || []);
  const touches = hdr('touches') || '';

  // idParts carry markup deliberately, so they are pre-escaped here rather than by the band.
  const b1 = band1Decision('Decide', 'Lock this contract?', [
    `<b>${txt(slug)}</b>`, txt(facets), `<b>${nF('invariants.total', inv.length)}</b> invariant${inv.length === 1 ? '' : 's'}`, txt(version),
  ]);

  // Each fact must answer a DIFFERENT question — a card that repeats its neighbour wastes
  // the one row a reader actually scans.
  // P12. NOT ENUMERATED IN SECTION 9. When a contract has no `## Done` section and no acceptance
  // bullet, the Brief's "Done means" card is goal SENTENCE TWO — and sentences three onward are
  // dropped with no marker. Candidates are materialised so the counter can tell whether this
  // fallback was the one actually SELECTED; counting it unconditionally would over-report on every
  // brief, since a JS array literal evaluates all of its elements either way.
  const _goalSents = goal.split(/(?<=[.!?])\s/);
  const _dmCands = [
    firstBullet(sec('Acceptance & INVARIANTs')), firstPara(sec('Done')),
    (_goalSents[1] || ''), 'every INVARIANT below passes its command.',
  ];
  const doneMeans = firstNonEmpty(_dmCands);
  if (_dmCands.findIndex((x) => x && String(x).trim()) === 2 && _goalSents.length > 2) {
    lossy('doneMeans.goalSentence2', String(_goalSents[1]).length, _goalSents.slice(1).join(' ').length, _goalSents.length - 2, () => _goalSents.slice(2));
  }
  const goldLine = firstNonEmpty([
    lineMatching(sec('Reconciliation'), /gold\s*(figure)?s?\b/i),
    firstBullet(sec('Reconciliation')), 'no reconciliation declared.',
  ]);
  // v0.30 defect 7: the list ended on a dangling separator, which reads as "and more, silently
  // dropped". Trim it, and say how many are not shown rather than implying it.
  const blast = String(firstNonEmpty([touches, indexTouches(), 'declared in the plan.']))
    .replace(/[;,]\s*$/, '').trim();
  const b2 = band2Facts('The facts you need to decide', [
    { k: 'Build what', v: fieldDisclosed(rc('build-what', goal), 150) },
    { k: 'Done means', v: fieldDisclosed(rc('done-means', doneMeans), 150) },
    { k: 'Proof', v: shareable
        ? 'Reconciliation gold is pinned locally and enforced by the suites; the literal is withheld here.'
        : fieldDisclosed(rc('proof', goldLine), 150) },
    { k: 'Blast radius', v: fieldDisclosed(rc('blast-radius', blast), 150) },
  ]);

  const b3 = band3Flow(
    logicBlockFor('contract'),
    // Route through flowCaption like every other view. The Brief asserted "drawn from this
    // contract's own logic map" unconditionally — so on the 14 of 28 builds whose contract carries
    // no diagram, the Brief and the Plan Map of the SAME build described one picture two different
    // ways, and the Brief's version was the false one.
    flowCaption('Drawn from this contract\u2019s own logic map — every box is a real check, not a stage name.'),
    ['Solid = the happy path', 'Dashed = refuses and stops'],
  );

  const scopeRows = [
    ...nowItems.map((i) => ({ p: 'now', t: i })),
    ...(rcList('later', sc.later || []).length ? [{ p: 'later', t: rcList('later', sc.later || []).join(' · ') }] : []),
    ...(rcList('never', sc.never || []).length ? [{ p: 'never', t: rcList('never', sc.never || []).join(' · ') }] : []),
  ];
  const scopeCard = scopeRows.length
    ? bandSection('What\u2019s in scope', 'What ships now, what waits, and what we\u2019ve ruled out for good.',
        `<ul class="pl">${scopeRows.map((r) => `<li><span class="pill ${r.p}">${r.p}</span><span>${txt(r.t)}</span></li>`).join('')}</ul>`)
    : bandNA('What\u2019s in scope', 'this contract declares no scope ladder');

  const invCard = inv.length
    ? bandSection('The promises that can\u2019t break', 'Each is asserted by a command, and each has a recipe proving that test goes red when broken.',
        `<table class="t"><tr><th>Invariant</th><th>What it asserts</th></tr>` +
        inv.map((i) => { const _p = fieldParts(i.summary, 150);
          // ONE control for this row, holding everything this row lost: the field's own remainder
          // AND the assert recipe / original wording that `invariants()` split off upstream.
          return `<tr><td class="k">${txt(i.name)}</td><td>${txt(_p.shown)}${disclose([_p.rest, i.dropped].filter(Boolean).join('\n\n'))}</td></tr>`; }).join('') + `</table>`)
    : (ARTEFACT_DATA && Number.isFinite(ARTEFACT_DATA['invariants.total']) && ARTEFACT_DATA['invariants.total'] > 0
        // v0.32.0 S19b: "pins no INVARIANTs" is a CLAIM, and it was false on any contract whose
        // invariant shape this parser does not know — it printed it beside a header stating a
        // declared count of 12. Saying what actually happened is both true and more useful.
        ? bandNA('The promises that can\u2019t break',
            `this contract declares ${ARTEFACT_DATA['invariants.total']}, and this page could not read them \u2014 they are written in a shape the renderer does not parse, so they are not shown here rather than silently reported as none`)
        : bandNA('The promises that can\u2019t break', 'this contract pins no INVARIANTs'));

  // ── restored behaviour (R2-M1 rule: a behavioural guard is re-expressed, never retired) ──
  // The rewrite initially dropped all of this and turned 9 asserts red. Each protects a
  // real post-ship finding: a false-green N/A badge, never-show leakage in the shareable
  // copy, and the honest best-effort caveat.
  const goldCard = shareable
    ? `<span class="badge">gold pinned ✓</span><p style="margin-top:8px">The reconciliation gold is pinned in this build's <b>local</b> Brief and enforced by the suites; its literal is withheld from the shareable copy.</p>`
    : bodyHtml(goldBody);
  let secCard;
  if (!security_.present) {
    secCard = `<span class="chip">no Security &amp; data-sensitivity block in this contract</span>
      <p style="margin-top:8px">Treat the sensitive surface as <b>unclassified</b>, not a cleared "N/A".</p>`;
  } else if (security_.na) {
    secCard = `<span class="badge">N/A — no sensitive surface</span>
      <p style="margin-top:8px">${txt(security_.naReason || 'declared N/A with reason')}</p>`;
  } else if (shareable) {
    const nsList = (security_.neverShow || []).map(() => `<li><b>never-show:</b> <span class="chip">⟨redacted ✓⟩</span></li>`).join('');
    secCard = `<p>${txt(firstPara(security_.body))}</p>${nsList ? `<ul style="margin-top:8px">${nsList}</ul>` : ''}`;
  } else {
    secCard = bodyHtml(security_.body);
  }
  const shareableCaveat = shareable ? `<div class="b-sec" style="border-color:var(--amberBorder);background:var(--amberBg)">
    <span class="badge warn">Best-effort redaction — review before sending</span>
    <p style="margin-top:8px">Declared values (the reconciliation gold + never-show fields) of 3+ significant digits are scrubbed with certainty. <b>Undeclared</b> restatements in free prose are best-effort. Read this copy before you send it.</p>
  </div>` : '';

  const guardCard = security_.present
    ? bandSection('Guardrails', 'How this gets turned off, undone, and watched.',
        `<ul class="pl">` +
        `<li><span class="pill now">off</span><span>${txt(fieldParts(hdr('Flag') || firstPara(sec('Rollout & kill-switch')) || 'kill-switch declared in the contract.', 150).shown)}</span>${disclose(fieldParts(hdr('Flag') || firstPara(sec('Rollout & kill-switch')) || 'kill-switch declared in the contract.', 150).rest)}</li>` +
        `<li><span class="pill now">undo</span><span>${txt(fieldParts(firstPara(sec('Rollback')) || 'rollback declared in the contract.', 150).shown)}</span>${disclose(fieldParts(firstPara(sec('Rollback')) || 'rollback declared in the contract.', 150).rest)}</li>` +
        `<li><span class="pill now">watch</span><span>${txt(fieldParts(firstPara(sec('Observability')) || 'observability declared in the contract.', 150).shown)}</span>${disclose(fieldParts(firstPara(sec('Observability')) || 'observability declared in the contract.', 150).rest)}</li>` +
        `</ul>`)
    : bandNA('Guardrails', 'no Security & data-sensitivity block in this contract — treat the sensitive surface as unclassified, not a cleared N/A');

  return `<section class="cv-body"><div class="wrap">
  <div class="kicker">Compass · Contract Brief${shareable ? ' · shareable' : ''}</div>
  ${b1}
  <!-- v0.30 defect 1: the goal used to render here AND in the Build-what card directly below,
       so the reader met the same sentence twice in the first screen (three times before the cover
       was removed). The facts row owns it now. -->
  ${shareableCaveat}
  ${b2}
  ${b3}
  <div class="b-cols">${scopeCard}${invCard}</div>
  ${bandSection('The number this is checked against', 'The reconciliation gold, and how it is proven.', goldCard)}
  ${bandSection('Security & data sensitivity', 'What is classified, who can see it, and what must never be shown.', secCard)}
  ${guardCard}
  <div class="foot">Compass · Contract Brief · ${txt(slug)} · a pure function of contract.md</div>
</div></section>`;
}

// ── cinematic-hero cover (full brief only) — its OWN accent + grade, excluded from the house gate ──
function cover() {
  const goal = hdr('Goal') || firstPara(sec('Goal') || sec('Goal & scope'));
  const oneLine = goal.split(/(?<=[.!?])\s/)[0] || goal;
  return `
<style>
  .cv-cover{position:relative;width:100%;height:430px;overflow:hidden;
    background:radial-gradient(120% 130% at 50% -10%, #171A3E 0%, #0C0E28 38%, #070818 66%, #04050E 100%);
    font-family:'Inter',system-ui,-apple-system,sans-serif;-webkit-font-smoothing:antialiased}
  .cv-cover .rays{position:absolute;left:50%;top:-320px;width:1700px;height:1200px;transform:translateX(-50%);
    background:conic-gradient(from 178deg at 50% 0%, transparent 0deg, rgba(150,140,255,.09) 3deg, transparent 7deg, rgba(150,140,255,.06) 12deg, transparent 17deg, rgba(150,140,255,.10) 22deg, transparent 27deg, rgba(150,140,255,.05) 33deg, transparent 39deg);
    filter:blur(7px);mix-blend-mode:screen}
  .cv-cover .bloom{position:absolute;left:50%;top:46%;transform:translate(-50%,-50%);width:1100px;height:760px;
    background:radial-gradient(closest-side, rgba(150,142,255,.28), rgba(120,112,255,.07) 44%, transparent 70%);filter:blur(11px)}
  .cv-cover .vign{position:absolute;inset:0;background:radial-gradient(120% 100% at 50% 42%, transparent 40%, rgba(2,3,10,.74) 100%)}
  .cv-cover .in{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:0 60px}
  .cv-cover .kick{font-size:13px;font-weight:700;letter-spacing:.42em;text-transform:uppercase;color:#8E88C4}
  .cv-cover .mark{margin-top:18px;font-size:52px;font-weight:900;letter-spacing:-.04em;line-height:1.04;color:#EFEDFF;max-width:16ch}
  .cv-cover .mark em{font-style:normal;color:#B8B2FF}
  .cv-cover .sub{margin-top:18px;font-size:18px;font-weight:500;color:#C9C5F0;max-width:62ch;line-height:1.45}
  .cv-cover .sub b{color:#EFEDFF;font-weight:700} .cv-cover .sub em{font-style:normal;color:#B8B2FF}
  .cv-cover .sub code{font-family:${THEME.fontMono};font-size:15px;color:#B8B2FF}
  .cv-cover .needle{position:absolute;left:50%;top:40px;transform:translateX(-50%)}
</style>
<section class="cv-cover">
  <div class="rays"></div><div class="rays" style="transform:translateX(-50%) scaleX(-1)"></div>
  <div class="bloom"></div>
  <svg class="needle" width="46" height="46" viewBox="0 0 46 46"><circle cx="23" cy="23" r="21" fill="none" stroke="rgba(124,116,255,.35)" stroke-width="1.4"/><path d="M23 6 L27 23 L23 40 L19 23 Z" fill="#7C74FF"/><circle cx="23" cy="23" r="2.6" fill="#EFEDFF"/></svg>
  <div class="in">
    <div class="kick">Compass · Contract Brief</div>
    <div class="mark">${txt(title.replace(/^Contract\s+[—-]\s*/i, ''))}</div>
    <div class="sub">${txt(oneLine)}</div>
  </div>
  <div class="vign"></div>
</section>`;
}

// ── cockpit (where it stands) ──
function cockpit() {
  const progress = read('progress.md');
  const plan = read('plan.md');
  const receipts = read('receipts.md');
  const ledger = read('review-ledger.md');
  // v0.32.0 S24b, found by the independent reviewer of S24: this is a SIXTH **Status:** parser,
  // and unifying the five in compass.sh left it behind. It was unanchored and took the FIRST
  // match, so on a build folder that stacks its status lines (an append log — one in the live
  // corpus has six) the page Rishi actually looks at reported a SHIPPED build as
  // "Contract LOCKED". It now reads the LAST line, at the start of a line, and strips the
  // markdown emphasis a status may be written in (`**SHIPPED (post-ship …)**`).
  const status = (() => {
    const all = progress.match(/^[ \t]*\*\*Status:\*\*[ \t]*(.+)$/gm) || [];
    if (!all.length) return '—';
    const last = all[all.length - 1].replace(/^[ \t]*\*\*Status:\*\*[ \t]*/, '');
    return last.replace(/^[*_`\s]+/, '').replace(/[*_`\s]+$/, '').trim() || '—';
  })();
  const stage = (progress.match(/\*\*Stage:\*\*\s*(.+)/) || [, '—'])[1].trim();
  const next = (progress.match(/\*\*Next:\*\*\s*(.+)/) || [, '—'])[1].trim();
  // v0.32.0 S31b: `total` must count a step marked IN FLIGHT too, or the cockpit's denominator
  // disagrees with the plan-map's — the same self-contradiction §17-6 is about, introduced by the
  // very change that added `[~]`. Found by an independent reviewer: three counters, three answers.
  const done = (plan.match(/^\s*- \[x\]/gim) || []).length;
  const total = (plan.match(/^\s*- \[[ x~]\]/gim) || []).length;
  const stages = ['contract', 'review-contract', 'plan', 'review-plan', 'build', 'review-build', 'ship'];
  const passed = new Set();
  for (const m of receipts.matchAll(/RECEIPT\s+[—-]\s+([a-z-]+)\s+·[^\n]*·\s*PASS/gi)) passed.add(m[1].toLowerCase());
  const ledgerRows = (ledger.match(/^\|\s*(R[CP]?-?\d|RP-\d)/gim) || []).length;
  // count only rows whose STATUS cell (last column) is FIXED — not every FIXED token in prose
  // round-summaries (which made "fixed" exceed "findings") (R3-m1).
  const fixed = (ledger.match(/^\|.*\|\s*FIXED\b[^|]*\|\s*$/gim) || []).length;

  // the single most-specific stage the stage-line names (longest match wins so 'build' ⊄ 'review-build') (R3-m2).
  const stageL = stage.toLowerCase();
  const hereStage = [...stages].sort((a, b) => b.length - a.length).find((s) => stageL.includes(s)) || '';
  const timeline = stages.map((s) => {
    const state = passed.has(s) ? 'done' : (s === hereStage ? 'here' : 'left');
    const glyph = state === 'done' ? '✓' : state === 'here' ? '◉' : '·';
    return `<div class="st ${state}"><span class="g">${glyph}</span> ${s}</div>`;
  }).join('');

  const body = `
<section class="cv-body"><div class="wrap">
  <div class="kicker">Compass · Cockpit</div>
  <h1>${txt(title)}</h1>
  <p class="lede"><b>${txt(status)}</b> — stage <b>${txt(stage)}</b>.</p>
  <div class="card"><div class="kicker">Where it stands</div>
    <div class="tl">${timeline}</div>
  </div>
  <div class="grid2">
    <div class="card"><div class="kicker">Progress</div>
      <p><span class="badge">${nF('steps.done', done)}/${nF('steps.total', total)} steps</span></p>
      <p style="margin-top:10px"><b>Next:</b> ${txt(next)}</p>
    </div>
    <div class="card"><div class="kicker">What the reviews caught</div>
      <p><span class="chip">${ledgerRows} ledger findings</span> <span class="chip">${fixed} fixed</span></p>
      <p style="margin-top:10px">Every Critical/Major is cited to the bug-bar and refuted (reachable + not-already-guarded) before it counts.</p>
    </div>
  </div>
  <div class="foot">Generated from progress.md / plan.md / receipts.md / review-ledger.md by compass-visual · a pure function of the build's state.</div>
</div></section>`;
  const extra = `
  .cv-body .tl{display:flex;flex-wrap:wrap;gap:8px}
  .cv-body .st{font-size:12px;font-weight:600;color:var(--mut);padding:6px 12px;border:1px solid var(--line);border-radius:99px;background:var(--surface)}
  .cv-body .st .g{font-weight:700}
  .cv-body .st.done{color:var(--greenFg);background:var(--greenBg)}
  .cv-body .st.here{color:var(--accent);border-color:var(--accent)}
  .cv-body .row{display:flex;gap:8px;flex-wrap:wrap}`;
  return { body, extra };
}

// ── v0.24.0 milestone views (rk-house-style bodies; deterministic — no clock/rand) ─────────────
const _pillCss = `
  .cv-body .tl{display:flex;flex-wrap:wrap;gap:8px}
  .cv-body .tl.vert{flex-direction:column;align-items:flex-start}
  .cv-body .st,.cv-body .ph,.cv-body .ct{font-size:12px;font-weight:600;color:var(--mut);padding:6px 12px;border:1px solid var(--line);border-radius:99px;background:var(--surface)}
  .cv-body .st .g,.cv-body .ph .g,.cv-body .ct .g{font-weight:700}
  .cv-body .st.done,.cv-body .ph.shipped,.cv-body .ct.shipped{color:var(--greenFg);background:var(--greenBg)}
  .cv-body .st.here,.cv-body .ph.here{color:var(--accent);border-color:var(--accent)}
  .cv-body .ct{margin-left:22px;border-radius:8px}
  .cv-body .wv{font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--accent);margin:14px 0 2px}
  .cv-body .vp-prog{display:flex;flex-wrap:wrap;gap:8px;margin-top:10px}
  .cv-body .vr-hero .big{font-size:24px;font-weight:800;color:var(--accent);letter-spacing:-.02em;margin-top:6px}
  .cv-body .vr-hero .big .badge{vertical-align:middle;margin-left:8px}`;

// PLAN MAP — the locked step checklist + what it touches (from plan.md). Milestone: plan-lock.
function planMap() {
  // ── v0.29.0 — same four bands as the Brief, then the rest of a world-class plan ──
  const plan = stripFences(read('plan.md'));
  const psec = sections(plan);
  const psecGet = (needle) => {
    const nd = needle.toLowerCase();
    const k = Object.keys(psec).find((x) => x.toLowerCase().replace(/^\d+\.\s*/, '').startsWith(nd));
    return k ? psec[k] : '';
  };

  // Parse each step into {n, title, detail, verify, done}. The VERIFY line belongs to the
  // step ABOVE it — v0.28 and earlier discarded it entirely, which removed the single most
  // important fact about a Compass step: the command that proves it.
  const steps = [];
  let cur = null;
  for (const ln of plan.split('\n')) {
    // v0.32.0 S31: `[~]` joins the alphabet, because the running count below needs something real
    // to read. CORRECTION (S31b, from an independent reviewer): the first version of this comment
    // said `[~]` is "what this project's own progress files already use". That is true of the
    // GITIGNORED progress.md files and false of every TRACKED file — `git grep -F '[~]'` finds only
    // the test written for this change. The marker is therefore NEW, and the three counters that
    // read plan checkboxes (here, `compass.sh`, and `cockpit()`) were widened together, because a
    // marker only one of them knows is a self-contradiction of exactly the §17-6 kind.
    const m = ln.match(/^\s*-\s*\[([ x~])\]\s*(.+)$/);
    if (m) {
      const raw = m[2].replace(/\*\*/g, '').replace(/`/g, '');
      // SUB-STEP labels are part of the plan's own numbering: `4a`, `7b`, `25b`. Matching only
      // `\d+` made them fall back to positional numbering, so the rendered column read
      // 1 2 3 4 5 6 5 6 7 10 8 9 … — a reader saw "5" twice and a row numbered 10 labelled 7b.
      // BOTH separators. Round 3 taught this `4a` for the `·` form only; two builds write `1b. `,
      // so 16 of 17 rows on one plan-map showed a number contradicting the number in their own
      // title. Same sibling class as the fence and severity readers.
      // Only the FALLBACK is marked: a number read off the plan line was written by a person and
      // is genuinely quoted; a number invented here because the line had none is this file counting.
      const _nm = raw.match(/^(\d+[a-z]?)\s*[·.)]\s+/);
      const num = _nm ? _nm[1] : nCt(steps.length + 1);
      let body = raw.replace(/^\d+[a-z]?\s*[·.)]\s+/, '');
      // The VERIFY usually sits ON the checkbox line, at the end: "… VERIFY: <command>". This
      // branch used to `continue` before the VERIFY matcher below ever ran, so the matcher was
      // unreachable for the format real plans actually use — all 30 steps rendered "none recorded"
      // under a caption promising every tick was proven. Split it off the body here.
      let inlineVerify = '';
      // Case-SENSITIVE and the colon is REQUIRED. With `/i` and an optional colon this matched the
      // ordinary English word in "nothing to verify (the common case)" and truncated the step
      // there — silently, on any step whose text happens to contain "verify". The convention is a
      // literal uppercase `VERIFY:` marker, so match exactly that.
      // Found by POSITION, not by case. Case-sensitivity was chosen to stop the ordinary word
      // "verify" in prose truncating a step — but real plans write `*Verify:*` and `- verify:`, so
      // it produced 92 false "none recorded for this step" claims on pages that display the very
      // command they say does not exist. The marker is what starts a segment: the line, a sentence
      // end, or a bullet. "there is nothing to verify (the common case)" is mid-sentence and is
      // therefore still not a marker.
      // A QUALIFIER may sit between the word and its colon — `**Verify (INV-8):**`,
      // `**SINGLE VERIFY (merged):**`, `*Verify each:*` — and the separator may be a dash rather
      // than a colon. 17 steps across 8 builds said "none recorded" while printing their command
      // in the very next column, under a caption promising a box is only ticked once it has run.
      const iv = body.match(/(?:^|(?<=[.;·—])\s+|(?<=\s)[-*]\s+)\*{0,2}(?:single\s+)?verify(?:\s+\w+)?\s*(?:\([^)]*\))?\s*[:—–]\*{0,2}\s*(.+)$/i)
              || body.match(/(?:^|\s)\*{1,2}V\.\*{1,2}\s*(.+)$/)
              // `*V.*` with nothing after it is a shorthand the plan defines once, not an absent
              // proof. Saying "none recorded" about it is false on all 17 of that build's steps.
              || (/\s\*{1,2}V\.\*{1,2}\s*$/.test(body) ? [body, 'V. — the shared verify recipe this plan defines once'] : null);
      if (iv && /[A-Za-z0-9`]/.test(iv[1])) { inlineVerify = iv[1].trim(); body = body.slice(0, iv.index).replace(/[\s—·]+$/, ''); }
      else if (iv) { body = body.slice(0, iv.index).replace(/[\s—·]+$/, ''); }
      const { lead, rest } = splitLead(body, 74);
      cur = { n: num, title: lead, detail: rest, verify: inlineVerify, done: m[1] === 'x', running: m[1] === '~' };
      steps.push(cur);
      continue;
    }
    // Also match VERIFY written INLINE, which is how a real plan writes it: the checkbox line ends
    // "… **VERIFY:** `cmd`". Requiring it at line start meant all 30 steps rendered "Verify — none
    // recorded for this step" on a page whose own caption reads "A box is only ticked when its
    // VERIFY command has actually run and passed" — 30 ticked boxes over 30 empty proofs, and the
    // gate's --steps check compared two integers and passed it.
    const VQ = '(?:single\\s+)?verify(?:\\s+\\w+)?\\s*(?:\\([^)]*\\))?\\s*[:—–]?';
    const v = ln.match(new RegExp(`^\\s*\\*{0,2}${VQ}\\*{0,2}\\s*(.+)$`, 'i'))
           || ln.match(new RegExp(`^\\s*[-*]\\s*\\*{0,2}${VQ}\\*{0,2}\\s*(.+)$`, 'i'))
           || ln.match(new RegExp(`(?:^|(?<=[.;·\u2014])\\s+)\\*{0,2}${VQ}\\*{0,2}\\s*(.+)$`, 'i'));
    if (v && cur) {
      const cand = v[1].replace(/\*\*/g, '').trim();
      // A capture that is only punctuation is not a command. With the separator optional, a line
      // ending `— VERIFY:` captured `":"` and rendered a bare-colon proof box.
      if (/[A-Za-z0-9`]/.test(cand)) {
        cur.verify = (cur.verify ? cur.verify + ' ' : '') + cand;
        continue;
      }
    }
    // A step line ending in a VERIFY marker with nothing after it means the command is on the NEXT
    // line. That is ordinary markdown wrapping, and it was being read as "no proof recorded".
    if (cur && !cur.verify && /(?:^|[\s—·])\*{0,2}(?:single\s+)?verify(?:\s+\w+)?\s*(?:\([^)]*\))?\s*[:—–]\*{0,2}\s*$/i.test(ln)) {
      cur.awaitVerify = true;
      continue;
    }
    if (cur && cur.awaitVerify && ln.trim()) {
      cur.verify = ln.trim().replace(/\*\*/g, '');
      cur.awaitVerify = false;
      continue;
    }
    if (cur && !cur.verify && /^\s{4,}\S/.test(ln) && !cur.detail) cur.detail = ln.trim().replace(/\*\*/g, '');
  }
  const done = steps.filter((s2) => s2.done).length;
  const total = steps.length;
  // v0.32.0 S31 (pulled in by Rishi at the plan gate, 2026-08-20). This was `total > done ? 1 : 0`
  // — a literal wearing a measurement's clothes: every plan with ANY unfinished step claimed that
  // EXACTLY ONE of them was running, including plans where nothing had been started at all.
  // CORRECTION (S31b, from an independent reviewer): my first wording said "every plan Compass has
  // ever rendered". Measured over the 30 rendered plans, it is SEVEN — the other 23 are complete,
  // so `total > done` is false and they correctly said 0. The defect is real and narrower than I
  // wrote it, and the number is stated here rather than the claim left standing.
  // It is now the count of steps a person actually marked in flight, and when nobody marked one
  // the page says nothing about running rather than inventing a one.
  const running = steps.filter((s2) => s2.running).length;

  const b1 = band1Decision('Decide', 'Approve this plan?', [
    `<b>${txt(slug)}</b>`,
    `<b>${nF('steps.total', total)}</b> step${total === 1 ? '' : 's'}`,
    running
      ? `${nF('steps.done', done)} done · ${nC(running)} running · ${nC(Math.max(0, total - done - running))} to go`
      : `${nF('steps.done', done)} done · ${nC(Math.max(0, total - done))} to go`,
  ]);

  const b2 = band2Facts('The facts you need to decide', [
    // Never empty. All three fallbacks were absent on 7 builds, so the first fact under "The facts
    // you need to decide" — on the page asking "Approve this plan?" — rendered as a blank box, and
    // the gate could not see it because an empty string trips no rule. Widen the chain, then say
    // plainly that the plan does not state it.
    { k: 'What changes', v: fieldDisclosed(firstNonEmpty([
        firstPara(psecGet('The approach')), firstPara(psecGet('Approach')),
        firstPara(sec('Goal & scope')), firstPara(sec('Goal')), hdr('Goal'),
        firstPara(psecGet('What changes')), firstPara(psecGet('Files to change')),
        steps.length ? `${nC(steps.length)} steps, beginning: ${txt(steps[0].title)}` : '',
        'not stated in this plan — read plan.md before approving',
      ]), 150) },
    { k: "How it's proven", v: `${nF('invariants.total', invariants().length)} ${txt("invariants, each a command; every step carries its VERIFY.")}` },
    { k: 'What it touches', v: fieldDisclosed(firstNonEmpty([hdr('touches'), indexTouches(), 'declared above.']), 150) },
    { k: 'Rollback', v: fieldDisclosed(firstNonEmpty([firstBullet(psecGet('Going live')), firstPara(sec('Rollback')), 'rollback declared in the contract.']), 150) },
  ]);

  const b3 = band3Flow(logicBlockFor('plan'),
    flowCaption('The shape of the work — every box is a real check, not a stage name.'),
    ['Solid = the happy path', 'Dashed = refuses and stops']);

  const stepRows = steps.map((st) => {
    const verify = st.verify
      ? `<div class="verify"><b>Verify</b>${txt(st.verify)}</div>`
      : `<div class="verify"><b>Verify</b>— none recorded for this step</div>`;
    return `<div class="b-step"><div class="b-num">${txt(st.n)}</div>` +
      `<div><div class="b-ttl">${txt(st.title)}</div>` +
      (st.detail ? `<div class="b-det">${txt(st.detail)}</div>` : '') + `</div>` +
      verify + `</div>`;
  }).join('');
  const b4 = steps.length
    ? bandSection(txt('The work — every step carries the command that proves it'),
        `${nF('steps.total', total)} ${txt('steps. A box is only ticked when its VERIFY command has actually run and passed.')}`,
        stepRows, true)
    : bandNA('The work', 'this plan declares no steps yet');

  // ── the rest of a world-class engineering plan (INV-COMPLETE-PLAN) ──
  // Present it, or say N/A with a reason. A section a reader cannot see is
  // indistinguishable from one that was never required.
  const secOrNA = (title, purpose, names, naReason) => {
    const body = firstNonEmpty(names.map((n) => psecGet(n)));
    if (!body) return bandNA(title, naReason);
    const allItems = bullets(body, /^-\s+/);
    // P4. Drops every bullet past the eighth and prints nothing to say so.
    if (allItems.length > 8) {
      lossy('bullets.slice8', allItems.slice(0, 8).join('').length, allItems.join('').length, allItems.length - 8, () => allItems.slice(8));
    }
    const items = allItems.slice(0, 8);
    const inner = items.length
      ? `<ul class="pl">${items.map((i) => (() => { const _p = fieldParts(i.replace(/^-\s+/, '').replace(/\*\*/g, ''), 190); return `<li><span class="pill now">·</span><span>${txt(_p.shown)}</span>${disclose(_p.rest)}</li>`; })()).join('')}</ul>`
      : (() => { const _p = fieldParts(firstPara(body), 400); return `<p class="b-det">${txt(_p.shown)}</p>${disclose(_p.rest)}`; })();
    return bandSection(title, purpose, inner);
  };
  const b5 = secOrNA('The approach', 'What we\u2019re doing, and what we deliberately rejected.',
    ['The approach', 'Approach'], 'this plan states no approach section');
  const b6 = secOrNA('What could break', 'Ranked, each with the thing that catches it.',
    ['What could break', 'Risks', 'Assumptions'], 'this plan names no risks — which is itself worth questioning');
  const b7 = secOrNA('How we know it works', 'The test strategy behind the invariants.',
    ['Test strategy', 'Test plan'], 'this plan states no test strategy');
  const b8 = secOrNA('Going live', 'Rollout, monitoring, rollback, ownership.',
    ['Going live', 'Rollout'], 'this plan states no rollout section');
  const b9 = secOrNA('Data & migration', 'What moves, and how it is proven safe.',
    ['Data & migration', 'DB / migration'], 'no database, schema or persisted format is touched by this build');

  return `<section class="cv-body"><div class="wrap">
  <div class="kicker">Compass · Plan Map</div>
  ${b1}
  ${b2}
  ${b3}
  ${b4}
  <div class="b-cols">${b5}${b6}</div>
  <div class="b-cols">${b7}${b8}</div>
  ${b9}
  <div class="foot">Compass · Plan Map · ${txt(slug)} · ${nF('steps.total', total)} steps · a pure function of plan.md</div>
</div></section>`;
}

// PROGRAM COCKPIT — the two-altitude view (program phases + contracts-per-phase, above the build
// strip). The HTML twin of `compass.sh cockpit`. Reads the ledger from <build-dir>/../PROGRAM.md.
function programCockpit() {
  const pf = join(dir, '..', 'PROGRAM.md');
  const pm = existsSync(pf) ? readFileSync(pf, 'utf8') : '';
  const pname = (pm.match(/^#\s*Program\s*[—-]\s*(.+)$/m) || [, ''])[1].trim();
  const cur = (pm.match(/^current:\s*(.+)$/m) || [, ''])[1].trim();
  const gl = (st) => (st === 'shipped' ? '✓' : (/in-flight|in-review/.test(st) ? '◉' : '○'));
  let strip = '';
  if (pname) {
    for (const ln of pm.split('\n')) {
      const p = ln.match(/^phase (\d+)\/(\d+) · ([^ ·]+) · status=([a-z-]+)(?: · (.+))?$/);
      if (p) {
        const here = p[3] === cur;
        strip += `<div class="ph ${here ? 'here' : p[4]}"><span class="g">${gl(p[4])}</span> P${p[1]} ${txt(p[3])}${p[5] ? ' (' + txt(p[5]) + ')' : ''}${here ? ' ◀ here' : ''}</div>`;
        continue;
      }
      const c = ln.match(/^\s+contract:\s*([^ ·]+) · status=([a-z-]+)/);
      if (c) strip += `<div class="ct ${c[2]}"><span class="g">${gl(c[2])}</span> ${txt(c[1])}</div>`;
    }
  }
  const receipts = read('receipts.md');
  const stages = ['contract', 'review-contract', 'plan', 'review-plan', 'build', 'review-build', 'ship'];
  const passed = new Set();
  // canonical receipt header `## RECEIPT — <stage> · … · PASS` (require PASS; middot after the stage)
  // — matches what compass.sh writes, and agrees with the bash cockpit's stage_pass (review-build R1).
  for (const m of receipts.matchAll(/RECEIPT\s+[—-]\s+([a-z-]+)\s+·[^\n]*·\s*PASS/gi)) passed.add(m[1].toLowerCase());
  let here = stages.find((s) => !passed.has(s)) || '';
  const build = stages.map((s) => {
    const st = passed.has(s) ? 'done' : (s === here ? 'here' : 'left');
    return `<div class="st ${st}"><span class="g">${st === 'done' ? '✓' : st === 'here' ? '◉' : '·'}</span> ${s}</div>`;
  }).join('');
  const body = `
<section class="cv-body"><div class="wrap">
  <div class="kicker">Compass · Program Cockpit</div>
  <h1>${txt(pname || title)}</h1>
  ${band3Flow(logicBlockFor('program'), flowCaption('The lifecycle every phase of this program passes through.'), ['Solid = the happy path', 'Dashed = refuses and stops'])}
  ${pname ? `<div class="card vpc-tl"><div class="kicker">Program — here: ${txt(cur || 'COMPLETE')}</div><div class="tl vert">${strip}</div></div>`
          : `<p class="lede">Standalone build — no program.</p>`}
  <div class="card"><div class="kicker">This build — ${txt(slug)}</div><div class="tl">${build}</div></div>
  <div class="foot">Generated from PROGRAM.md / receipts.md by compass-visual · a pure function of the build's state.</div>
</div></section>`;
  return { body, extra: _pillCss };
}

// RELEASE CARD — what shipped (version + NOW-scope headline). Milestone: ship. Deterministic (contract.md).
// ── review artefact (v0.30) ───────────────────────────────────────────────────────────────────
// "What the reviews caught, and what happened to it." The contract puts this above the Release
// Card deliberately: a shipping certificate tells you a thing shipped; this tells you what was
// wrong with it and whether anyone fixed it. It reads the ledger, which is the only record that
// survives a review.
// ── the ledger parser (v0.30, review-3 round 4) ───────────────────────────────────────────────
// Four rounds of patching a row-splitting heuristic produced a page that printed a wrong number on
// 21 of 25 builds — including four that rendered "0 findings · Nothing is waiting on you" over
// ledgers mentioning CRITICAL a dozen times. The heuristic assumed one well-formed table shape. A
// real ledger has ten column counts, bullet sections, header rows, inline code spans containing a
// bare pipe, and tables with no Status column at all. So: parse it properly, once.
function splitLedgerRow(line) {
  // Mask what must not be treated as a column edge: markdown's `\|` escape, and any pipe inside an
  // inline code span (`a \| b`). Both were splitting rows into the wrong columns — and the two rows
  // that DOCUMENT that bug were themselves being mis-read by it.
  let masked = line.replace(/\\\|/g, '\u0001');
  masked = masked.replace(/`[^`]*`/g, (m) => m.replace(/\|/g, '\u0002'));
  const cells = masked.split('|');
  if (cells.length && !cells[0].trim()) cells.shift();
  if (cells.length && !cells[cells.length - 1].trim()) cells.pop();
  return cells.map((c) => c.replace(/\u0001/g, '|').replace(/\u0002/g, '|').trim());
}
const isSeparatorRow = (cells) => cells.length > 0 && cells.every((c) => /^:?-{2,}:?$/.test(c));
function findCol(header, re) {
  if (!header) return -1;
  return header.findIndex((h) => re.test(String(h).replace(/\*/g, '').trim()));
}
// The leading verdict of a cell, never a keyword anywhere in it: "**MAJOR** — … **Not Critical**:
// it cannot ship a wrong number" was being graded CRITICAL off its own explanation.
// THE severity vocabulary, used by every reader. Whole words only: `CRITIQUE-TARGET`,
// `cold-critic` and `Majority` are not severities, and substring matching graded 13 real rows
// wrong — three of them rows whose own id says Major, shipping with a red `crit` pill.
const SEV_WORD = /\b(CRIT(?:ICAL)?|BLOCKER|MAJ(?:OR)?|MIN(?:OR)?|NIT)\b/i;
function sevFromText(t) {
  const m = String(t || '').match(SEV_WORD);
  if (!m) return null;
  const w = m[1].toUpperCase();
  return (w.startsWith('CRIT') || w === 'BLOCKER') ? 'crit' : w.startsWith('MAJ') ? 'maj' : 'min';
}
function leadingSeverity(cell) {
  // ABBREVIATIONS COUNT. Real ledgers head the column `Sev` and write `Crit`, `Maj`, `Crit→spec`.
  // Demanding the full word painted two CRITICAL findings `min` on a shipped page and printed
  // "1 critical" where there were three.
  const m = String(cell || '').replace(/\*/g, '').trim().match(/^(CRIT(?:ICAL)?|MAJ(?:OR)?|MIN(?:OR)?)\b/i);
  if (!m) return null;
  const w = m[1].toUpperCase();
  return w.startsWith('CRIT') ? 'crit' : w.startsWith('MAJ') ? 'maj' : 'min';
}
function parseLedger(text) {
  const out = [];
  const lines = String(text || '').split('\n');
  let header = null, pending = null, blanks = 0;
  const seenSev = new Map();   // id → severity, for sub-finding inheritance
  // An id is a SHORT TOKEN WITH NO SPACES — not necessarily one bare word starting with a letter.
  // Requiring `^[A-Za-z]` and a single `-`/`.`-joined token dropped every row whose id is a range
  // or a list (`R-1..R-11`, `G3/G4/G6/G7/S1/S2`) or a plain number (`1`) — ids this very ledger
  // uses. A four-row ledger of three OPEN CRITICALs rendered as "1 findings … Nothing is waiting
  // on you", which is precisely the output the previous round was convened to eliminate. Narrowing
  // an id filter to fix a fabricated-finding bug created a vanishing-finding bug.
  const NOT_ID = /^(findings?|round|severity|status|total|summary|notes?|honest|converged|clean|verdict|tally|columns?|issue|id|area|fix|owner|round\s*#?)$/i;
  const isId = (x) => !!x && !/\s/.test(x) && x.length <= 32 && !NOT_ID.test(x)
    && /[0-9]/.test(x) && /^[A-Za-z0-9]/.test(x) && /^[A-Za-z0-9][A-Za-z0-9._/,+-]*$/.test(x)
    // A DATE, a VERSION or a URL satisfies every shape rule above and is never a finding id.
    // These were excluded only in the rescue path, so they still walked in through the front door.
    && !/^\d{4}-\d{2}-\d{2}$/.test(x) && !/^v?\d+\.\d+(\.\d+)?$/.test(x) && !/^https?:/i.test(x);
  // Does this header look like a findings table? Used to decide whether an ODD-SHAPED first cell
  // in an established table is still a finding row.
  const isFindingsHeader = (h) => !!h && h.length >= 2
    && (findCol(h, /^(issue\s*id|id|issue|finding)$/i) === 0 || findCol(h, /^sev(erity)?$/i) >= 0 || findCol(h, /^(status|verdict)$/i) >= 0);
  // The id cell often carries the id AND its description: `MIN-1: the grep matched the island body`.
  // Requiring the whole cell to be an id dropped every row of one ledger and single rows from
  // three more — the page then reported "no review recorded" over six real findings.
  const leadingId = (cell) => {
    const c = String(cell || '').replace(/\*/g, '').replace(/`/g, '').trim();
    if (isId(c)) return c;
    const m = c.match(/^([A-Za-z][A-Za-z0-9]*(?:[-.][A-Za-z0-9]+)*)\s*[:—-]\s+\S/);
    return m && isId(m[1]) ? m[1] : null;
  };
  const sevCellRaw = (cells, hdr) => {
    const c = findCol(hdr, /^sev(erity)?$/i);
    return c >= 0 && cells[c] !== undefined ? cells[c] : null;
  };
  // A row whose cells are all column LABELS is a header, not data. Used to detect a second table
  // starting after a single blank line, which used to be counted as a finding.
  const looksLikeHeader = (cells) => cells.length >= 2
    && cells.every((c) => /^[A-Za-z][A-Za-z /#()-]{0,24}$/.test(String(c).replace(/\*/g, '').trim()))
    // `fix`, `area`, `round` and `owner` are dropped from this set: they are ordinary CELL values
    // too (`| gate | MAJOR | fix |` is a finding), and including them silently deleted real rows.
    // What remains only ever heads a column.
    && cells.some((c) => /^(issue\s*id|id|issue\s*number|sev(erity)?|status|verdict)$/i
                          .test(String(c).replace(/\*/g, '').trim()));

  const pushRow = (cells, hdr) => {
    let id = leadingId(cells[0]);
    // Once a findings table's header is established, a row of the same shape IS a finding, even if
    // its id cell is unusual. Dropping it silently is how a readable one-row ledger came to be
    // reported as unreadable.
    if (!id && (isFindingsHeader(hdr) ? cells.length === hdr.length : (!hdr || !hdr.length) && cells.length >= 3)) {
      // The rescue exists for real ids the shape test cannot express (`R-1..R-11`, `FN-1/2/3`).
      // It must NOT rescue a row that is not a finding at all: a `| — | … | NONE |` "no material
      // findings" row, a totals row, a date, a version, a URL. Three shipped builds gained phantom
      // findings this way, one of them titled `—`.
      const raw = String(cells[0] || '').replace(/[*_`]/g, '').trim();
      const looksLikeId = raw && raw.length <= 32 && !/\s/.test(raw)
        && !/^[—–-]+$/.test(raw) && !/^(total|totals|none|n\/a|sum|—)$/i.test(raw)
        && !/^https?:/i.test(raw) && !/^\d{4}-\d{2}-\d{2}$/.test(raw) && !/^v?\d+\.\d+/.test(raw);
      // `hasSeverity` may PROMOTE an odd-but-plausible id; it may never override a rejection.
      // As an AND-guard it made the whole blocklist dead, because a findings table always has a
      // severity — so a `| — | MINOR ×11 | folded into the above |` roll-up row shipped as a
      // finding, and the page counted 51 where the ledger records 50.
      if (!looksLikeId) return;
      // Never a parse-order index: a row rendered `(row 159)` on the shipping page, OPEN, on a
      // page telling the reader to read the open rows — and "row 159" appears nowhere in the file.
      id = raw.slice(0, 32);
    }
    if (!id) return;
    const sevCol = findCol(hdr, /^sev(erity)?$/i);
    const stCol  = findCol(hdr, /^(status|verdict|state|outcome|disposition|resolution|result|fix applied)$/i);
    // The DESCRIPTION column, by name. This was hard-coded to cells[1] — which on the standard
    // ledger header is `Review`, so on 19 builds every row's description read "R1" or "R2" under
    // a heading saying "Every finding, and what happened to it".
    let ttlCol = findCol(hdr, /^(failure mode|finding|title|description|issue|problem|what)$/i);
    if (ttlCol < 0) ttlCol = findCol(hdr, /^(affected area|area)$/i);
    if (ttlCol < 0) ttlCol = cells.findIndex((c, i) => i > 0 && i !== sevCol && i !== stCol && String(c).trim().length > 12);
    // A row whose cell count does not match its header is NOT safely indexable. Guessing produced
    // four Major findings graded `min` off the Root-cause column, under a caption claiming the
    // table had no severity column at all.
    const shapeOk = !hdr || !hdr.length || cells.length === hdr.length;
    const sevCell = (shapeOk && sevCol >= 0) ? cells[sevCol] : null;
    const stCell  = (shapeOk && stCol  >= 0) ? cells[stCol]  : null;
    out.push({
      id,
      // Only use the id cell's REMAINDER when there actually is one (`MIN-1: text`). When the cell
      // is just the id, the description lives in another column and falling back to the id printed
      // the id twice.
      title: ((() => { const c = String(cells[0] || '').replace(/\*/g, '').trim();
                       const rest = c.replace(/^[A-Za-z][A-Za-z0-9]*(?:[-.][A-Za-z0-9]+)*\s*[:—-]\s+/, '').trim();
                       return rest && rest !== c ? rest : ''; })()
              || String((ttlCol >= 0 ? cells[ttlCol] : cells[1]) || '').replace(/\*/g, '').trim()
              || String(cells.find((c, i) => i > 0 && String(c).trim().length > 8) || '').replace(/\*/g, '').trim()
              || id),
      text: cells.slice(1).join(' — '),
      sev: sevCell != null ? (leadingSeverity(sevCell) || sevFromText(sevCell) || 'min')
         : (sevFromText(cells.join(' ')) || 'min'),
      sevStated: sevCell != null && leadingSeverity(sevCell) != null,
      shapeMismatch: !shapeOk,
      status: stCell != null ? String(stCell).replace(/\*/g, '').trim() : null,
    });
  };
  // Is there ANY table in this file outside a blockquote? If so, quoted tables are quotations of
  // earlier rounds and must NOT be counted — counting them inflated a 2-finding build to 5, and
  // Compass ledgers quote prior rounds routinely. If not, the whole ledger is quoted, and reading
  // it is the only way to avoid falsely telling the reader it could not be read.
  const hasUnquotedTable = (() => {
    const fs2 = fenceScanner();
    for (const x of lines) {
      const st = fs2(x);
      if (st.fence || st.inside) continue;      // a fenced EXAMPLE table is not a real one
      if (/^\s*\|/.test(x)) return true;
    }
    return false;
  })();
  const fenceScan = fenceScanner();
  for (let _li = 0; _li < lines.length; _li++) {
    const raw = lines[_li];
    // FENCE-BLIND, like every other reader here (INV-FENCE-BLIND). A ledger that SHOWS an example
    // table inside a code fence had that example counted as real findings.
    // Track the fence's CHARACTER and LENGTH: only a run at least as long, of the same character,
    // closes it. A four-backtick fence wrapping a three-backtick example was treated as two
    // separate fences, so the example's rows counted as findings — including a phantom one titled
    // `Issue ID`, the example's own header. Same rule the reader-copy extractor already uses.
    // Strip the blockquote marker BEFORE scanning for fences. Scanning the raw line meant `> ```` was not recognised as a fence, so the >-stripped example rows inside it were parsed as findings:
    // truth 1 became 2, and a CRITICAL OPEN finding was invented out of a code sample.
    const quoted = /^\s*>/.test(raw);
    const l = raw.replace(/^(\s*)>\s?/, '$1');
    const fst = fenceScan(l);
    if (fst.fence || fst.inside) continue;
    // A blockquoted table is still a table — `^\s*\|` never matched `> | A-1 | ... |`, so the page
    // said the ledger "could not be read" about a table that renders in every markdown viewer.
    // But a ledger that QUOTES a prior round's table is the ordinary Compass shape, and counting
    // those rows inflated a 2-finding build to 5. So a quoted table is read only when the file has
    // NO unquoted table to read: it is a fallback for "the whole ledger is quoted", never an
    // addition to rows that were found normally.
    if (quoted && hasUnquotedTable) continue;
    if (!/^\s*\|/.test(l)) {
      // A blank line inside a table does NOT end it. Resetting on every non-pipe line dropped the
      // row after any blank, and dropped `pending` — the first data row — on the floor.
      if (!l.trim()) { blanks++; if (blanks < 2) continue; }
      // The severity may appear ANYWHERE in the bullet's leading segment — the part before the
      // first dash or colon — and in any wrapper: `**A-1 CRITICAL**`, `A-1 (CRITICAL)`,
      // `**A-1 (Crit)** —`, `A-1 [CRITICAL] —`. Requiring it immediately after the id kept ONE of
      // six real formats, so a build with 28 bullet findings (four of them CRITICAL) rendered
      // "6 findings — 2 critical" and another rendered "2 findings — 0 critical" over 23.
      const bm = l.match(/^\s*[-*]\s+(.{1,120}?)\s*[—:–\u2192-]\s+(.+)$/);
      const b = (() => {
        if (!bm) return null;
        const head = bm[1].replace(/\*\*/g, '').trim();
        const idm = head.match(/^\(?\[?([A-Za-z0-9][A-Za-z0-9._/,+-]*)\)?\]?/);
        if (!idm) return null;
        // A BARE COUNT is not an id: "- **3 MINOR hardenings applied (round 2 fixes):**" became a
        // finding called `3`. A finding id carries a letter somewhere.
        if (!/[A-Za-z]/.test(idm[1])) return null;
        const sevm = head.match(/\b(CRIT(?:ICAL)?|MAJ(?:OR)?|MIN(?:OR)?)\b/i);
        if (sevm) { seenSev.set(idm[1], sevm[1]); return [l, idm[1], sevm[1], bm[2]]; }
        // A SUB-FINDING inherits its parent's severity: `C1a` and `C1b` are the two halves of `C1`
        // and state no severity of their own. Requiring an explicit one dropped them, hiding two
        // CRITICALs. Inheritance is narrow on purpose — the id must extend an id already seen —
        // so an ordinary prose bullet still cannot become a finding.
        for (const [pid, psev] of seenSev) {
          // A SEPARATOR must follow the parent id. Bare `startsWith` made `R10` a child of `R1`
          // — and `R1…R10` is the commonest id scheme here, so this fired the moment a ledger
          // numbered past nine, silently and with `sevStated: true` so the page did not disclose it.
          if (idm[1] !== pid && new RegExp(`^${pid.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}[a-z.]`).test(idm[1])) {
            return [l, idm[1], psev, bm[2]];
          }
        }
        return null;
      })();
      // The severity must be the bullet's OWN, stated right after its id — not a word appearing
      // somewhere in its prose. A re-attack note reading "- R2-M1/M2 (rollback-rehearsed …)" was
      // counted as a finding called `R2` because the sentence happened to mention a severity.
      if (b && isId(b[1]) && b[2]) {
        const body = String(b[3]).replace(/\*\*/g, '').trim();
        const W = String(b[2]).toUpperCase();
        const word = W.startsWith('CRIT') ? 'CRITICAL' : W.startsWith('MAJ') ? 'MAJOR' : 'MINOR';
        out.push({ id: b[1], title: body, text: body,
          sev: word === 'CRITICAL' ? 'crit' : word === 'MAJOR' ? 'maj' : 'min',
          sevStated: true, shapeMismatch: false, status: null });
      }
      if (l.trim()) {
        // FLUSH before resetting. A single-row table (one row, no header, no separator) parked its
        // only row in `pending`, and ending the table threw it away — one real finding per
        // occurrence, silently. Only the very last pending was ever recovered.
        if (pending && leadingId(pending[0])) pushRow(pending, []);
        header = null; pending = null;
      }
      continue;
    }
    blanks = 0;
    const cells = splitLedgerRow(l);
    if (!cells.length) { continue; }
    if (isSeparatorRow(cells)) { header = pending; pending = null; continue; }
    // A SECOND TABLE starting after a single blank line: its header row was being parsed as a data
    // row of the first table and counted as a finding — the page said 3 findings over 2 real rows
    // and rendered one titled "ID". Compass's own ledgers repeat an id across review sections, so
    // this is the ordinary shape. A row that is plainly a header ends the previous table.
    // A header is followed by a SEPARATOR row. Requiring that is exact, and it tells the target
    // case (a second table starting after one blank line) apart from a real finding whose cells
    // happen to read like labels — `| gate | status | Major | open |` is a finding, and the label
    // test alone deleted it.
    const _nx = (lines[_li + 1] || '').replace(/^(\s*)>\s?/, '$1');
    const nextIsSeparator = /^\s*\|[\s:|-]*\|?\s*$/.test(_nx) && /-/.test(_nx);
    if (header && looksLikeHeader(cells) && !leadingId(cells[0]) && nextIsSeparator) { pending = cells; header = null; continue; }
    if (!header) {
      if (!pending) { pending = cells; continue; }
      // Two data rows and no separator between them: this table has no separator row. Decide once
      // whether `pending` was a header or a finding — and if it was a finding, KEEP IT. The first
      // version dropped it silently, losing the first row of six shipped ledgers.
      const pendingIsId = !!leadingId(pending[0]);
      if (pendingIsId) { header = []; pushRow(pending, header); }
      else { header = pending; }
      pending = null;
      pushRow(cells, header);
      continue;
    }
    pushRow(cells, header);
  }
  // A table that ended with `pending` still holding a data row (no separator, single row).
  if (pending && leadingId(pending[0])) pushRow(pending, []);
  return out;
}

function reviewArtefact() {
  const led = read('review-ledger.md');
  const rows = parseLedger(led);
  // The same id appears in more than one review section (`R2-1` from review-plan and from
  // review-build). Rendering both as bare `R2-1` left a reader unable to tell which row is which.
  const idSeen = new Map();
  for (const r of rows) {
    const n = (idSeen.get(r.id) || 0) + 1;
    idSeen.set(r.id, n);
    if (n > 1) r.dupN = n;
  }
  const guessedN = rows.filter((r) => !r.sevStated).length;
  const sevGuessed = guessedN > 0;
  const unknownStatus = rows.filter((r) => r.status == null).length;
  const sev = (r) => r.sev || 'min';
  const nCrit = rows.filter((r) => sev(r) === 'crit').length;
  const nMaj  = rows.filter((r) => sev(r) === 'maj').length;
  // CLOSED means the row's own status says so. Unknown status is NOT open and NOT closed — saying
  // "still open" about 49 rows whose tables carry no status column is a wrong number, and saying
  // "closed" about them would be worse. ACCEPTED / NOTED / WAIVED are dispositions, not failures
  // left lying around, so they count as dealt with and are labelled by their own word.
  // Anchored to the START of the status, but tolerant of a leading word: `VERIFIED FIXED` was
  // rendering as OPEN. A status that is stated but recognised by neither list is its own third
  // state — band 2 used to describe those rows as "states no status" while band 4 labelled them
  // OPEN, so the two bands of one page contradicted each other on five builds.
  const CLOSED  = /(^|\b)(FIXED|RESOLVED|CLOSED|DONE|ACCEPTED|NOTED|WAIVED|OK|N\/A)\b/i;
  const OPENISH = /^\s*\**\s*(OPEN|NOT[\s-]?FIXED|NOT[\s-]?CLOSED|UNFIXED|PENDING|TODO|DEFERRED|FLAGGED|NEW|WONTFIX|WON'T[\s-]?FIX)\b/i;
  // An open-ish word ANYWHERE in the status, not only at the start. "m4 FIXED …; rest OPEN." was
  // read as closed and the row vanished from a list captioned as the complete set of what still
  // needs you. When a status says both, the honest reading is the one that keeps it visible.
  const OPEN_ANYWHERE = /(^|\b)(OPEN|NOT[\s-]?FIXED|NOT[\s-]?CLOSED|UNFIXED|PENDING|TODO|DEFERRED|FLAGGED|WONTFIX|WON'T[\s-]?FIX)\b/i;
  const isClosed = (r) => r.status != null && r.status.trim() !== '' && !OPEN_ANYWHERE.test(r.status) && CLOSED.test(r.status);
  const isOpen   = (r) => r.status != null && (OPENISH.test(r.status) || OPEN_ANYWHERE.test(r.status));
  const isUnclear = (r) => !isClosed(r) && !isOpen(r);
  const fixed = rows.filter(isClosed).length;
  const open  = rows.filter(isOpen).length;
  const unstated = rows.filter(isUnclear).length;

  // "0 findings · Nothing is waiting on you" printed over a ledger mentioning CRITICAL twelve times
  // is the worst output this page can produce, and four shipped builds produced it. If the file has
  // real content the parser could not read, SAY THAT — never report zero.
  // THREE states, not two. "No ledger file at all" is not "every finding was fixed" — and the page
  // said exactly that on three shipped builds and on every build before its first review: `0
  // findings · Every finding was fixed and re-checked. Nothing is waiting on you.` over a directory
  // with no review-ledger.md in it. A 400-character floor also meant a real 147-byte ledger reading
  // "Round 1 found three CRITICAL defects. Do not ship." produced the same all-clear.
  // An all-clear is only ever printed when rows were actually parsed AND all of them are closed.
  // An empty file is not a missing file. The page said "There is no review-ledger.md in this
  // build directory" about a file that exists and is blank. The substance was right; the stated
  // fact was false, and a page that states a false fact about itself cannot be trusted on the rest.
  const ledgerAbsent = !led;
  const ledgerMissing = !led || !led.trim();
  const unreadable = rows.length === 0 && !ledgerMissing;

  const b1 = band1Decision('Decide',
    ledgerMissing ? 'No review has been recorded for this build yet.'
      : unreadable ? 'This ledger could not be read — check it before accepting.'
      : open > 0 ? 'Accept this build with open findings?' : 'Accept what the reviews caught?', [
    `<b>${txt(slug)}</b>`,
    ledgerMissing ? 'no review on file' : unreadable ? 'ledger unreadable' : `${nF('findings.total', rows.length)} findings`,
    ledgerMissing ? 'nothing to count' : unreadable ? 'nothing counted' : `${nF('findings.closed', fixed)} closed`,
  ]);
  const b2 = band2Facts('The facts you need to decide', ledgerMissing ? [
    { k: 'How many', v: 'None recorded — this build has no review-ledger.md.' },
    { k: 'What that means', v: 'This is NOT "no problems found". It means no review has written anything down yet. Read it as missing evidence, not as an all-clear.' },
    { k: 'Where it came from', v: ledgerAbsent ? 'There is no review-ledger.md in this build directory.' : 'review-ledger.md exists in this build directory but is empty.' },
  ] : unreadable ? [
    { k: 'How many', v: 'Unknown — review-ledger.md has content this page could not parse into findings.' },
    { k: 'What that means', v: 'Do not read this as "no findings". Open review-ledger.md and read it directly before accepting.' },
    { k: 'Where it came from', v: 'review-ledger.md.' },
  ] : [
    { k: 'How many', v: `${nF('findings.total', rows.length)} findings — ${nF('findings.critical', nCrit)} critical, ${nF('findings.major', nMaj)} major.` },
    { k: 'How many closed', v: `${nF('findings.closed', fixed)} closed, ${nF('findings.open', open)} still open${unstated ? `, ${nC(unstated)} whose status this page could not read` : ''}.` },
    { k: 'What that means', v: open ? 'Something was found and not fixed. Read the open rows before accepting.'
        : unstated ? 'Nothing is recorded as open, but some rows state no status — those are unresolved on the page, not resolved.'
        : 'Every finding was fixed and re-checked. Nothing is waiting on you.' },
    { k: 'Where it came from', v: `review-ledger.md — written during the reviews, not after.${sevGuessed ? ` ${nC(guessedN)} of ${nC(rows.length)} rows state no severity this page could read, so their severity is taken from the row's wording instead.` : ''}` },
  ]);
  const b3 = band3Flow(logicBlockFor('review'),
    flowCaption('How a finding travels: raised, proven reachable, fixed, then re-attacked.'),
    ['Solid = the happy path', 'Dashed = dropped, or sent back round']);

  // EVERY row that is not closed is shown. The cut applies only to closed rows — a heading that
  // says "everything still blocking acceptance is above" was false while 42 of 66 open rows sat
  // below it, and no cap can make that sentence true.
  const notClosed = rows.filter((r) => !isClosed(r));
  const closedRows = rows.filter(isClosed);
  const CLOSED_SHOWN = Math.max(0, 24 - notClosed.length);
  const shown = [...notClosed, ...closedRows.slice(0, CLOSED_SHOWN)];
  const hiddenN = rows.length - shown.length;
  // P5. Drops WHOLE ledger rows. The unit here is a row, not a character, which is why the
  // char figures are reported as 0 rather than guessed at.
  if (hiddenN > 0) lossy('closedRows.slice', 0, 0, hiddenN,
    () => rows.filter((r) => !shown.includes(r)).map((r) => Object.values(r).filter((v) => typeof v === 'string').join(' ')));
  const list = shown.map((r) => {
    const cls = sev(r);
    // THREE labels, matching band 2's three counts. A status that is stated but recognised by
    // neither list rendered as OPEN here while band 2 filed it under "could not read" — so three
    // shipped builds printed two different open counts on one page, one of them saying "0 still
    // open" directly above a row labelled OPEN.
    const label = r.status == null ? 'no status'
      : isClosed(r) ? r.status.split(/\s+/)[0].toLowerCase()
      : isOpen(r) ? 'OPEN'
      : `? ${r.status.split(/\s+/)[0].toLowerCase()}`;
    return `<div class="b-step"><div class="b-num"><span class="pill ${cls === 'crit' ? 'never' : cls === 'maj' ? 'later' : 'now'}">${cls}</span></div>` +
      `<div><div class="b-ttl">${fieldDisclosed(r.id + (r.dupN ? ` (${r.dupN})` : ''), 90)}</div>` +
      `<div class="b-det">${fieldDisclosed(r.title || r.text || '', 190)}</div></div>` +
      `<div class="verify"><b>${txt(label)}</b>${fieldDisclosed(r.status || 'not stated in the ledger', 90)}</div></div>`;
  }).join('');
  const moreRow = hiddenN > 0
    ? `<div class="b-step"><div class="b-num"><span class="pill now">+${nC(hiddenN)}</span></div>` +
      `<div><div class="b-ttl">${nC(hiddenN)} closed finding${hiddenN === 1 ? '' : 's'} ${hiddenN === 1 ? 'is' : 'are'} not shown here.</div>` +
      `<div class="b-det">Everything not marked closed is listed above — that is the complete set of what still needs you. The full record is review-ledger.md.</div></div>` +
      `<div class="verify"><b>note</b>all ${nF('findings.total', rows.length)} are counted in the totals</div></div>`
    : '';
  // The title carries provenance markers, so it is rendered by the caller and passed raw.
  const b4 = bandSection(
    ledgerMissing ? txt('No review has been recorded')
      : unreadable ? txt('This ledger could not be read')
      // The heading must be true. "Everything still open, and N closed on file" was printed on
      // builds where band 2 said `0 still open` in the line above it.
      : hiddenN > 0 && (open + unstated) > 0 ? `${txt('Everything not closed, and')} ${nC(hiddenN)} ${txt('closed ' + (hiddenN === 1 ? 'finding' : 'findings') + ' not shown here')}`
      : hiddenN > 0 ? `${nC(rows.length - hiddenN)} ${txt('of')} ${nF('findings.total', rows.length)} ${txt('findings, all of them closed')}`
      : txt('Every finding, and what happened to it'),
    txt('Each row was proven reachable before it counted, and re-attacked after it was fixed.'),
    ledgerMissing
      ? '<div class="b-na"><b>No ledger</b> — this build has no review-ledger.md. That is missing evidence, not a clean bill of health.</div>'
      : unreadable
      ? '<div class="b-na"><b>Unreadable</b> — review-ledger.md has content, but no findings could be parsed from it. Read the file directly.</div>'
      : (list + moreRow) || '<div class="b-na"><b>N/A</b> — no ledger rows yet</div>', true);
  return { body: `<section class="cv-body"><div class="wrap"><div class="kicker">Compass · Review</div>${b1}${b2}${b3}${b4}<div class="foot">Generated from review-ledger.md by compass-visual · a pure function of the build's state.</div></div></section>`, extra: _pillCss };
}

function releaseCard() {
  // version: prefer an explicit "Ships as vX.Y.Z" anchor over the first semver in the file
  // (which could be an older version mentioned in prose) — review-build R2 MINOR-5.
  const ver = (contractFields.match(/Ships as \*{0,2}v(\d+\.\d+\.\d+)/i)
            || contractFields.match(/v(\d+\.\d+\.\d+)/) || [, hdr('version') || '?'])[1];
  // "What shipped" = the GOAL, not the H1 title line — R2 MAJOR-4 (`sec('')` returned __pre__ = title).
  // The SAME fallback chain the Brief uses. This one stopped at `**Goal:**`, so 21 of 28 Release
  // Cards rendered no "what shipped" line at all — the card's entire subject, missing.
  const goal = hdr('Goal') || (contractFields.match(/\*\*Goal:\*\*\s*(.+)/) || [, ''])[1]
    || firstPara(sec('Goal')) || firstPara(sec('Goal & scope')) || '';
  // "In this release" = the NOW block's numbered items ONLY — never the LATER/NEVER `- ` bullets
  // (R2 MAJOR-3: the old fallback advertised deferred + non-goal items as shipped).
  // v0.29.1: the canonical ladder the contract skill actually writes is `## Scope ladder`
  // with `- NOW:` bullets — NOT a `### NOW` section of numbered items. Reading only the
  // latter meant every standard contract rendered "0 changes": a release card advertising
  // that nothing shipped. Use scope() (which already separates NOW from LATER/NEVER, so the
  // v0.24 R2 guard against advertising deferred items as shipped is preserved), and keep the
  // numbered `### NOW` form as a fallback for contracts written that way.
  const ladderNow = scope().now || [];
  const nowBlock = (contractFields.match(/###\s*NOW[^\n]*\n([\s\S]*?)(?=\n###|\n##\s|$)/i) || [, ''])[1];
  const numbered = nowBlock.split('\n').filter((l) => /^\s*\d+\.\s/.test(l))
    .map((l) => l.replace(/^\s*\d+\.\s*/, '').replace(/\*\*/g, ''));
  // v0.32.0 S6: keep BOTH halves per item, so each <li> can disclose its own remainder. The
  // shortened text still feeds every downstream count, so nothing else moves.
  const nowParts = (ladderNow.length ? ladderNow : numbered).map((t) => fieldParts(String(t), 140));
  const nowItems = nowParts.map((p) => p.shown);
  // P6. Drops scope items past the sixth.
  if (nowItems.length > 6) lossy('nowItems.slice6', 0, 0, nowItems.length - 6, () => nowItems.slice(6));
  const items = nowParts.slice(0, 6).map((p) => `<li>${txt(p.shown)}${disclose(p.rest)}</li>`).join('')
    + (nowItems.length > 6 ? `<li style="color:var(--mut2)">+ ${nC(nowItems.length - 6)} more</li>` : '');
  const facet = hdr('facets') || 'library';
  // BEAT 1 — vX.Y.Z shipped · BEAT 2 — what changed (NOW items ONLY) · BEAT 3 — proof + the undo
  const body = `
<section class="cv-body"><div class="wrap">
  <div class="kicker">Compass · Release</div>
  ${band3Flow(logicBlockFor('release'), flowCaption('How this build reached production \u2014 every box a real gate it had to pass.'), ['Solid = the happy path', 'Dashed = refuses and stops'])}
  <div class="card vr-hero"><div class="kicker">Shipped</div>
    <h1>${txt(slug)}</h1>
    <div class="big">v${txt(ver)}<span class="badge">SHIPPED</span></div>
    ${goal ? (() => { const _p = fieldParts(String(rc('build-what', goal)), 400); return `<p class="lede">${txt(_p.shown)}</p>${disclose(_p.rest)}`; })() : ''}
  </div>
  ${items ? `<div class="card"><div class="kicker">What changed — ${nC(nowItems.length)} in this release</div><ul>${items}</ul></div>` : ''}
  <div class="card"><div class="kicker">Proof &amp; rollback</div>
    <div class="tl">${(() => {
      // A build that shipped with known open findings MUST say so on its own release page.
      // Derived from the receipt, not written by hand, because "say so" is exactly the thing a
      // person forgets when they are relieved to be shipping.
      const rb = read('receipts.md');
      const blk = (rb.split(/^## RECEIPT — review-build/m).pop() || '');
      const m = blk.match(/^- \[x\] converge-waiver: user-signed[^\n]*/m);
      if (!m || !/ACCEPTED WITH OPEN FINDINGS/.test(rb)) return '';
      // P13. NOT ENUMERATED IN SECTION 9, and it lands on the one chip whose whole job is to
      // disclose what is still open: only the FIRST unchecked receipt line becomes the reason.
      const _whyAll = blk.match(/^- \[ \][^\n]*/gm) || [];
      if (_whyAll.length > 1) lossy('waiverReason.firstOnly', _whyAll[0].length, _whyAll.join('\n').length, _whyAll.length - 1, () => _whyAll.slice(1));
      const why = (_whyAll[0] || '').replace(/^- \[ \]\s*/, '').replace(/\*/g, '');
      const _w = fieldParts(why, 120);
      return `<span class="chip" style="background:var(--amberBg);color:var(--amberFg);border:1px solid var(--amberBorder)">shipped un-converged — ${txt(_w.shown)}</span>${disclose(_w.rest, 'Show the rest of the reason')}`;
    })()}<span class="chip">facet: ${txt(facet)}</span><span class="chip">${nowItems.length ? `${nC(nowItems.length)} changes` : 'changes not itemised in this contract'}</span><span class="chip">reversible — revert the release commit + tag</span></div>
  </div>
  <div class="foot">Generated from contract.md by compass-visual · a pure function of the build's state.</div>
</div></section>`;
  return { body, extra: _pillCss };
}

// ── v0.30 INV-6: a BODY FRAGMENT, not a full document ─────────────────────────────────────────
// The Artifact host wraps whatever it is given in its own <!doctype><head></head><body> skeleton,
// so emitting a complete document nested a document inside a document and put this <style> — all
// of it — inside the body. One file, two destinations: it must be a fragment.
// Line 1 is now `<title>`; the leak tracer's real property is that line 1 is NEVER a
// `<!-- COMPASS-MOCK` marker, and that still holds.
function page(styleBlocks, bodyMarkup) {
  // CR-15. `title` is contract.md's first heading, so using it for every view named the Review page,
  // the Plan Map and the Release Card all "Contract — <slug>" — in the browser tab and, because that
  // is where a published Artifact takes its gallery name, on every artefact Compass has shipped. A
  // page says what it is.
  // Only the four views gen.mjs actually serves. `progress` is not one — the usage line rejects it —
  // so naming it here would be claiming a page that does not exist.
  const VIEW_NAME = { brief: 'Contract', 'brief-body': 'Contract', 'plan-map': 'Plan',
                      review: 'Review', 'release-card': 'Release' };
  const pageName = VIEW_NAME[view] ? `${VIEW_NAME[view]} — ${slug}` : title;
  return `<title>${esc(demd(pageName))} · compass-visual</title>
<style>${styleBlocks}</style>
${bodyMarkup}
`;
}

// ── brief-data fence (the shareable scrub's declared source of truth, v0.17.0) ──────────────────
// Recognition (contract RP-M3/RP2-m3/m4 — this LINE is the fail-open boundary): a code-fence opener
// LINE (≥3 backticks OR ≥3 tildes) whose info-string — lowercased, CR/space-trimmed, [-_ ] collapsed
// — equals 'compassbriefdata'. First recognized opener wins; its closer is the next same-char fence
// of length ≥ the opener. No opener line → absent (a prose/inline mention is NOT an opener). Unclosed
// opener, or a non-blank body line that is neither `none` nor a recognized `gold:`/`never-show:` key
// → malformed. Empty/none-only body → declaredNothing (valid, no error). Deterministic (file order).
function parseBriefData(md) {
  const lines = String(md).split(/\r?\n/);   // CRLF-agnostic (R3 D-1): a Windows/pasted CRLF opener must still be recognized, never fail-open to "absent"
  const norm = (s) => s.replace(/\r/g, '').trim().toLowerCase().replace(/[-_\s]+/g, '');  // collapse ALL whitespace (tab/NBSP too, RB3 D-R3-1) — the split uses \s+, so norm must match
  let openIdx = -1, fenceCh = '', fenceLen = 0;
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^\s*(`{3,}|~{3,})(.*)$/s);   // /s so (.*) spans U+2028/U+2029 line-separators inside the info-string, which norm then collapses (RB4 D-R4-1) — lines are already \n-split, so /s changes nothing else
    if (!m) continue;
    // Recognize the fence on ANY of: the full info-string, its first whitespace token, or that token
    // minus a trailing .ext — all normalized (RB2-m2). Covers ```compass-brief-data, the ```compass-brief-data json
    // markdown info-string reflex (D-2), a space-separated ```compass brief data, and a dotted ```compass-brief-data.json,
    // while NEVER mis-recognizing an unrelated tag like ```compass-brief-database. Never silently downgrade a real
    // declaration to "absent" (the fail-open this build exists to kill).
    const info = (m[2] || '').trim(); const firstTok = info.split(/\s+/)[0] || ''; const T = 'compassbriefdata';
    if (norm(info) === T || norm(firstTok) === T || norm(firstTok.replace(/\.[a-z0-9]+$/i, '')) === T) { openIdx = i; fenceCh = m[1][0]; fenceLen = m[1].length; break; }
  }
  if (openIdx < 0) return { present: false };
  let closeIdx = -1;
  for (let j = openIdx + 1; j < lines.length; j++) {
    const c = lines[j].match(/^\s*(`{3,}|~{3,})\s*$/);
    if (c && c[1][0] === fenceCh && c[1].length >= fenceLen) { closeIdx = j; break; }
  }
  if (closeIdx < 0) return { present: true, malformed: true };            // unclosed
  const gold = [], neverShow = [];
  for (const raw of lines.slice(openIdx + 1, closeIdx)) {
    const l = raw.replace(/\r/g, '').trim();
    if (!l || /^none$/i.test(l)) continue;
    const g = l.match(/^gold\s*:\s*(.*)$/i);
    const n = l.match(/^never-?show\s*:\s*(.*)$/i);
    if (g) { for (const t of g[1].split(',')) { const v = t.trim(); if (v) gold.push(v); } continue; }
    if (n) { for (const t of n[1].split(',')) { const v = t.trim(); if (v) neverShow.push(v); } continue; }
    return { present: true, malformed: true };                           // junk body line
  }
  if (gold.length === 0 && neverShow.length === 0) return { present: true, declaredNothing: true };
  return { present: true, gold, neverShow };
}

// ── genForms: the bounded-certainty set generated FROM a declared gold literal (contract RP-C1 /
//    RP2-M1 / RP3-m1/m2). Normalize to a bare integer magnitude (strip currency + all grouping
//    separators; a lone trailing period before fractional digits is the decimal and is preserved,
//    all other periods are grouping and stripped), then emit {Western-3, Indian-2-2-3} × {plain,
//    comma, ASCII/NBSP/thin/narrow space, apostrophe ('/’), European period} × {no-prefix, currency}.
//    The exact declared literal is ALWAYS scrubbed. A literal with letters (e.g. '87.5 lakh') or <3
//    digits is scrubbed EXACT-ONLY (no cross-product) — RP3-m2 / RP-m6 fail-safe floor. ──
// Single source of truth for grouping separators (R3 F2): the SAME set seeds genForms' generated output
// AND the best-effort NUMRUN matcher (built from GROUP_SEPS in shareableScrub) so the two cannot drift.
// Members: comma, ASCII space, NBSP, thin space, narrow space, apostrophe(U+2019) and apostrophe(U+0027).
// European period is grouping in genForms OUTPUT ONLY (decimal-ambiguous) -> appended for genForms,
// deliberately EXCLUDED from the best-effort matcher.
const GROUP_SEPS = [',', '\u0020', '\u00a0', '\u2009', '\u202f', '\u2019', '\u0027'];
function groupWestern(d) { return d.replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
function groupIndian(d) { if (d.length <= 3) return d; const last3 = d.slice(-3), rest = d.slice(0, -3); return rest.replace(/\B(?=(\d{2})+(?!\d))/g, ',') + ',' + last3; }
function genForms(literal) {
  const lit = String(literal).trim();
  if (!lit) return [];
  const stripped = lit.replace(/[$₹€£’',\s]/g, '');   // strip currency + both apostrophes + comma + \s (NBSP/thin/narrow)
  let intPart = stripped, frac = '';
  const periods = (stripped.match(/\./g) || []).length;
  if (periods >= 2) intPart = stripped.replace(/\./g, '');
  else if (periods === 1) { const m = stripped.match(/^(\d+)\.(\d+)$/); if (m) { intPart = m[1]; frac = m[2]; } else intPart = stripped.replace(/\./g, ''); }
  if (!/^\d+$/.test(intPart)) return [lit];                               // has letters/symbols (e.g. '87.5 lakh', '1.5x') -> exact-only
  intPart = intPart.replace(/^0+(?=\d)/, '');                             // strip leading zeros so '0042' -> '42' (RB4 D-R4-2: gate on significant digits, not char length)
  if (intPart.length < 3) return frac ? [lit] : [...new Set([lit, intPart])];  // <3-digit: scrub the exact literal AND (when no decimal tail) the bare integer magnitude, so a declared '₹42' also catches a bare '42' (RB3 D-R3-2). Over-redaction is the safe direction; a genuine decimal like '1.5' stays exact-only to avoid nuking its '1'.
  const forms = new Set([lit]);                                          // >=3-digit pure-numeric -> scrub exact + the full cross-product
  const SEPS = [...GROUP_SEPS, '.'];                                      // + European period (output-only)
  const PREF = ['', '$', '₹', '€', '£'];
  const tail = frac ? '.' + frac : '';
  const groupings = [intPart, groupWestern(intPart), groupIndian(intPart)];  // [0]=plain (no separator)
  for (let gi = 0; gi < groupings.length; gi++) {
    const seps = gi === 0 ? [''] : SEPS;
    for (const sep of seps) {
      if (sep === '.' && frac) continue;                                  // period-grouping ambiguous w/ a decimal
      const withSep = gi === 0 ? intPart : groupings[gi].replace(/,/g, sep);
      for (const p of PREF) forms.add(p + withSep + tail);
    }
  }
  return [...forms];
}

// ── leak gate (shareable only) — SCRUB then HARD-STOP: any secret class / commercial VALUE / gold
//    or never-show residue is scrubbed from the written copy (so the literal is truly absent) AND
//    reported as a hit that forces exit 3. Never a soft pass: a leak both scrubs AND stops. The
//    `declared` arg (from parseBriefData) adds the CERTAIN declared-value cross-product + seeds the
//    normalized layer + declared never-show — ADDITIVE to the existing best-effort scrub (v0.17.0). ──
function shareableScrub(html, declared = {}) {
  const hits = [];
  // Strip provenance markers before matching. They are invisible to a reader and must be invisible
  // to the leak gate too — a `<span>` between the characters of a password is not a reason to miss it.
  // Strip ALL inline markup, not just provenance markers. `**bold**` becomes <b>, and a scrub rule
  // matching a contiguous substring cannot see `AKIA<b>QWERTYUIOPASDFGH</b>` — which a reader reads
  // as one key. Un-hiding only the markers I had added fixed the case I created and left the case
  // markdown creates. The reader sees text; the gate must match on the same text.
  const INLINE_TAG = /<\/?(?:span|b|strong|em|i|u|a|sup|sub|small|code|abbr|mark|time|var|q|s|wbr)\b[^>]*>/gi;
  const unmark = (x) => { let prev; let cur = String(x); do { prev = cur; cur = cur.replace(INLINE_TAG, ''); } while (cur !== prev); return cur; };
  html = unmark(html);
  const R = '<span class="chip">⟨redacted ✓⟩</span>';
  const SECRETS = [
    [/sk-[A-Za-z0-9]{8,}/g, 'api key'],
    [/AKIA[0-9A-Z]{12,}/g, 'aws access key'],
    [/xox[baprs]-[A-Za-z0-9-]{8,}/g, 'slack token'],
    [/eyJ[A-Za-z0-9_-]{6,}\.eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}/g, 'jwt'],
    [/-----BEGIN [A-Z ]*PRIVATE KEY-----/g, 'pem private key'],
    [/\b[a-z][a-z0-9+.-]*:\/\/[^:@/\s]+:[^@/\s]+@/g, 'inline url credentials'],
    // The leading `[A-Z]` ate the first letter, so the alternation could never start at position 0:
    // `API_KEY=`, `SECRET=`, `TOKEN=`, `PASSWORD=` and `SECRET_KEY=` were ALL missed, and only a
    // prefixed `MY_API_KEY=` was caught. The bare forms are the common ones.
    [/\b[A-Z0-9_]*(?:SECRET|TOKEN|PASSWORD|API_?KEY)[A-Z0-9_]*\s*[:=]\s*['"]?[^\s'"<]+/g, 'inline secret assignment'],
  ];
  // commercial-sensitive VALUES: the term adjacent to a numeric value (not the bare vocabulary).
  // R9-C2: the window was 12 characters and the class excluded `.`, so "The IRR for this fiscal
  // year is 18.5% net" and "IRR approx. 18.5%" both published at exit 0 — the first too far, the
  // second stopped by an ordinary full stop. A sentence is not 12 characters long, and a full stop
  // is not a boundary a leak respects. Widened to a sentence-ish window that still cannot run past
  // a line break, and fullwidth/Arabic-Indic digits count as digits because a reader reads them.
  const COMMERCIAL = [[
    // `margin` was added and immediately fired on the page's own CSS (`margin:10px 0 0`), turning a
    // clean Brief into a hard-stop. A leak rule that cries wolf on a stylesheet gets switched off
    // within a week, which is worse than the narrow rule it replaced. The vocabulary stays as the
    // commercial-sensitivity guard defines it; what widened is the WINDOW, which is what the real
    // bypasses used.
    /\b(?:IRR|take[- ]?rate|gross[- ]?rev(?:enue)?|COF)\b[^\n<]{0,80}?[\p{Nd}][\p{Nd}.,%\u066b\u066c]*\s*%?/giu,
    'commercial value']];
  let out = html;
  for (const [re, label] of [...SECRETS, ...COMMERCIAL]) {
    if (re.test(out)) { hits.push(label); out = out.replace(re, R); }
  }
  const esc_re = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  // gold-figure residue: scrub the actual VALUE(s) everywhere — the badge only hides the gold CARD, so a
  // figure restated in the Goal/touches must be caught by value, not by an alpha prefix (R3-C2 / D-01).
  for (const fig of goldFigures()) {
    const re = new RegExp(esc_re(fig), 'g');
    if (re.test(out)) { hits.push('gold residue'); out = out.replace(re, R); }
  }
  // DECLARED gold values (v0.17.0, brief-data fence) — CERTAIN: scrub every generated form of each
  // declared literal (the bounded cross-product). ADDITIVE to the best-effort layers above/below.
  for (const g of (declared.gold || [])) {
    for (const form of genForms(g)) {
      if (!form) continue;
      // scrub the RAW form AND its HTML-escaped form: injected prose is esc()'d (& → &amp;, < → &lt; …),
      // so a declared value containing an HTML metachar would render escaped and slip a raw-only regex (RB-v0.26).
      for (const target of new Set([form, esc(form)])) {
        const re = new RegExp(esc_re(target), 'g');
        if (re.test(out)) { hits.push('declared gold residue.'); out = out.replace(re, R); }
      }
    }
  }
  // normalized-numeric residue (R3-R4-D4-1): the exact-string scrub above misses the SAME figure restated
  // with different digit-grouping / symbol / insignificant trailing zeros (gold "1,200,000" vs Goal
  // "12,00,000" — Indian vs Western). Match on a digits-only KEY instead. ≥3 significant digits so a
  // library gold's trivial "0"/"3" is never over-matched (a figure-less gold yields no keys → no scrub).
  const numKey = (s) => { let k = String(s).replace(/[^\d.]/g, ''); if (k.includes('.')) k = k.replace(/0+$/, '').replace(/\.$/, ''); return k; };
  const nDigits = (k) => (k.match(/\d/g) || []).length;
  // A numeric run = an optionally-grouped number with ANY common thousands separator — comma, ASCII space,
  // NBSP (U+00A0), narrow/thin space (U+202F/U+2009), apostrophe (U+2019/U+0027) — where each group AFTER
  // the first is EXACTLY 3 digits (so unrelated adjacent numbers in prose aren't glued) — OR a plain
  // digit/comma run. numKey then collapses EVERY locale formatting of the same value to one digits-only key,
  // so a gold figure restated with different grouping/symbol is caught (R3-R4-D4-1 + R3-R5-D5-01).
  // built from the SAME GROUP_SEPS as genForms (R3 F2 — single source, cannot drift). European period is
  // intentionally NOT here (it is decimal-ambiguous in the best-effort matcher; it lives in genForms output only).
  const SEP = '[' + GROUP_SEPS.map((c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0')).join('') + ']';
  const NUMRUN = new RegExp('\\d{1,3}(?:' + SEP + '\\d{3})+(?:\\.\\d+)?|\\d[\\d,]*(?:\\.\\d+)?', 'g');
  const goldKeys = new Set();
  for (const src of [...goldFigures(), ...((goldBody || '').match(NUMRUN) || [])]) { const k = numKey(src); if (nDigits(k) >= 3) goldKeys.add(k); }
  // seed the normalized layer from DECLARED values too (INV-BRIEF-ADDITIVE / RP-M5): so the best-effort
  // "suspenders" catch an undeclared regrouping EVEN when the Reconciliation section is N/A (the intended
  // hybrid setup — the canonical value lives in the fence, not the gold prose).
  for (const g of (declared.gold || [])) { const k = numKey(g); if (nDigits(k) >= 3) goldKeys.add(k); }
  if (goldKeys.size) {
    out = out.replace(NUMRUN, (m) => {
      const k = numKey(m);
      if (nDigits(k) >= 3 && goldKeys.has(k)) { hits.push('gold residue (normalized)'); return R; }
      return m;
    });
  }
  // never-show VALUES — case-INSENSITIVE (a mis-cased restatement must not slip past exact-substring).
  // Union of the security-block never-show tokens AND any declared via the brief-data fence (v0.17.0).
  for (const v of [...(security().neverShow || []), ...(declared.neverShow || [])]) {
    if (!v) continue;
    for (const target of new Set([v, esc(v)])) {   // raw AND HTML-escaped (a never-show value with & < > " renders escaped) — RB-v0.26
      const re = new RegExp(esc_re(target), 'gi');
      if (re.test(out)) { hits.push('never-show residue'); out = out.replace(re, R); }
    }
  }
  return { out, hits };
}

// ── build ─────────────────────────────────────────────────────────────────────
let html;
if (view === 'brief-body') {
  html = page(HOUSE_CSS, briefBody());
} else if (view === 'brief') {
  // v0.30: no cinematic cover. It was a separate visual world inside a decision page — 13
  // off-theme colours and its own face — and a body fragment published as an Artifact has no
  // place for a 430px full-page hero. `cinematic-hero` stays the bundled skill for launch and
  // marketing assets; that is its job, not this one. `brief` and `brief-body` are now the same
  // page, and `brief-body` is retained as an alias so existing callers keep working.
  html = page(HOUSE_CSS, briefBody());
} else if (view === 'plan-map') {
  html = page(HOUSE_CSS + _pillCss, planMap());
} else if (view === 'review') {
  const r = reviewArtefact();
  html = page(HOUSE_CSS + r.extra, r.body);
} else if (view === 'release-card') {
  const c = releaseCard();
  html = page(HOUSE_CSS + c.extra, c.body);
} else { // cockpit
  const c = cockpit();
  html = page(HOUSE_CSS + c.extra, c.body);
}

// v0.30 INV-5/leak: the scrub used to run for the Brief ONLY, while the plan-map and release-card
// were published too — and gen.mjs's own note calls the unscrubbed copy INV-BRIEF-LOCAL-FULL,
// i.e. deliberately never meant to leave the machine. This build made exactly that copy the
// published one. EXTEND first, refuse second: refusing without extending would have blocked
// precisely the artefacts Features 1-2 must publish.
const SCRUBBABLE = ['brief', 'brief-body', 'plan-map', 'release-card', 'review'];
if (shareable && !SCRUBBABLE.includes(view)) {
  console.error(`gen: REFUSED — '${view}' has no redaction path, so it cannot be published shareable.`);
  console.error('  Add it to SCRUBBABLE and give it a brief-data fence, or publish it locally only.');
  process.exit(3);
}
if (shareable && SCRUBBABLE.includes(view)) {
  // brief-data fence: parsed ONLY on the shareable path (LOCAL never touches it — INV-BRIEF-LOCAL-FULL).
  const bd = parseBriefData(contract);
  if (bd.malformed) {
    // MALFORMED (unclosed OR unparseable body) never fails OPEN: write an error stub (truncating any
    // prior --out so a stale unscrubbed copy can't be shared — RP-m7), then HARD-STOP exit 2. Distinct
    // from "absent"/"none" (best-effort, exit 0) — INV-BRIEF-FAILCLOSED.
    const stub = '<!doctype html>\n<title>brief-data MALFORMED</title>\n<!-- compass-visual: brief-data fence MALFORMED (unclosed or unparseable body) — shareable Brief REFUSED (exit 2). This is NOT a blessed copy. Fix the fence in contract.md. -->\n';
    if (outFile) writeFileSync(outFile, stub);
    else process.stdout.write(stub);
    console.error('compass-visual: brief-data fence MALFORMED (unclosed or unparseable body) — shareable Brief refused (exit 2). Fix the fence in contract.md; the --out copy is an error stub, NOT blessed.');
    process.exit(2);
  }
  const { out, hits } = shareableScrub(html, bd);
  if (hits.length) {
    // Write the fully-SCRUBBED copy (every literal absent) so it is inspectable, then HARD-STOP.
    if (outFile) writeFileSync(outFile, out);
    else process.stdout.write(out);
    console.error(`compass-visual: LEAK GATE HARD-STOP — ${hits.length} hit(s) scrubbed from the shareable Brief: ${[...new Set(hits)].join(', ')}`);
    console.error('  fix the contract (a secret/commercial value does not belong in it) — the shareable copy was scrubbed but is NOT blessed.');
    process.exit(3);
  }
}

// ── v0.29.0 INV-NO-TOKEN — refuse, never ship a placeholder or a silent blank ──
// v0.15-v0.28 emitted `<goal from INDEX>` to the reader because a failed lookup fell
// back to the template's own placeholder text. After the fence fix the failure mode
// CHANGED: a missing field now renders as nothing at all — a blank where the most
// important sentence should be, which is quieter and therefore worse.
//
// A blanket scan for `<... from ...>` is the wrong instrument: a contract may legitimately
// QUOTE a token while discussing it (this very build's contract does), and refusing to
// render that would be a false positive. So the check is precise: a required field that
// fails to resolve emits a distinctive SENTINEL, and the write seam refuses if any
// sentinel survives. Only the generator can produce one, so there are no false positives.
{
  const leaks = [...html.matchAll(/\u27ea missing:([a-z0-9 _-]+)\u27eb/gi)].map((m) => m[1]);
  if (leaks.length) {
    const uniq = [...new Set(leaks)];
    console.error(`compass-visual: REFUSING to write ${outFile || '<stdout>'} — ${uniq.length} required field(s) did not resolve:`);
    for (const f of uniq) console.error(`  ${f} — no source section produced a value`);
    console.error('  A blank here is a silent lie. Fix the source section, or the extractor — do not weaken this check.');
    process.exit(4);
  }
}

// ── v0.31: a page that carries `counted` numbers owes its reader the words, not just the markup.
//
// A marker is invisible to the person the warning is FOR. If any number on this page was worked out
// by reading the build's files — rather than read from a declared data block — the page says so, in
// the sentence the contract pins, next to the numbers it is about.
//
// v0.31 cold read, CR-2 + CR-3. The sentence used to say "numbers marked as counts" — a distinction
// living in an HTML attribute no reader can see ("it never says WHICH numbers, so there's nothing to
// act on") — and it covered only the numbers a reader could already check by eye, leaving the
// unverifiable ones bare. Worse, arming on `counted` alone meant 15 of 116 pages carrying quoted
// numbers and no counted ones printed NO caveat: every number on them unverifiable and unmarked.
// So: arm on either kind, point at something visible, and say what the other numbers are.
const hasCounted = /data-prov="counted"/.test(html);
const hasQuoted = /data-prov="quoted"/.test(html);
const hasDeclared = /data-count="/.test(html);
if (hasCounted || hasQuoted) {
  // How the unchecked numbers got here, named only for the kinds this page actually carries — so the
  // sentence never describes a category that is not on the page, and each branch contains the exact
  // words `unsaid` requires for the kinds present.
  const how = hasCounted && hasQuoted
    ? `they were either ` + COUNTED_NOTE + `, or copied from what someone wrote there`
    : hasCounted
      ? `they were ` + COUNTED_NOTE
      : `they were copied from what someone wrote in this build's files`;
  // The mark earns its place only where it separates one number from another. On a page where
  // nothing is checked, underlining every number distinguishes nothing — so say it in words instead.
  const body = hasDeclared
    ? `Numbers with a dotted underline were not checked against anything: ` + how + `. Any of them `
      + `can be wrong. The numbers without the underline were declared as data by this build, and `
      + `this page is held to them.`
    : `No number on this page was checked against anything: ` + how + `. Any of them can be wrong.`;
  const note = `<div class="prov-note prov-note-inline">` + body + `</div>`;
  // No literal hex fallbacks. Two of them (#8a8a8a, #2a2a2a) were the first colours the house
  // anti-drift gate reported OFF-THEME — a note about honesty that broke the theme check.
  // The affordance the sentence points at. Quiet enough not to shout on every number, distinct
  // enough to be nameable. Applied only when a counted number is actually present, so the page never
  // describes a mark it does not carry.
  // CR-12. This used to be 12px, muted, under a hairline rule — footnote styling, and two
  // independent cold readers skipped it for that reason before its position could matter. It now
  // takes the house's "read this" grammar (the accent left-rule `.b-decide` uses) at body weight in
  // the body's own colour, because it is a claim about every number above it, not an aside.
  const css = `<style>.prov-note{font:400 13px/1.55 var(--ui);color:var(--ink);`
    + `background:var(--surface);border:1px solid var(--line);`
    + `border-left:5px solid var(--accent);border-radius:8px;padding:12px 14px;margin:14px 0}`
    + (hasDeclared ? `[data-prov="counted"],[data-prov="quoted"]{border-bottom:1px dotted var(--mut2)}` : ``)
    + `</style>`;
  // B-1: appended before the footer, this sat AFTER 20+ finding rows on a review page while the
  // reader decides on the numbers ~15 lines in. A caveat the decision-maker never reaches has been
  // published, not delivered — the v0.26 lesson in a different costume. It goes with the numbers:
  // immediately after the facts band, which is where the counts are read.
  if (/<div class="b-facts">/.test(html)) {
    // Insert directly after the facts band, before whatever follows it.
    html = html.replace(/(<div class="b-facts">[\s\S]*?)(<div class="b-label"|<div class="foot">)/,
      (m, band, next) => band + note + next);
  } else if (/<div class="foot">/.test(html)) {
    html = html.replace(/<div class="foot">/, note + '<div class="foot">');
  } else if (html.includes('</body>')) {
    html = html.replace('</body>', note + '</body>');
  } else {
    html += note;
  }
  html = html.includes('</head>') ? html.replace('</head>', css + '</head>') : css + html;
}

// A surviving sentinel is a private-use character sitting on a page a person will read, and it means
// some path built text without going through `txt()`. Refuse rather than ship the glyph.
if (CNT_A_RE.test(html)) {
  console.error('compass-visual: REFUSING — a counted-number sentinel reached the output, so some text '
    + 'path bypassed txt(). The number would render as a private-use glyph. Fix the path, not this check.');
  process.exit(5);
}

if (outFile) { writeFileSync(outFile, html); process.stderr.write(`wrote ${outFile} (${html.length} bytes)\n`); }
else process.stdout.write(html);
