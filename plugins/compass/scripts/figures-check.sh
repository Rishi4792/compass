#!/usr/bin/env bash
# figures-check — re-derive EVERY figure this contract publishes, from the tree.
#
# WHY: v1 of this contract stated `shared/` holds 1 file (it holds 5). v2's fix for that then
# stated 9 vacuous occurrences (there are 21) because the count came from a `head`-truncated grep.
# Two wrong figures in the contract about wrong figures. A person re-reading is how both got in;
# a script is how neither gets in again. This is the v0.33 mechanical suite in prototype.
#
# Usage: figures-check.sh <repo-root>   Exit 0 all figures match · 1 any mismatch · 2 usage.
set -uo pipefail
R="${1:-.}"; cd "$R" 2>/dev/null || { echo "usage: figures-check.sh <repo-root>"; exit 2; }
[ -d plugins/compass ] || { echo "figures-check: not a compass repo root: $R"; exit 2; }
LEDGER=".claude/builds/user-invariants-v0-32/review-ledger.md"
pass=0; fail=0
chk() { # <label> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  ok   %-46s %s\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL %-46s got=%s want=%s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

echo "figures-check — re-deriving every published figure from the tree"
echo

# ── doctrine denominators — DELEGATED, not re-counted ────────────────────────────────────────────
# These figures used to be computed here AND in doctrine-wired-check.sh. That is one fact with two
# sources, which is precisely what INV-NO-DUPLICATED-FACT forbids, and the two promptly drifted:
# this file still expected "5 doctrine files, 4 unwired" after the build had wired them and added
# two more. The owner is doctrine-wired-check; this file asks it rather than counting again.
dw="$(bash plugins/compass/scripts/doctrine-wired-check.sh . 2>/dev/null | grep '^doctrine-wired-check:' || true)"
chk "doctrine: unwired count (owned by doctrine-wired-check)" "$(printf '%s' "$dw" | sed -nE 's/.*: ([0-9]+) unwired of ([0-9]+).*/\1/p')" "0"
chk "doctrine: file count (owned by doctrine-wired-check)"    "$(printf '%s' "$dw" | sed -nE 's/.*: ([0-9]+) unwired of ([0-9]+).*/\2/p')" "7"

# ── dangling delegations — also delegated to its owner ──────────────────────────────────────────
chk "doctrine: dangling delegations (owned by doctrine-wired-check)" "$(printf '%s' "$dw" | sed -nE 's/.*· ([0-9]+) dangling.*/\1/p')" "0"

# ── tree shape (§2) ──────────────────────────────────────────────────────────────
chk "skill directories" "$(ls plugins/compass/skills | wc -l | tr -d ' ')" "12"
chk "skills carrying a FEYNMAN block" "$(git grep -l -F '<!-- FEYNMAN -->' -- plugins/compass/skills | wc -l | tr -d ' ')" "7"

# ── the gold's denominator (§9) ──────────────────────────────────────────────────
if [ -f "$LEDGER" ]; then
  ids=$(awk -F'|' '/^\|/ {gsub(/^ +| +$/,"",$2);
        if ($2!="" && $2!~/^:?-+:?$/ && $2!="Issue ID") print $2}' "$LEDGER" | sort -u | wc -l | tr -d ' ')
  # The first version of this line counted the HEADER row: its exclusion pattern was
  # `^ *(Issue|:?-+:?) *$`, which does not match the literal header cell "Issue ID", so the header
  # was counted as data and every published row figure was one too high. Exclude the cell by value.
  rows=$(awk -F'|' '/^\|/ {gsub(/^ +| +$/,"",$2); if($2!="" && $2!="Issue ID" && $2 !~ /^:?-+:?$/) n++} END{print n+0}' "$LEDGER")
  chk "v0.32 ledger distinct issue ids" "$ids" "59"
  chk "v0.32 ledger data rows" "$rows" "61"
  # `grep -c` PRINTS 0 and EXITS 1. The first version wrote `|| echo 0` after it, so the
  # substitution emitted "0\n0" and the comparison could never match. A gate that cannot pass is
  # as broken as one that cannot fail.
  chk "v0.32 ledger 'vacuous|vacuity' occurrences" "$(grep -ciE 'vacuit|vacuous' "$LEDGER")" "0"
else
  # §2's rule: .claude/builds is gitignored, so on a clean clone this set is ABSENT. Say so; never
  # report a silent pass over nothing.
  echo "  N/A  v0.32 ledger figures — $LEDGER absent (gitignored; expected on a clean clone)."
fi

# ── the vacuity record that does not exist (§8, INV-NO-VACUOUS-ASSERTION) ────────
# THE SET IS STATED, because §2 says every figure must state it — and the first version of this
# check broke that rule. `grep -r .` descends into `.claude/builds/`, which is GITIGNORED and
# therefore ABSENT on a clean clone: the same command gave 21 here and 69 there. The TRACKED TREE
# is the only set an installer can reproduce, so that is the set.
C="${CONTRACT:-.claude/builds/mechanical-checks-v0-33/contract.md}"

# ── the claim, not the incidental count ─────────────────────────────────────────────────────────
# This block used to pin the absolute number of times the word "vacuous" appears in the tracked
# tree (21, then 45, then 58). That number moves every time anyone writes a comment about vacuity —
# including the comments in the checks this build added — so it churned three times in one release
# and would have been disabled inside a week. A pinned count that changes for reasons unrelated to
# the thing it protects is not a check.
#
# What the figure was ever PROTECTING is a claim: that no enumerated record of "thirteen vacuities"
# exists anywhere, which is why INV-NO-VACUOUS-ASSERTION cannot cite one as its fixture set. That
# claim is stable, and it is what is checked now.
# REPORTED, NOT MEASURED — and the first version of this line got it wrong in the way this build
# keeps finding. "A file that CLAIMS an enumerated record of thirteen vacuities" is not a shape:
# a proximity match between "13" and "vacuous" hits any file that discusses the claim in order to
# refute it, which is exactly what the classification file and this build's own evidence do. That
# is a judgment about what a sentence asserts, so it prints and never fails.
vaclist=$(git ls-files -z 2>/dev/null | xargs -0 grep -liE "(thirteen|13)[^.]{0,40}(vacuit|vacuous)" 2>/dev/null | grep -c . || true)
printf '  note %s tracked file(s) mention a count near the word vacuous. REPORTED, not failed —\n' "${vaclist:-0}"
printf '       whether any of them ASSERTS such a record (rather than refuting the claim) is a\n'
printf '       judgment. The finding that no such record exists is recorded in red-first R-01.\n' 

# ── the perf ceiling: ONE fact that lived in five places and drifted in three ───────────────────
# Round 4 of Review-2 found the correction of a fabricated baseline landing in the contract header
# and NOT in the invariant it corrects, so the contract stated two different ceilings at once. That
# is INV-NO-DUPLICATED-FACT's own class, committed by this build, on the very figure the build was
# correcting. This check is what stops it recurring before that invariant's real check exists.
P="${PLAN:-.claude/builds/mechanical-checks-v0-33/plan.md}"
if [ -f "$C" ] && [ -f "$P" ]; then
  # every ceiling the two documents state, deduped — there must be exactly ONE distinct value
  # TARGETED, not a broad scan. The first version of this check matched any 40-69s figure near the
  # word "ceiling" and so fired on the measured BASELINE and on the sentence that quotes the old
  # ceiling in order to correct it — a check that fires on correct work gets disabled within a week,
  # which is this project's own stated rule. Compare the two AUTHORITATIVE statements instead.
  hdr_c=$(sed -n 's/.*p95 ceiling on the whole suite is \([0-9][0-9.]*\)s.*/\1/p' "$C" | head -1)
  inv_c=$(sed -n 's/.*run completes inside the \*\*\([0-9][0-9.]*\)s\*\* ceiling.*/\1/p' "$C" | head -1)
  chk "perf ceiling: contract header" "${hdr_c:-none}" "53"
  chk "perf ceiling: the invariant agrees" "${inv_c:-none}" "${hdr_c:-none}"
  # the superseded figure may survive ONLY inside the sentence that corrects it
  chk "stale 53.6s ceiling left in the plan" "$(grep -c '53\.6' "$P" 2>/dev/null)" "0"
  chk "stale 53.6s anywhere in the contract" "$(grep -c '53\.6' "$C" 2>/dev/null)" "0"
  chk "clean-clone baseline series present" "$(grep -c '38 / 37 / 38s' "$C" 2>/dev/null)" "1"
  chk "working-tree series present too (both sets stated)" "$(grep -c '48 / 50 / 48s' "$C" 2>/dev/null)" "1"
fi

echo
# VACUITY GUARD (§15): a run that checked nothing is never a pass.
total=$((pass+fail))
if [ "$total" -eq 0 ]; then
  echo "figures-check: ERR — 0 figures checked. A green over an empty set is not a signal."; exit 1
fi
echo "figures-check: $pass of $total figures reproduce from the tree, $fail mismatched."
[ "$fail" -eq 0 ] || exit 1
exit 0
