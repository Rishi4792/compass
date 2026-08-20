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
