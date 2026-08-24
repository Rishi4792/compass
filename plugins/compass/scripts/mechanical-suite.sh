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
_current_build() {
  local c; c="$(cat .claude/builds/CURRENT 2>/dev/null | head -1)"
  [ -n "$c" ] && [ -d ".claude/builds/$c" ] && printf '.claude/builds/%s' "$c"
}

CHILDREN="dup-fact-check vacuous-assert-check unwired-gate-check shell-trap-check doctrine-wired-check self-arm-check cap-enforce-check outside-in-reachable"
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
  [ "$QUIET" = "--quiet" ] || printf '%s\n' "$out" | LC_ALL=C grep -E '^  (DUP|VACUOUS|UNWIRED|KNOWN-OPEN|T[0-9])' | sed 's/^/    /'
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
if [ "$failed" -gt 0 ]; then
  printf '  FAILED:%s\n' "$names_failed"
  printf '  These are MEASURED findings — a defect of a class a script decides, so no reviewer should\n'
  printf '  ever see one of them. Fix them before spawning anybody.\n'
  exit 1
fi
printf '  Reviewers may now be spawned. Anything they find is, by construction, something no script\n'
printf '  here could decide — which is where their attention is worth paying for.\n'
exit 0
