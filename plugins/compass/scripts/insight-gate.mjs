#!/usr/bin/env node
// insight-gate — INV-1 (COLD-READ). The Feynman insight bar as an executable acceptance gate.
//
// The bar (from feynman-walkthrough references/insight-bar.md): a FRESH reader, given ONLY the
// rendered artefact, states its one MESSAGE and its IMPLICATION, unhedged. Hedged, wrong, or
// "asks for more" = FAIL, and the fix belongs in the ARTEFACT, never in prose wrapped around it.
//
// WHY THE HARNESS LOOKS LIKE THIS — every rule below was earned by a specific defeat:
//   · exit 3 = a genuine NO-GO from a COMPLETED read; 0 = GO; anything else = ERROR and never
//     valid RED. "exits non-zero" counted a missing file, a JSON parse error, an absent browser
//     and reader-unavailable as "the gate bites" (round-1 A1/P3).
//   · the reader runs in a temp dir holding ONLY the artefact. Compass's spawn inherits CWD, so a
//     reader launched in the build tree could read contract.md and score itself (round-1 E3/P7).
//   · a CONTROL page (the pinned pre-change artefact) is scored every round. A GO on the control
//     VOIDS the round: it proves the reader will say GO to anything (round-1 A6/P6).
//   · the intent is read from a file pinned BEFORE the artefact was written and is never rewritten
//     here — re-pinning lets the author move the yardstick (round-2 V1).
//   · a deterministic hedge lexicon of STEMS, not five literals, because synonyms trivially evade
//     a literal list (round-2 V8).
//   · each answer must QUOTE the page verbatim, so paraphrasing the headline cannot pass (V8).
//
// Usage:
//   insight-gate.mjs --artefact <f> --intent <f> --grader <f> [--control <reader's verdict on the control page>] [--json]
//   insight-gate.mjs --self-test
// Exit: 0 GO · 3 NO-GO (completed read, verdict negative) · 2 usage · 4 ERROR (never a valid RED)

import { readFileSync, existsSync, mkdtempSync, copyFileSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import { join, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const EXIT = { GO: 0, USAGE: 2, NOGO: 3, ERROR: 4 };

// Hedge STEMS — matched as substrings against the reader's own prose, lowercased. A literal list
// of five ("not sure / unclear / probably / seems / moderately") was defeated by synonyms.
// Round 2 evaded this list 16 times out of 16 with ordinary words — `apparently` slipped past
// `appear` because `appar` != `appear`. The list is now broader AND, more importantly, it is no
// longer the only thing standing here: the second grader must affirm `unhedged` as a judgement.
// A literal list cannot win a synonym race; it is a floor, not the wall.
export const HEDGE_STEMS = [
  'not sure', 'unsure', 'unclear', 'probabl', 'seem', 'moderat', 'appar', 'appear', 'rough',
  'i think', 'i believe', 'broadly', 'fairly', 'somewhat', 'perhaps', 'maybe', 'possibly',
  'might be', 'could be', 'hard to say', 'difficult to say', 'guess', 'assum', 'presum',
  'more or less', 'kind of', 'sort of', 'to some extent', 'not entirely', 'not fully',
  'cannot tell', "can't tell", 'ambiguous', 'vague',
  // round-2 evasions, every one of which scored GO
  'arguabl', 'ostensibl', 'plausibl', 'tentativ', 'as far as i can tell', 'my read is',
  'on balance', 'loosely', 'nominal', 'reads as', 'in effect', 'give or take',
  'if pressed', 'it looks like', 'approximat', 'i would say', 'i\'d say', 'essentially',
  'more of a', 'something like', 'you could say', 'in a sense', 'to a degree', 'largely',
  'mostly', 'generally', 'typically', 'i suspect', 'my sense is', 'best guess',
];

export function findHedges(text) {
  const t = String(text || '').toLowerCase();
  return HEDGE_STEMS.filter((h) => t.includes(h));
}

// A quote counts only if a non-trivial run of it actually appears in the page text.
export function quoteIsReal(quote, pageText) {
  const q = String(quote || '').trim().replace(/\s+/g, ' ');
  if (q.length < 12) return false;
  const page = String(pageText || '').replace(/\s+/g, ' ');
  return page.includes(q);
}

// A round is VOID if the control page — the pinned pre-change artefact, known to be unreadable —
// receives a GO. That proves the reader will say GO to anything, so its verdict on the real page
// carries no information. Voiding is not the same as failing: it indicts the reader, not the page.
export function scoreRound({ subject, control }) {
  if (control && control.pass) {
    return { verdict: 'VOID', why: 'the control page scored GO — the reader will pass anything, so this round proves nothing' };
  }
  return { verdict: subject.pass ? 'GO' : 'NO-GO', why: subject.problems.join('; ') };
}

// A page-specific question whose answer is NOT in the title or headline. Quoting the headline back
// satisfies message+implication but proves nothing about comprehension (round-2 V8), so the reader
// must also answer something only a real read can supply.
// The CONTROL is the pinned pre-change artefact — a page known NOT to support a confident read.
// It is scored WITHOUT the verbatim-quote rule on purpose: the control ships as a PNG, and a check
// that needs extractable text could never fire against it, which would make the VOID rule a rule
// that cannot go red (the exact defect class this build exists to kill). What the control measures
// is page-independent and is the only thing it needs to measure: did the reader return an unhedged,
// confident read of a page that cannot support one? That is a rubber stamp, and it voids the round.
export function scoreControl({ verdict }) {
  const v = verdict || {};
  const halves = [v.message, v.implication];
  // ABSENT IS NOT CAREFUL. `echo '{}' > control.json` used to read as "the reader declined to
  // answer — correct behaviour" and left the round standing. A missing control read is a control
  // that was never run, and an unrun control cannot vouch for the reader. It is an ERROR.
  for (const h of halves) {
    if (!h || !String(h.answer || '').trim()) {
      return { pass: false, incomplete: true, why: 'control: the control verdict is empty or incomplete — the control read was not performed, so it vouches for nothing' };
    }
  }
  // A refusal must be EXPLICIT. One hedging word sprinkled into an otherwise assertive sentence
  // let a rubber-stamp reader dodge the VOID while confidently passing the real page. The reader
  // states confident:false (or cannot_determine) when it cannot read a page — that is the protocol,
  // and anything less counts as a confident read of a page that cannot support one.
  // BOTH halves must decline. `some()` let a control verdict that confidently "read" the known-bad
  // page in one half and declined in the other vouch for the reader — half a rubber stamp is a
  // rubber stamp.
  const refused = halves.every((h) => h.confident === false || h.cannot_determine === true);
  if (refused) return { pass: false, why: 'control: the reader explicitly reported it could not read the control — correct behaviour' };
  return { pass: true, why: 'control: the reader returned a confident read of the known-bad page' };
}

export function scoreProbe({ probe, pageText }) {
  // MANDATORY. This returned pass:true when `probe` was absent, so a reader could delete one JSON
  // key and skip the only check that distinguishes comprehension from paraphrasing the headline —
  // the round-2 defeat worked verbatim again by omission. The reader does not get to choose
  // whether it is tested.
  if (!probe || !probe.question) {
    return { pass: false, problems: ['probe: MISSING — a read with no page-specific question is a read that only quoted the headline back'] };
  }
  const problems = [];
  if (!probe.answer) problems.push('probe: no answer returned');
  else if (!quoteIsReal(probe.evidence, pageText)) problems.push('probe: evidence not found verbatim in the page');
  // The evidence must actually SUPPORT the answer. Round 2 answered "91,000 widgets" and cited a
  // CSS variable as its evidence; both halves checked out independently and the answer was wrong.
  else if (!String(probe.evidence || '').toLowerCase().includes(String(probe.answer || '').trim().toLowerCase()))
    problems.push('probe: the cited evidence does not contain the answer — a real quote pinned to an unrelated claim');
  else if (findHedges(probe.answer).length) problems.push(`probe: hedged (${findHedges(probe.answer).join(', ')})`);
  return { pass: problems.length === 0, problems };
}

export function scoreVerdict({ verdict, intent, pageText, intentSha }) {
  const problems = [];
  for (const half of ['message', 'implication']) {
    const v = verdict?.[half];
    if (!v || !v.answer) { problems.push(`${half}: no answer returned`); continue; }
    const hedges = findHedges(v.answer);
    if (hedges.length) problems.push(`${half}: hedged (${hedges.join(', ')})`);
    if (v.confident === false) problems.push(`${half}: reader reported confident=false`);
    if (!quoteIsReal(v.quote, pageText)) {
      problems.push(`${half}: quote not found verbatim in the page`);
    }
  }
  // ── intent match: a SECOND GRADER's judgement, never word overlap ────────────────────────
  // This was lexical: it counted how many of the pinned intent's words appeared in the reader's
  // answer. That is a PROXY for comprehension and the wrong one — it rewards a reader who parrots
  // the project's vocabulary and PENALISES one who understood a page written in plain English.
  // It failed the rebuilt Brief on exactly that: the reader matched 2 of 12 terms because the
  // page no longer says "artefact", "invariants" or "terminal-clarity" at them, which was the
  // entire objective. A metric that punishes the thing it measures is worse than no metric.
  // The grader is a separate agent that sees ONLY the pinned intent and the reader's answers —
  // never the page — so it cannot be swayed by how the page looks.
  const g = verdict?.grader;
  // The pinned INTENT must be the one the grader actually graded against. `intent` used to be
  // read from disk and never referenced again — an empty intent file produced the same GO — so the
  // "the yardstick is pinned before the page is seen" rule was enforced by nothing at all. The
  // grader now states which intent it saw, and it must be this one.
  if (g && intentSha) {
    if (!g.intent_sha) problems.push('grader: no intent_sha — cannot tell which intent was graded against');
    else if (String(g.intent_sha).toLowerCase() !== intentSha) {
      problems.push(`grader: graded against a different intent (${g.intent_sha}, expected ${intentSha}) — the yardstick moved`);
    }
  }
  if (!g) {
    // An UNGRADED read is not a passing read. Returning "pass" here would be the soft-pass this
    // whole gate exists to refuse.
    problems.push('UNGRADED: no second-grader verdict supplied (--grader). An ungraded read cannot pass.');
  } else {
    if (g.message_matches !== true) problems.push(`grader: message does not match the pinned intent — ${g.reason || 'no reason given'}`);
    if (g.implication_matches !== true) problems.push(`grader: implication does not match the pinned intent — ${g.reason || 'no reason given'}`);
  }
  return { pass: problems.length === 0, problems };
}

// Isolation: the reader sees a temp dir containing ONLY the artefact. Returns the dir so the
// caller records it in the receipt — "which files could the reader see" is itself evidence.
export function isolate(artefact) {
  const dir = mkdtempSync(join(tmpdir(), 'coldread-'));
  copyFileSync(artefact, join(dir, basename(artefact)));
  return dir;
}

function main(argv) {
  const arg = (n) => { const i = argv.indexOf(n); return i > -1 ? argv[i + 1] : ''; };
  if (argv.includes('--self-test')) return selfTest();

  const artefact = arg('--artefact');
  const intentFile = arg('--intent');
  if (!artefact || !intentFile) {
    console.error('usage: insight-gate.mjs --artefact <file> --intent <file> [--control <file>]');
    return EXIT.USAGE;
  }
  if (!existsSync(artefact)) { console.error(`insight-gate: ERROR — no artefact at ${artefact}`); return EXIT.ERROR; }
  if (!existsSync(intentFile)) { console.error(`insight-gate: ERROR — no intent file at ${intentFile}`); return EXIT.ERROR; }

  // The reader itself is spawned by the caller (Compass supplies the agent); this harness owns
  // isolation, scoring and the exit contract. A verdict is read from stdin as JSON.
  // Read stdin ONLY when it is actually a pipe. Called from a terminal with no pipe — exactly what
  // the documented one-liner used to invite — readFileSync(0) blocks forever with no message. A
  // gate that hangs is worse than a gate that fails: nothing tells you it is your turn to act.
  let raw = '';
  try {
    if (process.stdin.isTTY) {
      console.error('insight-gate: ERROR — no verdict on stdin. The reader\'s verdict is PIPED in:');
      console.error('  node insight-gate.mjs --artefact <f> --intent <f> --grader <f> < reader-verdict.json');
      return EXIT.ERROR;
    }
    raw = readFileSync(0, 'utf8');
  } catch { raw = ''; }
  if (!raw.trim()) { console.error('insight-gate: ERROR — no verdict on stdin (reader unavailable)'); return EXIT.ERROR; }
  let verdict;
  try { verdict = JSON.parse(raw); } catch (e) {
    console.error(`insight-gate: ERROR — verdict is not JSON (${e.message})`); return EXIT.ERROR;
  }

  // THE READER MAY NOT GRADE ITSELF. stdin is the reader's own output, so anything it says about
  // its own correctness is discarded here, unconditionally, before scoring. Without this line a
  // reader that appends `"grader":{"message_matches":true,"implication_matches":true}` to its own
  // JSON passes the gate with no second opinion in the loop at all — the self-armed-gate class,
  // in the one gate this whole build was built around.
  if ('grader' in verdict) {
    delete verdict.grader;
    console.error('insight-gate: NOTE — discarded a `grader` field supplied on stdin; the reader does not grade itself.');
  }
  const graderFile = arg('--grader');
  if (!graderFile) {
    console.error('insight-gate: ERROR — --grader <file> is required. An ungraded read cannot pass.');
    return EXIT.USAGE;
  }
  if (!existsSync(graderFile)) { console.error(`insight-gate: ERROR — no grader verdict at ${graderFile}`); return EXIT.ERROR; }
  try { verdict.grader = JSON.parse(readFileSync(graderFile, 'utf8')); }
  catch (e) { console.error(`insight-gate: ERROR — grader verdict is not JSON (${e.message})`); return EXIT.ERROR; }

  // Strip style/script FIRST. Without this, `--bg:#0b0d10;--fg:#e8eef7` counted as a verbatim
  // quote from the page, so a reader could "cite" the stylesheet and answer the probe with a
  // number that appears nowhere — a wrong figure passing the comprehension check. Every generated
  // artefact carries a <style> block, so this was live on all of them.
  const pageText = readFileSync(artefact, 'utf8')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<[^>]+>/g, ' ');
  const intent = readFileSync(intentFile, 'utf8');
  const intentSha = createHash('sha256').update(intent.trim()).digest('hex').slice(0, 16);
  const res = scoreVerdict({ verdict, intent, pageText, intentSha });

  // The probe — a page-specific question the headline cannot answer. Documented in this file's
  // header since round 2 and, until now, called from nowhere.
  const probeRes = scoreProbe({ probe: verdict.probe, pageText });
  if (!probeRes.pass) res.problems.push(...probeRes.problems);
  res.pass = res.pass && probeRes.pass;

  // The control round. Also documented in the header and, until now, called from nowhere: --control
  // was accepted on the command line and parsed by nothing, so a reader that GO'd the known-bad page
  // still passed.
  // --control is REQUIRED, for the same reason --grader is: the round's only defence against a
  // rubber-stamp reader was optional, and the one documented invocation left it out. An optional
  // guard on the documented path is a guard that does not run.
  const controlFile = arg('--control');
  if (!controlFile) {
    console.error('insight-gate: ERROR — --control <control-verdict.json> is required.');
    console.error('  The same reader must also read the pinned known-bad page. If it passes THAT,');
    console.error('  its verdict on the real page carries no information and the round is void.');
    return EXIT.USAGE;
  }
  let round = { verdict: res.pass ? 'GO' : 'NO-GO' };
  if (controlFile) {
    if (!existsSync(controlFile)) { console.error(`insight-gate: ERROR — no control verdict at ${controlFile}`); return EXIT.ERROR; }
    let cv;
    try { cv = JSON.parse(readFileSync(controlFile, 'utf8')); }
    catch (e) { console.error(`insight-gate: ERROR — control verdict is not JSON (${e.message})`); return EXIT.ERROR; }
    const control = scoreControl({ verdict: cv });
    // An INCOMPLETE control is not a careful reader — it is a control that was never run, and it
    // must not be scored as evidence of discrimination. `{}` in the control file used to read as
    // "the reader declined to answer — correct behaviour" and left the round standing.
    if (control.incomplete) {
      console.error(`insight-gate: NO-GO — ${basename(artefact)}`);
      console.error(`  ${control.why}`);
      return EXIT.NOGO;
    }
    round = scoreRound({ subject: res, control });
    if (round.verdict === 'VOID') {
      if (argv.includes('--json')) console.log(JSON.stringify({ verdict: 'VOID', why: round.why, artefact }, null, 2));
      console.error(`insight-gate: VOID — ${basename(artefact)}`);
      console.error(`  ${round.why}`);
      return EXIT.NOGO;
    }
  }

  if (argv.includes('--json')) console.log(JSON.stringify({ ...res, round: round.verdict, artefact }, null, 2));
  if (res.pass) { console.log(`insight-gate: GO — ${basename(artefact)}`); return EXIT.GO; }
  console.error(`insight-gate: NO-GO — ${basename(artefact)}`);
  for (const p of res.problems) console.error(`  ${p}`);
  return EXIT.NOGO;
}

function selfTest() {
  let fail = 0;
  const ok = (label, cond) => { console.log(`  ${cond ? 'ok  ' : 'FAIL'} ${label}`); if (!cond) fail = 1; };
  const page = 'Lock this contract? This page asks you to lock a rebuild of the artefact layer.';
  const intent = 'this page asks you to lock a contract for rebuilding the artefact layer';
  const good = {
    message: { answer: 'It asks you to lock a contract for rebuilding the artefact layer.', confident: true, quote: 'asks you to lock a rebuild of the artefact layer' },
    implication: { answer: 'Locking it commits the rebuild of the artefact layer to this spec.', confident: true, quote: 'Lock this contract? This page asks you' },
  };
  ok('a clean confident quoted verdict passes ONCE GRADED',
     scoreVerdict({ verdict: { ...good, grader: { message_matches: true, implication_matches: true } }, intent, pageText: page }).pass);

  const hedgedLiteral = JSON.parse(JSON.stringify(good));
  hedgedLiteral.implication.answer = 'It probably commits the rebuild of the artefact layer.';
  ok('a literal hedge is caught', !scoreVerdict({ verdict: hedgedLiteral, intent, pageText: page }).pass);

  // the defeat that motivated stems over literals
  for (const syn of ['It appears to commit the rebuild of the artefact layer.',
                     'It roughly commits the rebuild of the artefact layer.',
                     'I think it commits the rebuild of the artefact layer.',
                     'It broadly commits the rebuild of the artefact layer.',
                     'It fairly clearly commits the rebuild of the artefact layer.']) {
    const v = JSON.parse(JSON.stringify(good)); v.implication.answer = syn;
    ok(`synonym hedge caught: "${syn.split(' ').slice(0, 3).join(' ')}…"`,
       !scoreVerdict({ verdict: v, intent, pageText: page }).pass);
  }

  const selfReported = JSON.parse(JSON.stringify(good));
  selfReported.message.confident = false;
  ok('a self-reported confident=false is caught', !scoreVerdict({ verdict: selfReported, intent, pageText: page }).pass);

  const fabricated = JSON.parse(JSON.stringify(good));
  fabricated.message.quote = 'a sentence that is nowhere on the page at all';
  ok('a quote not on the page is caught', !scoreVerdict({ verdict: fabricated, intent, pageText: page }).pass);

  const graded = (m, i) => ({ ...good, grader: { message_matches: m, implication_matches: i, reason: 'test' } });
  ok('an UNGRADED read cannot pass', !scoreVerdict({ verdict: good, intent, pageText: page }).pass);
  ok('a graded matching read passes', scoreVerdict({ verdict: graded(true, true), intent, pageText: page }).pass);
  ok('the grader rejecting the message fails it', !scoreVerdict({ verdict: graded(false, true), intent, pageText: page }).pass);
  ok('the grader rejecting the implication fails it', !scoreVerdict({ verdict: graded(true, false), intent, pageText: page }).pass);

  const offIntent = { message: { answer: 'It is a picture of a cat.', confident: true, quote: 'Lock this contract? This page asks you' },
                      implication: { answer: 'Nothing much follows from it.', confident: true, quote: 'asks you to lock a rebuild of the artefact layer' } };
  ok('an answer that ignores the pinned intent is caught', !scoreVerdict({ verdict: offIntent, intent, pageText: page }).pass);

  // fileURLToPath, not URL.pathname: the latter percent-encodes spaces, so a repo under
  // "Claude Code Projects" produced a path that does not exist. A path with a space is exactly
  // the class of input this build keeps getting caught by.
  const dir = isolate(fileURLToPath(import.meta.url));
  ok('isolation dir holds exactly one file', readdirSync(dir).length === 1);
  rmSync(dir, { recursive: true, force: true });

  // control-page voiding (round-1 A6/P6): a reader that GOes the known-bad page indicts itself
  const goodSubj = scoreVerdict({ verdict: { ...good, grader: { message_matches: true, implication_matches: true } }, intent, pageText: page });
  ok('control NO-GO + subject GO → GO',
     scoreRound({ subject: goodSubj, control: { pass: false } }).verdict === 'GO');
  ok('control GO → round VOID, not GO',
     scoreRound({ subject: goodSubj, control: { pass: true } }).verdict === 'VOID');
  ok('a VOID round is not reported as a pass',
     scoreRound({ subject: goodSubj, control: { pass: true } }).verdict !== 'GO');

  // page-specific probe (round-2 V8): headline paraphrase must not be enough
  ok('probe with real evidence passes',
     scoreProbe({ probe: { question: 'q', answer: 'the artefact layer', evidence: 'asks you to lock a rebuild of the artefact layer' }, pageText: page }).pass);
  ok('probe with fabricated evidence is caught',
     !scoreProbe({ probe: { question: 'q', answer: 'x', evidence: 'not on the page anywhere at all' }, pageText: page }).pass);
  ok('probe with a hedged answer is caught',
     !scoreProbe({ probe: { question: 'q', answer: 'it appears to be the artefact layer', evidence: 'asks you to lock a rebuild of the artefact layer' }, pageText: page }).pass);

  console.log(fail ? 'self-test: FAILED' : 'self-test: all guards fire');
  return fail;
}
process.exit(main(process.argv.slice(2)));
