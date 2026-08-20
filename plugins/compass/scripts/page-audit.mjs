#!/usr/bin/env node
// THE page auditor. One implementation, called by the gold's loop AND by the gold's positive
// control — which is the point.
//
// Review-1 round 4 (R4-C8) found the previous control was a *different implementation* from the
// loop it was supposed to guard: the loop stripped <style> and the control didn't, the loop matched
// a double-quoted attribute literal and the control fed itself a hardcoded string. So the control
// printed "fires" on every single broken run, including the runs where the loop was returning a
// pass it should not have. A control over code the checker does not execute proves nothing.
//
// Both callers now run these exact functions on their exact inputs.

// There is NO noun list any more, and that is the point.
//
// Round 5 measured what noun-adjacency was worth as a proxy for "a number that makes a claim about
// this build's data": it saw **12.5%** of the numeric tokens on the page (1,115 of 8,950), and
// **6.8%** of what it DID demand were not data at all — it wanted a "counted by reading" label on
// `v0.28.0 SHIPPED`, on `(INV-5 row`, on `a G1 or G2 gate`. Forcing that label onto a version string
// is not a technicality; it is a false statement to the reader, printed by the gate meant to stop
// false statements. And the proxy was trivially escaped: inserting the single word "total" between
// number and noun cut the demand from 1041 to 126, and a zero-width space cut it to 0 while
// rendering identically.
//
// So the question is answered directly instead of guessed at: **a number is a claim about this
// build's data if it CHANGES when the build's data changes.** The gold renders each page twice, from
// the real state files and from a mutated copy, and every number that moved must be marked. A
// version string does not move. A finding ID does not move. A count does.
//
// This has a property the proxy never had: it cannot demand a label on something that is not data,
// because a number that responded to the data IS data. Its recall is a floor, not a guess - a number
// the mutation did not happen to move is simply not yet proven to be a claim, and `mutations` below
// is widened when a reviewer finds one that hides.
const M1 = "", M2 = "";

// EVERY Unicode decimal digit folds to ASCII. `\p{Nd}` is the whole class, so this cannot be
// escaped by finding one more script the previous fix did not list — which is exactly how the U+200B
// fix fell: it enumerated an input instead of closing the shape, and Arabic-Indic digits walked
// through it (303 -> 0, EXIT 0, all controls green). Verified against Arabic-Indic, Devanagari,
// fullwidth, math-bold and ASCII.
export const asciiDigits = (x) => x.replace(/\p{Nd}/gu, (c) => {
  let base = c.codePointAt(0);
  while (base > 0 && /\p{Nd}/u.test(String.fromCodePoint(base - 1))) base--;
  return String(c.codePointAt(0) - base);
});

// A character reference may not decode to a control character: that is how the walk was hijacked.
const safeCp = (n) => (!Number.isFinite(n) || n < 0x20 || n === 0x7f ? " " : String.fromCharCode(n));
const decode = (s) => s
  .replace(/&#(\d+);/g, (_, d) => safeCp(+d))
  .replace(/&#x([0-9a-f]+);/gi, (_, d) => safeCp(parseInt(d, 16)))
  .replace(/&nbsp;/gi, " ").replace(/&amp;/gi, "&");

// Attribute matching is deliberately quote-agnostic. R4-C2: the old check matched the raw literal
// `data-prov="counted"`, so the identical violation written with single quotes was invisible to it
// and 140 broken pages reported clean.
const ATTR = (name) => new RegExp(`data-${name}\\s*=\\s*["']?([a-zA-Z0-9._-]+)`);

/**
 * Split a page into its marked regions and the numbers a reader sees.
 *
 * v6 SIMPLIFICATION. Five review rounds were spent trying to INFER, from outside, which numbers on a
 * page are claims about the build's data — first by the noun sitting next to them (12.5% recall,
 * 6.8% false demands), then by re-rendering each page from a mutated twin and diffing (35.6% recall,
 * 19% false demands from an environment artefact, plus an alignment that blamed the wrong occurrence
 * when a page repeated a value). Both are heuristics, and a heuristic at the sink cannot be made
 * exact.
 *
 * The generator KNOWS which numbers it computed. Instrumenting at the source turns an inference
 * problem into a bookkeeping one: every number gen.mjs prints goes through one function that marks
 * it with WHAT IT IS. The check then has no vocabulary, no twin, no alignment and no recall — it is
 * a containment test: every digit run a reader sees sits inside a marker, or it does not.
 *
 * `literal` is what makes this honest rather than merely convenient. A version, a date, an issue id
 * is marked as a literal — a number that claims nothing — so the page carries a complete account of
 * every number on it, and no number has to be mislabelled a count to satisfy the rule.
 */
// Bidi controls are `\p{Cf}`, so the auditor stripped them — while a browser OBEYS them and paints
// the digits in a different order. 207 in the markup, 702 on the screen, every counter zero. These
// are not formatting noise to normalise away; they are instructions to the eye, and a page that
// contains one is a page whose numbers cannot be trusted to read as written.
export const BIDI = /[\u202a-\u202e\u2066-\u2069\u200f\u200e]/;

export function auditPage(raw) {
  // R7-C1: the sentinels are IN-BAND, and `decode()` turned `&#1;` into the OPEN sentinel — so one
  // numeric character reference anywhere in the page made depth permanently >= 1 and EVERY number
  // read as marked, with ZERO markers on the page. Full gold, exit 0, all controls green, and
  // U+0001 renders as nothing so the page a reader sees was unchanged. Nothing from the input may
  // ever be a sentinel.
  raw = String(raw).replace(/[\u0001\u0002]/g, " ");
  let css = "";
  for (const st of raw.matchAll(/<style[\s\S]*?<\/style>/g)) {
    for (const c of st[0].matchAll(/content\s*:\s*(["'])([\s\S]*?)\1/g)) css += " " + c[2];
    // A CSS counter paints a number the markup never contains as a digit: the value sits in
    // `counter-reset`, and `content: counter(x)` renders it. Harvest the seed values too.
    for (const c of st[0].matchAll(/counter-(?:reset|increment)\s*:\s*([^;}]*)/gi)) css += " " + c[1];
  }

  // <head> is browser chrome, not the page. A <span> inside <title> renders literally in the tab,
  // so scanning it demanded a marker that could not honestly be placed. The <title> still carries
  // the build slug, which is not a claim about the build's data.
  // <title> is dropped only where it IS chrome — inside <head>. An `<svg><title>` is shown to the
  // reader as a tooltip, so it is SCANNED — but as spoken text, not body text: it cannot hold a
  // marker any more than an attribute can, so its numbers must already be marked where they show.
  // Harvest titles from the BODY ONLY. Collecting them from `raw` swept in the <head> <title>,
  // which is browser chrome and was deliberately excluded a few lines below — so the tab caption
  // "Contract — always-clarity-v0-28 · v4" contributed the digits 0, 28 and 4 as numbers the page
  // was said to "speak", and 13 of those went unaccounted for across the corpus.
  const _noHead = raw.replace(/<head[\s\S]*?<\/head>/i, " ");
  let svgTitles = "";
  for (const t of _noHead.matchAll(/<title\b[^>]*>([\s\S]*?)<\/title>/gi)) svgTitles += " " + t[1];
  let body = _noHead.replace(/<title\b[^>]*>[\s\S]*?<\/title>/gi, " ")
                .replace(/<style[\s\S]*?<\/style>/g, " ")
                .replace(/<script[\s\S]*?<\/script>/g, " ");

  // Wrap each marked element's WHOLE inner text in sentinels, so every digit inside it — not just
  // the first — counts as covered. One marker on `v0.28.0` covers all three of its runs.
  const els = [];
  const MARK = /<([a-zA-Z][a-zA-Z0-9]*)([^>]*?data-(?:count|prov)\s*=\s*["']?[a-zA-Z0-9._-]+[^>]*)>([\s\S]*?)<\/\1\s*>/gi;
  let nestedSeen = 0;
  body = body.replace(MARK, (full, tag, attrs, inner) => {
    // A marker inside a marker, detected from the inner content itself. The previous regex tried to
    // spot the pair in the raw text and any intervening `</b>` defeated it — while the outer
    // non-greedy match swallowed the inner element, so its value was never checked at all.
    if (/data-(?:count|prov)\s*=/i.test(inner)) nestedSeen++;
    const it = asciiDigits(decode(inner.replace(/<[^>]+>/g, " ")).normalize("NFKC").replace(/[\p{Cf}\p{Mn}]/gu, ""));
    const all = it.match(/\d[\d,]*/g) || [];
    const f = ATTR("count").exec(attrs), p = ATTR("prov").exec(attrs);
    const kind = f ? "declared" : (p ? p[1] : "");
    els.push({ nums: all, num: all[0], field: f ? f[1] : null, prov: p ? p[1] : null, kind });
    // The sentinel carries the KIND, so a digit run's marker is known by POSITION rather than by
    // value. Matching `literal` by value meant one literal `5` anywhere on the page tainted every
    // other `5` that moved — a false accusation, and the converse hid real ones.
    return M1 + (kind === "literal" ? "L" : kind === "quoted" ? "Q" : "C") + it + M2;
  });

  const norm = (x) => asciiDigits(decode(x).normalize("NFKC").replace(/[\p{Cf}\p{Mn}]/gu, "")).replace(/[ \t]+/g, " ");

  // Attributes that a person actually perceives — the alt text, the tooltip, the label a screen
  // reader speaks — were stripped with their tag and so were invisible to the containment rule. A
  // number a reader HEARS is a number a reader sees.
  let spoken = "";
  for (const a of body.matchAll(/\s(?:alt|title|aria-label)\s*=\s*(["'])([\s\S]*?)\1/gi)) spoken += " " + a[2];
  spoken += " " + svgTitles;

  const text = norm(body.replace(/<[^>]+>/g, " ")) + " " + norm(css);
  // An attribute cannot hold a <span>, so it cannot carry its own marker. The honest rule is that
  // whatever it says must ALREADY be marked in the visible body — an aria-label describing the
  // diagram a reader can see states numbers that are marked where they are shown. A number that
  // appears ONLY in an attribute is stated to a screen-reader user and to nobody else, and nothing
  // on the page says where it came from.
  const spokenNums = (norm(spoken).match(/\d[\d,]*/g) || []).map((x) => x.replace(/,/g, ""));

  // Every digit run a reader sees, each flagged by whether a marker contains it. Containment is
  // decided by sentinel depth, so nothing depends on a word list or on a second render.
  const seq = [];
  const stack = [];
  for (const m of text.matchAll(/\u0001[LQC]|\u0002|\d[\d,]*/gu)) {
    const t = m[0];
    if (t.charCodeAt(0) === 1) { stack.push(t[1] === "L" ? "literal" : t[1] === "Q" ? "quoted" : "counted"); continue; }
    if (t === M2) { stack.pop(); continue; }
    seq.push({ value: t.replace(/,/g, ""), marked: stack.length > 0, kind: stack[stack.length - 1] || null });
  }
  return { els, seq, text, spokenNums, nestedSeen };
}

/** Score one page under the rule its build qualifies for. */
// The words a legacy page must actually say. A marker in the markup is invisible to the person the
// warning is FOR, so the phrase has to appear in the rendered text of any page carrying markers.
export const PHRASE = "counted by reading this build's files";
// The same requirement for the OTHER unverifiable kind. A `quoted` number was copied out of prose
// someone wrote; the reader can check it no more easily than a count, and until v0.31's cold read
// nothing obliged the page to say so — `unsaid` scored counts only, so 15 of 116 pages stated quoted
// numbers under no caveat at all and the gold still read green.
export const QUOTED_PHRASE = "copied from what someone wrote";

/**
 * Which numbers on this page are CLAIMS ABOUT THE BUILD'S DATA?
 * The ones that changed when the build's data changed. Compared by position between the real render
 * and a render of a mutated copy. A number the mutation did not move is not proven to be a claim, so
 * this is a floor rather than a guess — and it can never demand a label on a version string, because
 * a version string does not respond to the data.
 */
export function dataClaims(raw, mutatedRaw) {
  const a = auditPage(raw).seq;
  if (mutatedRaw === undefined || mutatedRaw === null) return { claims: a.map((_, i) => i), a };
  const b = auditPage(mutatedRaw).seq;

  // Aligned by LONGEST COMMON SUBSEQUENCE, not by index. Index alignment looked right until the
  // mutation moved a plan step from "to go" to "done": two numbers left the page, every later
  // number shifted one position, and the comparison read the shift as 98 numbers having "changed".
  // It reported 1289 claims where the truth was a handful — worse than the proxy it replaced.
  // An LCS match means the same number is still there in the same order, so only numbers that
  // genuinely have no counterpart are claims.
  const av = a.map((x) => x.value), bv = b.map((x) => x.value);
  const n = av.length, mLen = bv.length;
  const L = Array.from({ length: n + 1 }, () => new Uint16Array(mLen + 1));
  for (let i = n - 1; i >= 0; i--)
    for (let j = mLen - 1; j >= 0; j--)
      L[i][j] = av[i] === bv[j] ? L[i + 1][j + 1] + 1 : Math.max(L[i + 1][j], L[i][j + 1]);

  const claims = [];
  let i = 0, j = 0;
  while (i < n && j < mLen) {
    if (av[i] === bv[j]) { i++; j++; }            // survived the mutation unchanged: not a claim
    else if (L[i + 1][j] >= L[i][j + 1]) { claims.push(i); i++; }  // present only in the real page
    else j++;                                     // present only in the mutated page
  }
  while (i < n) { claims.push(i); i++; }
  return { claims, a };
}

// The vocabulary is CLOSED. R7-C3: `data-prov` was never validated, so `banana` was accepted, and
// `Counted` with a capital C evaded the disclosure requirement entirely.
export const PROV_KINDS = new Set(["counted", "quoted", "literal", "declared"]);

export function scorePage(raw, mode, block, mutatedRaw, sources) {
  const { els, seq, text, spokenNums, nestedSeen } = auditPage(raw);
  // A bidi override anywhere in the page body makes every number on it unverifiable by inspection.
  const bidi = BIDI.test(String(raw).replace(/<head[\s\S]*?<\/head>/i, ' ')) ? 1 : 0;
  const out = { unmarked: 0, mismatch: 0, bogus: 0, noblock: 0, unsaid: 0, nested: 0, mislabelled: 0,
                badprov: 0, fabricated: 0, bidi, spoken: 0 };

  for (const e of els) {
    if (e.prov && !PROV_KINDS.has(e.prov)) out.badprov++;
    // R7-C3: on a NEW build, writing `prov` instead of `count` bypassed the entire correctness rule
    // — same wrong value, same page, same block, mismatch=0. A number a declared build states must
    // be declared or be an honest literal; it may not opt out by calling itself counted.
    // NOT a violation: `counted` and `quoted` on a declared build. R7-C3 was right that a number
    // which SHOULD be declared must not escape by calling itself counted — but forbidding the kinds
    // outright was the wrong instrument, and it fired 674 times on a build whose block legitimately
    // declares 3 fields out of hundreds of numbers. A block declares what the model knows; the rest
    // is counted-and-disclosed, which IS the design. What actually guards the concern is structural:
    // `nF()` in the generator renders a declared field as `declared` at the single call site that
    // states it, so a declared field cannot be quietly downgraded, and `mismatch` catches it if the
    // value disagrees.
  }

  // R7-C2, and it is the one I did to myself. `quoted` was added so the cross-check would stop
  // accusing innocent numbers — and it carried NO obligation at all, so my own generator reached
  // `unmarked=0` with 94.3% of every number under no check whatsoever. A label that demands nothing
  // is not provenance, it is padding with a nicer name.
  //
  // The obligation is the one thing `quoted` actually asserts: these are the model's own words,
  // reproduced. So the number must APPEAR, verbatim, in this build's state files. A number the
  // generator DERIVED does not — which is exactly the difference the label is claiming.
  if (sources) {
    // Compare DIGITS ONLY, on both sides. The token class includes `,` so `1,051` stays inside one
    // marker — which also swallows a sentence comma, making `465,` look absent from a source that
    // plainly contains 465. Normalising both sides removes a false accusation that was 10 of the
    // first 13 hits.
    const srcDigits = String(sources).replace(/,/g, "");
    for (const e of els) {
      if (e.prov !== "quoted") continue;
      // Check each DIGIT RUN on its own. Stripping every non-digit turned `2458-2534` into
      // `24582534`, a string that appears nowhere — accusing a range that is plainly in the source.
      let missing = false;
      for (const n of e.nums) {
        for (const run of String(n).match(/\d+/g) || []) {
          if (!srcDigits.includes(run)) { missing = true; break; }
        }
        if (missing) break;
      }
      if (missing) out.fabricated++;
    }
  }

  // THE rule. Every digit run a reader sees is inside a marker saying what it is. No word list, no
  // second render, no alignment — a containment test, which is either true of a page or not.
  out.unmarked = seq.filter((x) => !x.marked).length;

  // SPOKEN numbers — alt text, tooltips, aria-labels, svg titles — are REPORTED, never scored, and
  // the reason is measured rather than assumed. An attribute cannot hold a marker, so the only
  // check available is "does this value appear marked somewhere on the page", and a review found
  // that accepts 39 of 39 real cases by pure value-collision: a page states enough small integers
  // that almost any spoken number matches one by accident. It passes by coincidence and fails by
  // absence, so scoring it would be theatre in both directions — 13 corpus numbers were being
  // demanded on that basis, none of them a real provenance gap.
  //
  // It is counted and printed so the blind spot stays visible instead of being quietly dropped.
  const markedValues = new Set(seq.filter((x) => x.marked).map((x) => x.value));
  out.spoken = (spokenNums || []).filter((n) => !markedValues.has(n)).length;

  // A marker inside a marker breaks containment depth, so it is a violation rather than something
  // silently miscounted. Each number gets its own marker; a phrase does not wrap a count.
  out.nested = nestedSeen;

  const counted = els.filter((e) => e.prov === "counted" || (e.field && mode === "legacy"));
  const flat = (x) => x.toLowerCase()
    .replace(/[\u2018\u2019\u02BC\u00B4`]/g, "'")
    .replace(/&(?:rsquo|apos|#8217|#39);/g, "'")
    .replace(/\s+/g, " ").trim();

  // A `quoted` number is copied out of prose and is unverifiable in EITHER mode, so this one is not
  // inside the legacy branch. Scoring it only for legacy builds would leave the same hole one build
  // type over — the variant of this defect that keeps coming back.
  const quotedEls = els.filter((e) => e.prov === "quoted");
  if (quotedEls.length > 0 && !flat(text).includes(flat(QUOTED_PHRASE))) out.unsaid += quotedEls.length;

  // Also NOT inside the legacy branch. I moved the quoted check out and wrote a comment saying that
  // was deliberate, "because that is exactly where this defect would have come back one build type
  // over" — and left the counted check inside, which is the same defect, in the same function, three
  // lines down. An independent reviewer proved it end-to-end: a new-format build printing the
  // quoted-only sentence over two `counted` numbers scored `unsaid=0`, gold EXIT 0, 48 controls
  // green. And new-format is the GROWING half — every build `compass.sh new-build` creates carries
  // the stamp; the 27 legacy ones are frozen history.
  // A number counted by reading is unverifiable whatever rule the build was created under.
  if (counted.length > 0 && !flat(text).includes(flat(PHRASE))) out.unsaid += counted.length;

  if (mode === "legacy") {
    // No correctness claim is possible for a build whose data was never structured. Nothing extra is
    // demanded here now — the disclosure requirement above applies to both rules.
  } else {
    const declared = els.filter((e) => e.field);
    const realBlock = block !== null && typeof block === "object" && !Array.isArray(block)
                      && Object.keys(block).length > 0;
    if (!realBlock && (seq.length > 0 || declared.length > 0)) {
      out.noblock = 1;                       // `{}`, `[]`, `0` and `false` are not data blocks
    } else if (realBlock) {
      for (const e of declared) {
        if (!Object.prototype.hasOwnProperty.call(block, e.field)) { out.bogus++; continue; }
        const want = block[e.field];
        if (typeof want !== "number" || !Number.isFinite(want)) { out.bogus++; continue; }
        if (e.nums.length !== 1) { out.mismatch++; continue; }
        if (Number(e.num) !== want) out.mismatch++;
      }
    }
  }

  // THE CROSS-CHECK, and the only job the differential still has. A `literal` marker asserts "this
  // number is not derived from this build's data". That is a falsifiable claim: if the number MOVES
  // when the data moves, the claim is false. This is narrow on purpose — it no longer defines
  // completeness, so its recall gap only means fewer lies caught, never a wrong demand.
  if (mutatedRaw !== undefined && mutatedRaw !== null) {
    const { claims } = dataClaims(raw, mutatedRaw);
    for (const i of claims) if (seq[i] && seq[i].kind === "literal") out.mislabelled++;
  }
  return out;
}

// INV-0b POSITIVE CONTROLS. Fixed known-violating inputs, run through the SAME functions the gold
// runs, every time the gold runs. If any control stops failing, the auditor has stopped working and
// the gold reports ERR instead of a verdict.
export const CONTROLS = [
  { why: "an unmarked number a reader sees is a violation",
    html: "<p>207 findings</p>", mode: "legacy", block: null,
    expect: (r) => r.unmarked === 1 },
  { why: "five unmarked numbers score five (a capped scan fails here)",
    html: "<p>207 findings, 115 closed, 64 crit, 100 major, 30 steps</p>", mode: "legacy", block: null,
    expect: (r) => r.unmarked === 5 },
  { why: "a marked count on a disclosed legacy page is accepted",
    html: "<p><span data-prov='counted'>207</span> findings — counted by reading this build's files</p>",
    mode: "legacy", block: null, expect: (r) => r.unmarked === 0 && r.unsaid === 0 },
  { why: "marked in markup but the words never say so",
    html: "<p><span data-prov='counted'>207</span> findings</p>", mode: "legacy", block: null,
    expect: (r) => r.unsaid === 1 },
  { why: "quoted numbers with no words covering them are unsaid (the 15-page hole)",
    html: "<p><span data-prov='quoted'>4242</span> and <span data-prov='quoted'>7</span></p>",
    mode: "legacy", block: null, sources: "the ledger says 4242 things, 7 of them",
    expect: (r) => r.unsaid === 2 },
  { why: "quoted numbers ARE covered once the page says where they came from",
    html: "<p><span data-prov='quoted'>4242</span> \u2014 copied from what someone wrote in the files</p>",
    mode: "legacy", block: null, sources: "the ledger says 4242 things",
    expect: (r) => r.unsaid === 0 },
  { why: "a NEW build's COUNTED numbers are unsaid too — the half I left in the legacy branch",
    html: "<p><span data-count='findings.total'>207</span> <span data-prov='counted'>42</span></p>",
    mode: "new", block: { "findings.total": 207 }, expect: (r) => r.unsaid === 1 },
  { why: "a NEW build's counted numbers ARE covered once the page says so",
    html: "<p><span data-prov='counted'>42</span> \u2014 counted by reading this build's files</p>",
    mode: "new", block: { "findings.total": 207 }, expect: (r) => r.unsaid === 0 },
  { why: "a NEW build's quoted numbers are unsaid too — the rule is not legacy-only",
    html: "<p><span data-count='findings.total'>207</span> <span data-prov='quoted'>4242</span></p>",
    mode: "new", block: { "findings.total": 207 }, sources: "4242 things",
    expect: (r) => r.unsaid === 1 },
  { why: "a typographic apostrophe still counts as saying it",
    html: "<p><span data-prov='counted'>5</span> findings — counted by reading this build\u2019s files</p>",
    mode: "legacy", block: null, expect: (r) => r.unsaid === 0 },
  { why: "a literal covers every digit run inside it",
    html: "<p><span data-prov='literal'>v0.28.0</span> shipped</p>", mode: "legacy", block: null,
    expect: (r) => r.unmarked === 0 },
  { why: "an UNMARKED version string is still three unmarked runs",
    html: "<p>v0.28.0 shipped</p>", mode: "legacy", block: null,
    expect: (r) => r.unmarked === 3 },
  { why: "a marker inside a marker is a violation, not a miscount",
    html: "<span data-prov='literal'>1 <span data-count='x'>2</span> 3</span>", mode: "legacy", block: null,
    expect: (r) => r.nested === 1 },
  { why: "single-quoted markers are seen",
    html: "<p><span data-prov='literal'>5</span></p>", mode: "legacy", block: null,
    expect: (r) => r.unmarked === 0 },
  { why: "a marked number in a heading is seen (the gate must not block its own fix path)",
    html: "<h2 data-prov='literal'>5</h2>", mode: "legacy", block: null,
    expect: (r) => r.unmarked === 0 },
  { why: "Arabic-Indic digits are numbers too",
    html: "<p>\u0662\u0660\u0667 findings</p>", mode: "legacy", block: null,
    expect: (r) => r.unmarked === 1 },
  { why: "a number hidden in CSS content: is still a number a reader sees",
    html: "<style>.a::before{content:'207 findings'}</style><p></p>", mode: "legacy", block: null,
    expect: (r) => r.unmarked === 1 },
  { why: "a number written as numeric entities is still a number",
    html: "<p>&#50;&#48;&#55; findings</p>", mode: "legacy", block: null,
    expect: (r) => r.unmarked === 1 },
  { why: "a large page is scored the same as a small one (a size-gated bypass fails here)",
    html: "<p>" + "filler that is not a number. ".repeat(120) + "207 findings, 115 closed, 64 crit</p>",
    mode: "legacy", block: null, expect: (r) => r.unmarked === 3 },
  { why: "new: a declared number that agrees with the block is accepted",
    html: "<p><span data-count='findings.total'>207</span></p>", mode: "new",
    block: { "findings.total": 207 }, expect: (r) => r.mismatch === 0 && r.unmarked === 0 },
  { why: "new: a declared number that disagrees is a mismatch",
    html: "<p><span data-count='findings.total'>999</span></p>", mode: "new",
    block: { "findings.total": 207 }, expect: (r) => r.mismatch === 1 },
  { why: "new: three wrong declared numbers score three",
    html: "<p><span data-count='a'>1</span><span data-count='b'>2</span><span data-count='c'>3</span></p>",
    mode: "new", block: { a: 9, b: 9, c: 9 }, expect: (r) => r.mismatch === 3 },
  { why: "new: a field the block does not declare is bogus",
    html: "<p><span data-count='pad.n'>0</span></p>", mode: "new",
    block: { "findings.total": 207 }, expect: (r) => r.bogus === 1 },
  { why: "new: a field declared null is not a licence to render 0",
    html: "<p><span data-count='steps'>0</span></p>", mode: "new",
    block: { steps: null }, expect: (r) => r.bogus === 1 },
  { why: "new: a marked element holding two numbers cannot be compared to one field",
    html: "<p><span data-count='steps'>v0.30.0 30</span></p>", mode: "new",
    block: { steps: 30 }, expect: (r) => r.mismatch === 1 },
  { why: "new: numbers stated with no block at all",
    html: "<p>207 findings</p>", mode: "new", block: null, expect: (r) => r.noblock === 1 },
];

// Controls for the CROSS-CHECK. Narrow now: the differential no longer defines completeness, it
// only falsifies a `literal` marker that moves when the data moves.
export const DIFF_CONTROLS = [
  { why: "a number that changed is claimed; one that did not is not",
    real: "<p>5 findings, 4 open</p>", mutated: "<p>4 findings, 4 open</p>",
    expect: (r, seq) => r.length === 1 && seq[r[0]].value === "5" },
  { why: "an identical twin claims nothing",
    real: "<p>5 findings, 4 open</p>", mutated: "<p>5 findings, 4 open</p>",
    expect: (r) => r.length === 0 },
  { why: "a version and a date never move, so they are never claimed",
    real: "<p>v0.30.0 on 2026-08-20: 5 findings</p>", mutated: "<p>v0.30.0 on 2026-08-20: 6 findings</p>",
    expect: (r, seq) => r.length === 1 && seq[r[0]].value === "5" },
  { why: "an inserted number shifts the rest without claiming them",
    real: "<p>1 a 2 b 3 c</p>", mutated: "<p>1 a 9 z 2 b 3 c</p>",
    expect: (r) => r.length === 0 },
];

// And the cross-check as scorePage sees it: a literal that moves is a false label.
export const MISLABEL_CONTROLS = [
  { why: "a literal that MOVES with the data is a false label",
    real: "<p><span data-prov='literal'>5</span> findings</p>",
    mutated: "<p><span data-prov='literal'>6</span> findings</p>",
    expect: (r) => r.mislabelled === 1 },
  { why: "a literal that does not move is honest",
    real: "<p><span data-prov='literal'>2026</span> findings</p>",
    mutated: "<p><span data-prov='literal'>2026</span> findings</p>",
    expect: (r) => r.mislabelled === 0 },
];

CONTROLS.push(
  { why: "an in-band sentinel from the INPUT cannot mark the page (R7-C1: &#1; marked everything)",
    html: "<p>&#1; 207 findings</p>", mode: "legacy", block: null,
    expect: (r) => r.unmarked === 1 },
  { why: "the hex form of the same attack is closed too",
    html: "<p>&#x1; 207 findings</p>", mode: "legacy", block: null,
    expect: (r) => r.unmarked === 1 },
);

CONTROLS.push(
  { why: "an unknown data-prov value is rejected (R7-C3: 'banana' was accepted)",
    html: "<p><span data-prov='banana'>5</span></p>", mode: "legacy", block: null,
    expect: (r) => r.badprov === 1 },
  { why: "a capitalised kind does not evade the vocabulary",
    html: "<p><span data-prov='Counted'>5</span></p>", mode: "legacy", block: null,
    expect: (r) => r.badprov === 1 },
  { why: "on a NEW build, counting a field the block does NOT declare is the designed fallback",
    html: "<p><span data-prov='counted'>999</span></p>", mode: "new",
    block: { "findings.total": 207 }, expect: (r) => r.badprov === 0 },
  { why: "a declared marker that disagrees with the block is still caught",
    html: "<p><span data-count='findings.total'>999</span></p>", mode: "new",
    block: { "findings.total": 207 }, expect: (r) => r.mismatch === 1 },
  { why: "a quoted number that is NOT in the build's files is fabricated",
    html: "<p><span data-prov='quoted'>4242</span></p>", mode: "legacy", block: null,
    sources: "there is no such number here", expect: (r) => r.fabricated === 1 },
  { why: "a quoted number that IS in the build's files is honest",
    html: "<p><span data-prov='quoted'>4242</span></p>", mode: "legacy", block: null,
    sources: "the ledger says 4242 things", expect: (r) => r.fabricated === 0 },
);

CONTROLS.push(
  { why: "an empty fence is not a data block (R7-M8: `{}` satisfied noblock)",
    html: "<p>207 findings</p>", mode: "new", block: {}, expect: (r) => r.noblock === 1 },
  { why: "an array is not a data block either",
    html: "<p>207 findings</p>", mode: "new", block: [], expect: (r) => r.noblock === 1 },
  { why: "a number spoken only in alt text is REPORTED, not scored (it cannot carry a marker)",
    html: '<img alt="207 findings">', mode: "legacy", block: null,
    expect: (r) => r.unmarked === 0 && r.spoken === 1 },
  { why: "an aria-label repeating a number the body marks reports nothing",
    html: '<svg aria-label="7 steps"></svg><p><span data-prov="literal">7</span> steps</p>',
    mode: "legacy", block: null, expect: (r) => r.unmarked === 0 },
);

CONTROLS.push(
  { why: "a bidi override makes the reader see a different number than the auditor (R9-C3)",
    html: "<p><span data-prov='literal'>2\u202e07</span></p>", mode: "legacy", block: null,
    expect: (r) => r.bidi === 1 },
  { why: "an ordinary page has no bidi flag",
    html: "<p><span data-prov='literal'>207</span></p>", mode: "legacy", block: null,
    expect: (r) => r.bidi === 0 },
);

CONTROLS.push(
  { why: "a CSS counter paints a number the markup has no digit for (R9-C4)",
    html: "<style>.z{counter-reset:zc 4242}.z b::after{content:counter(zc)}</style><p class='z'><b></b></p>",
    mode: "legacy", block: null, expect: (r) => r.unmarked === 1 },
  { why: "an svg title stating a number shown nowhere marked is reported, not scored",
    html: "<svg><title>207 findings</title></svg>", mode: "legacy", block: null,
    expect: (r) => r.unmarked === 0 && r.spoken === 1 },
  { why: "an svg title repeating a number the body marks reports nothing",
    html: "<svg><title>207 findings</title></svg><p><span data-prov='literal'>207</span></p>",
    mode: "legacy", block: null, expect: (r) => r.unmarked === 0 },
);

CONTROLS.push(
  { why: "a marker inside a marker is caught even with a closing tag between them (R9-M6)",
    html: "<span data-prov='literal'>1 <b>x</b> <span data-count='y'>2</span></span>",
    mode: "legacy", block: null, expect: (r) => r.nested === 1 },
);

export function runControls() {
  const failed = CONTROLS.filter((c) => !c.expect(scorePage(c.html, c.mode, c.block, undefined, c.sources)));
  for (const c of DIFF_CONTROLS) {
    const { claims, a } = dataClaims(c.real, c.mutated);
    if (!c.expect(claims, a)) failed.push(c);
  }
  for (const c of MISLABEL_CONTROLS) {
    if (!c.expect(scorePage(c.real, "legacy", null, c.mutated))) failed.push(c);
  }
  return failed;
}

// `file://${process.argv[1]}` does not equal import.meta.url when the path contains a space (it
// arrives percent-encoded), so this guard silently never fired and `--controls` exited 0 having run
// nothing — a self-test that reports success by doing nothing is the defect this file exists to fix.
import { pathToFileURL } from "node:url";
import { realpathSync } from "node:fs";
// `import.meta.url` is the REALPATH; `pathToFileURL(process.argv[1])` is not. On macOS `/tmp` and
// `/var` are symlinks, as are Docker mounts and symlinked worktrees — so invoked through one of
// those this guard was false, `--controls` printed NOTHING and exited 0, and both callers read
// "exit 0, no output" as "all controls fire". The control-of-controls was silently off. The earlier
// comment here claimed this class was closed: it closed the spaces case, not the symlink case.
const _self = (() => { try { return pathToFileURL(realpathSync(process.argv[1] || "")).href; } catch { return ""; } })();
if (_self && import.meta.url === _self) {
  const failed = runControls();
  if (process.argv[2] === "--controls") {
    if (failed.length) {
      console.log("page-audit: " + failed.length + " control(s) NOT firing:");
      for (const f of failed) console.log("    " + f.why);
      process.exit(1);
    }
    console.log("page-audit: all " + (CONTROLS.length + DIFF_CONTROLS.length + MISLABEL_CONTROLS.length) + " controls fire (" + (DIFF_CONTROLS.length + MISLABEL_CONTROLS.length) + " exercise the cross-check)");
    process.exit(0);
  }
}
