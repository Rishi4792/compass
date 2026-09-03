#!/usr/bin/env bash
# suite-member: mechanical-suite — the suite's child list must NAME this check; removing it from
# CHILDREN while this line stands makes the suite ERR.
#
# autofix-check — one repair, Autonomous only, recorded, and never to the contract. (v0.35, item 10)
#
#   usage: autofix-check.sh [repo-root]
#
# WHY THIS EXISTS. In Autonomous mode a failing gate should not simply stop the build — that is the
# stall this release is about. But an unattended repair loop is the opposite hazard, and the contract
# names it rather than dismissing it: "an unattended repair could rewrite the locked contract." So
# the repair is bounded, and the bound is what this check measures:
#
#   ONE attempt per sub-gate, per stage. A second failure stops and asks. Two `autofix:` lines for
#     the same sub-gate in the same stage block is a loop, however well each one is worded.
#   AUTONOMOUS ONLY. In Human-gated mode the answer to a failing gate is the person, not a retry.
#   RECORDED, in the stated shape: `autofix: <sub-gate> · <what changed> · <re-run result>`. A repair
#     nobody can read afterwards is indistinguishable from a build that quietly edited itself.
#   NEVER THE CONTRACT. Five of Compass's own sub-gates fail on contract.md, so without this rule an
#     unattended repair could rewrite the locked spec to make its own gate pass. The contract's sha
#     is recorded when it locks; this compares it against the file now.
#
# WHAT IT GRADES. The CURRENT build. Finished builds are reported, never failed — re-grading history
# is how a check starts refusing what nobody can fix. A build with no `autofix:` line at all passes
# and says so: the rule is a bound on a repair, not a demand for one.
#
# exit 0  no repair, or every repair inside the bound
# exit 1  a second attempt at the same sub-gate · a repair in Human-gated mode · a malformed record
#         · the contract changed since it locked
# exit 2  usage / not a compass repo
set -uo pipefail
ROOT="${1:-.}"
case "$ROOT" in --help|-h) sed -n '5,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
cd "$ROOT" 2>/dev/null || { echo "autofix-check: cannot enter '$ROOT'" >&2; exit 2; }
[ -d plugins/compass ] || { echo "autofix-check: not a compass repo root" >&2; exit 2; }
SR=".claude/builds"
[ -d "$SR" ] || { echo "autofix-check: N/A — no build state on this tree. Stated, not skipped."; exit 0; }

cur=""
if [ -f "$SR/INDEX" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|\#*) continue ;; esac
    s="$(printf '%s' "$line" | sed -nE 's/^([^ ·\t]+).*/\1/p')"; [ -n "$s" ] || continue
    [ -d "$SR/$s" ] || continue
    st="$(sed -nE 's/^[[:space:]]*\*\*Status:\*\*[[:space:]]*(.*)$/\1/p' "$SR/$s/progress.md" 2>/dev/null | tail -1 \
         | sed -E 's/^[*_`[:space:]]+//' | sed -E 's/^([A-Za-z()0-9 -]*).*/\1/' | tr 'A-Z' 'a-z')"
    case "$st" in shipped*|rolled-back*|closed*) continue ;; esac
    cur="$s"
  done < "$SR/INDEX"
fi

# REPORT every other build's repair count. Named, never failed.
other=0
for d in "$SR"/*/; do
  [ -d "$d" ] || continue
  s="$(basename "$d")"; [ "$s" = "$cur" ] && continue
  n="$(grep -cE '^[-* ]*\[?[xX ]?\]? *autofix:' "$d/receipts.md" 2>/dev/null || true)"
  other=$((other + ${n:-0}))
done

if [ -z "$cur" ]; then
  printf 'autofix-check: N/A — no build in flight to grade. %s repair(s) recorded across finished builds, reported not graded.\n' "$other"
  exit 0
fi
D="$SR/$cur"; REC="$D/receipts.md"
[ -f "$REC" ] || { printf 'autofix-check: N/A — %s has no receipts.md yet, so no repair can have been recorded.\n' "$cur"; exit 0; }

rc=0
lines="$(grep -nE '^[-* ]*\[?[xX ]?\]? *autofix:' "$REC" 2>/dev/null || true)"
n="$(printf '%s' "$lines" | grep -c . || true)"; n="${n:-0}"

if [ "$n" -gt 0 ]; then
  # AUTONOMOUS ONLY.
  if [ ! -f "$D/.auto-mode" ]; then
    echo "autofix-check: $cur records $n repair(s) but is NOT Autonomous. In Human-gated mode the answer to a failing gate is the person, not a retry."
    rc=1
  fi
  # THE SHAPE. Three fields, separated by ' · '.
  bad=0
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    body="${l#*autofix:}"
    f="$(printf '%s' "$body" | awk -F' · ' '{print NF}')"
    if [ "${f:-0}" -lt 3 ]; then
      echo "autofix-check: malformed record — $(printf '%s' "$l" | cut -c1-100)"
      echo "  expected: autofix: <sub-gate> · <what changed> · <re-run result>"
      bad=1
    fi
  done <<EOF_L
$lines
EOF_L
  [ "$bad" = 0 ] || rc=1
  # ONE PER SUB-GATE. The sub-gate is the first field.
  dup="$(printf '%s' "$lines" | sed -E 's/^[0-9]+://' | sed -E 's/^[-* ]*\[?[xX ]?\]? *autofix: *//' \
        | awk -F' · ' '{print $1}' | sed 's/[[:space:]]*$//' | sort | uniq -d || true)"
  if [ -n "$dup" ]; then
    printf 'autofix-check: %s repaired more than once:%s\n' "$cur" " $(printf '%s' "$dup" | tr '\n' ' ')"
    echo "  One attempt per sub-gate. A second failure stops and asks — two attempts is a loop, however well each is worded."
    rc=1
  fi
fi

# NEVER THE CONTRACT. The sha is recorded when the contract locks; compare it with the file now.
want="$(grep -oE 'contract-sha: *[0-9a-f]{8,}' "$REC" 2>/dev/null | tail -1 | sed -E 's/.*: *//' || true)"
if [ -n "$want" ] && [ -f "$D/contract.md" ]; then
  got="$(shasum -a 256 "$D/contract.md" | cut -c1-16)"
  if [ "$got" != "$want" ]; then
    echo "autofix-check: $cur's contract.md has CHANGED since it locked (recorded ${want}, now ${got})."
    echo "  A repair may never edit the contract — five of Compass's own sub-gates fail on contract.md,"
    echo "  so an unattended repair could rewrite the locked spec to make its own gate pass. If this was"
    echo "  a deliberate AMENDMENT, re-record the sha in the contract receipt alongside the signature."
    rc=1
  fi
fi

if [ "$rc" = 0 ]; then
  if [ "$n" = 0 ]; then
    printf 'autofix-check: %s records no repair. The rule bounds a repair; it does not demand one. %s recorded across finished builds, reported not graded.\n' "$cur" "$other"
  else
    printf 'autofix-check: %s — %s repair(s), each inside the bound (one per sub-gate, Autonomous, recorded, contract untouched).\n' "$cur" "$n"
  fi
fi
exit "$rc"
