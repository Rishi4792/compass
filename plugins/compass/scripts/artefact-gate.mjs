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
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

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
// A missing `--steps` used to skip this check AND the VERIFY check in silence. `claimed-count-matches`
// in this same file refuses when `--source` is absent; a gate that quietly checks less because it was
// given less is the softest failure there is.
if (!wantSteps && /class="b-step"/.test(html)) {
  check('counts-match', false,
    'this page renders steps but --steps was not given, so the count could not be checked. Pass --steps N.');
}
if (wantSteps) {
  const rendered = (html.match(/class="b-step"/g) || []).length;
  // v0.31: every number a page states now sits inside a provenance marker, so the header reads
  // `<b><span data-prov="counted">20</span></b> steps`. Matching the raw markup found nothing and
  // the gate reported `header says ?` on a page that plainly says 20 steps. Strip tags between the
  // digits and the noun — the gate is asserting what the page SAYS, not how it is marked up.
  // Keep the <b> anchor — stripping every tag let this match the FOOTER, or a build directory
  // literally named "20 steps", and pass a page whose header was wrong. Only the provenance marker
  // needs to be transparent here.
  const plain = html.replace(/<(?!\/?b\b)[^>]+>/g, '');
  const header = (plain.match(/<b>\s*(\d+)\s*<\/b>\s*steps?\b/) || [, ''])[1];
  check('counts-match', String(rendered) === String(wantSteps) && String(header) === String(wantSteps),
    `header says ${header || '?'}, body renders ${rendered}, --steps was given as ${wantSteps} (this gate does not read the step count from --source)`);

  // The plan skill states this gate "proves that every step carries its VERIFY". It did not — it
  // compared two integers, and passed a page showing 30 ticked boxes over 30 empty proof slots.
  // Make the claim true.
  const verifyBlocks = [...html.matchAll(/class="verify">([\s\S]*?)<\/div>/g)]
    .map((m) => m[1].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim());
  // `n/a` is exactly 3 characters and cleared a `length < 3` bar — replacing all 30 VERIFY blocks
  // with it passed. A proof is a command; require something command-shaped and long enough to be one.
  const emptyVerify = verifyBlocks.filter((v) => {
    const body = String(v || '').replace(/^verify\s*[\u2014-]?\s*/i, '').trim();
    // Reject PLACEHOLDERS by name, not by length. A length floor of 8 flagged `cmd 1` — a real
    // command in the twenty-steps fixture — so the gate refused correct output, which is how a
    // gate gets switched off. `n/a` is caught because it is on the list, not because it is short.
    return !body || /none recorded/i.test(body) || /^(n\.?\/?a\.?|none|nil|tbd|todo|pending|deferred|-+|\?+)$/i.test(body) || body.length < 3;
  });
  check('every-step-carries-its-verify', verifyBlocks.length > 0 && emptyVerify.length === 0,
    `${emptyVerify.length} of ${verifyBlocks.length} steps show no VERIFY command, on a page whose caption says a box is only ticked when its VERIFY has run`);
}

// 6 ── nothing was cut mid-word. A hard character slice leaves a word fragment at the
// boundary; a real split lands on a word or sentence edge.
const cutMarks = (html.match(/[\w)]\u2026(?=\s*<)|[\w)]\.\.\.(?=\s*<)/gi) || []).length;
check('no-truncation', cutMarks === 0, `${cutMarks} text node(s) end in an ellipsis cut`);

// 7 ── the artefact is not older than the source it renders.
if (source && existsSync(source)) {
  const a = statSync(file).mtimeMs;
  const b = statSync(source).mtimeMs;
  check('fresh', a >= b, `artefact is ${Math.round((b - a) / 1000)}s older than ${source} — regenerate it`);
}

// ── 8 ── v0.30 --copy: the checks a STRUCTURAL gate cannot make.
// The structural gate passed a page that printed its goal three times, cut two fields mid-word,
// mashed two table headings into one word, and claimed 11 invariants while showing 2. Every one
// of those is invisible to "are the four bands present" and obvious to a reader.
if (argv.includes('--copy')) {
  const text = html.replace(/<style[\s\S]*?<\/style>/g, ' ').replace(/<[^>]+>/g, ' ')
    .replace(/&[a-z]+;/g, ' ').replace(/\s+/g, ' ').trim();

  // duplicated sentences — the defect the cold reader named FIRST
  // Normalise before comparing: the second copy of a repeated sentence is usually preceded by its
  // card label ("BUILD WHAT Rebuild the artefact layer…"), so a raw string compare misses exactly
  // the duplication a reader sees. Drop a leading run of ALL-CAPS label words and lowercase.
  const norm = (x) => x.replace(/^(?:[A-Z][A-Z']*\s+){1,4}/, '').toLowerCase().replace(/[^a-z0-9 ]/g, '').trim();
  // Segment on BLOCK boundaries, then on sentence punctuation inside each block. Splitting only on
  // /(?<=[.?!])\s+/ meant a page with no sentence-final punctuation yielded ONE chunk, so nothing
  // could ever be a duplicate — and card values, scope-ladder bullets and headings are routinely
  // unpunctuated. The same 60-char line printed three times passed; adding full stops to it failed.
  // A check that only fires on text that happens to end in a period is not a check.
  // Blocks are found STRUCTURALLY, not by an allow-list of tags and classes. The old list covered
  // 6 tags and 4 div classes, so the same sentence printed twice in two <span class="chip"> was
  // invisible while the identical duplicate in a <p> failed — and the Release Card, which renders
  // none of the listed classes, could not be checked at all.
  const blocks = [];
  for (const m of html.matchAll(/<(p|li|td|th|h[1-6]|figcaption|blockquote|span|div|dd|dt|figure|caption|summary)\b[^>]*>([\s\S]*?)<\/\1>/gi)) {
    // skip wrappers: a block that still contains another block is a container, not a text node
    if (/<(p|li|td|th|h[1-6]|span|div|dd|dt)\b/i.test(m[2])) continue;
    blocks.push(m[2]);
  }
  const flat = (x) => x.replace(/<[^>]+>/g, ' ').replace(/&[a-z]+;/g, ' ').replace(/\s+/g, ' ').trim();
  const sentences = (blocks.length ? blocks.map(flat) : [text])
    .flatMap((b) => b.split(/(?<=[.?!])\s+/))
    .map((x) => x.trim()).filter((x) => x.length > 40);
  const seen = new Map();
  for (const x of sentences) { const k = norm(x); if (k.length > 40) seen.set(k, (seen.get(k) || 0) + 1); }
  const dupes = [...seen.entries()].filter(([, n]) => n > 1);
  check('no-duplicated-sentence', dupes.length === 0,
    `${dupes.length} sentence(s) printed more than once: ${dupes.slice(0, 2).map(([x, n]) => `"${x.slice(0, 48)}…" ×${n}`).join(' · ')}`);

  // adjacent headings that render as one word — two <th>/<div> labels with no separator
  const mashed = [...html.matchAll(/<(th|div)[^>]*>([A-Z][A-Z ]{3,})<\/\1>\s*<\1[^>]*>([A-Z][A-Z ]{3,})<\/\1>/g)];
  check('no-mashed-headings', mashed.length === 0,
    `${mashed.length} adjacent uppercase heading pair(s) with no separator, e.g. "${mashed[0]?.[2]}${mashed[0]?.[3]}"`);

  // a field that ends mid-word: a letter immediately before a tag, with no terminal punctuation
  // Scan every field class that carries prose, not just `v`. Four real mid-thought cuts sat in
  // `b-det` and `b-ttl` on a Plan Map this check passed — it was looking at one of the three
  // places a field can be.
  // Flatten inner tags before testing. The old regex was `class="v">([^<]{40,})</div>`, which
  // matches nothing the moment a field contains an inline tag — and `plan-map.html` ships
  // `<div class="v"><code>git revert</code> of the release commit.` today, so the check was off
  // for that field. A 40-character floor also let short cuts through, and any field ending in the
  // word "more" was exempted outright rather than only the generator's own "— and N more".
  const flatBlock = (h) => h.replace(/<[^>]+>/g, ' ').replace(/&[a-z]+;/g, ' ').replace(/\s+/g, ' ').trim();
  const classed = (cls) => [...html.matchAll(new RegExp(`class="${cls}"[^>]*>([\\s\\S]*?)<\\/div>`, 'g'))]
    .map((m) => flatBlock(m[1])).filter(Boolean);
  // "Looks like a list of things, not a sentence": mostly path/identifier tokens joined by
  // separators, and no sentence-like word run at the end.
  // A LIST is exempt from the terminal-punctuation rule: lists do not end in full stops, and six
  // correct pages were refused for values byte-identical to their source (`…README.md,CHANGELOG.md,
  // manifests`). An attempt to distinguish "complete list" from "cut list" by whether the last item
  // has a file extension was itself wrong — `manifests` is a real, whole word. The two are not
  // mechanically distinguishable, so the punctuation rule does not apply to lists at all, and a
  // truncated list is caught by the `(continues)` marker the generator writes instead. This is a
  // stated limit, not an oversight: a list cut exactly at an item boundary reads as complete.
  const isListy = (v) => {
    if (!/[/,+;]/.test(v) || (v.match(/[/,+;]/g) || []).length < 2) return false;
    if (/\s(the|a|an|is|are|was|were|and then|so that)\s/i.test(v)) return false;
    // A list cut mid-PATH is not ambiguous — `…,plugins/compass/skills/build/SKI` stops inside a
    // path segment and a reader can see it. That is different from `…,manifests`: a whole word with
    // no slash, which is why an earlier extension-only test wrongly refused six correct pages.
    // Requiring a slash to call something a path separates the two.
    const segs = v.split(/[,;+]/).map((x) => x.trim()).filter(Boolean);
    const tail = segs[segs.length - 1] || '';
    if (/\//.test(tail) && !/\.[a-z0-9]{1,5}$/i.test(tail) && !/\/$/.test(tail)) return false;
    return true;
  };
  const exempt = (v) => /\(continues\)$/.test(v) || /— and \d+ more$/.test(v);
  const CONTINUATION = /[\u2026]$|\.\.\.$|\b(and|or|but|the|a|an|of|to|in|on|for|with|before|after|that|which|is|are|was|were|from|by|as|its|their|no|not)$/i;
  const cuts = [
    // `v` fields and <p> paragraphs are generated PROSE: no terminal punctuation means a cut.
    // The Release Card renders neither `v` nor `b-det`, so with a class-only rule a hard slice in
    // its lede paragraph could not be seen by any check on the page.
    // A LIST or PATH value legitimately ends without punctuation — `review-plan/review-build/plan
    // SKILL.md + smoke.sh + recon.sh + selftest.sh` is complete and byte-identical to its source.
    // Six correct pages were refused for it, and a gate that refuses correct work gets switched off.
    ...classed('v').filter((v) => v.length >= 20 && !exempt(v) && !isListy(v) && /[^.!?)\]:]$/.test(v)),
    ...[...html.matchAll(/<p\b[^>]*>([\s\S]*?)<\/p>/gi)].map((m) => flatBlock(m[1]))
      .filter((v) => v.length >= 20 && !exempt(v) && /[^.!?)\]:]$/.test(v)),
    // everything else a reader reads: a bare ellipsis, or a stop on a word no line ends on.
    ...blocks.map(flatBlock).filter((v) => v.length >= 20 && !exempt(v) && CONTINUATION.test(v)),
  ];
  check('no-mid-field-cut', cuts.length === 0,
    `${cuts.length} field(s) end without punctuation or a stated continuation: "${(cuts[0] || '').slice(-44)}"`);

  // ── Internal code on the reader's page (INV-9). ────────────────────────────────────────────
  // `compass.sh copy-gate` checks the reader-copy BLOCK in the contract. gen.mjs renders the block
  // UNION whatever it scrapes from contract prose for fields the block does not cover — so a
  // contract with a clean block still put "INV-ORIENT: a front-door invocation with a Compass
  // state-root; see gen.mjs:385" on the page as its first field, while copy-gate printed
  // "reader copy carries no internal codes". The gate's scope was the source; the reader's scope
  // is the page. Check the page.
  //
  // Scoped per INV-9: NOT the invariant table (where the codes are the subject a reader came for),
  // and NOT code shown as code. A guard that fires on correct work gets disabled within a week.
  try {
    const patFile = join(dirname(fileURLToPath(import.meta.url)), 'fixtures', 'copy', 'jargon.txt');
    const pats = readFileSync(patFile, 'utf8').split('\n')
      .map((x) => x.trim()).filter((x) => x && !x.startsWith('#'));
    if (!pats.length) throw new Error('jargon pattern file is empty');
    let readerHtml = html
      .replace(/<style[\s\S]*?<\/style>/gi, ' ')
      .replace(/<script[\s\S]*?<\/script>/gi, ' ')
      .replace(/<code[\s\S]*?<\/code>/gi, ' ')
      // the invariant table: a <table> that carries INV- ids in its key column
      .replace(/<table[^>]*>[\s\S]*?<\/table>/gi, (t) => (/class="k">\s*INV-/i.test(t) ? ' ' : t))
      // Band 4's step details and finding rows are QUOTED SOURCE — plan.md's own step text and the
      // ledger's own rows. INV-9 as contracted scopes the no-internal-code rule to model-authored
      // reader copy and explicitly exempts quoted text, so policing them here would be a gate
      // firing outside its own invariant. They are still cleaned of pure ADDRESSES by gen.mjs
      // (file:line, cmd_* names carry nothing a reader can use); what remains is a real tension
      // between "quoted text is exempt" and "a reader should not meet undecodable words", and it
      // is raised for the human sign-off rather than settled here by widening an invariant.
      .replace(/<div class="b-ttl"[^>]*>[\s\S]*?<\/div>/gi, ' ')
      .replace(/<div class="b-det"[^>]*>[\s\S]*?<\/div>/gi, ' ')
      .replace(/<div class="verify"[^>]*>[\s\S]*?<\/div>/gi, ' ');
    const readerText = readerHtml.replace(/<[^>]+>/g, ' ').replace(/&[a-z]+;/g, ' ').replace(/\s+/g, ' ').trim();
    const hits = [];
    for (const pat of pats) {
      // Case-insensitive: reader copy is sentences, and these terms appear capitalised at the
      // start of one. Seven patterns compiled without the flag caught nothing sentence-initial.
      const m = readerText.match(new RegExp(pat, 'i'));
      if (m) hits.push(m[0]);
    }
    check('no-internal-code-on-the-page', hits.length === 0,
      `${hits.length} internal code(s) reached reader-facing copy: ${hits.slice(0, 3).map((h) => `"${h}"`).join(' · ')}`);
  } catch (e) {
    // A check that cannot run must never read as a pass — the founding rule of this build.
    check('no-internal-code-on-the-page', false, `could not run the jargon check: ${e.message}`);
  }

  // ── An EMPTY reader field (INV-9). ─────────────────────────────────────────────────────────
  // Seven pages shipped a blank "What changes" box — the first fact on the page that asks
  // "Approve this plan?" — and every check passed, because an empty string trips no rule about
  // punctuation, duplication or jargon. A labelled box with nothing in it is the clearest possible
  // defect and was the only one nothing looked for.
  // FLATTEN and DECODE before judging. The check fired only on a literal `<div class="v"></div>`,
  // so `&nbsp;`, a lone em-dash, or an empty `<code></code>` all passed — one character away from
  // the defect it was written for, and reachable from a reader-copy block writing `build-what: —`.
  const emptyFields = [...html.matchAll(/<div class="k">([^<]*)<\/div><div class="v">([\s\S]*?)<\/div>/g)]
    .filter((m) => {
      const v = m[2].replace(/<[^>]+>/g, ' ')
        .replace(/&nbsp;/gi, ' ').replace(/&[a-z]+;/gi, ' ')
        .replace(/[\u00a0\u2013\u2014\-–—·:;,.]/g, ' ').trim();
      return !/\w/.test(v);
    })
    .map((m) => m[1].trim());
  check('no-empty-field', emptyFields.length === 0,
    `${emptyFields.length} labelled field(s) render with no value: ${emptyFields.slice(0, 3).map((f) => `"${f}"`).join(' · ')}`);

  // An asserted count must equal what the SOURCE declares.
  // This used to compare the claim against `<td class="k">INV-` rows and carried an escape hatch:
  // `rendered === 0 || …`. plan-map is the only view that prints the claim and it renders zero such
  // rows, so the escape hatch disabled the check on precisely the one page it was written for — it
  // could not go red at all. Faking the number 1 → 11 still passed. Ground truth is the contract,
  // not how many rows a given layout happens to show.
  // Case-sensitive, digits-only, and requiring the word to come last: "11 INVARIANTs",
  // "eleven invariants" and "11 invariant checks" all sailed past a check whose whole job is to
  // stop a wrong number reaching the page.
  const WORDNUM = { one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
    eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17,
    eighteen: 18, nineteen: 19, twenty: 20 };
  const claimRe = /(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)(?:\s+\w+){0,2}\s+invariants?\b/i;
  // EVERY claim, not just the first — but matched PER BLOCK, never across the flattened page.
  // Joining every element into one string let the tail of one element run into the head of the
  // next: "…0" + "No INVARIANT may be recorded…" matched as a claim of zero invariants, and the
  // gate told a correct page it was wrong. A claim is a sentence someone wrote, not a seam.
  // Scan the WHOLE page, but flatten it with a SEPARATOR so a match cannot cross an element seam.
  // Joining elements with a space let "…0" run into "No INVARIANT may be…" and read as a claim of
  // zero. Restricting the scan to leaf blocks fixed that and introduced the opposite blindness —
  // a claim inside a container block stopped being seen at all, so the check silently skipped the
  // very fixture written to prove it fires. A separator gets both: nothing is skipped, and nothing
  // matches across a boundary, because the separator is neither a word character nor whitespace.
  // INLINE tags are not seams. `<b>13</b> invariants` is one claim a person reads as one phrase,
  // and marking every tag as a boundary broke it — the check then silently stopped running on the
  // Brief. Only BLOCK boundaries separate one statement from another.
  const INLINE = 'b|i|em|strong|code|span|small|sup|sub|u|a|mark|abbr|kbd|var|time';
  const seamText = html
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    // Band 4 is QUOTED SOURCE — plan step text and ledger rows — scoped out here for exactly the
    // reason the jargon scan scopes it out: a sentence the plan wrote about a past defect ("11
    // invariants shown as 2") is not a claim this page is making about itself. Reading it as one
    // produced three phantom claims and refused four correct builds.
    .replace(/<div class="b-ttl"[^>]*>[\s\S]*?<\/div>/gi, ' ')
    .replace(/<div class="b-det"[^>]*>[\s\S]*?<\/div>/gi, ' ')
    .replace(/<div class="verify"[^>]*>[\s\S]*?<\/div>/gi, ' ')
    .replace(new RegExp(`</?(?:${INLINE})\\b[^>]*>`, 'gi'), '')
    .replace(/<[^>]+>/g, ' \u00b6 ')
    .replace(/&[a-z]+;/g, ' ')
    .replace(/[ \t\n\r]+/g, ' ')
    .trim();
  // A QUOTED phrase is not a claim the page makes about itself. This page quotes a past defect —
  // "11 invariants shown as 2" — and reading that as an assertion produced three phantom claims.
  const unquoted = seamText.replace(/[\u201c"'][^\u201d"']{0,160}[\u201d"']/g, ' \u00b6 ');
  // A word-number followed by the SINGULAR is English, not a count: "missing one INVARIANT" is a
  // sentence, "eleven invariants" is a claim. Digits keep both forms, because "1 invariant" on a
  // page that renders one really is a claim.
  const allClaims = [...unquoted.matchAll(new RegExp(claimRe.source, 'gi'))]
    .filter((m) => /^\d+$/.test(m[1]) || /invariants\b/i.test(m[0]));
  const claimRaw = allClaims[0] || null;
  const claim = claimRaw
    ? [claimRaw[0], String(/^\d+$/.test(claimRaw[1]) ? Number(claimRaw[1]) : WORDNUM[claimRaw[1].toLowerCase()])]
    : null;
  if (claim) {
    const srcs = [];
    const si = argv.indexOf('--source');
    if (si > -1 && argv[si + 1]) {
      srcs.push(argv[si + 1]);
      const sib = argv[si + 1].replace(/[^/]+$/, 'contract.md');
      if (sib !== argv[si + 1]) srcs.push(sib);
    }
    const ids = new Set();
    let read = 0;
    for (const f of srcs) {
      let t; try { t = readFileSync(f, 'utf8'); } catch { continue; }
      read++;
      // An id starts UPPERCASE or a digit: `**INV-gated:**` is prose meaning "invariant-gated",
      // not an id, and counting it told a correct page it was one short.
      // The character class omitted `-`, so `**INV-MILESTONE-DELIVERY**` counted as `INV-MILESTONE`
      // and collapsed with its siblings. The gate then told 13 of 28 builds their page claimed more
      // invariants than the contract declares — the page was right and the gate was wrong, on every
      // view. A gate that refuses correct work is the one that gets switched off.
      for (const m of t.matchAll(/\*\*(INV-[A-Z0-9][A-Za-z0-9-]*)/g)) ids.add(m[1]);
    }
    if (!read) {
      // Never a silent pass. If the ground truth was not supplied, say the check did not run.
      check('claimed-count-matches', false,
        `page claims ${claim[1]} invariants but no --source was given, so the claim could not be checked against anything`);
    } else {
      const WN = WORDNUM;
      const nums = allClaims.map((m) => (/^\d+$/.test(m[1]) ? Number(m[1]) : WN[m[1].toLowerCase()]));
      const wrong = nums.filter((n) => n !== ids.size);
      check('claimed-count-matches', wrong.length === 0,
        `page makes ${nums.length} invariant-count claim(s) (${nums.join(', ')}); the source declares ${ids.size}`);
    }
  }
}

// ── v0.32.0 S11, INV-DISCLOSE-UNVERIFIED — the PAGE half ──────────────────────────────────────
// Contract §4: proving independence is impossible in this environment and Compass has stopped
// claiming it can, so every review page carries the disclosure. This refuses one that does not.
// The branch a page took is RECORDED either way (`review-disclosure` vs `review-disclosure-na`),
// because a rule that silently skips is indistinguishable from a rule that passed — and this build
// has already found four assertions scoring over an empty set.
{
  // THE VIEW, not the kicker. This matched the display string "Compass · Review", so renaming the
  // kicker to "Compass · Findings" in the same edit that strips the disclosure made this record a
  // PASS for a review page that says nothing — found by an independent reviewer. The page does not
  // get to decide whether the rule applies to it. The kicker is kept as a FALLBACK so a page from an
  // older generator, which has no meta field, is still judged rather than waved through.
  const _mv = (html.match(/<meta[^>]*name=["']compass-view["'][^>]*content=["']([^"']*)["']/i) || [])[1];
  const isReview = _mv !== undefined
    ? _mv.toLowerCase() === 'review'
    : /Compass\s*(?:·|&middot;|&#183;)\s*Review/i.test(html);
  const said = /this review was NOT independently verified/i.test(html);
  if (isReview) {
    check('review-disclosure', said,
      'a review page must say "this review was NOT independently verified" — contract §4 deleted the claim that independence can be proven here, and a page that stays silent reads as though it was');
  } else {
    pass.push('review-disclosure-na');
  }
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
