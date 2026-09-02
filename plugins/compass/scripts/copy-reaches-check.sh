#!/usr/bin/env bash
# suite-member: mechanical-suite — this line is how the suite proves its child list still NAMES this
# check. Removing the check from CHILDREN while this line stands makes the suite ERR.
#
# copy-reaches-check — INV-COPYREACHES, which had NO CHECK AT ALL. (v0.34, round 4 C-16)
#
#   usage: copy-reaches-check.sh [repo-root]
#
# WHY THIS EXISTS. INV-COPYREACHES is the invariant carrying this build's entire thesis: plain words
# written by a person must actually REACH the page a reader sees. Its own text says "no demotion
# available". `grep -rn COPYREACHES plugins/` returned ZERO. The contract named it three times and
# nothing on this machine tested it — the flagship rule of the release, unchecked, for four contract
# revisions. A reviewer found it by grepping for the name.
#
# WHAT IT MEASURES, and it is BEHAVIOURAL rather than a count. A static "how many rc() call sites"
# figure is exactly what drifted: the contract published planMap=0 while the generator had five, and
# the producer itself missed a third accessor. So this does not count call sites. It renders each
# in-scope view TWICE from the same fixture — once with the reader-copy block, once with it removed —
# and asserts the VISIBLE TEXT differs. If removing a person's plain words changes nothing a reader
# can see, the words did not reach the page, whatever any count says.
#
# MEASURE, not report. "Did this text change" is decidable with no judgement, which is what makes it
# safe to fail a build on.
#
# exit 0  reader copy reaches every in-scope view
# exit 1  at least one in-scope view is unreachable — named
# exit 2  usage / not a compass repo
# exit 3  ERR — no fixture carrying a reader-copy block, or a render failed. An empty population is
#         never a pass; that rule is the reason this file exists at all.
set -uo pipefail

ROOT="${1:-.}"
case "$ROOT" in --help|-h) sed -n '5,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
cd "$ROOT" 2>/dev/null || { echo "copy-reaches-check: cannot enter '$ROOT'" >&2; exit 2; }
[ -d plugins/compass ] || { echo "copy-reaches-check: not a compass repo root" >&2; exit 2; }
command -v node >/dev/null 2>&1 || { echo "copy-reaches-check: node is required" >&2; exit 3; }

GEN="plugins/compass/skills/compass-visual/gen.mjs"
FIX="plugins/compass/scripts/fixtures/pages/with-block"
# The in-scope set is DERIVED from the check that defines it, never re-typed here.
VIEWS="$(LC_ALL=C sed -n 's/^VIEWS="\(.*\)"$/\1/p' plugins/compass/scripts/readable-pages-check.sh | head -1)"
[ -n "$VIEWS" ] || { echo "copy-reaches-check: ERR — could not read the in-scope view list"; exit 3; }
[ -f "$GEN" ] || { echo "copy-reaches-check: ERR — generator absent"; exit 3; }
[ -d "$FIX" ] || { echo "copy-reaches-check: ERR — no fixture at $FIX"; exit 3; }
LC_ALL=C grep -q 'compass-reader-copy' "$FIX/contract.md" 2>/dev/null \
  || { echo "copy-reaches-check: ERR — $FIX carries no reader-copy block, so there is nothing to remove. An empty population is not a pass."; exit 3; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp -R "$FIX" "$TMP/f" || { echo "copy-reaches-check: ERR — could not stage the fixture"; exit 3; }

# A MARKER, NOT A DIFF. The first version of this file rendered with and without the block and
# compared the visible text — and it PASSED with `rc()` neutered to always return the fallback,
# because removing the block moves other things on the page too. That is a check that cannot fail,
# written inside the round convened to fix checks that cannot fail. It was caught by mutating the
# generator and watching the check stay green, which is why every check here is mutated before it
# is trusted. What this does instead is put a unique string into the block and require it to appear
# in the page's VISIBLE text. The raw block is never dumped onto the page (verified: the fence
# literal appears zero times), so the marker can only arrive by being read and rendered.
# visible text only: an invisible markup change must never count as reaching a reader.
_vis() { LC_ALL=C sed -e 's/<script[^>]*>.*<\/script>//g' -e 's/<style[^>]*>.*<\/style>//g' -e 's/<[^>]*>/ /g' "$1" | tr -s ' \n' '  '; }

MARK="ZZCOPYREACHESMARKERZZ"
node -e '
const fs=require("fs"); const p=process.argv[1], mark=process.argv[2];
const s=fs.readFileSync(p,"utf8");
const out=s.replace(/^(build-what:\s*)/m, "$1"+mark+" ");
if(out===s){ console.error("no build-what key to mark"); process.exit(1); }
fs.writeFileSync(p,out);
' "$TMP/f/contract.md" "$MARK" || { echo "copy-reaches-check: ERR — the fixture has no build-what key to mark"; exit 3; }

printf '── does reader copy reach the page? ─────────────────────────────────\n'
bad=0; checked=0
for v in $VIEWS; do
  node "$GEN" "$TMP/f" "$v" --out "$TMP/p.html" >/dev/null 2>&1 \
    || { echo "  ERR   $v did not render"; exit 3; }
  _vis "$TMP/p.html" > "$TMP/p.txt"
  checked=$((checked+1))
  if LC_ALL=C grep -q "$MARK" "$TMP/p.txt"; then
    printf '  ok    %-14s a person\x27s words reach the reader\n' "$v"
  else
    echo "  FAIL  $v — text written in the reader-copy block never reaches the page"
    bad=$((bad+1))
  fi
done
printf '─────────────────────────────────────────────────────────────────────\n'

if [ "$checked" -eq 0 ]; then
  echo "copy-reaches-check: ERR — no view was checked. An empty population is not a pass."
  exit 3
fi
if [ "$bad" -gt 0 ]; then
  echo "copy-reaches-check: $bad of $checked in-scope view(s) cannot be reached by reader copy."
  echo "  A person's plain words that change nothing on the page did not reach the page."
  exit 1
fi
echo "copy-reaches-check: reader copy reaches all $checked in-scope view(s) — measured by marking the block and finding the mark in the page's visible text."
exit 0
