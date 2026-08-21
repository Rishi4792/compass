#!/usr/bin/env bash
# v0.32 S32 — the per-reviewer evidence file, validated against contract §4.
#
# WHY THIS EXISTS. §4 specified this file's shape and NO step in the plan covered it — the whole
# clause had no check at all, found by the traceability reviewer. A schema nothing validates is a
# paragraph, not a contract.
#
# THE RULE THAT MATTERS, and it is §4's own words: "A file missing `nonce` or `target-sha` is
# treated as ABSENT, not as a pass." That direction is deliberate. The tempting behaviour is to
# accept a nearly-right file and note the gap; that turns a malformed file into evidence a stream
# was reviewed. Counting it ABSENT makes the round fail for a missing stream, which is the truth.
#
# What this does NOT claim. §4 also says plainly that the nonce is an attribution LABEL and never
# evidence of independence — a reviewer forged four transcripts in about thirty lines of Python.
# This checks the SHAPE of a file. It cannot check who wrote it, and it says so rather than
# implying otherwise.
#
# Usage: evidence-shape-check.sh <agents-dir> [--expect-streams a,b,c]
# Exit: 0 every present file is well-formed (and every expected stream present) · 1 not · 2 usage.
set -uo pipefail
DIR="${1:-}"
[ -n "$DIR" ] && [ -d "$DIR" ] || { echo "evidence-shape-check: usage: evidence-shape-check.sh <agents-dir> [--expect-streams a,b,c]"; exit 2; }
shift || true
EXPECT=""
[ "${1:-}" = "--expect-streams" ] && EXPECT="${2:-}"

# §4's seven fields. `findings` is the only nullable one, so its ABSENCE is legal and its presence
# is not required; the other six must be there and non-empty.
REQUIRED="nonce stream review round target-sha verdict"

field() { # <file> <name>  -> value, or empty
  LC_ALL=C sed -nE "s/^[[:space:]]*[-*]?[[:space:]]*\**${2}\**[[:space:]]*:[[:space:]]*(.+)$/\1/p" "$1" 2>/dev/null \
    | head -1 | sed -e 's/^[\`"]//' -e 's/[\`"]$//' -e 's/[[:space:]]*$//'
}

n=0; ok=0; absent=0; bad=0; seen=""
for f in "$DIR"/*.md; do
  [ -f "$f" ] || continue
  n=$((n+1)); base="$(basename "$f")"
  missing=""
  for k in $REQUIRED; do
    v="$(field "$f" "$k")"
    [ -n "$v" ] || missing="$missing $k"
  done
  nonce="$(field "$f" nonce)"; tsha="$(field "$f" target-sha)"
  if [ -z "$nonce" ] || [ -z "$tsha" ]; then
    # §4, word for word: absent, never a pass.
    echo "  ABSENT $base — missing$( [ -z "$nonce" ] && printf ' nonce'; [ -z "$tsha" ] && printf ' target-sha'). Contract §4: treated as ABSENT, not as a pass."
    absent=$((absent+1)); continue
  fi
  if [ -n "$missing" ]; then
    echo "  BAD    $base — missing required field(s):$missing"
    bad=$((bad+1)); continue
  fi
  case "$(field "$f" review)" in review-contract|review-plan|review-build) : ;; *) echo "  BAD    $base — 'review' is not one of review-contract|review-plan|review-build"; bad=$((bad+1)); continue ;; esac
  case "$(field "$f" verdict)" in CLEAN|FINDINGS|COULD-NOT-VERIFY) : ;; *) echo "  BAD    $base — 'verdict' is not one of CLEAN|FINDINGS|COULD-NOT-VERIFY"; bad=$((bad+1)); continue ;; esac
  case "$(field "$f" round)" in ''|*[!0-9]*) echo "  BAD    $base — 'round' is not an integer"; bad=$((bad+1)); continue ;; esac
  [ "$(field "$f" round)" -ge 1 ] 2>/dev/null || { echo "  BAD    $base — 'round' must be >= 1"; bad=$((bad+1)); continue; }
  [ "${#nonce}" -ge 16 ] || { echo "  BAD    $base — 'nonce' is shorter than the 16 characters §4 requires"; bad=$((bad+1)); continue; }
  ok=$((ok+1)); seen="$seen $(field "$f" stream)"
done

missing_streams=""
if [ -n "$EXPECT" ]; then
  for s in $(printf '%s' "$EXPECT" | tr ',' ' '); do
    case " $seen " in *" $s "*) : ;; *) missing_streams="$missing_streams $s" ;; esac
  done
fi

echo "evidence-shape: $n files, $ok well-formed, $absent treated as ABSENT, $bad malformed."
if [ -n "$missing_streams" ]; then
  echo "  ROUND FAILS — no usable evidence for stream(s):$missing_streams"
  echo "  A stream with no well-formed evidence file was not reviewed, whatever the receipt says."
  exit 1
fi
[ "$bad" -eq 0 ] && [ "$absent" -eq 0 ] || exit 1
exit 0
