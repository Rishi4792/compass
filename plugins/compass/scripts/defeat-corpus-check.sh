#!/usr/bin/env bash
# v0.31 GOLD, VALUE HALF — is the number RIGHT?
#
# The label half (gold-stated-numbers.sh) asks whether every stated number is accounted for. It
# cannot ask whether a number is CORRECT, and Review-1 proved an implementation that changes no
# number at all can drive it a long way toward target. This half is the negative case v0.30's own
# R1-1 lesson demands: inputs where the parser's answer differs from the truth, so an implementation
# that keeps the prose parsing and only adds labels FAILS RED.
#
# Each entry is a build dir plus an EXPECTED file naming the view, the true value, and the value the
# page must never state — with the reproduction that earned its place. Entries may only be ADDED,
# each with its reproduction; none may be removed. A review round is CLEAN when it adds none.
set -uo pipefail
ROOT="${1:-.}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORPUS="$HERE/fixtures/defeat"
G="$ROOT/plugins/compass/skills/compass-visual/gen.mjs"
[ -d "$CORPUS" ] || { echo "defeat-corpus: no corpus at $CORPUS"; exit 2; }
[ -f "$G" ] || { echo "defeat-corpus: no generator at $G"; exit 2; }

n=0; bad=0
for e in "$CORPUS"/*/; do
  [ -f "$e/EXPECTED" ] || continue
  n=$((n+1))
  slug="$(basename "$e")"
  view="$(sed -nE 's/^view:[[:space:]]*(.*)/\1/p' "$e/EXPECTED" | head -1)"
  want="$(sed -nE 's/^true\.findings\.total:[[:space:]]*([0-9]+).*/\1/p' "$e/EXPECTED" | head -1)"
  never="$(sed -nE 's/^must-not-state:[[:space:]]*([0-9]+).*/\1/p' "$e/EXPECTED" | head -1)"
  # An entry with no recorded reproduction is not evidence — it is an assertion the author made up.
  grep -q '^reproduction:' "$e/EXPECTED" || { echo "  REFUSE $slug — no recorded reproduction"; bad=$((bad+1)); continue; }
  node "$G" "$e" "$view" --out /tmp/dcc.html >/dev/null 2>&1 || { echo "  FAIL $slug — did not render"; bad=$((bad+1)); continue; }
  got="$(node -e '
const h=require("fs").readFileSync("/tmp/dcc.html","utf8").replace(/<[^>]+>/g,"|");
const m=h.match(/(\d+) findings/);
const refused=/could not be read|No review has been recorded/.test(h);
console.log(m? m[1] : (refused ? "REFUSED" : "NONE"));')"
  if [ "$got" = "$never" ]; then
    echo "  FAIL $slug — states $got, which is the known-wrong value (true: $want)"; bad=$((bad+1))
  elif [ "$got" = "$want" ]; then
    echo "  ok   $slug — states the true value $want"
  elif [ "$got" = "REFUSED" ]; then
    # A refusal is only honest if what it SAYS is true. An entry may pin a claim the refusal must
    # NOT make — a page that states no number but misdescribes why is still stating a falsehood
    # about its own input, which is what the contract's Goal forbids.
    nc="$(sed -nE 's/^refusal-must-not-claim:[[:space:]]*(.*)/\1/p' "$e/EXPECTED" | head -1)"
    if [ -n "$nc" ] && grep -qiF "$nc" /tmp/dcc.html; then
      echo "  FAIL $slug — refuses, but claims \"$nc\", which is not true of this input"; bad=$((bad+1))
    else
      echo "  ok   $slug — states no number and says why (true: $want; an honest refusal is allowed)"
    fi
  else
    echo "  FAIL $slug — states $got (true: $want)"; bad=$((bad+1))
  fi
done
echo "defeat-corpus: $n entries, $bad failing"
[ "$bad" -eq 0 ]
