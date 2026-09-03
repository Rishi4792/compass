#!/usr/bin/env bash
# mechanical-suite — every cheap check, in one command, before any reviewer is spawned. (v0.33)
#
# THE POINT OF THIS FILE. v0.32 ran six independent adversarial reviews and they found 59 recorded
# defects. Just over half — 32 — needed no judgment at all: a count, a duplicate, a shape, a check
# nobody called. Paying a reasoning model to find the fourth copy of a constant is the waste this
# suite exists to end. It runs first, for no tokens, and hands its findings to the reviewers so
# they spend their attention where a script cannot go.
#
# WHAT IT PROMISES, AND WHAT IT DOES NOT. Each child states whether a finding MEASURES (it fails the
# run) or REPORTS (it prints and never fails). That distinction is not decoration: building these
# checks showed that only 1 of the 5 shell-trap classes is soundly mechanical by a line scan, and
# three separate rules for one of them each failed on correct code. A check that fires on correct
# work gets disabled within a week, so anything that cannot decide soundly reports instead.
#
# VACUITY GUARD. Every child prints its own denominator, and this runner ERRs — never passes — if a
# child reports nothing at all. A green over an empty set is not a signal; that is the defect that
# let a whole release report "target met" on a clean clone with zero pages measured.
#
# Usage: mechanical-suite.sh <repo-root> [--quiet]   Exit 0 all clean · 1 a MEASURED check failed
#        · 2 usage · 3 a child was missing or measured nothing.
set -uo pipefail
R="${1:-.}"; QUIET="${2:-}"
cd "$R" 2>/dev/null || { echo "mechanical-suite: cannot enter '$R'"; exit 2; }
[ -d plugins/compass ] || { echo "mechanical-suite: not a compass repo root: $R"; exit 2; }
D=plugins/compass/scripts
_strict() {
  case "${COMPASS_V32_STRICT:-1}" in 0|off|OFF|false|FALSE|no|NO) printf '0' ;; *) printf '1' ;; esac
}
_current_build() {
  local c; c="$(cat .claude/builds/CURRENT 2>/dev/null | head -1)"
  [ -n "$c" ] && [ -d ".claude/builds/$c" ] && printf '.claude/builds/%s' "$c"
}

# ── v0.34 S12 — THE ERR CHANNEL QUESTION, ANSWERED BY SEPARATING TWO KINDS OF ERR ─────────────
# This suite has no ERR channel: any non-zero child exits the whole suite 1, and the suite gates
# Step 0a of all three review skills. A reviewer flagged that an honest "empty population" ERR would
# therefore become a permanent red on every review in the repo.
#
# The answer is not a new channel. It is that those are two different things:
#   - a (page, metric) pair with NOTHING TO INSPECT is ordinary and common — 69 of 92 real pages
#     render no truncation control at all. readable-pages-check names each one on its own line and
#     returns 0, because a page with nothing to measure is not a failure.
#   - a corpus that will not RENDER, or is missing, means no verdict exists over that population.
#     That returns 3 and the suite is right to fail on it.
# So the check distinguishes them itself and the suite needs no change. Written down here rather
# than left to whoever runs it, because the plan required that choice be recorded.
CHILDREN="dup-fact-check vacuous-assert-check unwired-gate-check shell-trap-check doctrine-wired-check self-arm-check cap-enforce-check outside-in-reachable incremental-check readable-pages-check gold-diff-check argshift-check copy-reaches-check leak-scan-check"

# THE CHILD LIST MUST NAME EVERY CHECK THAT CLAIMS MEMBERSHIP. INV-CHECKWIRED asserts the list NAMES
# a check "not merely present on disk", and the only assertion that existed was a file-exists test —
# so deleting `readable-pages-check` from the line above left the suite printing "11 of 11 checks
# clean" and the whole smoke suite passing 1031/0. Two independent reviewers found it, one of them by
# accident while testing something else. Each child now carries a `suite-member: mechanical-suite`
# line, and the two sets are compared here. Removing a check from CHILDREN and leaving its
# declaration standing is now an ERR; removing both together is a deliberate removal.
_sm_declared="$(LC_ALL=C grep -lE '^(#|//) suite-member: mechanical-suite' "$(dirname "${BASH_SOURCE[0]}")"/* 2>/dev/null \
  | while read -r _f; do basename "$_f" | sed -E 's/\.(sh|mjs)$//'; done | sort -u)"
_sm_listed="$(printf '%s\n' $CHILDREN | sort -u)"
_sm_missing="$(comm -23 <(printf '%s\n' "$_sm_declared") <(printf '%s\n' "$_sm_listed") | grep -c . || true)"
if [ "${_sm_missing:-0}" -gt 0 ]; then
  echo "mechanical-suite: ERR — ${_sm_missing} check(s) declare membership of this suite but are NOT named in CHILDREN:"
  comm -23 <(printf '%s\n' "$_sm_declared") <(printf '%s\n' "$_sm_listed") | sed 's/^/    /'
  echo "  A check the suite does not name is a check the suite does not run. Add it, or delete its"
  echo "  'suite-member' line to record the removal as deliberate."
  exit 1
fi
ran=0; failed=0; missing=""; names_failed=""

printf '── mechanical suite ─────────────────────────────────────────────────\n'
for c in $CHILDREN; do
  f="$D/$c.sh"; [ -f "$f" ] || f="$D/$c.mjs"
  if [ ! -f "$f" ]; then missing="$missing $c"; continue; fi
  # cap-enforce-check needs a build dir as well as the root; the rest take the root alone. Passing
  # the CURRENT build keeps the suite a single command rather than a thing you have to remember
  # arguments for — a check you have to look up how to run is a check that stops being run.
  case "$c" in
    cap-enforce-check)     out="$(bash "$f" . "$(_current_build)" 2>&1)"; rc=$? ;;
    outside-in-reachable)  out="$(node "$f" --corpus "$D/fixtures/corpus" 2>&1)"; rc=$? ;;
    *)                     out="$(bash "$f" . 2>&1)"; rc=$? ;;
  esac
  ran=$((ran+1))
  summary="$(printf '%s' "$out" | LC_ALL=C grep -E "^$c:" | tail -1)"
  if [ -z "$summary" ]; then
    printf '  ERR   %-22s ran but printed no denominator. A check that cannot say what it measured\n' "$c"
    printf '        is not a check. Treating as a failure rather than a pass.\n'
    failed=$((failed+1)); names_failed="$names_failed $c"; continue
  fi
  if [ "$rc" -eq 0 ]; then printf '  ok    %s\n' "$summary"
  else printf '  FAIL  %s\n' "$summary"; failed=$((failed+1)); names_failed="$names_failed $c"; fi
  # ── v0.33 S18 — the kill switch's REPORTING half, which v0.32 documented and never built ──────
  # COMPASS_V32_STRICT=0 silences REPORTING output — the advisory lines a check prints about things
  # it cannot decide. It NEVER touches a MEASUREMENT: every child still runs, every verdict still
  # counts, and a failing check still fails. The flag can make the suite quieter; it cannot make it
  # blinder.
  #
  # outside-in-reachable.mjs and reachable-argument.mjs both deliberately refuse to read this
  # variable at all, and that stays true — a measurement that a flag can move is not a measurement.
  if [ "$(_strict)" = "0" ]; then
    [ "$QUIET" = "--quiet" ] || printf '    (reporting silenced by COMPASS_V32_STRICT=0 — measurements are unaffected)\n'
  else
    [ "$QUIET" = "--quiet" ] || printf '%s\n' "$out" | LC_ALL=C grep -E '^  (DUP|VACUOUS|UNWIRED|KNOWN-OPEN|PROBE|T[0-9])' | sed 's/^/    /'
  fi
done

printf '─────────────────────────────────────────────────────────────────────\n'
if [ -n "$missing" ]; then
  printf 'mechanical-suite: MISSING child check(s):%s\n' "$missing"
  printf '  A suite that silently skips a check reports a green it did not earn. Missing is an ERR,\n'
  printf '  never a pass — the same rule every child applies to its own empty set.\n'
  exit 3
fi
if [ "$ran" -eq 0 ]; then
  printf 'mechanical-suite: ERR — 0 checks ran. A green over an empty set is not a signal.\n'; exit 3
fi
printf 'mechanical-suite: %s of %s checks clean.\n' "$((ran-failed))" "$ran"
# ── v0.33.3 — BOTH VERDICTS FROM ONE PASS ────────────────────────────────────────────────────────
# The release suite used to run this whole file TWICE — once normally and once with
# COMPASS_V32_STRICT=0 — purely to prove the flag cannot move a verdict. That comparison cost ~6s of
# a 15s wall-clock allowance, and the allowance was spent to the second.
#
# The claim never needed two runs. Silencing REPORTING is a property of how output is PRINTED, not
# of what the children measured, so the flag-silenced verdict is derivable from the same pass. It is
# emitted here, and the suite asserts the two agree. Same claim, one execution.
printf 'mechanical-suite[strict=0]: %s of %s checks clean.\n' "$((ran-failed))" "$ran"
if [ "$failed" -gt 0 ]; then
  printf '  FAILED:%s\n' "$names_failed"
  printf '  These are MEASURED findings — a defect of a class a script decides, so no reviewer should\n'
  printf '  ever see one of them. Fix them before spawning anybody.\n'
  exit 1
fi
printf '  Reviewers may now be spawned. Anything they find is, by construction, something no script\n'
printf '  here could decide — which is where their attention is worth paying for.\n'
exit 0
