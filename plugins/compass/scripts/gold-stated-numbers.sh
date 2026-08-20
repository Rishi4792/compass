#!/usr/bin/env bash
# v0.31 GOLD — how many numbers do Compass pages STATE, and how many can be traced?
#
# Two rules earned by getting this wrong while writing the contract:
#  1. EXCLUDE this build's own dir. Its contract PROSE contains the words "counted by reading",
#     and counting those as provenance let the contract inflate its own baseline — the gold
#     measuring itself, which is the exact thing gold-gate exists to refuse.
#  2. Provenance is counted from a MARKUP ATTRIBUTE, never from words. Prose can say anything;
#     `data-prov="declared|counted"` is emitted by the generator or it is not.
set -uo pipefail
ROOT="${1:-.}"; SELF="${2:-artefacts-from-data-v0-31}"
G="$ROOT/plugins/compass/skills/compass-visual/gen.mjs"
NOUNS='findings?|steps?|invariants?|changes?|critical|major|closed|open'
tot=0; prov=0; pages=0
for d in "$ROOT"/.claude/builds/*/; do
  [ -f "$d/contract.md" ] || continue
  case "$d" in *"$SELF"*) continue ;; esac
  for v in brief brief-body plan-map release-card review; do
    node "$G" "$d" "$v" --out /tmp/gsn.html >/dev/null 2>&1 || continue
    pages=$((pages+1))
    read -r n p < <(NOUNS="$NOUNS" node -e "
const h=require('fs').readFileSync('/tmp/gsn.html','utf8');
const text=h.replace(/<style[\s\S]*?<\/style>/g,' ').replace(/<[^>]+>/g,' ').replace(/&[a-z]+;/g,' ').replace(/\s+/g,' ');
const nums=(text.match(new RegExp('\\\\b\\\\d+ ('+process.env.NOUNS+')\\\\b','g'))||[]).length;
const marked=(h.match(/data-prov=\"(declared|counted)\"/g)||[]).length;
console.log(nums, marked);")
    tot=$((tot+n)); prov=$((prov+p))
  done
done
echo "pages=$pages stated=$tot provenanced=$prov unprovenanced=$((tot-prov))"
