#!/usr/bin/env node
// g3-check — structural validator for the G3 gate (house-style).
// A script CANNOT prove the scorer was a truly independent agent (that's an
// honor-system step — the USER is the final backstop). What it CAN enforce is that
// the gate leaves a COMPLETE, FALSIFIABLE record that the user can spot-check:
//   • a real full-page screenshot exists (size guard discourages a flattering 1px crop)
//   • score.md scores EVERY gestalt item (G_a..G_e) with a PASS/FAIL + evidence
//   • the LATEST round is all-PASS, OR carries a literal `owner-signed:` exception
// This shrinks "theater" to exactly the judgment call, on the record, for the user.
//
// Usage: node g3-check.mjs <proof-dir>   (expects shot.png + score.md inside)

import { readFileSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const dir = process.argv[2];
if (!dir) { console.error('usage: g3-check <proof-dir>'); process.exit(2); }
const shot = join(dir, 'shot.png'), score = join(dir, 'score.md');
const problems = [];

// 1. full-page screenshot exists and isn't a tiny crop
if (!existsSync(shot)) problems.push('shot.png missing — a full-page screenshot is required');
else { const kb = statSync(shot).size / 1024; if (kb < 10) problems.push(`shot.png is only ${kb.toFixed(0)}KB — suspiciously small; a full-page screenshot is required (anti-crop)`); }

// 2. score.md scores every gestalt item
if (!existsSync(score)) { problems.push('score.md missing — the independent scorer must write it'); }
else {
  const s = readFileSync(score, 'utf8');
  const ITEMS = ['G_a', 'G_b', 'G_c', 'G_d', 'G_e'];
  for (const it of ITEMS) {
    const row = new RegExp(`${it}[^|\\n]*\\|\\s*(PASS|FAIL)`, 'i').exec(s);
    if (!row) problems.push(`${it}: not scored (need a "| ${it} … | PASS/FAIL | evidence |" row)`);
  }
  // 3. latest round all-PASS, or a literal owner-signed exception
  const lastVerdict = [...s.matchAll(/VERDICT:\s*([^\n]+)/gi)].pop();
  const fails = (s.match(/\|\s*FAIL\b/gi) || []).length;
  const ownerSigned = /owner-signed:\s*\S/i.test(s);
  if (!lastVerdict) problems.push('no VERDICT line');
  else if (!/ALL-PASS/i.test(lastVerdict[0]) && !ownerSigned) {
    problems.push(`latest VERDICT is not ALL-PASS ("${lastVerdict[1].trim()}") and no "owner-signed:" exception — gate not cleared`);
  }
  if (fails > 0 && /ALL-PASS/i.test(lastVerdict ? lastVerdict[0] : '') ) {
    // a FAIL row in an earlier round is fine (append-only history); only warn if the file is single-round
    if (!/round\s*2|v2|re-score|fresh/i.test(s)) problems.push(`score.md shows FAIL rows but claims ALL-PASS and has no round history — overwrite suspected (keep an append-only log)`);
  }
}

if (problems.length === 0) { console.log(`g3-check: ${dir} record is complete + cleared (independent judgment is the user's to spot-check)`); process.exit(0); }
console.error(`g3-check: ${problems.length} issue(s) in ${dir}:`);
for (const p of problems) console.error('  - ' + p);
process.exit(1);
