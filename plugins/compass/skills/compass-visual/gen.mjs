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

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

// ── args ──────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
const dir = argv[0];
const view = argv[1];
const shareable = argv.includes('--shareable');
const outIdx = argv.indexOf('--out');
const outFile = outIdx >= 0 ? argv[outIdx + 1] : null;
if (!dir || !['brief', 'brief-body', 'cockpit'].includes(view || '')) {
  console.error('usage: node gen.mjs <build-dir> <brief|brief-body|cockpit> [--shareable] [--out <file>]');
  process.exit(2);
}
const read = (name) => (existsSync(join(dir, name)) ? readFileSync(join(dir, name), 'utf8') : '');
const contract = read('contract.md');
if (!contract) { console.error(`gen: no contract.md in ${dir}`); process.exit(2); }

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
const secs = sections(contract);
const sec = (needle) => {
  const k = Object.keys(secs).find((x) => x.toLowerCase().includes(needle.toLowerCase()));
  return k ? secs[k] : '';
};
const hdr = (key) => {
  const m = contract.match(new RegExp('^\\s*\\*{0,2}' + key.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&') + '\\*{0,2}\\s*:\\s*(.+)$', 'im'));
  return m ? m[1].replace(/\*/g, '').trim() : '';
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
const mdInline = (s) => s
  .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
  .replace(/(?<![\w*])\*([^*\n]+)\*(?![\w*])/g, '<em>$1</em>')
  .replace(/`([^`]+)`/g, '<code>$1</code>');
const txt = (s) => mdInline(esc(breakColors(String(s))));

// ── first paragraph of a section (skips leading blank/bold-label lines) ──
function firstPara(body) {
  const paras = body.split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
  return paras[0] || '';
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
    const m = l.match(/^-\s+\*\*(INV-[A-Z0-9][A-Z0-9-]*)[^*]*\*\*:?\s*(.*)$/);
    if (!m) continue;
    // drop ONLY the "→ *assert:*" recipe tail — NOT every internal arrow, or binding text is lost
    // (INV-COMMSCAN's "→ CRITICAL", INV-SUITES' full "→ 0 … → PASS" chain, INV-NO-LEAK) (R3-M2).
    let summary = m[2].split(/→\s*\*?\s*assert/i)[0].replace(/\*/g, '').replace(/[:.\s]+$/, '').trim();
    rows.push({ name: m[1], summary });
  }
  return rows;
}
// ── scope ladder NOW / LATER / NEVER ──
function scope() {
  const body = sec('Scope ladder') || sec('scope');
  const pick = (kw) => bullets(body, new RegExp('^-\\s+' + kw + '\\b', 'i'))
    .map((l) => l.replace(new RegExp('^-\\s+' + kw + '\\s*:?\\s*', 'i'), '').replace(/\*/g, '').trim());
  return { now: pick('NOW'), later: pick('LATER'), never: pick('NEVER') };
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
const HOUSE_CSS = `
  :root{
    --ink:#0A2540; --mut:#5A6472; --mut2:#657081; --kicker:#606B7B;
    --accent:#4F46E5; --accentDark:#271DD0;
    --greenFg:#0E6245; --greenBg:#E6F8F1;
    --amberFg:#9A6A14; --amberBg:#FFF9EE; --amberBorder:#F5E3BC;
    --redFg:#A41C00; --redBg:#FCE8E6;
    --chipFg:#3F4650; --chipBg:#E9EBEF;
    --bg:#F9FAFB; --surface:#FFFFFF; --headBg:#FBFBFC; --line:#F2F4F5; --grid:#F0F1F3;
  }
  *{box-sizing:border-box;margin:0}
  .cv-body{background:var(--bg);color:var(--ink);
    font-family:'Inter',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
    font-variant-numeric:tabular-nums;-webkit-font-smoothing:antialiased;padding:34px}
  .cv-body .wrap{max-width:1120px;margin:0 auto}
  .cv-body .kicker{font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--kicker)}
  .cv-body h1{font-size:23px;font-weight:700;letter-spacing:-.01em;margin-top:4px}
  .cv-body .lede{font-size:14px;color:var(--mut);margin-top:8px;line-height:1.55;max-width:80ch}
  .cv-body .lede b{color:var(--ink);font-weight:600}
  .cv-body .card{background:var(--surface);border:1px solid var(--line);border-radius:12px;
    box-shadow:0 1px 2px rgba(10,37,64,.04);padding:18px 20px;margin-top:16px}
  .cv-body .card>.kicker{margin-bottom:8px;font-weight:700;text-transform:uppercase}
  .cv-body .grid2{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-top:16px}
  .cv-body .grid3{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-top:16px}
  .cv-body p{font-size:13px;color:var(--mut);line-height:1.55}
  .cv-body p b{color:var(--ink);font-weight:600}
  .cv-body code{font-family:ui-monospace,monospace;font-size:12px;background:var(--chipBg);color:var(--ink);padding:1px 5px;border-radius:5px}
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
`;

// ── house-style Brief body (returns inner markup; used standalone AND inside the full brief) ──
function briefBody() {
  const goal = firstPara(sec('Goal') || sec('Goal & scope'));
  const touchesBody = sec('Data / Schema / Scale') || sec('Data');
  const inv = invariants();
  const sc = scope();
  const security_ = security();
  const facets = hdr('Facets') || 'library';
  const deploy = hdr('deploy');
  const mode = hdr('Mode');

  // reconciliation gold: full literal (local) vs redacted badge (shareable)
  const goldCard = shareable
    ? `<span class="badge">gold pinned ✓</span>
       <p style="margin-top:8px">The reconciliation gold is pinned in this build's <b>local</b> Brief and enforced by the suites; its literal is withheld from the shareable copy.</p>`
    : bodyHtml(goldBody);   // LOCAL: the FULL gold literal (figure + tolerance in any paragraph) — SKILL.md:34 (post-ship PS-1r4-B)

  // security card: honest about present / genuine-N/A / absent
  let secCard;
  if (!security_.present) {
    secCard = `<span class="chip">no Security &amp; data-sensitivity block in this contract</span>
      <p style="margin-top:8px">This contract carries no security block — treat the sensitive surface as <b>unclassified</b>, not as a cleared "N/A". (F-SECPIN makes this block required going forward.)</p>`;
  } else if (security_.na) {
    secCard = `<span class="badge">N/A — no sensitive surface</span>
      <p style="margin-top:8px">${txt(security_.naReason || 'declared N/A with reason')}</p>`;
  } else if (shareable) {
    // SHAREABLE: classification LABEL (first para) + never-show VALUES redacted (accepted best-effort leak gate; Phase-2).
    const nsList = (security_.neverShow || []).map(() =>
      `<li><b>never-show:</b> <span class="chip">⟨redacted ✓⟩</span></li>`).join('');
    secCard = `<p>${txt(firstPara(security_.body))}</p>${nsList ? `<ul style="margin-top:8px">${nsList}</ul>` : ''}`;
  } else {
    // LOCAL: the FULL security block — classification + never-show + role×view matrix + STRIDE-lite (post-ship PS-1r4-B).
    secCard = bodyHtml(security_.body);
  }

  const invRows = inv.map((r, i) =>
    `<tr><td><span class="n">${txt(r.name)}</span></td><td>${txt(r.summary)}</td></tr>`).join('');
  const scopeCol = (cls, label, items) =>
    `<div class="col ${cls}"><div class="hd">${label}</div><ul>${items.length ? items.map((x) => `<li>${txt(x)}</li>`).join('') : '<li>—</li>'}</ul></div>`;

  return `
<section class="cv-body"><div class="wrap">
  <div class="kicker">Compass · Contract Brief${shareable ? ' · shareable' : ''}</div>
  <h1>${txt(title)}</h1>
  <p class="lede">${txt(goal)}</p>
  <div class="row" style="margin-top:12px">
    <span class="chip">facet: ${txt(facets)}</span>
    ${deploy ? `<span class="chip">deploy: ${txt(deploy.split('—')[0])}</span>` : ''}
    ${mode ? `<span class="chip">mode: ${txt(mode.split('—')[0])}</span>` : ''}
  </div>${shareable ? `
  <div class="card" style="border-color:var(--amberBorder);background:var(--amberBg)">
    <span class="badge warn">Best-effort redaction — review before sending</span>
    <p style="margin-top:8px">Declared values (the reconciliation gold + never-show fields pinned in the brief-data fence) of 3+ significant digits are scrubbed with certainty across every numeric locale form. <b>Undeclared</b> restatements in free prose — unit words, spelled-out numbers, exotic formats — and very short (≤2-digit) or unit-suffixed values are best-effort. Read this copy before you send it.</p>
  </div>` : ''}

  <div class="grid2">
    <div class="card"><div class="kicker">What it touches</div><p>${txt(firstPara(touchesBody) || 'see plan')}</p></div>
    <div class="card"><div class="kicker">Reconciliation gold</div>${goldCard}</div>
  </div>

  <div class="card"><div class="kicker">Invariants — every "done" proves one of these</div>
    <table><thead><tr><th>Invariant</th><th>What it asserts</th></tr></thead><tbody>${invRows || '<tr><td>—</td><td>none declared</td></tr>'}</tbody></table>
  </div>

  <div class="card"><div class="kicker">Scope — now / later / never</div>
    <div class="cols">
      ${scopeCol('now', 'Now', sc.now)}
      ${scopeCol('later', 'Later', sc.later)}
      ${scopeCol('never', 'Never', sc.never)}
    </div>
  </div>

  <div class="card"><div class="kicker">Security &amp; data-sensitivity</div>${secCard}</div>

  <div class="foot">Generated from contract.md by compass-visual · a pure function of the build's state · lock the contract before anything proceeds.</div>
</div></section>`;
}

// ── cinematic-hero cover (full brief only) — its OWN accent + grade, excluded from the house gate ──
function cover() {
  const goal = firstPara(sec('Goal') || sec('Goal & scope'));
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
  .cv-cover .sub code{font-family:ui-monospace,monospace;font-size:15px;color:#B8B2FF}
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
  const status = (progress.match(/\*\*Status:\*\*\s*(.+)/) || [, '—'])[1].trim();
  const stage = (progress.match(/\*\*Stage:\*\*\s*(.+)/) || [, '—'])[1].trim();
  const next = (progress.match(/\*\*Next:\*\*\s*(.+)/) || [, '—'])[1].trim();
  const done = (plan.match(/^\s*- \[x\]/gim) || []).length;
  const total = (plan.match(/^\s*- \[[ x]\]/gim) || []).length;
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
      <p><span class="badge">${done}/${total} steps</span></p>
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

// ── full HTML page wrapper (line 1 = <!doctype html>, NEVER a COMPASS-MOCK marker) ──
function page(styleBlocks, bodyMarkup) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)} · compass-visual</title>
<style>${styleBlocks}</style></head>
<body>${bodyMarkup}
</body></html>
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
  const R = '<span class="chip">⟨redacted ✓⟩</span>';
  const SECRETS = [
    [/sk-[A-Za-z0-9]{8,}/g, 'api key'],
    [/AKIA[0-9A-Z]{12,}/g, 'aws access key'],
    [/xox[baprs]-[A-Za-z0-9-]{8,}/g, 'slack token'],
    [/eyJ[A-Za-z0-9_-]{6,}\.eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}/g, 'jwt'],
    [/-----BEGIN [A-Z ]*PRIVATE KEY-----/g, 'pem private key'],
    [/\b[a-z][a-z0-9+.-]*:\/\/[^:@/\s]+:[^@/\s]+@/g, 'inline url credentials'],
    [/\b[A-Z][A-Z0-9_]*(?:SECRET|TOKEN|PASSWORD|APIKEY|API_KEY)\s*[:=]\s*['"]?[^\s'"<]+/g, 'inline secret assignment'],
  ];
  // commercial-sensitive VALUES: the term adjacent to a numeric value (not the bare vocabulary).
  const COMMERCIAL = [[/\b(?:IRR|take[- ]?rate|gross[- ]?rev(?:enue)?|COF)\b[^.\n<]{0,12}?\d[\d.,%]*/gi, 'commercial value']];
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
      const re = new RegExp(esc_re(form), 'g');
      if (re.test(out)) { hits.push('declared gold residue'); out = out.replace(re, R); }
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
    const re = new RegExp(esc_re(v), 'gi');
    if (re.test(out)) { hits.push('never-show residue'); out = out.replace(re, R); }
  }
  return { out, hits };
}

// ── build ─────────────────────────────────────────────────────────────────────
let html;
if (view === 'brief-body') {
  html = page(HOUSE_CSS, briefBody());
} else if (view === 'brief') {
  html = page(HOUSE_CSS, cover() + briefBody());
} else { // cockpit
  const c = cockpit();
  html = page(HOUSE_CSS + c.extra, c.body);
}

if (shareable && (view === 'brief' || view === 'brief-body')) {
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

if (outFile) { writeFileSync(outFile, html); process.stderr.write(`wrote ${outFile} (${html.length} bytes)\n`); }
else process.stdout.write(html);
