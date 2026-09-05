#!/usr/bin/env bash
# suite-member: mechanical-suite — the suite's child list must NAME this check; removing it from
# CHILDREN while this line stands makes the suite ERR.
#
# armed-check — Autonomous is armed THROUGH auto-init, never by writing the marker. (v0.35, item 7)
#
#   usage: armed-check.sh [repo-root]
#
# WHY THIS EXISTS. `compass.sh auto-init` refuses to arm a build that has no declared budget:
#
#     auto-init: --auto requires a declared budget — run 'compass.sh budget-init <dir>' first
#
# That refusal is the only thing standing between "the user chose Autonomous" and "an unbounded
# loop". It is also trivially bypassed, because arming is just a marker file: write `.auto-mode` by
# hand and the budget guard never runs. Nothing detected that — and this build's own folder was in
# exactly that state while it was building the mechanism that depends on it. The contract said so:
#
#     "Writing the `.auto-mode` marker directly is forbidden: it bypasses the budget guard, and this
#      build's own folder is currently in that state because the author armed it by hand."
#
# A hand-armed build is not merely irregular. Every bound in this system reads `budget.env`, so a
# build without one has NO wall ceiling, NO session ceiling and NO refusal ceiling — and the v0.35
# Stop hook, which reads the budget before it refuses, stays silently inert on it. The user chose
# Autonomous and got nothing, with no error anywhere.
#
# WHAT IT GRADES, and what it only reports. The CURRENT build is graded: if its contract receipt
# records `answer=Autonomous`, it must carry both the marker and a budget with declared ceilings.
# Every OTHER build is REPORTED, never failed — a finished build is a record of what was true when
# it shipped, and re-grading history is how a check starts refusing things nobody can fix.
#
# exit 0  the current build is armed correctly (or is not Autonomous, or there is no current build)
# exit 1  the current build says Autonomous and is not armed through auto-init
# exit 2  usage / not a compass repo
set -uo pipefail
ROOT="${1:-.}"
case "$ROOT" in --help|-h) sed -n '5,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
cd "$ROOT" 2>/dev/null || { echo "armed-check: cannot enter '$ROOT'" >&2; exit 2; }
[ -d plugins/compass ] || { echo "armed-check: not a compass repo root" >&2; exit 2; }
SR=".claude/builds"
[ -d "$SR" ] || { echo "armed-check: N/A — no build state on this tree, so there is no arming to check. Stated, not skipped."; exit 0; }

# The CURRENT build: the newest non-terminal row in the INDEX, the same identity rule `status` uses.
cur=""
if [ -f "$SR/INDEX" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|\#*) continue ;; esac
    # `[^ ·\t]` DOES NOT MEAN "not a tab". Inside a bracket expression sed reads it as the two
    # characters backslash and t — so the class excluded the LETTER t, and every slug was truncated
    # at its first one: `always-clarity-v0-28` became `always-clari`. 28 of this repository's 34
    # build slugs contain a t; this check passed only because the one it grades does not. Found by
    # an independent reviewer. `[:space:]` is the portable class that means what was intended.
    s="$(printf '%s' "$line" | sed -nE 's/^([^ ·[:space:]]+).*/\1/p')"; [ -n "$s" ] || continue
    [ -d "$SR/$s" ] || continue
    # THE LEADING TOKEN ONLY, never the whole status line. compass.sh reads it this way
    # (`status_line --token`) for a reason this check reproduced on its first run: the current
    # build's status reads "④ build — … **P1 CLOSED** …", and a substring match on "closed" declared
    # the live build terminal and reported "no build in flight". A status is what it STARTS with;
    # everything after the dash is prose about the build, not its state.
    st="$(sed -nE 's/^[[:space:]]*\*\*Status:\*\*[[:space:]]*(.*)$/\1/p' "$SR/$s/progress.md" 2>/dev/null | tail -1 \
         | sed -E 's/^[*_`[:space:]]+//' | sed -E 's/^([A-Za-z()0-9 -]*).*/\1/' | tr 'A-Z' 'a-z')"
    case "$st" in shipped*|rolled-back*|closed*) continue ;; esac
    cur="$s"
  done < "$SR/INDEX"
fi

armed_ok() { # <dir> → 0 when armed through auto-init
  [ -f "$1/.auto-mode" ] || return 1
  [ -f "$1/budget.env" ] || return 1
  grep -qE '^ceiling_wall=[0-9]+' "$1/budget.env" 2>/dev/null || return 1
  return 0
}
says_auto() { grep -q 'answer=Autonomous' "$1/receipts.md" 2>/dev/null; }

# REPORT every hand-armed build. Named, never failed — history is a record, not a defect.
hand=""; n=0
for d in "$SR"/*/; do
  [ -d "$d" ] || continue
  s="$(basename "$d")"; n=$((n+1))
  if [ -f "$d/.auto-mode" ] && ! armed_ok "$d"; then hand="$hand $s"; fi
done

rc=0
if [ -z "$cur" ]; then
  echo "armed-check: N/A — no build in flight, so there is no current build to grade. Stated, not skipped."
elif ! says_auto "$SR/$cur"; then
  echo "armed-check: N/A — the current build ($cur) did not answer Autonomous, so there is nothing to arm."
elif armed_ok "$SR/$cur"; then
  echo "armed-check: $cur answered Autonomous and IS armed through auto-init (marker + declared budget)."
else
  echo "armed-check: $cur answered Autonomous and is NOT armed through auto-init."
  [ -f "$SR/$cur/.auto-mode" ] && echo "  the .auto-mode marker is present" || echo "  the .auto-mode marker is absent"
  [ -f "$SR/$cur/budget.env" ] && echo "  budget.env is present" || echo "  budget.env is ABSENT — so there is no wall ceiling, no session ceiling and no refusal ceiling"
  echo "  Every bound in Compass reads budget.env, and the Stop hook checks it before it refuses —"
  echo "  so this build chose Autonomous and gets nothing, silently. Arm it the way auto-init does:"
  echo "    compass.sh budget-init $SR/$cur --wall 3600 --sessions 6 --stages 40"
  echo "    compass.sh auto-init   $SR/$cur"
  rc=1
fi

if [ -n "$hand" ]; then
  printf '  KNOWN-OPEN  %s build(s) carry the marker without a budget:%s\n' "$(printf '%s' "$hand" | wc -w | tr -d ' ')" "$hand"
  printf '              Reported, not failed. A finished build records what was true when it shipped.\n'
fi
printf 'armed-check: %s of %s build folder(s) that carry the marker are armed through auto-init.\n' \
  "$(( $(ls -d "$SR"/*/.auto-mode 2>/dev/null | wc -l | tr -d ' ') - $(printf '%s' "$hand" | wc -w | tr -d ' ') ))" \
  "$(ls -d "$SR"/*/.auto-mode 2>/dev/null | wc -l | tr -d ' ')"
exit "$rc"
