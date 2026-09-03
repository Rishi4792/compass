#!/usr/bin/env bash
# v0.31 GOLD (v6 — containment) — TWO RULES, chosen by what the build actually has.
#
# Four golds were defeated before this one, all the same way: they tried to prove that a number on a
# LEGACY build's page was RIGHT. Round 4 showed why that can never work. For the 27 builds that
# predate the data block there is no true number to compare against — their data was never written
# down in a structured form, so any "independent reader" is another heuristic, wrong in both
# directions. Round 4 measured it: the reader was wrong on 8 of 25 ledgers, and its step counts
# agreed with the generator on ALL 28 builds, including the three shipped builds reporting 0/19,
# 0/17 and 0/14 whose own receipts record every wave done. The instrument had reproduced the exact
# defect it was built to detect.
#
# So the gold stops asking one question of every build, and asks the RIGHT question of each:
#
#   NEW build (carries the script-written `.compass-format` stamp):
#     the data block IS the truth. It is declared by the model, not inferred from prose. Every
#     number the page states must come from a field of that block and equal it. No reader, no
#     heuristic, no guessing — a string comparison against a declared value.
#
#   LEGACY build (no stamp):
#     no truth claim is made at all, because none can be. Every number a reader sees must be
#     LABELLED as counted-by-reading-and-possibly-wrong. That is the contract's own Phase 3
#     decision ("keep legacy numbers, LABELLED"); the previous four golds went beyond it and tried
#     to prove those numbers correct, which is where every round was lost.
#
# This is why "label every numeral" is no longer an attack. Against a claim of CORRECTNESS it was
# gaming. Against a claim of LABELLING it is compliance — the honest thing to do. The attack only
# ever worked because the gold claimed a label proved a value. It no longer claims that.
#
# The stamp is a FILE written by `compass.sh new-build`, never by the model, so a build cannot
# choose the easier rule for itself. That is v0.30's INV-1 mechanism, reused.
#
# Counts, each targeting 0:
#   unmarked - a number a reader sees that no marker says anything about.
#   nested/mislabelled - a marker inside a marker; a literal that moves when the data moves.
#   mismatch   - NEW: a tied number that differs from what the block declares. The real defect.
#   bogus      - NEW: a marker naming a field the block does not have.
#   noblock    - NEW: a page rendered from a build that states numbers with no data block at all.
set -uo pipefail
ROOT="${1:-.}"
# R9-C1 / round-3 C2: `gold-numbers-gate <dir>` ran this over the 28-dir manifest corpus and NEVER
# SCORED THE PAGES OF THE BUILD IT WAS HANDED. The build shipping v0.31 is deliberately outside the
# manifest, so its own four pages — which score `noblock=1` each, a counter this gold targets at 0 —
# were never looked at, and the gate reported PASS. Two skills print the promise that every declared
# field is cross-checked against its source; it was false for any build not in the manifest, which is
# every build a real user will ever run.
#
# `--only <slug>` audits ONE dir on its own terms. The corpus floors (dir/page/token counts) and the
# pinned-checksum requirement do not apply: those verify that the BASELINE has not moved, and the
# build being gated is live work, not a baseline. Everything that scores a page still runs.
ONLY=""
if [ "${2:-}" = "--only" ]; then
  ONLY="${3:-}"
  [ -n "$ONLY" ] || { echo "gold: --only needs a slug"; exit 2; }
fi
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MAN="$HERE/gold-manifest.txt"
G="$ROOT/plugins/compass/skills/compass-visual/gen.mjs"
AUD="$HERE/page-audit.mjs"
for f in "$MAN" "$G" "$AUD"; do [ -f "$f" ] || { echo "gold: missing $f"; exit 2; }; done
# INV-0b. The controls run through the SAME functions the loop below runs, on fixed known-violating
# inputs, every single run. R4-C8: the previous control was a separate implementation, so it printed
# "fires" during every broken run. If a control stops firing the auditor is broken and this reports
# ERR rather than its pass target.
# R5-M3: two mutations gutted the auditor while every control stayed green - a size-gated bypass,
# and replacing the control runner with `return []`. No control can catch the second, because the
# thing reporting "all controls fire" is the thing that was gutted. So the auditor is PINNED by hash
# from out here, in the file it does not control. Editing it legitimately means updating this pin,
# which is a visible diff in a git-tracked file.
# Field-extract (never strip-a-prefix) and REQUIRE the pin. An absent pin is not a pass.
pin_of() { awk -v k="$1" '$0 ~ "^# " k ":" {print $3; exit}' "$MAN"; }
check_pin() {
  local key="$1" file="$2" want got
  want="$(pin_of "$key")"
  if [ -z "$want" ]; then
    echo "gold: ERR - no '$key' pin in $MAN. An unpinned checker cannot be trusted; refusing to report a verdict."
    exit 2
  fi
  got="$(shasum -a 256 "$file" | cut -c1-16)"
  if [ "$want" != "$got" ]; then
    echo "gold: ERR - $(basename "$file") does not match its pinned hash (pinned $want, got $got). Refusing to report a verdict."
    exit 2
  fi
}
check_pin auditor-sha256 "$AUD"
check_pin generator-sha256 "$G"
_ctl="$(node "$AUD" --controls 2>&1)"; _ctlrc=$?
printf '%s\n' "$_ctl"
# Exit 0 with NO OUTPUT is not success. A symlinked path once made this print nothing and exit 0,
# and both callers read that as "all controls fire" — the control-of-controls silently off.
case "$_ctl" in
  *"controls fire"*) : ;;
  *) echo "gold: ERR - the auditor's controls produced no confirmation (rc=$_ctlrc). A checker that said nothing did not pass."; exit 2 ;;
esac
[ "$_ctlrc" -eq 0 ] || { echo "gold: ERR - the page auditor's positive controls are not all firing."; exit 2; }

# NULL-MUTATION SELF-CHECK. The differential's whole claim is that a number which moved did so
# BECAUSE THE DATA MOVED. Round 6 found that false: the twin lived somewhere the generator resolved a
# sibling INDEX file differently, so 61 of 317 demands (19%) were environment artefacts — a label
# demanded on a line number and on an exit code. If copying a dir WITHOUT changing it produces any
# claim at all, the twin is not a clean control and no verdict from it is worth anything.
null_probe() {
  local d="$1" slug="$2" t="$TMP/null"
  rm -rf "$t"; mkdir -p "$t"
  for sib in INDEX PROGRAM.md CURRENT; do
    [ -f "$ROOT/.claude/builds/$sib" ] && cp "$ROOT/.claude/builds/$sib" "$t/$sib"
  done
  cp -R "$d" "$t/$slug" 2>/dev/null
  local n=0 v
  for v in brief plan-map review; do
    node "$G" "$d" "$v" --out "$TMP/n1.html" >/dev/null 2>&1 || continue
    node "$G" "$t/$slug" "$v" --out "$TMP/n2.html" >/dev/null 2>&1 || continue
    local c
    c="$(A="$TMP/n1.html" B="$TMP/n2.html" AUD="$AUD" node -e '
const {pathToFileURL}=require("node:url");
import(pathToFileURL(process.env.AUD).href).then(m=>{
  const fs=require("fs");
  const r=m.dataClaims(fs.readFileSync(process.env.A,"utf8"),fs.readFileSync(process.env.B,"utf8"));
  console.log(r.claims.length);
});')"
    n=$((n + ${c:-0}))
  done
  echo "$n"
}

# v0.35 — THE CORPUS TOTALS ARE RE-BASELINED, and only after every QUALITY check reached zero.
# These are a RECORD of what was true, not a judgement: `unmarked`, `mismatch`, `bogus`, `noblock`,
# `unsaid`, `nested`, `mislabelled`, `badprov` and `fabricated` are the judgement, and all of them
# are 0 across all 140 pages before these two numbers were touched.
#
#   WANT_DISTINCT 112 → 140. At v0.31, 28 of 140 renders were not distinct — one page standing in
#   for many, which is exactly what this check is named for. Every page is now its own; the number
#   went UP because the defect went away.
#   WANT_TOKENS 8516 → 13701. Four releases of builds accumulated content, and pages now render
#   fields that used to be truncated away.
#
# Re-pinning a total while a quality check is red would be hiding a defect. Re-pinning it after they
# are all zero is recording where the corpus now stands, which is what a baseline is for.
WANT_PAGES=140; WANT_DIRS=28; WANT_NEW=1; WANT_LEGACY=27; WANT_DISTINCT=140; WANT_TOKENS=13701
pages=0; dirs=0; newdirs=0; legacydirs=0
unmarked=0; mismatch=0; bogus=0; noblock=0; unsaid=0; nested=0; mislabelled=0; badprov=0; fabricated=0; bidi=0; spoken=0
fail_ck=0; miss_dirs=""; untrusted=""; seen_pages=""; distinct=0; tokens=0; mut_blind=""; mut_noop=""
# Run the null probe on the first pinned dir before trusting any differential result.
_np_slug="$(awk '!/^#/&&NF{print $1; exit}' "$MAN")"
if [ -n "$_np_slug" ] && [ -f "$ROOT/.claude/builds/$_np_slug/contract.md" ]; then
  _np="$(null_probe "$ROOT/.claude/builds/$_np_slug" "$_np_slug")"
  if [ "${_np:-0}" -ne 0 ]; then
    echo "gold: ERR - the null-mutation control produced $_np claim(s) on $_np_slug. An UNCHANGED copy must produce none; the twin differs for a reason that is not the data, so every demand is suspect. Refusing to report a verdict."
    exit 2
  fi
fi

# Round 4 (R4-C11): `while read` drops the final line when a file has no trailing newline, so the
# last pinned entry vanished in silence. `|| [ -n "$line" ]` is the standard guard.
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in \#*|"") continue ;; esac
  slug="${line%% *}"
  d="$ROOT/.claude/builds/$slug"
  [ -f "$d/contract.md" ] || { miss_dirs="$miss_dirs $slug"; continue; }
  dirs=$((dirs+1))
  # Round 4 MAJOR: a line with no checksum made `${line#* }` return the whole line, so the
  # comparison was line-vs-line, always equal, and verification was skipped in SILENCE. Since
  # `.claude/builds/` is gitignored, that checksum is the ONLY protection the gold's input has.
  # Field-extract, don't strip-a-prefix. `${line#* }` removes only up to the FIRST space, so a
  # two-space separator left a leading space on the checksum and every one of the 28 dirs compared
  # unequal — the gold cried "changed since the baseline" 28 times and I missed it for several runs
  # because I was reading `tail -3`. A check that fires on everything is as useless as one that
  # fires on nothing, and it trains you to ignore the output.
  want_ck="$(printf '%s\n' "$line" | awk '{print $2}')"
  if [ -z "$want_ck" ] && [ -z "$ONLY" ]; then
    echo "gold: $slug has no pinned checksum - the gold's input cannot be verified"; fail_ck=1
  fi
  if [ -n "$want_ck" ]; then
    # EVERY .md, not five named ones. The data block may live in any of them, so pinning a subset
    # left the file that defines "truth" unpinned - and the stamp that decides WHICH RULE applies was
    # not pinned either, so deleting one unpinned file demoted a build out of the correctness rule.
    # EVERY regular file in the dir. Globbing *.md left a non-.md sidecar invisible, which is how a
    # `.frozen` cache next to each state file bypassed the whole gold.
    # Hash NAME+content pairs, then sort. Hashing bare contents and sorting made a swap of two
    # files' contents produce a byte-identical checksum, while the rendered page plainly changed.
    # LOGS ARE NOT INPUTS. `_orient_log` appends a line every time `orient` or `progress-card` runs,
    # into the same directory as the build it observed — and this repository already calls those
    # files "residue, not inputs" where it stopped tracking them. Including them here meant a
    # READ-ONLY command invalidated the gold baseline: `always-clarity-v0-28 changed since the
    # baseline` was one log file growing, and nothing else in that directory had moved at all. A
    # baseline that merely LOOKING at a build can break is not a baseline; it is a tripwire on the
    # observer. Every other file still counts, so a real change to a real input still fails.
    got_ck="$(find "$d" -type f ! -name '*.log' -print0 2>/dev/null | xargs -0 shasum -a 256 2>/dev/null \
      | awk '{h=substr($1,1,12); p=$0; sub(/^[0-9a-f]+  /,"",p); n=p; sub(/.*\//,"",n); print n":"h}' \
      | sort | paste -sd'.' -)"
    [ "$got_ck" = "$want_ck" ] || { echo "gold: $slug changed since the baseline"; fail_ck=1; }
  fi

  # WHICH RULE? The stamp is a file compass.sh writes at build-dir creation. The model never writes
  # it, so a build cannot opt itself into the easier rule.
  # The stamp must LOOK like one, not merely exist: `compass.sh` writes `compass-format: v...`, and
  # an empty file was being accepted as a valid stamp.
  if [ -f "$d/.compass-format" ] && grep -q '^compass-format: v' "$d/.compass-format" 2>/dev/null; then
    mode=new; newdirs=$((newdirs+1))
  else
    mode=legacy; legacydirs=$((legacydirs+1))
    # A contract carrying the mirror header while the stamp is gone means the stamp was removed.
    if [ -f "$d/contract.md" ] && grep -q '^compass-format: v' "$d/contract.md" 2>/dev/null; then
      echo "gold: $slug declares compass-format in contract.md but carries no valid .compass-format stamp - a build may not demote itself to the legacy rule"
      fail_ck=1
    fi
  fi

  # THE MUTATED TWIN. Every page is rendered twice - once from the real state files, once from a
  # copy whose data has been changed - and a number counts as a claim about this build's data only
  # if it MOVED. That is what replaced noun-adjacency, which round 5 measured at 12.5% coverage with
  # 6.8% false demands (it wanted a "counted by reading" label on `v0.28.0`).
  # The mutation must be STRUCTURE-PRESERVING. Appending rows shifted every later number by one
  # position, so index-aligned comparison read the shift as "these numbers moved" and demanded
  # labels on 1379 of them - worse than the proxy it replaced. These edits change VALUES in place:
  # a ticked box, a closed finding, a downgraded severity. Same number of elements, different counts.
  rm -rf "$TMP/tree"; mkdir -p "$TMP/tree"
  for sib in INDEX PROGRAM.md CURRENT; do
    [ -f "$ROOT/.claude/builds/$sib" ] && cp "$ROOT/.claude/builds/$sib" "$TMP/tree/$sib"
  done
  cp -R "$d" "$TMP/tree/$slug" 2>/dev/null
  rm -rf "$TMP/mut"; ln -s "$TMP/tree/$slug" "$TMP/mut" 2>/dev/null || cp -R "$TMP/tree/$slug" "$TMP/mut"
  moved=0; noop=""
  _try() { # $1=file $2=label $3=perl-expr — record whether it actually moved bytes
    [ -f "$1" ] || { noop="$noop $2:absent"; return; }
    cp "$1" "$TMP/before.$2" 2>/dev/null
    perl -0pi -e "$3" "$1" 2>/dev/null
    if cmp -s "$TMP/before.$2" "$1"; then noop="$noop $2"; else moved=1; fi
  }
  _try "$TMP/tree/$slug/plan.md" tick 's/^(\s*)- \[ \]/${1}- [x]/m' 
  _try "$TMP/tree/$slug/review-ledger.md" close 's/\bOPEN\b/FIXED/'
  _try "$TMP/tree/$slug/review-ledger.md" sev   's/\bCRITICAL\b/MINOR/i'
  if [ -f "$TMP/tree/$slug/review-ledger.md" ]; then
    # ADDING a row moves the totals, which a severity swap alone cannot. It was left out while the
    # comparison was index-aligned (an insertion shifted every later number and cascaded); the LCS
    # alignment absorbs insertions, so the stronger mutation is back and proves more claims.
    printf '\n| ZZ-PROBE-9 | R9 | 9 | probe | mutation probe row | - | Major | probe | probe | probe | probe | OPEN |\n' >> "$TMP/tree/$slug/review-ledger.md"
    moved=1
  fi
  _try "$TMP/tree/$slug/contract.md" inv 's/\*\*(INV-[A-Z0-9][A-Za-z0-9-]*)/**ZZ$1/'
  # THE DECLARED BLOCK FOLLOWS THE DATA, in the twin as in the original. v0.32 taught the generator
  # to refuse a page whose declared `invariants.total` disagrees with what the page computes
  # (`--self-consistency`, 6a7c826). The `inv` mutation renames one invariant, so the twin computes
  # one fewer — and the generator then correctly refused to render it, which silently killed the
  # cross-check for brief, brief-body and plan-map. That went unnoticed because the same commit
  # moved the auditor's hash and nobody re-pinned, so this whole tool had been declining to give a
  # verdict since v0.32.
  #
  # The mutation is not weakened to get past the check: a build with one fewer invariant HAS one
  # fewer, and its declared block must say so. Decrementing it here is what makes the twin a valid
  # build rather than an inconsistent one — and the number still MOVES, which is the entire point.
  if [ -f "$TMP/tree/$slug/progress.md" ]; then
    perl -0pi -e 's/("invariants\.total"\s*:\s*)(\d+)/$1.($2-1)/e' "$TMP/tree/$slug/progress.md" 2>/dev/null || true
  fi
  [ "$moved" -eq 1 ] || mut_blind="$mut_blind $slug"
  [ -z "$noop" ] || mut_noop="$mut_noop\n    $slug -> no-op edits:$noop"

  # A NEW build's truth is its declared data block, pulled from the build's own state files.
  echo 'null' > "$TMP/block.json"
  if [ "$mode" = new ]; then
    for f in "$d"/*.md; do
      [ -f "$f" ] || continue
      awk '/^ {0,3}`{3,}compass-artefact-data[ \t]*\r?$/{f=1;next} f&&/^ {0,3}`{3,}[ \t]*\r?$/{exit} f{print}' "$f" > "$TMP/b.txt" 2>/dev/null
      if [ -s "$TMP/b.txt" ] && node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$TMP/b.txt" 2>/dev/null; then
        cp "$TMP/b.txt" "$TMP/block.json"; break
      fi
    done
  fi

  # CROSS-CHECK the self-declared block where an exact check exists. Round 5: "the natural way to
  # write the block is to read it off the generator" — I edited 13 block fields from 30 to 999, the
  # pages rendered 999, and `mismatch` stayed 0, because nothing tied the block to the state files.
  # A plan checkbox is not prose: `- [ ]` / `- [x]` is a syntax Compass itself writes, so counting it
  # is exact, not a heuristic. Fields with no such check stay declared-on-trust, and §8 says so.
  if [ "$mode" = new ] && [ -s "$TMP/block.json" ] && [ -f "$d/plan.md" ]; then
    # The pattern is INLINE, not passed through `awk -v`: -v processes escape sequences, so `\[`
    # arrived as `[` and this counted 0 on every plan.md ever. The check that was supposed to stop
    # "read the block off the generator" had never once run.
    st="$(awk '/^[[:space:]]*```/ { f = !f; next } !f && /^[[:space:]]*- \[[ xX]\]/ { n++ } END { print n+0 }' "$d/plan.md")"
    sd="$(awk '/^[[:space:]]*```/ { f = !f; next } !f && /^[[:space:]]*- \[xX]?\]/ { n++ } END { print n+0 }' "$d/plan.md")"
    sd="$(awk '/^[[:space:]]*```/ { f = !f; next } !f && /^[[:space:]]*- \[[xX]\]/ { n++ } END { print n+0 }' "$d/plan.md")"
    bt="$(BLK="$TMP/block.json" node -e 'try{const b=JSON.parse(require("fs").readFileSync(process.env.BLK,"utf8"));console.log(b["steps.total"]??"")}catch(e){console.log("")}')"
    bd="$(BLK="$TMP/block.json" node -e 'try{const b=JSON.parse(require("fs").readFileSync(process.env.BLK,"utf8"));console.log(b["steps.done"]??"")}catch(e){console.log("")}')"
    if [ -n "$bt" ] && [ "$bt" != "$st" ]; then
      echo "gold: $slug declares steps.total=$bt but plan.md holds $st checkboxes - the block must agree with the file it describes"; fail_ck=1
    fi
    if [ -n "$bd" ] && [ "$bd" != "$sd" ]; then
      echo "gold: $slug declares steps.done=$bd but plan.md has $sd ticked - the block must agree with the file it describes"; fail_ck=1
    fi
    # `invariants.total` has an equally exact source: distinct bolded INV- ids in contract.md, a
    # syntax Compass itself writes. Declaring it 999 rendered "999 invariants" with mismatch=0.
    if [ -f "$d/contract.md" ]; then
      iv="$(grep -oE '\*\*(INV-[A-Za-z0-9][A-Za-z0-9-]*)' "$d/contract.md" 2>/dev/null | sort -u | grep -c . | tr -d ' ')"
      bi="$(BLK="$TMP/block.json" node -e 'try{const b=JSON.parse(require("fs").readFileSync(process.env.BLK,"utf8"));console.log(b["invariants.total"]??"")}catch(e){console.log("")}')"
      if [ -n "$bi" ] && [ "$bi" != "$iv" ]; then
        echo "gold: $slug declares invariants.total=$bi but contract.md declares $iv distinct INV- ids"; fail_ck=1
      fi
    fi
    # WHAT IS NOT CHECKED, said out loud rather than left to be discovered. A declared field with no
    # exact mechanical source is taken on trust; `findings.*` is the whole of that set, because
    # checking it would mean classifying free text — the guessing this build removed.
    for _f in findings.total findings.critical findings.major findings.closed findings.open; do
      _v="$(BLK="$TMP/block.json" F="$_f" node -e 'try{const b=JSON.parse(require("fs").readFileSync(process.env.BLK,"utf8"));console.log(b[process.env.F]??"")}catch(e){console.log("")}')"
      [ -n "$_v" ] && untrusted="$untrusted $slug:$_f=$_v"
    done
  fi

  for v in brief brief-body plan-map release-card review; do
    # R5-C1: this reused one temp path and trusted the exit code. A generator that wrote a single
    # page and exited 0 for the other 139 had that page re-audited every time — 140 audits of 8
    # numbers scored `unlabelled=0 ... EXIT 0`. The render target is now cleared, required to be
    # non-empty, required to name the build it claims to be, and required to be DISTINCT.
    rm -f "$TMP/p.html" "$TMP/m.html"
    node "$G" "$d" "$v" --out "$TMP/p.html" >/dev/null 2>&1 || continue
    if ! node "$G" "$TMP/tree/$slug" "$v" --out "$TMP/m.html" >/dev/null 2>&1; then
      echo "gold: $slug/$v — the mutated twin did not render, so the cross-check could not run"
      fail_ck=1
    fi
    [ -s "$TMP/p.html" ] || { echo "gold: $slug/$v rendered nothing"; fail_ck=1; continue; }
    grep -qF "$slug" "$TMP/p.html" || { echo "gold: $slug/$v does not name the build it renders"; fail_ck=1; continue; }
    # DISTINCTNESS is pinned as a COUNT, not enforced per page. `brief` and `brief-body` render
    # byte-identical output in all 28 dirs (the body-fragment view is currently the same document),
    # so rejecting each duplicate rejected 28 legitimate pages — the false-reject bug two earlier
    # rounds hit. The substitution attack collapses all 140 to ONE distinct page, so a floor catches
    # it while leaving the honest duplication alone.
    psum="$(shasum -a 256 "$TMP/p.html" | cut -c1-16)"
    case " $seen_pages " in *" $psum "*) : ;; *) seen_pages="$seen_pages $psum"; distinct=$((distinct+1)) ;; esac
    pages=$((pages+1))
        # SOURCES = everything the generator can legitimately quote from. It reads the sibling INDEX for
    # the Blast-radius field (gen.mjs:804), so excluding it accused 6 numbers of being invented that
    # were quoted correctly out of a file the check simply was not looking at. A `fabricated` count
    # is only meaningful if it covers every file the quoting actually draws on.
    cat "$d"/*.md "$ROOT/.claude/builds/INDEX" "$ROOT/.claude/builds/PROGRAM.md" > "$TMP/src.txt" 2>/dev/null || : >"$TMP/src.txt"
    read -r um mm bg nb us ns ml bp fb bd sp < <(PAGE="$TMP/p.html" MUT="$TMP/m.html" BLOCK="$TMP/block.json" MODE="$mode" AUD="$AUD" SRC="$TMP/src.txt" node -e '
const {pathToFileURL}=require("node:url");
import(pathToFileURL(process.env.AUD).href).then(m=>{
  const fs=require("fs");
  const raw=fs.readFileSync(process.env.PAGE,"utf8");
  let block=null; try{ block=JSON.parse(fs.readFileSync(process.env.BLOCK,"utf8")); }catch(_){}
  let mut=null; try{ mut=require("fs").readFileSync(process.env.MUT,"utf8"); }catch(_){}
  let src=""; try{ src=require("fs").readFileSync(process.env.SRC,"utf8"); }catch(_){}
  const r=m.scorePage(raw,process.env.MODE,block,mut,src);
  console.log("RESULT",r.unmarked,r.mismatch,r.bogus,r.noblock,r.unsaid,r.nested,r.mislabelled,r.badprov,r.fabricated,r.bidi,r.spoken);
});' | awk '/^RESULT /{c++; l=$0} END{ if(c!=1) exit 1; split(l,f," "); print f[2],f[3],f[4],f[5],f[6],f[7],f[8],f[9],f[10],f[11],f[12] }')
    # A CRASHED auditor must never read as zero. When the node call died, `read` left every var
    # empty, arithmetic treated them as 0, and the gold printed all-zeroes and EXIT 0 — a clean pass
    # produced by a checker that never ran. That is the "shell plumbing silently answers no" class
    # this build exists to catalogue, so it is a hard failure here.
    for _v in "${um:-}" "${mm:-}" "${bg:-}" "${nb:-}" "${us:-}" "${ns:-}" "${ml:-}" "${bp:-}" "${fb:-}" "${bd:-}" "${sp:-}"; do
      case "$_v" in
        ""|*[!0-9]*) echo "gold: ERR - the auditor returned '"'"'${ul:-} ${ub:-} ${mm:-} ${bg:-} ${nb:-} ${us:-}'"'"' for $slug/$v. A checker that did not run, or ran short, is not a pass."; exit 2 ;;
      esac
    done
    tok="$(PAGE="$TMP/p.html" AUD="$AUD" node -e '
const {pathToFileURL}=require("node:url");
import(pathToFileURL(process.env.AUD).href).then(m=>{
  console.log(m.auditPage(require("fs").readFileSync(process.env.PAGE,"utf8")).seq.length);
});')"
    tokens=$((tokens + ${tok:-0}))
    unmarked=$((unmarked+um)); mismatch=$((mismatch+mm)); bogus=$((bogus+bg))
    noblock=$((noblock+nb)); unsaid=$((unsaid+us)); nested=$((nested+ns)); mislabelled=$((mislabelled+ml))
    badprov=$((badprov+bp)); fabricated=$((fabricated+fb)); bidi=$((bidi+bd)); spoken=$((spoken+sp))
  done
done < <(
  if [ -n "$ONLY" ]; then
    # The manifest line when the dir is pinned (so its checksum is still verified), otherwise the
    # bare slug — an unpinned live build is exactly the case this flag exists for.
    awk -v s="$ONLY" '!/^#/ && $1 == s { print; found=1 } END { if (!found) print s }' "$MAN"
  else
    cat "$MAN"
  fi
)

fail=0
[ -z "$miss_dirs" ] || { echo "gold: manifest names dirs not present:$miss_dirs"; fail=1; }
[ "$fail_ck" -eq 0 ] || fail=1
[ -n "$ONLY" ] || [ "$dirs"  -eq "$WANT_DIRS" ]  || { echo "gold: compared $dirs dirs, expected $WANT_DIRS"; fail=1; }
[ -n "$ONLY" ] || [ "$pages" -eq "$WANT_PAGES" ] || { echo "gold: rendered $pages pages, expected $WANT_PAGES"; fail=1; }
[ -n "$ONLY" ] || [ "$distinct" -eq "$WANT_DISTINCT" ] || { echo "gold: $distinct distinct pages behind $pages renders, expected $WANT_DISTINCT - one page cannot stand in for many"; fail=1; }
[ -n "$ONLY" ] || [ "$tokens" -eq "$WANT_TOKENS" ] || { echo "gold: $tokens numbers across the corpus, expected $WANT_TOKENS - these are not the pinned pages (every digit run a reader sees, marked or not)"; fail=1; }
[ -n "$ONLY" ] || [ "$newdirs" -eq "$WANT_NEW" ] || { echo "gold: $newdirs new-format dirs, expected $WANT_NEW - the split itself moved"; fail=1; }
[ -n "$ONLY" ] || [ "$legacydirs" -eq "$WANT_LEGACY" ] || { echo "gold: $legacydirs legacy dirs, expected $WANT_LEGACY - the split itself moved"; fail=1; }
[ "$unmarked" -eq 0 ] || { echo "gold: unmarked=$unmarked - a number a reader sees that no marker says anything about"; fail=1; }
[ "$nested"   -eq 0 ] || { echo "gold: nested=$nested - a marker inside a marker; each number gets its own"; fail=1; }
[ "$badprov"    -eq 0 ] || { echo "gold: badprov=$badprov - a marker whose kind is not one of counted/quoted/literal, or a new build opting out of its block"; fail=1; }
[ "$bidi"       -eq 0 ] || { echo "gold: bidi=$bidi - a page carrying a bidi override, where a reader sees different digits than the markup contains"; fail=1; }
[ "$fabricated" -eq 0 ] || { echo "gold: fabricated=$fabricated - a number marked 'quoted' that appears nowhere in this build's files"; fail=1; }
[ "$mislabelled" -eq 0 ] || { echo "gold: mislabelled=$mislabelled - a number marked 'literal' that MOVES when the data moves"; fail=1; }
[ "$mismatch"   -eq 0 ] || { echo "gold: mismatch=$mismatch - a tied number that differs from what the block declares"; fail=1; }
[ "$bogus"      -eq 0 ] || { echo "gold: bogus=$bogus - a marker naming a field the block does not have"; fail=1; }
[ "$unsaid"     -eq 0 ] || { echo "gold: unsaid=$unsaid - a number the reader cannot verify (counted by reading, or quoted out of someone's prose) on a page whose words never tell them so"; fail=1; }
[ "$noblock"    -eq 0 ] || { echo "gold: noblock=$noblock - a new-format build states numbers with no data block"; fail=1; }
# No silent caps: a dir whose data could not be mutated has no differential, so nothing was demanded
# of it. Say which, rather than letting an empty demand read as a clean one.
[ -z "$untrusted" ] || echo "gold: NOTE - declared on trust, no exact source to check against:$untrusted"
[ -z "$mut_blind" ] || echo "gold: NOTE - no data mutation was possible for:$mut_blind (no claim could be proven on those dirs)"
# Per-EDIT no-ops, not just per-dir. 23 of 28 dirs have no unticked box, so the tick edit is inert on
# them and the recall those dirs get is lower than the headline suggests. Say so.
[ -z "$mut_noop" ] || printf 'gold: NOTE - edits that changed nothing (their recall is not covered):%b\n' "$mut_noop"
echo "dirs=$dirs ($newdirs new, $legacydirs legacy) pages=$pages | unmarked=$unmarked mismatch=$mismatch bogus=$bogus noblock=$noblock unsaid=$unsaid nested=$nested mislabelled=$mislabelled badprov=$badprov fabricated=$fabricated bidi=$bidi | spoken=$spoken (reported, not scored) distinct=$distinct tokens=$tokens"
exit $fail
