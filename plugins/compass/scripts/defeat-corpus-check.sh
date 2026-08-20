#!/usr/bin/env bash
# v0.31 GOLD, VALUE HALF — is the number RIGHT?
#
# The label half (proven-numbers.sh) asks whether every stated number is tied to a field. It
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
# The reader this check depends on is pinned, and an ABSENT pin is an error, never a skip.
RDR="$HERE/page-number.mjs"
RMAN="$HERE/defeat-corpus-manifest.txt"
if [ -f "$RDR" ] && [ -f "$RMAN" ]; then
  _wr="$(awk '/^# reader-sha256:/{print $3; exit}' "$RMAN")"
  if [ -z "$_wr" ]; then
    echo "defeat-corpus: ERR - no 'reader-sha256' pin in $RMAN. An unpinned reader cannot be trusted."; exit 2
  fi
  _gr="$(shasum -a 256 "$RDR" | cut -c1-16)"
  [ "$_wr" = "$_gr" ] || { echo "defeat-corpus: ERR - page-number.mjs does not match its pinned hash (pinned $_wr, got $_gr)."; exit 2; }
  _rctl="$(node "$RDR" --controls 2>&1)"; _rrc=$?
  printf '%s\n' "$_rctl"
  case "$_rctl" in
    *"controls fire"*) : ;;
    *) echo "defeat-corpus: ERR - the reader's controls produced no confirmation (rc=$_rrc). Silence is not a pass."; exit 2 ;;
  esac
  [ "$_rrc" -eq 0 ] || { echo "defeat-corpus: ERR - the reader's controls are not all firing."; exit 2; }
fi
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
  # R4-C6: this used to embed its own python row-counter — a THIRD implementation of "compute a
  # true value", invisible to INV-7's grep because it lived inside a .sh file, and disagreeing with
  # the other two on 11 of 28 builds. The anchor it provided is now the manifest pin: the fixture's
  # sha256 and its expected value are both recorded, so editing either is a visible diff rather than
  # a silent re-baseline. These fixtures are a few lines long and hand-verified; they do not need a
  # parser to tell us what is in them.
  # SECOND OPINION. R8 showed the manifest pin alone can be re-baselined: edit EXPECTED's true value
  # AND the manifest column and a real regression is blessed ("ok — states the true value 3"). The
  # checksum stops silent fixture drift but says nothing about whether the pinned truth is TRUE of
  # the fixture. These fixtures are three-line tables, so an independent count is trivial and
  # reliable at this scale — the reasons the build-scale python readers were retired do not apply.
  # The pin and the derivation must AGREE; if they do not, the entry is refused either way.
  derived="$(awk '
    /^[[:space:]]*```/ { f = !f; next }
    f { next }
    /^[[:space:]]*>?[[:space:]]*\|/ {
      line = $0; sub(/^[[:space:]]*>[[:space:]]?/, "", line)
      if (line ~ /^[[:space:]]*\|[[:space:]]*:?-+/) next          # separator row
      n = split(line, c, "|")
      id = c[2]; gsub(/[[:space:]*`]/, "", id)
      if (id == "") next
      if (tolower(id) ~ /^(id|issue|issueid|sev|severity|status|verdict|round|area|fix|owner|total|none)$/) next
      if (id !~ /[0-9]/) next
      n_rows++     # ROWS, not distinct ids: `dup-id-two-tables` exists precisely because Compass
                   # ledgers repeat an id across review sections, so de-duplicating would count 1
                   # where the truth is 2 — the very defect the fixture pins.
    }
    END { print n_rows+0 }' "$e/review-ledger.md" 2>/dev/null)"

  # The anchor is the MANIFEST, whose line for this slug pins both the fixture's sha256 and its true
  # value. Round 5 found that setting `derived=""` had left this guard and the refusal guard below
  # dead while their comments still described a derivation — the code no longer did what it said.
  pinned_true="$(awk -v s="$slug" '$1==s{print $3}' "$HERE/defeat-corpus-manifest.txt" 2>/dev/null | head -1)"
  if [ -z "$pinned_true" ]; then
    echo "  REFUSE $slug — present in the corpus but not pinned in the manifest; an entry must be pinned to count"
    bad=$((bad+1)); continue
  fi
  if [ "$pinned_true" != "$want" ]; then
    echo "  REFUSE $slug — the manifest pins the truth at $pinned_true, EXPECTED says $want"
    bad=$((bad+1)); continue
  fi
  if [ -n "$derived" ] && [ "$derived" != "$want" ]; then
    echo "  REFUSE $slug — EXPECTED and the manifest both say $want, but an independent count of the fixture says $derived. Re-baselining the pin does not make a number true."
    bad=$((bad+1)); continue
  fi
  node "$G" "$e" "$view" --out "$TMP/dcc.html" >/dev/null 2>&1 || { echo "  FAIL $slug — did not render"; bad=$((bad+1)); continue; }
  # R3-C4: this read the page with its own regex, whose tag-tolerant branch was dead code.
  # One shared reader now, so the two halves of the gold cannot disagree about what a page says.
  got="$(PAGE="$TMP/dcc.html" MOD="$HERE/page-number.mjs" node -e '
const {pathToFileURL}=require("node:url");
import(pathToFileURL(process.env.MOD).href).then(m=>{
  const h=require("fs").readFileSync(process.env.PAGE,"utf8");
  const n=m.statedNumber(h,"findings");
  console.log(n!==null? n : (m.refuses(h)? "REFUSED":"NONE"));
});')"
  if [ "$got" = "$never" ]; then
    echo "  FAIL $slug — states $got, which is the known-wrong value (true: $want)"; bad=$((bad+1))
  elif [ "$got" = "$want" ]; then
    echo "  ok   $slug — states the true value $want"
  elif [ "$got" = "REFUSED" ]; then
    # A refusal is only honest if what it SAYS is true. An entry may pin a claim the refusal must
    # NOT make — a page that states no number but misdescribes why is still stating a falsehood
    # about its own input, which is what the contract's Goal forbids.
    # ANCHORED, not author-declared. `refusal-must-not-claim` is free text the author owns, so
    # rewriting it to "ZZZ" made an entry pass. This rule needs no declaration and cannot be edited
    # away: the manifest pins this fixture's true row count AND its sha256, so if the pinned count is
    # above zero the ledger demonstrably HAS readable rows — and a page claiming it "could not be
    # read" is stating a falsehood about its own input. Changing that pin is a visible diff in a
    # git-tracked file; changing the fixture fails the checksum.
    nc=""
    if [ "${pinned_true:-0}" -gt 0 ]; then nc="could not be read"; fi
    # an entry may name an ADDITIONAL claim, but may never remove the anchored one
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
# R3-C3: a floor is still only a COUNT. Deleting the two entries that actually defeat the generator
# and adding two trivial ones kept n at 2 and scored clean. Entries are now pinned by IDENTITY.
MAN="$HERE/defeat-corpus-manifest.txt"
[ -f "$MAN" ] || { echo "defeat-corpus: no identity pin at $MAN — the corpus cannot be verified"; exit 2; }
pinned=0
while read -r slug hash want_p never_p _rest || [ -n "${slug:-}" ]; do
  case "${slug:-#}" in \#*|"") continue ;; esac
  pinned=$((pinned+1))
  e="$CORPUS/$slug"
  if [ ! -f "$e/EXPECTED" ]; then
    echo "  REFUSE $slug — pinned in the corpus but no longer present; an entry may be added, never removed"
    bad=$((bad+1)); continue
  fi
  # EVERY file in the fixture, not just its ledger. Pinning one file left EXPECTED and the fixture's
  # own contract.md unchecksummed, so the entry could be neutered with the pinned file untouched.
  now="$(find "$e" -type f -print0 2>/dev/null | xargs -0 shasum -a 256 2>/dev/null | cut -c1-12 | sort | paste -sd'.' - | shasum -a 256 | cut -c1-16)"
  if [ "$now" != "$hash" ]; then
    echo "  REFUSE $slug — the fixture changed (pinned $hash, now ${now:-missing}). Changing what a defeat entry PROVES is not a clean round."
    bad=$((bad+1)); continue
  fi
  now_w="$(sed -nE 's/^true\.findings\.total:[[:space:]]*([0-9]+).*/\1/p' "$e/EXPECTED" | head -1)"
  if [ "$now_w" != "$want_p" ]; then
    echo "  REFUSE $slug — the pinned true value was $want_p, EXPECTED now says $now_w"
    bad=$((bad+1)); continue
  fi
  # R4-m2: this column was parsed and then never compared, so the known-wrong value was pinned in
  # name only and could be edited to anything without a complaint.
  now_n="$(sed -nE 's/^must-not-state:[[:space:]]*([0-9]+).*/\1/p' "$e/EXPECTED" | head -1)"
  if [ "${never_p:--}" != "-" ] && [ "$now_n" != "$never_p" ]; then
    echo "  REFUSE $slug — the pinned known-wrong value was $never_p, EXPECTED now says ${now_n:-<none>}"
    bad=$((bad+1)); continue
  fi
done < "$MAN"
[ "$n" -ge "$pinned" ] || { echo "defeat-corpus: $n entries present, $pinned pinned"; bad=$((bad+1)); }
echo "defeat-corpus: $n entries ($pinned pinned by identity), $bad failing"
[ "$bad" -eq 0 ]
