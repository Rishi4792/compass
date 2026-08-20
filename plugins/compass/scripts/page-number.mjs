#!/usr/bin/env node
// v0.31 — THE reader that says what number a rendered page states. One implementation, two callers.
//
// Review-1 round 3 (R3-C4) found both value-half readers wrote a "tag-tolerant" regex —
// `(\d+)(?:\s|<[^>]+>|&nbsp;)*findings` — on a string whose tags had ALREADY been replaced by `|`
// one line earlier. The `<[^>]+>` branch could never match: the tolerance was dead code. Worse, the
// `|` left behind sat between the number and the noun, so `<span>3</span> findings` read as NONE —
// the reader reported "the page states no number" about a page plainly stating one. And
// recount-check.sh had the plainest form, `(\d+) findings`, which fails on any markup at all.
//
// Two readers that disagree are not two readers, they are one bug and one accident. This is the
// single implementation both now call.
//
// Inline tags are REMOVED (a number wrapped in a span is still that number to a reader); every
// other tag becomes `|` (a separator), so a count can never be read across a table-cell boundary.
import { readFileSync } from 'node:fs';

const INLINE = /<\/?(?:span|b|strong|em|i|u|a|sup|sub|small|code|abbr|mark|time|var|q|s)\b[^>]*>/gi;

export function pageText(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(INLINE, '')          // inline markup is invisible to a reader — drop it entirely
    .replace(/<[^>]+>/g, '|')     // every other tag is a boundary a number may not cross
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/[ \t]+/g, ' ');
}

// The number this page states for `noun`, or null. Only whitespace may sit between them — after the
// normalisation above, anything else means they are not the same phrase.
export function statedNumber(html, noun = 'findings') {
  const m = pageText(html).match(new RegExp(String.raw`(\d[\d,]*)\s*` + noun, 'i'));
  return m ? m[1].replace(/,/g, '') : null;
}

export function refuses(html) {
  return /could not be read|No review has been recorded|cannot be counted/i.test(pageText(html));
}


// INV-0b for this file. Round 6 found it pinned by nothing and guarded by no controls, so replacing
// three functions turned the defeat corpus from "2 of 2 failing" into "0 failing, EXIT 0" — a dead
// reader that nothing detected. `page-audit.mjs` had both; this one had neither.
export const CONTROLS = [
  { why: "a plain stated number is read", html: "<p>3 findings</p>", noun: "findings", want: "3" },
  { why: "a number inside inline markup is still read", html: "<p><span>3</span> findings</p>", noun: "findings", want: "3" },
  { why: "a number may not be read across a table-cell boundary", html: "<td>3</td><td>findings</td>", noun: "findings", want: null },
  { why: "a thousands separator is read", html: "<p>1,051 findings</p>", noun: "findings", want: "1051" },
  { why: "a non-breaking space is read", html: "<p>3&nbsp;findings</p>", noun: "findings", want: "3" },
  { why: "a refusal is recognised", html: "<p>could not be read</p>", noun: "findings", want: null, refuses: true },
  { why: "a page stating nothing is not a refusal", html: "<p>nothing here</p>", noun: "findings", want: null, refuses: false },
];

export function runControls() {
  return CONTROLS.filter((c) => {
    const got = statedNumber(c.html, c.noun);
    if (String(got) !== String(c.want)) return true;
    if (c.refuses !== undefined && refuses(c.html) !== c.refuses) return true;
    return false;
  });
}

// ONE entry point, guarded by a real path comparison. There used to be two: an older block using
// `file://${process.argv[1]}`, which silently never fired when the repo path contained a space and
// DID fire in a copy — where it then tried to read the string "--controls" as a file and crashed.
// Same class as the symlink guard: comparing constructed strings instead of resolved URLs.
import { pathToFileURL } from "node:url";
import { realpathSync } from "node:fs";
// `import.meta.url` is the REALPATH; `pathToFileURL(process.argv[1])` is not. On macOS `/tmp` and
// `/var` are symlinks, as are Docker mounts and symlinked worktrees — so invoked through one of
// those this guard was false, `--controls` printed NOTHING and exited 0, and both callers read
// "exit 0, no output" as "all controls fire". The control-of-controls was silently off. The earlier
// comment here claimed this class was closed: it closed the spaces case, not the symlink case.
const _self = (() => { try { return pathToFileURL(realpathSync(process.argv[1] || "")).href; } catch { return ""; } })();
if (_self && import.meta.url === _self) {
  if (process.argv[2] === "--controls") {
    const failed = runControls();
    if (failed.length) {
      console.log("page-number: " + failed.length + " control(s) NOT firing:");
      for (const f of failed) console.log("    " + f.why);
      process.exit(1);
    }
    console.log("page-number: all " + CONTROLS.length + " controls fire");
  } else if (process.argv[2]) {
    const html = readFileSync(process.argv[2], "utf8");
    const n = statedNumber(html, process.argv[3] || "findings");
    console.log(n !== null ? n : (refuses(html) ? "REFUSED" : "NONE"));
  }
}
