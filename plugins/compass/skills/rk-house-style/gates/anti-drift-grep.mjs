#!/usr/bin/env node
// anti-drift-grep — GATE G1 (house-style).
// Greps an artifact (HTML/CSS/TSX) for any COLOR or FONT not in the active theme's
// allowlist. NORMALIZES color notations (hex / rgb / rgba / hsl → canonical hex,
// alpha ignored so theme washes like rgba(accent,.07) pass) before comparing — so an
// off-theme rgb() can't slip past a hex-only grep (RP4). Exit 0 = clean; exit 1 = drift.
//
// Usage: node anti-drift-grep.mjs <artifact> <theme.json>

import { readFileSync } from 'node:fs';

const [artifactPath, themePath] = process.argv.slice(2);
if (!artifactPath || !themePath) { console.error('usage: anti-drift-grep <artifact> <theme.json>'); process.exit(2); }
const src = readFileSync(artifactPath, 'utf8');
const theme = JSON.parse(readFileSync(themePath, 'utf8'));

// ── color normalization → "R,G,B" (alpha dropped) ────────────────────────────
const clamp = (n) => Math.max(0, Math.min(255, Math.round(n)));
function hexNorm(h) {
  let s = h.replace('#', '');
  if (s.length === 3 || s.length === 4) s = s.slice(0, 3).split('').map((c) => c + c).join(''); // RGB / RGBA-short → RGB
  if (s.length === 8) s = s.slice(0, 6); // RRGGBBAA → RRGGBB (drop alpha)
  if (s.length !== 6) return null;
  return [0, 2, 4].map((i) => parseInt(s.slice(i, i + 2), 16)).join(',');
}
// the 148 CSS named colors (RB-01: a named off-theme color must NOT slip past).
const NAMED = { aliceblue: '240,248,255', antiquewhite: '250,235,215', aqua: '0,255,255', aquamarine: '127,255,212', azure: '240,255,255', beige: '245,245,220', bisque: '255,228,196', black: '0,0,0', blanchedalmond: '255,235,205', blue: '0,0,255', blueviolet: '138,43,226', brown: '165,42,42', burlywood: '222,184,135', cadetblue: '95,158,160', chartreuse: '127,255,0', chocolate: '210,105,30', coral: '255,127,80', cornflowerblue: '100,149,237', cornsilk: '255,248,220', crimson: '220,20,60', cyan: '0,255,255', darkblue: '0,0,139', darkcyan: '0,139,139', darkgoldenrod: '184,134,11', darkgray: '169,169,169', darkgreen: '0,100,0', darkgrey: '169,169,169', darkkhaki: '189,183,107', darkmagenta: '139,0,139', darkolivegreen: '85,107,47', darkorange: '255,140,0', darkorchid: '153,50,204', darkred: '139,0,0', darksalmon: '233,150,122', darkseagreen: '143,188,143', darkslateblue: '72,61,139', darkslategray: '47,79,79', darkturquoise: '0,206,209', darkviolet: '148,0,211', deeppink: '255,20,147', deepskyblue: '0,191,255', dimgray: '105,105,105', dodgerblue: '30,144,255', firebrick: '178,34,34', floralwhite: '255,250,240', forestgreen: '34,139,34', fuchsia: '255,0,255', gainsboro: '220,220,220', ghostwhite: '248,248,255', gold: '255,215,0', goldenrod: '218,165,32', gray: '128,128,128', green: '0,128,0', greenyellow: '173,255,47', grey: '128,128,128', honeydew: '240,255,240', hotpink: '255,105,180', indianred: '205,92,92', indigo: '75,0,130', ivory: '255,255,240', khaki: '240,230,140', lavender: '230,230,250', lavenderblush: '255,240,245', lawngreen: '124,252,0', lemonchiffon: '255,250,205', lightblue: '173,216,230', lightcoral: '240,128,128', lightcyan: '224,255,255', lightgoldenrodyellow: '250,250,210', lightgray: '211,211,211', lightgreen: '144,238,144', lightgrey: '211,211,211', lightpink: '255,182,193', lightsalmon: '255,160,122', lightseagreen: '32,178,170', lightskyblue: '135,206,250', lightslategray: '119,136,153', lightsteelblue: '176,196,222', lightyellow: '255,255,224', lime: '0,255,0', limegreen: '50,205,50', linen: '250,240,230', magenta: '255,0,255', maroon: '128,0,0', mediumaquamarine: '102,205,170', mediumblue: '0,0,205', mediumorchid: '186,85,211', mediumpurple: '147,112,219', mediumseagreen: '60,179,113', mediumslateblue: '123,104,238', mediumspringgreen: '0,250,154', mediumturquoise: '72,209,204', mediumvioletred: '199,21,133', midnightblue: '25,25,112', mintcream: '245,255,250', mistyrose: '255,228,225', moccasin: '255,228,181', navajowhite: '255,222,173', navy: '0,0,128', oldlace: '253,245,230', olive: '128,128,0', olivedrab: '107,142,35', orange: '255,165,0', orangered: '255,69,0', orchid: '218,112,214', palegoldenrod: '238,232,170', palegreen: '152,251,152', paleturquoise: '175,238,238', palevioletred: '219,112,147', papayawhip: '255,239,213', peachpuff: '255,218,185', peru: '205,133,63', pink: '255,192,203', plum: '221,160,221', powderblue: '176,224,230', purple: '128,0,128', rebeccapurple: '102,51,153', red: '255,0,0', rosybrown: '188,143,143', royalblue: '65,105,225', saddlebrown: '139,69,19', salmon: '250,128,114', sandybrown: '244,164,96', seagreen: '46,139,87', seashell: '255,245,238', sienna: '160,82,45', silver: '192,192,192', skyblue: '135,206,235', slateblue: '106,90,205', slategray: '112,128,144', snow: '255,250,250', springgreen: '0,255,127', steelblue: '70,130,180', tan: '210,180,140', teal: '0,128,128', thistle: '216,191,216', tomato: '255,99,71', turquoise: '64,224,208', violet: '238,130,238', wheat: '245,222,179', white: '255,255,255', whitesmoke: '245,245,245', yellow: '255,255,0', yellowgreen: '154,205,50' };
function hslNorm(hh, ss, ll) {
  const h = (hh % 360) / 360, s = ss / 100, l = ll / 100;
  if (s === 0) { const v = clamp(l * 255); return [v, v, v].join(','); }
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
  const f = (t) => { if (t < 0) t += 1; if (t > 1) t -= 1; if (t < 1 / 6) return p + (q - p) * 6 * t; if (t < 1 / 2) return q; if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6; return p; };
  return [f(h + 1 / 3), f(h), f(h - 1 / 3)].map((x) => clamp(x * 255)).join(',');
}
// extract every color token from a string → list of {raw, norm}
function colorsIn(text) {
  const out = [];
  for (const m of text.matchAll(/#[0-9a-fA-F]{3,8}/g)) { const n = hexNorm(m[0]); if (n) out.push({ raw: m[0], norm: n }); }
  // comma OR space separators (modern CSS) + case-insensitive (RGB/Rgb/HSL all valid)
  for (const m of text.matchAll(/rgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)/gi)) out.push({ raw: m[0] + ')', norm: [m[1], m[2], m[3]].map((x) => clamp(+x)).join(',') });
  for (const m of text.matchAll(/hsla?\(\s*([\d.]+)[\s,]+([\d.]+)%[\s,]+([\d.]+)%/gi)) out.push({ raw: m[0] + ')', norm: hslNorm(+m[1], +m[2], +m[3]) });
  return out;
}
// named CSS colors are detected ONLY inside a CSS color-property VALUE (so the word
// "red"/"tan" in body text or a class name never false-fails). RB-01.
const COLOR_PROP = /(?:^|[;{\s"'])(?:color|background|background-color|border|border-top|border-right|border-bottom|border-left|border-color|fill|stroke|outline|outline-color|box-shadow|text-shadow|--[\w-]+)\s*:\s*([^;}!"'<>\n]+)/gi;
function namedColorsIn(text) {
  const out = [];
  for (const decl of text.matchAll(COLOR_PROP)) {
    for (const w of decl[1].matchAll(/\b([a-z]{3,20})\b/gi)) {
      const name = w[1].toLowerCase();
      if (NAMED[name] && !KEYWORDS.has(name)) out.push({ raw: name, norm: NAMED[name] });
    }
  }
  return out;
}

// ── allowlist: every color value in the theme + structural + the neutral grid ──
const allow = new Set();
const addColor = (v) => { if (typeof v !== 'string') return; for (const c of colorsIn(v)) allow.add(c.norm); };
for (const v of Object.values(theme)) {
  if (typeof v === 'string') addColor(v);
  else if (v && typeof v === 'object') for (const vv of Object.values(v)) addColor(vv);
}
['#FFFFFF', '#000000', '#EEF1F6', '#FAFBFC', '#F6F9FC'].forEach((h) => allow.add(hexNorm(h))); // structural neutrals
const KEYWORDS = new Set(['transparent', 'inherit', 'currentColor', 'currentcolor', 'none', 'unset']);

// ── font allowlist: the theme's font stack family names ────────────────────────
const themeFonts = new Set();
for (const key of ['fontSans', 'fontMono']) {
  const stack = theme[key]; if (!stack) continue;
  for (const fam of stack.split(',')) themeFonts.add(fam.trim().replace(/['"]/g, '').toLowerCase());
}
const GENERIC_FONTS = new Set(['sans-serif', 'serif', 'monospace', 'system-ui', 'ui-monospace', 'ui-sans-serif', '-apple-system', 'blinkmacsystemfont', 'inherit']);

// ── scan the artifact ─────────────────────────────────────────────────────────
const offColors = [];
for (const c of [...colorsIn(src), ...namedColorsIn(src)]) if (!allow.has(c.norm)) offColors.push(c);
// dedupe by norm
const seen = new Set(); const offC = offColors.filter((c) => (seen.has(c.norm) ? false : seen.add(c.norm)));

const offFonts = [];
for (const m of src.matchAll(/font-family\s*:\s*([^;}]+)/gi)) {
  for (const fam of m[1].split(',')) {
    const f = fam.trim().replace(/['"]/g, '').toLowerCase();
    if (!f) continue;
    if (!themeFonts.has(f) && !GENERIC_FONTS.has(f)) offFonts.push(fam.trim());
  }
}
const offF = [...new Set(offFonts)];

if (offC.length === 0 && offF.length === 0) {
  console.log(`anti-drift: 0 off-theme tokens (${artifactPath} vs ${theme._name || themePath})`);
  process.exit(0);
}
if (offC.length) console.error(`anti-drift: ${offC.length} OFF-THEME color(s): ${offC.map((c) => `${c.raw}→${c.norm}`).join('  ')}`);
if (offF.length) console.error(`anti-drift: ${offF.length} OFF-THEME font(s): ${offF.join(', ')}`);
process.exit(1);
