#!/usr/bin/env bash
# v0.31 — the DECLARED half, exercised on real rendered pages.
#
# Review-1 round 6 (R6-C8) and round 7 both landed the same complaint: `mismatch` and `bogus` had
# never scored a single real page. No build in the pinned 28 carries a `compass-artefact-data` block,
# so those counters could not be non-zero, and their only evidence was synthetic controls inside the
# auditor. A counter whose sole witness is a unit test of itself is not a measurement.
#
# These fixtures are real build dirs. They are stamped, they carry a real block, and they are
# rendered by the real generator. Three of them, each pinning one behaviour:
#
#   honest       the block agrees with the files it describes -> the page states it, marked declared
#   lying        the block declares 999 steps over a 3-step plan -> MUST be caught, not rendered as truth
#   bogus-field  the block declares a field nothing states -> the page falls back to counting
#
# The `lying` case is the one that matters. Round 7 found the block cross-check had NEVER RUN — the
# pattern went through `awk -v`, which ate the backslashes, so the checkbox count was always 0 and
# both directions were wrong: declaring the truth was rejected and declaring anything passed. This
# fixture is the standing proof that it runs.
set -uo pipefail
ROOT="${1:-.}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FX="$HERE/fixtures/declared"
G="$ROOT/plugins/compass/skills/compass-visual/gen.mjs"
AUD="$HERE/page-audit.mjs"
for f in "$G" "$AUD"; do [ -f "$f" ] || { echo "declared: missing $f"; exit 2; }; done
[ -d "$FX" ] || { echo "declared: no fixtures at $FX"; exit 2; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Count plan checkboxes the way the gold does — inline, never through `awk -v`.
boxes() { awk '/^[[:space:]]*```/ { f = !f; next } !f && /^[[:space:]]*- \[[ xX]\]/ { n++ } END { print n+0 }' "$1"; }

fail=0; n=0
for d in "$FX"/*/; do
  [ -f "$d/contract.md" ] || continue
  slug="$(basename "$d")"; n=$((n+1))

  blk="$(awk '/^ {0,3}`{3,}compass-artefact-data[ \t]*\r?$/{f=1;next} f&&/^ {0,3}`{3,}[ \t]*\r?$/{exit} f{print}' "$d"/*.md 2>/dev/null)"
  [ -n "$blk" ] || { echo "  FAIL $slug — carries no data block, so it exercises nothing"; fail=1; continue; }
  printf '%s' "$blk" > "$TMP/block.json"

  # v0.32.0 S19b: the generator now REFUSES to render a page whose DECLARED number contradicts what
  # it computes. For `lying` that refusal IS the catch — earlier and harder than the auditor's — so
  # assert it here rather than reading a refusal as a broken fixture. For any other slug a refusal
  # is still a failure.
  if ! node "$G" "$d" plan-map --out "$TMP/p.html" >/dev/null 2>"$TMP/generr.txt"; then
    if [ "$slug" = "lying" ] && grep -q 'disagrees with itself' "$TMP/generr.txt"; then
      want_st="$(boxes "$d/plan.md")"
      got_st="$(BLK="$TMP/block.json" node -e 'try{const b=JSON.parse(require("fs").readFileSync(process.env.BLK,"utf8"));console.log(b["steps.total"]??"")}catch(e){console.log("")}')"
      if [ -n "$got_st" ] && [ "$got_st" != "$want_st" ]; then
        echo "  ok   $slug — caught AT RENDER: the block declares steps.total=$got_st over a $want_st-step plan, and the generator refused to draw the page"
      else
        echo "  FAIL $slug — refused, but not for the declared-vs-computed reason this fixture exists to prove"; fail=1
      fi
      continue
    fi
    echo "  FAIL $slug — did not render"; fail=1; continue
  fi
  cat "$d"/*.md > "$TMP/src.txt" 2>/dev/null

  read -r um mm bg nb us ns ml bp fb < <(PAGE="$TMP/p.html" BLOCK="$TMP/block.json" AUD="$AUD" SRC="$TMP/src.txt" node -e '
const {pathToFileURL}=require("node:url");
import(pathToFileURL(process.env.AUD).href).then(m=>{
  const fs=require("fs");
  let b=null; try{ b=JSON.parse(fs.readFileSync(process.env.BLOCK,"utf8")); }catch(_){}
  let src=""; try{ src=fs.readFileSync(process.env.SRC,"utf8"); }catch(_){}
  const r=m.scorePage(fs.readFileSync(process.env.PAGE,"utf8"),"new",b,null,src);
  console.log("RESULT",r.unmarked,r.mismatch,r.bogus,r.noblock,r.unsaid,r.nested,r.mislabelled,r.badprov,r.fabricated);
});' | awk '/^RESULT /{c++; l=$0} END{ if(c!=1) exit 1; split(l,f," "); print f[2],f[3],f[4],f[5],f[6],f[7],f[8],f[9],f[10] }')
  for _v in "${um:-}" "${mm:-}" "${bg:-}" "${nb:-}"; do
    case "$_v" in ""|*[!0-9]*) echo "  ERR $slug — the auditor returned nothing"; exit 2 ;; esac
  done

  # Does the BLOCK agree with the files it claims to describe? This is the check that had never run.
  want_st="$(boxes "$d/plan.md")"
  got_st="$(BLK="$TMP/block.json" node -e 'try{const b=JSON.parse(require("fs").readFileSync(process.env.BLK,"utf8"));console.log(b["steps.total"]??"")}catch(e){console.log("")}')"
  lies=0
  [ -n "$got_st" ] && [ "$got_st" != "$want_st" ] && lies=1

  case "$slug" in
    honest)
      if [ "$mm" -eq 0 ] && [ "$bg" -eq 0 ] && [ "$nb" -eq 0 ] && [ "$lies" -eq 0 ] && [ "$um" -eq 0 ]; then
        echo "  ok   $slug — the block agrees with its files and the page states it, marked declared"
      else
        echo "  FAIL $slug — an honest block must score clean (unmarked=$um mismatch=$mm bogus=$bg noblock=$nb block-vs-files=$lies)"; fail=1
      fi ;;
    lying)
      if [ "$lies" -eq 1 ]; then
        echo "  ok   $slug — caught: the block declares steps.total=$got_st over a $want_st-step plan"
      else
        echo "  FAIL $slug — a block declaring $got_st over a $want_st-step plan was NOT caught. This is the check round 7 found had never run."; fail=1
      fi ;;
    bogus-field)
      if [ "$um" -eq 0 ] && [ "$nb" -eq 0 ]; then
        echo "  ok   $slug — a field nothing states does not break the page; the rest falls back to counting"
      else
        echo "  FAIL $slug — unmarked=$um noblock=$nb"; fail=1
      fi ;;
    *) echo "  ok   $slug — rendered (unmarked=$um mismatch=$mm bogus=$bg)" ;;
  esac
done

# ── v0.32.0 S19b: the auditor's `mismatch` counter must keep a REAL witness ───────────────────
# Round 7 found that counter had never scored a real page; `lying` became its witness. The generator
# now refuses to render `lying` at all — a stronger control, but one that would leave the auditor
# untested again, and the auditor is the defence for pages the generator did NOT produce: an older
# version, or one edited by hand. So take a page the REAL generator made, corrupt ONE declared
# number in it, and require the auditor to catch it.
if node "$G" "$FX/honest" plan-map --out "$TMP/h.html" >/dev/null 2>&1; then
  awk '/^ {0,3}`{3,}compass-artefact-data[ \t]*\r?$/{f=1;next} f&&/^ {0,3}`{3,}[ \t]*\r?$/{exit} f{print}' "$FX/honest"/*.md > "$TMP/hblock.json" 2>/dev/null
  sed -e 's/data-prov="declared">3</data-prov="declared">77</' "$TMP/h.html" > "$TMP/tampered.html"
  if cmp -s "$TMP/h.html" "$TMP/tampered.html"; then
    echo "  FAIL witness — the tamper changed nothing, so this check proves nothing"; fail=1
  else
    cat "$FX/honest"/*.md > "$TMP/hsrc.txt" 2>/dev/null
    _mm="$(PAGE="$TMP/tampered.html" BLOCK="$TMP/hblock.json" AUD="$AUD" SRC="$TMP/hsrc.txt" node -e '
const {pathToFileURL}=require("node:url");
import(pathToFileURL(process.env.AUD).href).then(m=>{
  const fs=require("fs");
  let b=null; try{ b=JSON.parse(fs.readFileSync(process.env.BLOCK,"utf8")); }catch(_){}
  let src=""; try{ src=fs.readFileSync(process.env.SRC,"utf8"); }catch(_){}
  const r=m.scorePage(fs.readFileSync(process.env.PAGE,"utf8"),"new",b,null,src);
  console.log(r.mismatch);
});' 2>/dev/null)"
    case "${_mm:-}" in
      ""|*[!0-9]*) echo "  ERR  witness — the auditor returned nothing"; fail=1 ;;
      0)           echo "  FAIL witness — a page stating 77 where its block declares 3 was NOT caught by the auditor"; fail=1 ;;
      *)           echo "  ok   witness — the auditor catches a real generated page whose declared number was altered to 77 (mismatch=$_mm)" ;;
    esac
  fi
else
  echo "  FAIL witness — the honest fixture did not render, so the auditor has no real page to score"; fail=1
fi

WANT=3
[ "$n" -eq "$WANT" ] || { echo "declared: $n fixtures, expected $WANT — a case may be added, never quietly dropped"; fail=1; }
echo "declared: $n fixtures exercising the declared half on rendered pages, $fail failing"
exit $fail
