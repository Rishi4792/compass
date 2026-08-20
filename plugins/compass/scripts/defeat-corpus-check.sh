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

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
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
  # ANCHOR the truth. `true.findings.total` was an author-written literal that nothing cross-checked,
  # so two sed edits made every entry pass with no code change — the value half had no more spine
  # than the label half it was added to protect. The truth is now DERIVED from the fixture by an
  # independent reader (python, sharing no code with the generator) and the literal must agree with
  # it. Editing the literal alone now fails; changing the fixture changes what is being tested,
  # which is visible in the diff.
  derived="$(python3 - "$e/review-ledger.md" <<'PY'
import io,re,sys
try: lines=io.open(sys.argv[1],encoding='utf-8').read().split('\n')
except OSError: print(''); raise SystemExit
ID=re.compile(r'^[A-Za-z0-9][A-Za-z0-9._/,+-]{0,31}$')
NOT=re.compile(r'^(id|issue|issue id|round|severity|sev|status|total|none|n/a|summary|findings?|area|fix|owner|verdict)$',re.I)
def is_id(x):
    x=x.replace('*','').strip()
    return bool(x) and ' ' not in x and bool(ID.match(x)) and not NOT.match(x) and bool(re.search(r'\d',x))
n=0
for l in lines:
    s=l.lstrip('> ').strip()
    if not s.startswith('|'): continue
    cells=[c.strip() for c in s.strip('|').split('|')]
    if not cells or all(re.match(r'^:?-{2,}:?$',c) for c in cells): continue
    if is_id(cells[0]): n+=1
print(n)
PY
)"
  if [ -n "$derived" ] && [ "$derived" != "$want" ]; then
    echo "  REFUSE $slug — EXPECTED says the truth is $want, an independent read of the fixture says $derived"
    bad=$((bad+1)); continue
  fi
  node "$G" "$e" "$view" --out "$TMP/dcc.html" >/dev/null 2>&1 || { echo "  FAIL $slug — did not render"; bad=$((bad+1)); continue; }
  got="$(PAGE="$TMP/dcc.html" node -e '
const h=require("fs").readFileSync(process.env.PAGE,"utf8").replace(/<[^>]+>/g,"|");
const m=h.match(/(\d+)(?:\s|<[^>]+>|&nbsp;)*findings/);
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
    # DERIVED, not author-declared. `refusal-must-not-claim` was free text the author owned, so
    # rewriting it to "ZZZ" made the entry pass. The real rule needs no declaration: if an
    # INDEPENDENT reader found rows in this fixture, then a refusal claiming the ledger could not be
    # read is false BY CONSTRUCTION — it was read, just now, by a different implementation.
    nc=""
    if [ -n "$derived" ] && [ "${derived:-0}" -gt 0 ]; then nc="could not be read"; fi
    # an entry may name an ADDITIONAL claim, but may never remove the derived one
    extra="$(sed -nE 's/^refusal-must-not-claim:[[:space:]]*(.*)/\1/p' "$e/EXPECTED" | head -1)"
    if [ -n "$extra" ] && grep -qiF "$extra" "$TMP/dcc.html"; then
      echo "  FAIL $slug — refuses, but claims \"$extra\", which is not true of this input"; bad=$((bad+1)); continue
    fi
    if [ -n "$nc" ] && grep -qiF "$nc" "$TMP/dcc.html"; then
      echo "  FAIL $slug — refuses, but claims \"$nc\", which is not true of this input"; bad=$((bad+1))
    else
      echo "  ok   $slug — states no number and says why (true: $want; an honest refusal is allowed)"
    fi
  else
    echo "  FAIL $slug — states $got (true: $want)"; bad=$((bad+1))
  fi
done
# R2-C4: INV-5 asserted a floor that was never pinned, and counted directories rather than entries —
# so deleting one EXPECTED silently dropped an entry while `ls | wc -l` still said 2.
FLOOR=2
[ "$n" -ge "$FLOOR" ] || { echo "defeat-corpus: $n entries, floor is $FLOOR — an entry may be added, never removed"; exit 1; }
echo "defeat-corpus: $n entries (floor $FLOOR), $bad failing"
[ "$bad" -eq 0 ]
