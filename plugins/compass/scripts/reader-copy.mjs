#!/usr/bin/env node
// reader-copy — THE extractor for the `compass-reader-copy` block. One implementation, two callers.
//
// There used to be two: gen.mjs matched /^```compass-reader-copy\n/ and copy-gate's awk matched
// /^```compass-reader-copy/. They agreed on the day they were written and disagreed the moment a
// fence line picked up a single trailing space — gen.mjs then LAID THE BLOCK OUT ON THE PAGE while
// copy-gate reported "N/A — no compass-reader-copy block", so unreviewed copy shipped to a reader
// through a gate that said it had checked. A trailing space is invisible in every renderer.
//
// CommonMark fence rules, because contracts are ordinary markdown: up to 3 leading spaces, 3+
// backticks, trailing whitespace allowed, CRLF allowed, and a block closes only on a fence at
// least as long as the one that opened it (so a 3-backtick sample can be nested inside a
// 4-backtick block without silently ending it — which used to leave the remainder unpoliced).
//
// Usage: reader-copy.mjs --extract <file>
// Exit:  0 block found (body on stdout) · 3 no block · 4 malformed (fence-like but unparseable,
//        or present-and-empty) — 4 is never a pass, because "I could not read it" is not "it is fine".

import { readFileSync } from 'node:fs';

const NAME = 'compass-reader-copy';
const OPEN = new RegExp(String.raw`^ {0,3}(\`{3,})${NAME}[ \t]*\r?$`);
// A line that was MEANT to be the fence but cannot be parsed as one. Recognising these is what
// turns a silent N/A-pass into a loud refusal.
const FENCEISH = new RegExp(String.raw`^\s*\`+\s*${NAME}`, 'i');

export function extractReaderCopy(text) {
  const lines = String(text || '').split('\n');
  let open = -1, ticks = 0;
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(OPEN);
    if (m) { open = i; ticks = m[1].length; break; }
  }
  if (open === -1) {
    const near = lines.findIndex((l) => FENCEISH.test(l));
    if (near > -1) {
      return { status: 'malformed', body: '', line: near + 1,
        why: `line ${near + 1} looks like a ${NAME} fence but is not one (leading spaces > 3, or stray characters after the name): ${JSON.stringify(lines[near])}` };
    }
    return { status: 'absent', body: '', why: `no ${NAME} block` };
  }
  const CLOSE = new RegExp(String.raw`^ {0,3}\`{${ticks},}[ \t]*\r?$`);
  for (let j = open + 1; j < lines.length; j++) {
    if (CLOSE.test(lines[j])) {
      const body = lines.slice(open + 1, j).join('\n');
      if (!body.trim()) {
        return { status: 'malformed', body: '', line: open + 1,
          why: `the ${NAME} block at line ${open + 1} is EMPTY. An empty block is a block someone meant to fill, not a page with no reader copy.` };
      }
      return { status: 'ok', body, line: open + 1 };
    }
  }
  return { status: 'malformed', body: '', line: open + 1,
    why: `the ${NAME} block opened at line ${open + 1} is never closed by a fence of ${ticks}+ backticks` };
}

// Parse the body into key → value(s). Repeated keys accumulate (the scope ladder needs many).
// ── v0.34 S9 — THE KEY VOCABULARY, DERIVED FROM THE GENERATOR, DECLARED HERE ──────────────────
// Wiring the gate into the lock proves a block EXISTS, not that it reaches the page. A reviewer
// showed a contract cut down to a single `build-what:` key PASSES the gate and its rendered brief
// gets WORSE — 16 internal codes become 17 — because `rc(key, fallback)` silently substitutes the
// spec's own prose for every key the block does not supply. A misspelled `done_means:` does the
// same thing, quietly.
//
// These eight are what `gen.mjs` actually reads: derived by scanning its rc/rcList/rcText call
// sites, not typed from memory. Hand-typing a set has been the cause of four separate defects in
// this build alone.
export const READER_COPY_KEYS = ['build-what', 'done-means', 'proof', 'blast-radius', 'now', 'later', 'never', 'rollback'];

// TWO RULES, and they are deliberately not the same strength.
//
// UNKNOWN KEY -> REFUSE. It is structural, decidable, and it is the silent one: a typo renders the
// spec's prose under a heading that promises plain words, and nothing anywhere says so.
//
// MISSING KEY -> REPORT, never refuse. A block that omits a key falls back on purpose, and
// demanding all eight would refuse the shipped `fixtures/copy/clean.txt` — which carries ZERO keys
// and which `assert-invariants.sh:316` requires this gate to PASS — plus a real contract on this
// machine that omits `later`. A rule that fires on correct work gets switched off within a week,
// and this build demoted ten of its own rules for exactly that reason.
// THE SIGNAL IS THE SOURCE CASE, and getting this wrong twice is instructive.
//
// `parseReaderCopy` accepts any `Name:` line, because the block is prose with keys in it. So an
// ordinary sentence starting "Note:" or "Example:" parsed as a key, and the unknown-key rule then
// HARD-BLOCKED a contract lock over a comma. A reviewer found it live.
//
// The first fix asked whether the key "looks like a key" — lowercase and hyphenated. That is
// exactly backwards: `note` passes that test and IS prose, while `done_means` fails it and IS the
// misspelled key the rule exists to catch. The distinguishing fact is not the shape of the word,
// it is that **every real key is written lowercase in the source and a sentence is not**. The
// parser lowercases before anyone can see that, so this reads the BODY.
export function checkReaderCopyKeys(parsed, body) {
  const known = new Set(READER_COPY_KEYS);
  // names exactly as the author typed them, before parseReaderCopy folded the case
  const rawNames = [];
  for (const line of String(body || '').split('\n')) {
    const m = line.match(/^\s*([A-Za-z][A-Za-z0-9_.-]*)\s*:\s*\S/);
    if (m) rawNames.push(m[1]);
  }
  const unknown = rawNames.filter((n) => n === n.toLowerCase() && !known.has(n.toLowerCase()));
  const missing = READER_COPY_KEYS.filter((k) => !(k in (parsed || {})));
  return { unknown: [...new Set(unknown)], missing };
}

export function parseReaderCopy(body) {
  const out = {};
  for (const line of String(body || '').split('\n')) {
    // Leading whitespace is allowed: a fence indented inside a list item carries its indent into
    // every body line, and a parser that ignored that read the block as empty.
    const m = line.match(/^\s*([A-Za-z][A-Za-z0-9_.-]*)\s*:\s*([\s\S]*)$/);
    if (!m) continue;
    const k = m[1].toLowerCase(), v = m[2].trim();
    if (!v) continue;
    if (k in out) out[k] = [].concat(out[k], v); else out[k] = v;
  }
  return out;
}

function main(argv) {
  // --keys <file>: print the vocabulary verdict for a file's block. Exit 1 on an UNKNOWN key,
  // 0 otherwise; missing keys are printed and never fail. See checkReaderCopyKeys for why the two
  // rules differ in strength.
  const ki = argv.indexOf('--keys');
  if (ki !== -1 && argv[ki + 1]) {
    let t; try { t = readFileSync(argv[ki + 1], 'utf8'); } catch { console.error('reader-copy: cannot read'); return 4; }
    const r = extractReaderCopy(t);
    if (r.status !== 'ok') { console.log(`keys: n/a (${r.status})`); return 0; }
    const { unknown, missing } = checkReaderCopyKeys(parseReaderCopy(r.body), r.body);
    if (missing.length) console.log(`missing: ${missing.join(' ')}`);
    if (unknown.length) { console.log(`unknown: ${unknown.join(' ')}`); return 1; }
    console.log('keys: every key is one the generator reads');
    return 0;
  }
  const i = argv.indexOf('--extract');
  if (i === -1 || !argv[i + 1]) { console.error('usage: reader-copy.mjs --extract <file>'); return 2; }
  let text;
  try { text = readFileSync(argv[i + 1], 'utf8'); }
  catch (e) { console.error(`reader-copy: cannot read ${argv[i + 1]} (${e.message})`); return 4; }
  const r = extractReaderCopy(text);
  if (r.status === 'ok') { process.stdout.write(r.body); return 0; }
  console.error(`reader-copy: ${r.why}`);
  return r.status === 'absent' ? 3 : 4;
}

if (process.argv[1] && process.argv[1].endsWith('reader-copy.mjs')) process.exit(main(process.argv.slice(2)));
