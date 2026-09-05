#!/usr/bin/env bash
# suite-member: mechanical-suite — the suite's child list must NAME this check; removing it from
# CHILDREN while this line stands makes the suite ERR.
#
# secret-corpus-check — score `secret-scan` against a FIXED population. (v0.34.4)
#
#   usage: secret-corpus-check.sh [repo-root]
#
# WHY THIS EXISTS. Four review rounds moved this scanner between refusing half of ordinary code and
# missing half of real leaks. Every round measured itself against a corpus the author wrote AFTER
# choosing the rule, so every round scored well and every round had a hole its own corpus contained
# no example of. Round 3 refused 5 ordinary strings and missed 6 real leaks, and its commit message
# reported "0 of 25 refused" — true of the list it was tested on, and useless.
#
# The fix is not a better regex. It is a population that does not move: two files, one of things
# that must be refused and one of things that must not, seeded with every string six independent
# reviewers produced. A change is graded by re-running this, and a reviewer who finds a new hole
# ADDS A LINE rather than writing a paragraph.
#
# The fixture files carry TOKENS, not the shapes themselves — a file full of real leak shapes would
# be refused by the very scanner it grades. The tokens are substituted here, at run time.
#
# exit 0  every leak refused and every ordinary line allowed
# exit 1  any false alarm or any missed leak — both are named
# exit 2  usage / fixtures missing
set -uo pipefail
ROOT="${1:-.}"
case "$ROOT" in --help|-h) sed -n '5,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
cd "$ROOT" 2>/dev/null || { echo "secret-corpus-check: cannot enter '$ROOT'" >&2; exit 2; }
F=plugins/compass/scripts/fixtures/secrets
SH=plugins/compass/scripts/compass.sh
[ -f "$F/leaks.txt" ] && [ -f "$F/not-leaks.txt" ] && [ -f "$SH" ] || {
  echo "secret-corpus-check: fixtures or scanner missing under '$ROOT'" >&2; exit 2; }

# The substitutions. Assembled from halves so this script is not a leak either — and every VALUE is
# invented. The first version used a login name one letter away from the repository owner's, which
# is the same mistake as shipping the real one: a fixture must not read as anybody's identity.
_U="Us""ers"; _H="ho""me"; _N="fixture""person"; _AK="AK""IA"; _SK="s""k-"; _SEC="_SEC""RET"
_PG="post""gres"; _XO="xo""xb-"; _GH="gh""p_"; _SS="ses""sion_"; _sec="_sec""ret"; _KEY="K""EY"; _PW="PASS""WORD"
# Three of the scanner's ten refusal rules had NO example in this corpus at all — a PEM private-key
# header, a JSON Web Token, and a GitHub fine-grained token. The check still printed a confident
# "45 of 45 · 112 of 112", so deleting any one of those three rules would have let a real leak of
# that class through with the corpus fully green. Found by review-build round 1. Split the same way
# as every token above, so this file never carries the shape it describes.
_PEM="-----BE""GIN RSA PRIVATE ""KEY-----"; _JWT="ey""J"; _GPAT="git""hub_pat_"
# AN INVENTED ID. The first version of this line assembled the AUTHOR'S REAL session id at run time
# — the same defect this project has now found three times, in three different files, twice after
# declaring it fixed. Splitting a string hides a value from the scanner; it does not make the value
# safe to ship. This one is made up, and it is checked against the real thing by nothing, which is
# the point.
_ID="1a2b""3c4d-0000-4000-8000-00000000f00d"; _IDU="$(printf '%s' "$_ID" | tr 'a-f' 'A-F')"
subst() { sed -e "s|<U>|$_U|g" -e "s|<H>|$_H|g" -e "s|<N>|$_N|g" -e "s|<AK>|$_AK|g" \
              -e "s|<SK>|$_SK|g" -e "s|<SEC>|$_SEC|g" -e "s|<PG>|$_PG|g" -e "s|<XO>|$_XO|g" \
              -e "s|<PEM>|$_PEM|g" -e "s|<JWT>|$_JWT|g" -e "s|<GPAT>|$_GPAT|g" -e "s|<GH>|$_GH|g" -e "s|<SS>|$_SS|g" -e "s|<sec>|$_sec|g" -e "s|<KEY>|$_KEY|g" -e "s|<PW>|$_PW|g" -e "s|<IDU>|$_IDU|g" -e "s|<ID>|$_ID|g"; }

D="$(mktemp -d)"; mkdir -p "$D/d"
one() { printf '%s\n' "$1" > "$D/d/f.txt"; bash "$SH" secret-scan "$D/d" >/dev/null 2>&1; local r=$?; rm -f "$D/d/f.txt"; return $r; }

# TWO scans in the common case, not one per line. The whole corpus goes into a single file and is
# scanned once; only when that disagrees with the expected answer does the check fall back to
# line-by-line, which is slower but names the offender. Scoring 70 lines one at a time cost ~21s of
# a 78s test run, and a check nobody can afford to run is a check that stops being run.
grep -v '^#' "$F/not-leaks.txt" | subst | grep -v '^$' > "$D/not-leaks"
grep -v '^#' "$F/leaks.txt"     | subst | grep -v '^$' > "$D/leaks"
n="$(grep -c . "$D/not-leaks" || true)"; n="${n:-0}"
m="$(grep -c . "$D/leaks" || true)";     m="${m:-0}"
fp=0; miss=0

mkdir -p "$D/nl" && cp "$D/not-leaks" "$D/nl/f.txt"
if ! bash "$SH" secret-scan "$D/nl" >/dev/null 2>&1; then
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    one "$l" || { fp=$((fp+1)); printf '  FALSE-ALARM  %s\n' "$l"; }
  done < "$D/not-leaks"
fi

mkdir -p "$D/lk" && cp "$D/leaks" "$D/lk/f.txt"
_hits="$(bash "$SH" secret-scan "$D/lk" 2>&1 | grep -cE '^[^ ].*:[0-9]+:' || true)"; _hits="${_hits:-0}"
if [ "$_hits" -ne "$m" ]; then
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    one "$l" && { miss=$((miss+1)); printf '  MISSED-LEAK  %s\n' "$l"; }
  done < "$D/leaks"
fi
rm -rf "$D"

# An empty population is not a pass — the rule every other check in this suite applies.
if [ "$n" -eq 0 ] || [ "$m" -eq 0 ]; then
  printf 'secret-corpus-check: ERR — corpus is empty (%s ordinary, %s leaks). A green over nothing is not a signal.\n' "$n" "$m"
  exit 1
fi
printf 'secret-corpus-check: %s of %s real leaks refused · %s of %s ordinary lines allowed.\n' \
  "$((m-miss))" "$m" "$((n-fp))" "$n"
if [ "$fp" -gt 0 ] || [ "$miss" -gt 0 ]; then
  printf '  A false alarm and a missed leak are BOTH failures, and a scanner is only ever tuned\n'
  printf '  between them. Add the case above to the fixture rather than adjusting a regex to suit it.\n'
  exit 1
fi
exit 0
