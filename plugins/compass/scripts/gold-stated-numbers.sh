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

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
WANT_PAGES=140; WANT_STATED=1051
tot=0; prov=0; pages=0; refused=0; decl_marks=0; missing=""; fail_ck=0
while IFS= read -r line; do
  case "$line" in \#*|"") continue ;; esac
  slug="${line%% *}"
  [ -n "$slug" ] || continue
  d="$ROOT/.claude/builds/$slug"
  [ -f "$d/contract.md" ] || { missing="$missing $slug"; continue; }
  # VERIFY the checksums. They were recorded and then compared by nothing, so the claim that a
  # re-measurement on another machine "says so" if the input differs was simply false.
  want_ck="${line#* }"
  if [ "$want_ck" != "$line" ] && [ -n "$want_ck" ]; then
    got_ck="$(for f in contract.md plan.md review-ledger.md progress.md receipts.md; do
        [ -f "$d/$f" ] && shasum -a 256 "$d/$f" | cut -c1-12; done | paste -sd'.' -)"
    [ "$got_ck" = "$want_ck" ] || { echo "gold: $slug has changed since the baseline (manifest $want_ck, now $got_ck)"; fail_ck=1; }
  fi
  for v in brief brief-body plan-map release-card review; do
    node "$G" "$d" "$v" --out "$TMP/gsn.html" >/dev/null 2>&1 || continue
    pages=$((pages+1))
    read -r n p < <(PAGE="$TMP/gsn.html" node -e '
const fs=require("fs");
const h=fs.readFileSync(process.env.PAGE,"utf8");
// The noun set was 8 words and captured 367 of the 2489 numeral+word occurrences on these pages —
// 15%. Review-1 named the generator-COMPUTED ones it missed (`+N more`, `N rows`, `N files`,
// `N shipped`, `N done`, ...), which are exactly the ones this build is responsible for. Widened to
// 25 nouns: 1051 captured. The remainder are numerals inside quoted source text (a ledger row, a
// contract sentence), which the generator reproduces rather than computes, and which the value
// half — not a label — is the right instrument for.
const NOUN="findings?|steps?|invariants?|changes?|critical|major|minor|closed|open|more|rows?|files?|shipped|done|views?|items?|builds?|failures?|assertions?|checks?|pages?|defects?|rounds?|entries|to go";
const NUM=new RegExp("\\b\\d+ ("+NOUN+")\\b","g");
// stated: over rendered TEXT
const text=h.replace(/<style[\s\S]*?<\/style>/g," ").replace(/<[^>]+>/g," ").replace(/&[a-z]+;/g," ").replace(/\s+/g," ");
const stated=(text.match(NUM)||[]).length;
// accounted-for: POSITIONAL, and each stated number counted AT MOST ONCE.
// The first version summed markers and asserted `stated - provenanced <= 0`, so wrapping every
// numeral in its own span scored provenanced=8989 against stated=1056 and PASSED. Over-labelling
// won. Now: walk the stated numbers in document order and ask, for each one, whether the element
// that encloses IT carries the marker. A marker with no number behind it counts for nothing.
let ok=0;
// index the span of every marked element in the raw html
const marked=[];
for(const m of h.matchAll(/<([a-z]+)\b[^>]*data-prov="(declared|counted)"[^>]*>([\s\S]*?)<\/\1>/g)){
  marked.push([m.index, m.index+m[0].length]);
}
// find the position of each stated number in the raw html, then ask if a marked element encloses it
const RAWNUM=new RegExp("\\b\\d+(?:\\s|&nbsp;|<[^>]+>)+("+NOUN+")\\b","g");
const seen=new Set();
for(const m of h.matchAll(RAWNUM)){
  if(seen.has(m.index)) continue; seen.add(m.index);
  if(marked.some(([a,b]) => m.index>=a && m.index<b)) ok++;
}
console.log(stated, ok);')
    ref=$(grep -o 'data-prov="refused"' "$TMP/gsn.html" 2>/dev/null | wc -l | tr -d " "); ref=${ref:-0}
    dm=$(grep -o 'data-prov="declared"' "$TMP/gsn.html" 2>/dev/null | wc -l | tr -d " "); decl_marks=$((decl_marks+${dm:-0}))
    tot=$((tot+n)); prov=$((prov+p)); refused=$((refused+ref))
  done
done < "$MAN"

fail=0
[ -z "$missing" ] || { echo "gold: manifest names dirs that are not present:$missing"; fail=1; }
[ "$pages" -eq "$WANT_PAGES" ] || { echo "gold: pages=$pages, expected $WANT_PAGES (the pinned page set changed)"; fail=1; }
# The floor counts STATED + EXPLICITLY REFUSED. Pinning it at exactly the pre-change stated count
# meant one honest refusal — the behaviour Features 3 and 4 exist to produce — failed the gold.
# A refusal is accounted for by a `data-prov="refused"` marker, so "we chose not to state this" is
# distinguishable from "we quietly dropped it".
# R2-M4: a `declared` marker asserts the BUILD stated this number. If no artefact-data block exists
# anywhere, every `declared` on every page is a lie, and labelling all of them scored a clean pass.
# Bound the declared markers by the number of declared fields that actually exist.
decl_fields=0
while IFS= read -r l2; do
  case "$l2" in \#*|"") continue ;; esac
  sd="${l2%% *}"
  for f in contract.md plan.md review-ledger.md; do
    [ -f "$ROOT/.claude/builds/$sd/$f" ] || continue
    c=$(awk '/^```compass-artefact-data/{f=1;next} f&&/^```/{f=0} f&&/^[a-z][a-z.]*:/{n++} END{print n+0}' "$ROOT/.claude/builds/$sd/$f")
    decl_fields=$((decl_fields+c))
  done
done < "$MAN"
if [ "$decl_marks" -gt 0 ] && [ "$decl_fields" -eq 0 ]; then
  echo "gold: $decl_marks numbers are marked 'declared' but no compass-artefact-data block exists anywhere — a declared number with nothing behind it"
  fail=1
fi
acct=$((tot+refused))
[ "$acct" -ge "$WANT_STATED" ] || { echo "gold: stated+refused=$acct, floor is $WANT_STATED (numbers were dropped, not refused)"; fail=1; }
# EXACT equality. `<=` rewarded over-labelling, which is how the round-1 attack survived its fix.
[ "$prov" -eq "$tot" ] || { echo "gold: provenanced=$prov but stated=$tot — every stated number needs exactly one marker on the element enclosing it"; fail=1; }
[ "$fail_ck" -eq 0 ] || fail=1
echo "pages=$pages stated=$tot provenanced=$prov refused=$refused unprovenanced=$((tot-prov))"
exit $fail
