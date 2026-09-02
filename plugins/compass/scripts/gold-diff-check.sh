#!/usr/bin/env bash
# suite-member: mechanical-suite — this line is how the suite proves its child list still NAMES this
# check. Removing the check from CHILDREN while this line stands makes the suite ERR. Delete both
# together and that is a deliberate removal, not an accident nobody noticed.
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
  # A GOLD BLOCK BELONGS TO ITS BUILD. This took whichever contract it found FIRST, which meant it
  # went on re-checking a SHIPPED build's historical figures for ever — and those figures are counted
  # over every build folder on the machine, so the next build starting moved them and 17 of 33 went
  # red on work that was correct when it was measured. The CURRENT build is checked; an older one's
  # gold is a record of what was true then, not a claim about today.
  _cur=""; [ -f .claude/builds/CURRENT ] && _cur="$(cat .claude/builds/CURRENT 2>/dev/null || true)"
  if [ -n "$_cur" ] && [ -f ".claude/builds/$_cur/contract.md" ] \
     && LC_ALL=C grep -qE '^[A-Za-z_][A-Za-z0-9_.-]* +=  *[^ ]' ".claude/builds/$_cur/contract.md"; then
    CONTRACT=".claude/builds/$_cur/contract.md"
  fi
fi
if [ -z "$CONTRACT" ] && [ -n "${_cur:-}" ] && [ -f ".claude/builds/$_cur/contract.md" ]; then
  echo "gold-diff-check: N/A — the current build ($_cur) publishes no gold block. An older build's figures are a record of what was true when they were measured, not a claim about today, so they are not re-checked here."
  exit 0
fi
# GUARD-FIRST, and this one shipped broken for exactly one commit. `.claude/builds/` is GITIGNORED,
# so in a fresh clone — which is every consumer project, and the population the perf ceiling is
# defined over — there is no contract at all. Returning ERR there took `mechanical-suite.sh` to
# exit 1 for EVERY USER on upgrade. Absent build state is the ordinary case, not a failure, and it
# N/A-PASSES while SAYING SO. It does not escape scrutiny by that route: where a gold block does
# exist, every published figure is still compared and a mismatch still exits 1.
if [ -z "$CONTRACT" ] || [ ! -f "$CONTRACT" ]; then
  echo "gold-diff-check: N/A — no build in this tree publishes a gold block (.claude/builds is gitignored, so a fresh clone has none). Nothing is claimed about figures that are not here."
  exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if ! node "$PRODUCER" > "$TMP/live.txt" 2>"$TMP/err.txt"; then
  echo "gold-diff-check: ERR — the producer failed to run:"; sed 's/^/    /' "$TMP/err.txt" | head -5; exit 3
fi

# ANY value, not only digits. A first draft matched `[0-9]+` and silently skipped `corpus.sha`,
# which is the exact defect this check exists to catch, one level up: a figure nobody compares.
# THE KEY PATTERN ADMITS HYPHENS AND CAPITALS. It did not, so `pages.brief-body`, `pages.plan-map`,
# `pages.release-card` and ALL FOUR `reach.*` were silently skipped — 7 of 33, including the four
# figures section 2 says "carry the whole argument on their own". Three independent reviewers found
# it the same way: set all seven to 9999 and this printed "all 26 reproduce EXACTLY", exit 0. That
# is the defect this file exists to catch, in this file, one column left of the comment claiming it
# was fixed. The denominator is asserted below so a silent skip can never be a pass again.
LC_ALL=C sed -nE 's/^([A-Za-z_][A-Za-z0-9_.-]*) +=  *([^ ].*)$/\1 \2/p' "$TMP/live.txt" | sed 's/[[:space:]]*$//' | sort > "$TMP/live.tsv"
LC_ALL=C sed -nE 's/^([A-Za-z_][A-Za-z0-9_.-]*) +=  *([^ ].*)$/\1 \2/p' "$CONTRACT"     | sed 's/[[:space:]]*$//' | sort > "$TMP/pub.tsv"

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
  # NAME THE CAUSE, NOT THE SYMPTOMS. These figures are counted over every build folder on the
  # machine, so CREATING A NEW BUILD moves the population and every dependent figure with it —
  # 17 of 33 went red the moment the next build rendered its first page. Listing 17 mismatches
  # invites re-deriving 17 numbers when only ONE thing happened. If the population figure itself
  # moved, say that first and say what it means, because the honest answer is usually
  # "this gold was pinned to a set that no longer exists", not "the producer is broken".
  _pop_pub="$(LC_ALL=C awk '$1=="pages.total"{print $2}' "$TMP/pub.tsv" | head -1)"
  _pop_live="$(LC_ALL=C awk '$1=="pages.total"{print $2}' "$TMP/live.tsv" | head -1)"
  if [ -n "$_pop_pub" ] && [ -n "$_pop_live" ] && [ "$_pop_pub" != "$_pop_live" ]; then
    echo "gold-diff-check: THE POPULATION MOVED — this gold was measured over ${_pop_pub} page(s) and there are now ${_pop_live}."
    echo "  $bad of $_pub published figure(s) disagree, and most of them follow from that one change"
    echo "  rather than from $bad separate errors. These counts are taken over EVERY build folder on"
    echo "  this machine, so starting a new build moves them. Re-derive the block against the current"
    echo "  set, or scope the producer to a fixed corpus — do not patch the figures one at a time."
    echo "gold-diff-check: ERR (population ${_pop_pub} -> ${_pop_live}; $bad of $_pub figures moved with it)"
    exit 1
  fi
  echo "gold-diff-check: $bad of $_pub published figure(s) do not match the producer ($absent no longer emitted),"
  echo "  and the population is UNCHANGED at ${_pop_live:-?} page(s) — so these are real disagreements, not drift."
  echo "  A figure the producer cannot reproduce is not a figure. Re-derive section 2, or fix the producer."
  exit 1
fi
# A CHECK MUST NOT CHOOSE ITS OWN DENOMINATOR. This reported "all 26" while 7 more sat unread and
# never said so. Now the number CHECKED is asserted equal to the number PUBLISHED.
if [ "$checked" -ne "$_pub" ]; then
  echo "gold-diff-check: ERR — $_pub figure(s) are published but only $checked were compared."
  echo "  $(( _pub - checked )) went unread, so a clean result here would mean nothing. Widen the key pattern."
  exit 3
fi
echo "gold-diff-check: all $checked of $_pub published figure(s) reproduce EXACTLY from $PRODUCER."
exit 0
