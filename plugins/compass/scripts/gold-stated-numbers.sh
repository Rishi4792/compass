#!/usr/bin/env bash
# v0.31 GOLD, LABEL HALF — how many numbers do Compass pages STATE, and how many are accounted for?
#
# Three bounds, not one. Review-1 proved a single derived difference is gameable: a three-line
# post-processor that wraps every numeral in a provenance span drives `unprovenanced` to 0 while
# every number is still produced by the same prose parsers and can still be wrong; and suppressing
# all numerals scores a perfect zero too. So:
#   pages == 140        the page set is PINNED by gold-manifest.txt, never globbed. A glob drifts
#                       the moment a new build gets a contract, which this build itself schedules.
#   stated >= 1051     a page that stops stating numbers must not pass. "State fewer" is the
#                       sanctioned direction of travel, so the floor is load-bearing.
#   unprovenanced == 0  POSITIONALLY — a stated number counts as accounted-for only when its OWN
#                       element carries data-prov. Counting attributes anywhere in the document is
#                       exactly what the label-only mutation exploited.
#
# This is only HALF the gold. A label is not a value. The value half lives in
# scripts/fixtures/defeat/ and is checked by defeat-corpus-check.sh — neither half passes alone.
set -uo pipefail
ROOT="${1:-.}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAN="$HERE/gold-manifest.txt"
G="$ROOT/plugins/compass/skills/compass-visual/gen.mjs"
[ -f "$MAN" ] || { echo "gold: no manifest at $MAN — the page set must be pinned, not globbed."; exit 2; }
[ -f "$G" ]   || { echo "gold: no generator at $G"; exit 2; }

WANT_PAGES=140; WANT_STATED=1051
tot=0; prov=0; pages=0; missing=""
while IFS= read -r line; do
  case "$line" in \#*|"") continue ;; esac
  slug="${line%% *}"
  [ -n "$slug" ] || continue
  d="$ROOT/.claude/builds/$slug"
  [ -f "$d/contract.md" ] || { missing="$missing $slug"; continue; }
  for v in brief brief-body plan-map release-card review; do
    node "$G" "$d" "$v" --out /tmp/gsn.html >/dev/null 2>&1 || continue
    pages=$((pages+1))
    read -r n p < <(node -e '
const fs=require("fs");
const h=fs.readFileSync("/tmp/gsn.html","utf8");
// The noun set was 8 words and captured 367 of the 2489 numeral+word occurrences on these pages —
// 15%. Review-1 named the generator-COMPUTED ones it missed (`+N more`, `N rows`, `N files`,
// `N shipped`, `N done`, ...), which are exactly the ones this build is responsible for. Widened to
// 25 nouns: 1049 captured. The remainder are numerals inside quoted source text (a ledger row, a
// contract sentence), which the generator reproduces rather than computes, and which the value
// half — not a label — is the right instrument for.
const NOUN="findings?|steps?|invariants?|changes?|critical|major|minor|closed|open|more|rows?|files?|shipped|done|views?|items?|builds?|failures?|assertions?|checks?|pages?|defects?|rounds?|entries|to go";
const NUM=new RegExp("\\b\\d+ ("+NOUN+")\\b","g");
// stated: over rendered TEXT
const text=h.replace(/<style[\s\S]*?<\/style>/g," ").replace(/<[^>]+>/g," ").replace(/&[a-z]+;/g," ").replace(/\s+/g," ");
const stated=(text.match(NUM)||[]).length;
// accounted-for: POSITIONAL — the element carrying the number must itself carry data-prov
let ok=0;
for(const m of h.matchAll(/<([a-z]+)\b([^>]*)>([^<]*)<\/\1>/g)){
  const attrs=m[2], inner=m[3];
  if(!/data-prov="(declared|counted)"/.test(attrs)) continue;
  ok += (inner.match(NUM)||[]).length;
  // a marker on the element may also cover a bare numeral it wraps, e.g. <span data-prov>13</span> steps
  if(/^\s*\d+\s*$/.test(inner)) ok += 1;
}
console.log(stated, ok);')
    tot=$((tot+n)); prov=$((prov+p))
  done
done < "$MAN"

fail=0
[ -z "$missing" ] || { echo "gold: manifest names dirs that are not present:$missing"; fail=1; }
[ "$pages" -eq "$WANT_PAGES" ] || { echo "gold: pages=$pages, expected $WANT_PAGES (the pinned page set changed)"; fail=1; }
[ "$tot" -ge "$WANT_STATED" ] || { echo "gold: stated=$tot, floor is $WANT_STATED (a page that stops stating numbers does not pass)"; fail=1; }
un=$((tot-prov)); [ "$un" -le 0 ] || { echo "gold: unprovenanced=$un (a stated number whose own element carries no data-prov)"; fail=1; }
echo "pages=$pages stated=$tot provenanced=$prov unprovenanced=$un"
exit $fail
