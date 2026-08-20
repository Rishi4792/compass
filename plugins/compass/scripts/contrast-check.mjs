#!/usr/bin/env node
// contrast-check — WCAG contrast for a Compass artefact theme, in BOTH themes.
//
// Runs against the RESOLVED PAIRS, not the token file in isolation. A token file cannot show a bad
// pairing that gen.mjs composes — "every colour is in the palette" and "every pairing is legible"
// are different claims, and only the second one matters to a reader.
//
// Usage:
//   contrast-check.mjs <theme.json> [--html <generated.html>] [--json]
//   contrast-check.mjs --self-test
// Exit: 0 all pairs meet their target · 1 one or more fail · 2 usage/precondition

import { readFileSync, existsSync } from 'node:fs';

// The pairs that actually appear on the page. Adding a component means adding its pair here —
// a pair that is never listed is a pair nobody checked.
const PAIRS = [
  ['ink', 'bg', 4.5, 'body text on the page ground'],
  ['ink', 'surface', 4.5, 'body text on a card'],
  ['mut', 'bg', 4.5, 'secondary text on the page ground'],
  ['mut', 'surface', 4.5, 'secondary text on a card'],
  ['kicker', 'surface', 4.5, 'label text on a card'],
  ['accent', 'surface', 4.5, 'the signal colour as text'],
  ['greenFg', 'greenBg', 4.5, 'ok state'],
  ['amberFg', 'amberBg', 4.5, 'warn state'],
  ['redFg', 'redBg', 4.5, 'stop state'],
  ['chipFg', 'chipBg', 4.5, 'chip text'],
  ['line', 'bg', 1.2, 'hairline against the ground (structural, not text)'],
];

export function parseHex(v) {
  const m = String(v || '').trim().match(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/);
  if (!m) return null;
  let h = m[1];
  if (h.length === 3) h = h.split('').map((c) => c + c).join('');
  return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16));
}

export function relLuminance(rgb) {
  const [r, g, b] = rgb.map((c) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export function contrast(a, b) {
  const la = relLuminance(a), lb = relLuminance(b);
  const [hi, lo] = la > lb ? [la, lb] : [lb, la];
  return (hi + 0.05) / (lo + 0.05);
}

export function checkTheme(tokens, label) {
  const rows = [];
  for (const [fg, bg, target, why] of PAIRS) {
    const a = parseHex(tokens[fg]), b = parseHex(tokens[bg]);
    if (!a || !b) {
      // A missing or unparseable token must NEVER read as a pass — the whole point of the
      // ERR contract elsewhere in this build.
      rows.push({ theme: label, fg, bg, ratio: null, target, why, pass: false, note: 'token missing or not a hex value' });
      continue;
    }
    const ratio = contrast(a, b);
    rows.push({ theme: label, fg, bg, ratio: Math.round(ratio * 100) / 100, target, why, pass: ratio >= target });
  }
  return rows;
}

function selfTest() {
  let fail = 0;
  const ok = (l, c) => { console.log(`  ${c ? 'ok  ' : 'FAIL'} ${l}`); if (!c) fail = 1; };
  ok('black on white is 21:1', Math.round(contrast([0, 0, 0], [255, 255, 255])) === 21);
  ok('white on white is 1:1', Math.round(contrast([255, 255, 255], [255, 255, 255])) === 1);
  ok('#777 on #fff is below 4.5', contrast(parseHex('#777777'), parseHex('#ffffff')) < 4.5);
  ok('#595959 on #fff clears 4.5', contrast(parseHex('#595959'), parseHex('#ffffff')) >= 4.5);
  ok('3-digit hex expands', JSON.stringify(parseHex('#fff')) === JSON.stringify([255, 255, 255]));
  ok('a non-hex token returns null', parseHex('rgba(1,2,3,0.5)') === null);
  // the guard that matters: a missing token must FAIL, never silently pass
  const rows = checkTheme({ ink: '#000000' }, 'probe');
  ok('a missing token FAILS rather than passing', rows.some((r) => !r.pass && r.note));
  console.log(fail ? 'self-test: FAILED' : 'self-test: all guards fire');
  return fail;
}

function main(argv) {
  if (argv.includes('--self-test')) return selfTest();
  const file = argv[0];
  if (!file) { console.error('usage: contrast-check.mjs <theme.json> [--html <f>] [--json]'); return 2; }
  if (!existsSync(file)) { console.error(`contrast-check: no theme at ${file}`); return 2; }
  const theme = JSON.parse(readFileSync(file, 'utf8'));
  const light = checkTheme(theme, 'light');
  const dark = checkTheme({ ...theme, ...(theme._dark || {}) }, 'dark');
  const rows = [...light, ...dark];

  if (argv.includes('--json')) { console.log(JSON.stringify(rows, null, 2)); }
  else {
    for (const r of rows) {
      const v = r.ratio === null ? 'n/a  ' : String(r.ratio).padEnd(5);
      console.log(`  ${r.pass ? 'ok  ' : 'FAIL'} ${r.theme.padEnd(5)} ${(r.fg + ' on ' + r.bg).padEnd(24)} ${v} (need ${r.target})  ${r.note || r.why}`);
    }
  }
  const bad = rows.filter((r) => !r.pass);
  if (bad.length) { console.error(`contrast-check: ${bad.length} pair(s) below target`); return 1; }
  console.log(`contrast-check: all ${rows.length} pairs meet target in both themes`);
  return 0;
}

process.exit(main(process.argv.slice(2)));
