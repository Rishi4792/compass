#!/usr/bin/env bash
# gold-diff-check — diff the contract's published figures against the producer that made them.
#
#   usage: gold-diff-check.sh [repo-root] [--contract <file>]
#
# WHY THIS EXISTS. Section 2 of a contract publishes a block of figures. `reconcile-pages.mjs`
# derives those figures from the corpus. Until now NOTHING RAN THE PRODUCER — it had zero callers,
# so the block was a transcript of a measurement taken once, by hand, and every later edit to the
# code silently invalidated it. Ten figures had already moved by the time a reviewer noticed, and
# the reader has no way to tell a live number from a stale one.
#
# This does not re-measure anything. It runs the producer and compares it, VALUE BY VALUE, with what
# the contract claims. A figure the producer no longer reproduces is not a figure.
#
# exit 0  every published figure matches the producer
# exit 1  at least one published figure disagrees with the producer — named, with both values
# exit 2  usage / not a compass repo
# exit 3  ERR — the producer could not run, or the contract publishes no gold block to check
set -uo pipefail

ROOT="."; CONTRACT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --contract) [ $# -ge 2 ] || { echo "gold-diff-check: --contract needs a file" >&2; exit 2; }
                CONTRACT="$2"; shift 2 ;;
    --*) echo "gold-diff-check: unknown flag '$1'" >&2; exit 2 ;;
    *) ROOT="$1"; shift ;;
  esac
done
cd "$ROOT" 2>/dev/null || { echo "gold-diff-check: cannot enter '$ROOT'" >&2; exit 2; }
[ -d plugins/compass ] || { echo "gold-diff-check: not a compass repo root" >&2; exit 2; }
command -v node >/dev/null 2>&1 || { echo "gold-diff-check: node is required to run the producer" >&2; exit 3; }

PRODUCER="plugins/compass/scripts/reconcile-pages.mjs"
[ -f "$PRODUCER" ] || { echo "gold-diff-check: producer '$PRODUCER' is absent" >&2; exit 3; }

# Find the contract that publishes a gold block, unless one was named.
if [ -z "$CONTRACT" ]; then
  for c in .claude/builds/*/contract.md; do
    [ -f "$c" ] || continue
    LC_ALL=C grep -qE '^[a-z_.]+ +=  *[^ ]' "$c" && { CONTRACT="$c"; break; }
  done
fi
[ -n "$CONTRACT" ] && [ -f "$CONTRACT" ] || { echo "gold-diff-check: ERR — no contract publishes a gold block"; exit 3; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if ! node "$PRODUCER" > "$TMP/live.txt" 2>"$TMP/err.txt"; then
  echo "gold-diff-check: ERR — the producer failed to run:"; sed 's/^/    /' "$TMP/err.txt" | head -5; exit 3
fi

# ANY value, not only digits. A first draft matched `[0-9]+` and silently skipped `corpus.sha`,
# which is the exact defect this check exists to catch, one level up: a figure nobody compares.
LC_ALL=C sed -nE 's/^([a-z_.]+) +=  *([^ ].*)$/\1 \2/p' "$TMP/live.txt" | sed 's/[[:space:]]*$//' | sort > "$TMP/live.tsv"
LC_ALL=C sed -nE 's/^([a-z_.]+) +=  *([^ ].*)$/\1 \2/p' "$CONTRACT"     | sed 's/[[:space:]]*$//' | sort > "$TMP/pub.tsv"

_pub="$(grep -c . "$TMP/pub.tsv" || true)"
_live="$(grep -c . "$TMP/live.tsv" || true)"
[ "${_pub:-0}" -gt 0 ] || { echo "gold-diff-check: ERR — '$CONTRACT' publishes no figure this can check. An empty comparison is not a pass."; exit 3; }
[ "${_live:-0}" -gt 0 ] || { echo "gold-diff-check: ERR — the producer emitted no figure. An empty comparison is not a pass."; exit 3; }

printf '── published figures vs the producer ────────────────────────────────\n'
bad=0; checked=0; absent=0
while read -r k v; do
  [ -n "${k:-}" ] || continue
  lv="$(LC_ALL=C awk -v k="$k" '$1==k {print $2}' "$TMP/live.tsv" | head -1)"
  if [ -z "$lv" ]; then
    printf '  GONE  %-40s published %-6s the producer no longer emits it\n' "$k" "$v"
    absent=$((absent+1)); bad=$((bad+1)); continue
  fi
  checked=$((checked+1))
  if [ "$lv" = "$v" ]; then printf '  ok    %-40s %s\n' "$k" "$v"
  else printf '  DIFF  %-40s published %-6s producer says %s\n' "$k" "$v" "$lv"; bad=$((bad+1)); fi
done < "$TMP/pub.tsv"
printf '─────────────────────────────────────────────────────────────────────\n'

if [ "$bad" -gt 0 ]; then
  echo "gold-diff-check: $bad of $_pub published figure(s) do not match the producer ($absent no longer emitted)."
  echo "  A figure the producer cannot reproduce is not a figure. Re-derive section 2, or fix the producer."
  exit 1
fi
echo "gold-diff-check: all $checked published figure(s) reproduce EXACTLY from $PRODUCER."
exit 0
