#!/usr/bin/env node
// seeds-to-tokens — PURE deterministic generator (house-style).
// 4 identity seeds → a full coherent TOKENS scale (the SYSTEM.md Part-1 shape).
// No Date / no random → same seeds produce byte-identical output.
//
// Usage: node seeds-to-tokens.mjs '<seeds-json>'   OR   node seeds-to-tokens.mjs path/to/seeds.json
// Seeds: { accent:"#635BFF", neutral:"cool"|"warm"|"true", font:"'Inter',sans-serif",
//          density:"airy"|"dense", radius:"soft"|"sharp" }

import { readFileSync } from 'node:fs';

// ── color math ───────────────────────────────────────────────────────────────
const clamp = (n, lo = 0, hi = 255) => Math.max(lo, Math.min(hi, n));
function hexToRgb(h) {
  const s = h.replace('#', '');
  const n = s.length === 3 ? s.split('').map((c) => c + c).join('') : s;
  return [parseInt(n.slice(0, 2), 16), parseInt(n.slice(2, 4), 16), parseInt(n.slice(4, 6), 16)];
}
const rgbToHex = (r, g, b) =>
  '#' + [r, g, b].map((v) => clamp(Math.round(v)).toString(16).padStart(2, '0')).join('').toUpperCase();
function rgbToHsl(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  let h = 0, s = 0; const l = (max + min) / 2;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
    h /= 6;
  }
  return [h * 360, s * 100, l * 100];
}
function hslToRgb(h, s, l) {
  h /= 360; s /= 100; l /= 100;
  if (s === 0) { const v = l * 255; return [v, v, v]; }
  const hue2rgb = (p, q, t) => {
    if (t < 0) t += 1; if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  };
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  return [hue2rgb(p, q, h + 1 / 3) * 255, hue2rgb(p, q, h) * 255, hue2rgb(p, q, h - 1 / 3) * 255];
}
const hslHex = (h, s, l) => rgbToHex(...hslToRgb(h, s, l));
function adjustL(hex, dL) { const [h, s, l] = rgbToHsl(...hexToRgb(hex)); return hslHex(h, s, clamp(l + dL, 0, 100)); }
// mix a hue/sat toward white at lightness L (for surfaces)
const surfaceAt = (hue, sat, L) => hslHex(hue, sat, L);
function relLum([r, g, b]) {
  const a = [r, g, b].map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * a[0] + 0.7152 * a[1] + 0.0722 * a[2];
}
const contrast = (h1, h2) => {
  const L1 = relLum(hexToRgb(h1)), L2 = relLum(hexToRgb(h2));
  return (Math.max(L1, L2) + 0.05) / (Math.min(L1, L2) + 0.05);
};
// darken a neutral until it clears AA (≥4.5) on white
function ensureAA(hex, on = '#FFFFFF', ratio = 4.5) {
  let c = hex; let [h, s, l] = rgbToHsl(...hexToRgb(c));
  for (let i = 0; i < 100 && contrast(c, on) < ratio; i++) { l = Math.max(0, l - 1); c = hslHex(h, s, l); }
  return c;
}

// ── identity anchors (the 4 seeds resolve to these) ───────────────────────────
const NEUTRAL = {
  // ink anchor + neutral hue/sat per temperature. cool→#0A2540 (a deep navy anchor).
  cool: { ink: '#0A2540', hue: 215, sat: 12 },
  warm: { ink: '#2B2016', hue: 28, sat: 16 },
  true: { ink: '#1A1B1F', hue: 230, sat: 3 },
};
const RADII = {
  soft: { card: 12, chip: 6, pill: 99, inset: 8, control: 9 },
  sharp: { card: 8, chip: 5, pill: 99, inset: 6, control: 7 },
};
const DENSITY = { airy: { cardPad: '20px 22px' }, dense: { cardPad: '16px 18px' } };
// status pairs are UNIVERSAL craft (AA-tuned) — semantics don't change per brand.
const STATUS = {
  greenFg: '#0E6245', greenBg: '#E6F8F1',
  amberFg: '#9A6A14', amberBg: '#FFF9EE', amberBorder: '#F5E3BC',
  redFg: '#A41C00', redBg: '#FCE8E6',
};

// ── the generator ─────────────────────────────────────────────────────────────
export function generate(seeds) {
  // RB-03: guard a HOSTILE accent seed (near-white / neon) — darken until ≥3:1 on
  // white so it's never an invisible accent. Already-usable accents (e.g. #635BFF=4.7,
  // teal #0D9488=3.7) clear 3:1 and pass through UNCHANGED (calibration safe).
  const accent = ensureAA((seeds.accent || '#635BFF').toUpperCase(), '#FFFFFF', 3);
  const neutral = seeds.neutral || 'cool';
  const font = seeds.font || "'Inter',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif";
  const density = seeds.density || 'airy';
  const radius = seeds.radius || 'soft';
  const N = NEUTRAL[neutral] || NEUTRAL.cool;
  const { hue, sat } = N;
  const ink = N.ink;

  // ink ramp: muted text is a DESATURATED neutral at the brand hue (NOT the ink's
  // full saturation — that would read as a vivid color, not gray), then AA-guarded.
  const mut = ensureAA(hslHex(hue, sat, 40), '#FFFFFF', 4.5);   // secondary
  const mut2 = ensureAA(hslHex(hue, sat, 45), '#FFFFFF', 4.5);  // tertiary
  const kicker = ensureAA(hslHex(hue, sat, 43), '#FFFFFF', 4.5);// label

  return {
    // 1 INK
    ink, mut, mut2, kicker,
    // 2 ACCENT
    accent, accentDark: adjustL(accent, -12), accentWash: `rgba(${hexToRgb(accent).join(',')},0.07)`,
    // 3 STATUS (universal) + neutral chip (AA-safe dark-on-faint, brand-tinted)
    ...STATUS,
    chipFg: ensureAA(hslHex(hue, sat, 28), '#FFFFFF', 7),
    chipBg: surfaceAt(hue, sat * 1.3, 92.5),
    // 4 SURFACES — faint BRAND-tinted neutrals toward white (a touch of hue so the
    // canvas reads cool/warm like the brand, not dead gray). Higher sat, very high L.
    bg: surfaceAt(hue, sat * 2, 98),
    surface: '#FFFFFF',
    headBg: surfaceAt(hue, sat * 1.4, 98.6),
    line: surfaceAt(hue, sat * 1.2, 95.6),
    grid: surfaceAt(hue, sat, 94.6),
    // 5 TYPE
    fontSans: font,
    // 6/7/8/9
    spacing: { cardPad: DENSITY[density].cardPad, grid: 4 },
    radii: RADII[radius],
    shadow: { card: `0 1px 2px rgba(${hexToRgb(ink).join(',')},0.04)` },
    motion: { enter: '0.55s cubic-bezier(.22,.61,.36,1)', stagger: 0.06, hover: '120ms' },
    _meta: { seeds: { accent, neutral, font, density, radius } },
  };
}

// ── CLI ───────────────────────────────────────────────────────────────────────
const arg = process.argv[2];
if (arg) {
  let seeds;
  try { seeds = JSON.parse(arg); } catch { seeds = JSON.parse(readFileSync(arg, 'utf8')); }
  process.stdout.write(JSON.stringify(generate(seeds), null, 2) + '\n');
}
