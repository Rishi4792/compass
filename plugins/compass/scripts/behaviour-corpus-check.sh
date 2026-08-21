#!/usr/bin/env bash
# v0.32 S5/S9 — THE BEHAVIOUR CORPUS. Every entry is a way to make a check look clean without
# fixing anything, plus the reproduction that earned its place.
#
# WHY IT IS RUN, not merely stored. `defeat-corpus-check.sh:143` already records the lesson: that
# corpus pinned a COUNT, so deleting the two entries that actually defeat the generator and adding
# two trivial ones scored the same. Here each entry is APPLIED to a throwaway copy of the repo and
# the named check is re-run against it. An entry that stops defeating anything fails loudly.
#
# Entries are ADD-ONLY and pinned by IDENTITY: the manifest carries a sha256 per entry. A removed
# slug fails. A hollowed-out entry fails on its checksum. This does not make the corpus
# tamper-proof — an author who edits the manifest too can still weaken it — it makes every
# weakening a VISIBLE DIFF LINE rather than a silent pass.
#
# Exit: 0 all entries still defeat what they claim · 1 one or more do not · 2 setup error.
set -uo pipefail
ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORPUS="$HERE/fixtures/defeat-behaviour"
MAN="$HERE/behaviour-corpus-manifest.txt"
FXCORP="$HERE/fixtures/corpus"
[ -d "$CORPUS" ] || { echo "behaviour-corpus: ERR - no corpus at $CORPUS"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "behaviour-corpus: ERR - node is not on PATH, so nothing was exercised. An ERR, never a pass."; exit 2; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# entry_sha: identity over the three files that make an entry evidence.
entry_sha() { cat "$1/apply.sh" "$1/EXPECTED" "$1/REPRODUCTION.md" 2>/dev/null | shasum -a 256 | cut -c1-16; }

# The baseline the cheats are measured against, taken on the UNMODIFIED tree.
base_out="$(bash "$HERE/reachable-argument-check.sh" "$ROOT" --corpus "$FXCORP" 2>&1)"
BASE="$(printf '%s' "$base_out" | sed -nE 's/^[[:space:]]*UNREACHABLE[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)"
# The SECOND baseline. Some cheats cannot be judged on the probe figure at all, because they change
# what there is to probe — see fixtures/defeat-behaviour/hide-rows. Its denominator is the source.
SBASE="$(printf '%s' "$base_out" | sed -nE 's/^[[:space:]]*SOURCE UNREACHABLE[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)"
# The CREDIT side. Every rule until now was "the figure must not FALL", which cannot express a cheat
# that leaves every figure byte-identical while making all 83 controls unopenable. Found by the
# independent review of S6, which built exactly that.
RBASE="$(printf '%s' "$base_out" | sed -nE 's/^[[:space:]]*REACHABLE[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)"
case "${BASE:-}" in
  ''|*[!0-9]*) echo "behaviour-corpus: ERR - no baseline figure from reachable-argument-check. Silence is not a pass."; exit 2 ;;
esac
[ "$BASE" -gt 0 ] || { echo "behaviour-corpus: ERR - the probe baseline is 0, so no cheat could lower it and every entry would 'pass' for free."; exit 2; }
case "${SBASE:-}" in
  ''|*[!0-9]*) echo "behaviour-corpus: ERR - no SOURCE baseline figure. Silence is not a pass."; exit 2 ;;
esac
# The same guard on the second baseline, and it is not theoretical: breaking the source measure so
# that every line counts as reachable takes SBASE to 0, and 0 -> 0 then satisfies "must not fall"
# for free. Found by mutating the measure and watching the corpus stay green.
[ "$SBASE" -gt 0 ] || { echo "behaviour-corpus: ERR - the SOURCE baseline is 0, so no cheat could lower it and every source-rule entry would 'pass' for free."; exit 2; }
echo "behaviour-corpus: baseline unreachable = $BASE over the tracked corpus."

# v0.32 S5b, all three found by an independent reviewer and all three reproduced:
#   - deleting the two entries that ever went red left "3 entries, 0 failing", rc=0. "A removed
#     slug fails" was simply false: the check only walked disk -> manifest, never the other way.
#   - deleting the MANIFEST silently disabled identity pinning altogether, so a hollowed-out
#     apply.sh still reported "defeated".
# This is `defeat-corpus-check.sh:143`'s own recorded lesson, re-committed here and now fixed.
[ -f "$MAN" ] || { echo "behaviour-corpus: ERR - no manifest at $MAN. Without it nothing is pinned and any entry can be hollowed out silently."; exit 2; }
_pinned="$(awk '!/^#/ && NF>=2 {print $1}' "$MAN")"
[ -n "$_pinned" ] || { echo "behaviour-corpus: ERR - the manifest pins nothing."; exit 2; }
_gone=""
for _slug in $_pinned; do
  [ -d "$CORPUS/$_slug" ] || _gone="$_gone $_slug"
done
if [ -n "$_gone" ]; then
  echo "behaviour-corpus: ERR - entries pinned in the manifest are MISSING from the corpus:$_gone"
  echo "  The corpus is ADD-ONLY. Removing an entry removes the proof it carried, and doing it"
  echo "  quietly is how a corpus becomes a decoration."
  exit 2
fi

n=0; bad=0
for d in "$CORPUS"/*/; do
  [ -d "$d" ] || continue
  slug="$(basename "$d")"; n=$((n+1))
  for f in apply.sh EXPECTED REPRODUCTION.md; do
    [ -s "$d/$f" ] || { echo "  FAIL $slug - $f is missing or empty; an entry without its reproduction is not evidence"; bad=$((bad+1)); continue 2; }
  done
  if [ -f "$MAN" ]; then
    want="$(awk -v s="$slug" '$1==s{print $2}' "$MAN" | head -1)"
    got="$(entry_sha "$d")"
    if [ -z "$want" ]; then echo "  FAIL $slug - not pinned in the manifest; an unpinned entry can be hollowed out silently"; bad=$((bad+1)); continue; fi
    if [ "$want" != "$got" ]; then echo "  FAIL $slug - does not match its pinned identity (pinned $want, got $got)"; bad=$((bad+1)); continue; fi
  fi
  rule="$(sed -nE 's/^rule=(.*)$/\1/p' "$d/EXPECTED" | head -1)"
  case "$rule" in
    figure-must-not-fall)
      work="$TMP/$slug"; mkdir -p "$work"
      # a copy is enough: the cheats only touch the generator.
      mkdir -p "$work/plugins/compass/skills/compass-visual" "$work/plugins/compass/scripts"
      cp -R "$ROOT/plugins/compass/skills/compass-visual/." "$work/plugins/compass/skills/compass-visual/" 2>/dev/null
      cp -R "$ROOT/plugins/compass/scripts/." "$work/plugins/compass/scripts/" 2>/dev/null
      if ! bash "$d/apply.sh" "$work" >"$TMP/$slug.apply.log" 2>&1; then
        echo "  FAIL $slug - its apply.sh no longer applies: $(tail -1 "$TMP/$slug.apply.log")"; bad=$((bad+1)); continue
      fi
      out="$(bash "$work/plugins/compass/scripts/reachable-argument-check.sh" "$work" --corpus "$FXCORP" 2>&1)"
      got="$(printf '%s' "$out" | sed -nE 's/^[[:space:]]*UNREACHABLE[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)"
      case "${got:-}" in
        ''|*[!0-9]*) echo "  FAIL $slug - the check printed no figure after the cheat (rendered pages: $(printf '%s' "$out" | head -1))"; bad=$((bad+1)); continue ;;
      esac
      if [ "$got" -lt "$BASE" ]; then
        echo "  FAIL $slug - THE CHEAT WORKS: unreachable fell $BASE -> $got without a single row being fixed"; bad=$((bad+1))
      elif [ "$got" -eq $BASE ]; then
        # Equal is a PASS — the cheat bought nothing — but it is weaker evidence than a rise, and
        # saying so is the difference between a corpus and a decoration. On a badly-broken baseline
        # a cheat has little room to make things worse; this line disappears on its own as the fix
        # lands and the figure falls toward zero.
        echo "  ok   $slug - defeated: unreachable $BASE -> $got (equal: the cheat bought nothing, but on this"
        echo "         baseline it also had little room to show, so this is the weaker form of the proof)"
      else
        echo "  ok   $slug - defeated: unreachable $BASE -> $got (the cheat made it WORSE, which is the strong form)"
      fi ;;
    source-unreachable-must-not-fall)
      work="$TMP/$slug"; mkdir -p "$work"
      mkdir -p "$work/plugins/compass/skills/compass-visual" "$work/plugins/compass/scripts"
      cp -R "$ROOT/plugins/compass/skills/compass-visual/." "$work/plugins/compass/skills/compass-visual/" 2>/dev/null
      cp -R "$ROOT/plugins/compass/scripts/." "$work/plugins/compass/scripts/" 2>/dev/null
      if ! bash "$d/apply.sh" "$work" >"$TMP/$slug.apply.log" 2>&1; then
        echo "  FAIL $slug - its apply.sh no longer applies: $(tail -1 "$TMP/$slug.apply.log")"; bad=$((bad+1)); continue
      fi
      out="$(bash "$work/plugins/compass/scripts/reachable-argument-check.sh" "$work" --corpus "$FXCORP" 2>&1)"
      got="$(printf '%s' "$out" | sed -nE 's/^[[:space:]]*SOURCE UNREACHABLE[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)"
      case "${got:-}" in
        ''|*[!0-9]*) echo "  FAIL $slug - the check printed no SOURCE figure after the cheat"; bad=$((bad+1)); continue ;;
      esac
      if [ "$got" -lt "$SBASE" ]; then
        echo "  FAIL $slug - THE CHEAT WORKS: source-unreachable fell $SBASE -> $got without a single row being fixed"; bad=$((bad+1))
      elif [ "$got" -eq $SBASE ]; then
        # Equal is a PASS — the cheat bought nothing — but it is weaker evidence than a rise, and
        # saying so is the difference between a corpus and a decoration. On a badly-broken baseline
        # a cheat has little room to make things worse; this line disappears on its own as the fix
        # lands and the figure falls toward zero.
        echo "  ok   $slug - defeated: source-unreachable $SBASE -> $got (equal: the cheat bought nothing, but on this"
        echo "         baseline it also had little room to show, so this is the weaker form of the proof)"
      else
        echo "  ok   $slug - defeated: source-unreachable $SBASE -> $got (the cheat made it WORSE, which is the strong form)"
      fi ;;
    figure-must-reach-zero)
      # The POSITIVE control. Every other entry asks "can this be cheated?"; this one asks the
      # question v0.31 forgot: can an HONEST implementation actually reach the target? A gold no
      # honest fix can reach is a wall, not a target.
      work="$TMP/$slug"; mkdir -p "$work"
      mkdir -p "$work/plugins/compass/skills/compass-visual" "$work/plugins/compass/scripts"
      cp -R "$ROOT/plugins/compass/skills/compass-visual/." "$work/plugins/compass/skills/compass-visual/" 2>/dev/null
      cp -R "$ROOT/plugins/compass/scripts/." "$work/plugins/compass/scripts/" 2>/dev/null
      if ! bash "$d/apply.sh" "$work" >"$TMP/$slug.apply.log" 2>&1; then
        echo "  FAIL $slug - its apply.sh no longer applies: $(tail -1 "$TMP/$slug.apply.log")"; bad=$((bad+1)); continue
      fi
      out="$(bash "$work/plugins/compass/scripts/reachable-argument-check.sh" "$work" --corpus "$FXCORP" 2>&1)"
      # Scoped to the BINDABLE paths — the ones that carry their shown half, so a control can be
      # tied to their rows at all. Ten of the thirteen are not wired yet (S7), and asserting zero
      # over paths the check cannot bind would be asserting something no implementation can satisfy,
      # which is the v0.31 failure in a new costume. The scope widens on its own as S7 lands.
      got="$(printf '%s' "$out" | sed -nE 's/^[[:space:]]*UNREACHABLE \(bindable\)[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)"
      case "${got:-}" in
        ''|*[!0-9]*) echo "  FAIL $slug - the check printed no bindable figure for the honest fix"; bad=$((bad+1)); continue ;;
      esac
      if [ "$got" -eq 0 ]; then
        echo "  ok   $slug - an honest fix reaches ZERO on every BINDABLE path, so the target is satisfiable"
      else
        echo "  FAIL $slug - AN HONEST FIX CANNOT REACH THE TARGET: $BASE -> $got, not 0."
        echo "         The gold is a wall, not a target. This is the v0.31 failure, and it is a"
        echo "         blocker on the CHECK, not on the generator."
        bad=$((bad+1))
      fi ;;
    reachable-must-not-hold)
      # A control the check CREDITS must be one a reader can open. This arm watches the credit side:
      # if a cheat makes every control unopenable, REACHABLE must FALL. Every other rule watches
      # the debit side and would report this cheat as defeated while crediting 83 controls that do
      # not exist for a reader.
      work="$TMP/$slug"; mkdir -p "$work"
      mkdir -p "$work/plugins/compass/skills/compass-visual" "$work/plugins/compass/scripts"
      cp -R "$ROOT/plugins/compass/skills/compass-visual/." "$work/plugins/compass/skills/compass-visual/" 2>/dev/null
      cp -R "$ROOT/plugins/compass/scripts/." "$work/plugins/compass/scripts/" 2>/dev/null
      if ! bash "$d/apply.sh" "$work" >"$TMP/$slug.apply.log" 2>&1; then
        echo "  FAIL $slug - its apply.sh no longer applies: $(tail -1 "$TMP/$slug.apply.log")"; bad=$((bad+1)); continue
      fi
      out="$(bash "$work/plugins/compass/scripts/reachable-argument-check.sh" "$work" --corpus "$FXCORP" 2>&1)"
      got="$(printf '%s' "$out" | sed -nE 's/^[[:space:]]*REACHABLE[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)"
      case "${got:-}" in
        ''|*[!0-9]*) echo "  FAIL $slug - the check printed no REACHABLE figure after the cheat"; bad=$((bad+1)); continue ;;
      esac
      if [ "$got" -ge "$RBASE" ]; then
        echo "  FAIL $slug - THE CHEAT WORKS: every control is inside display:none and REACHABLE held $RBASE -> $got"; bad=$((bad+1))
      else
        echo "  ok   $slug - defeated: REACHABLE fell $RBASE -> $got once the controls became unopenable"
      fi ;;
    *) echo "  FAIL $slug - EXPECTED names no rule this runner knows ('$rule')"; bad=$((bad+1)) ;;
  esac
done

echo "behaviour-corpus: $n entries, $bad failing"
[ "$n" -gt 0 ] || { echo "behaviour-corpus: ERR - zero entries. An empty corpus proves nothing and is never a pass."; exit 2; }
exit $([ "$bad" -eq 0 ] && echo 0 || echo 1)
