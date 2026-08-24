#!/usr/bin/env bash
# self-arm-check — nothing Compass ships may restart itself. (v0.33, INV-ENGINE-NO-SELF-ARM)
#
# The one privilege this plugin refuses to hand a stranger. A self-re-arming wakeup is safe for
# someone who opted into it, understands the fences and can close the window. Shipped to an
# installer it is a loop nobody agreed to, and the failure mode is not hypothetical: 1.16 billion
# tokens, one night, a loop re-scheduling itself to "wait for CI".
#
# shared/engine.md ships the HABITS — long turns, detached jobs, state on disk, the five fences —
# and deliberately not the mechanism. This check is what stops the mechanism drifting back in.
#
# It scans for the TOOL NAME and for the CONCEPT ("self-re-arming", "re-arm"), because a mechanism
# that drifts back in will not necessarily arrive under the same name. Guard-first: the shipped tree
# mentions the tool name ZERO times today, so a name-only rule would have been scanning for
# something that does not exist — a green over an empty set, which is the exact vacuity this
# build's own S3 check was written to catch.
#
# MEASURED, not reported: an instruction to schedule a repeating wakeup is a definite shape.
# DOCUMENTATION OF WHAT NOT TO DO IS NOT A CALL SITE, and the distinction is decidable: a line that
# tells you to arm one is an instruction; a line inside a sentence explaining why Compass does not
# is prose. The check requires an imperative form, and shared/engine.md — which discusses the
# mechanism at length in order to refuse it — must pass. If it ever fails, the check is wrong.
#
# Usage: self-arm-check.sh <repo-root>   Exit 0 clean · 1 a self-arm found · 2 usage.
set -uo pipefail
R="${1:-.}"
cd "$R" 2>/dev/null || { echo "self-arm-check: cannot enter '$R'"; exit 2; }
[ -d plugins/compass ] || { echo "self-arm-check: not a compass repo root: $R"; exit 2; }

found=0; scanned=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # A scanner must not scan its own patterns. This file necessarily contains every string it looks
  # for, so including it would make the check fail the instant it was committed — which is exactly
  # what happened in its red proof, before it was tracked. Excluded by name, and the exclusion is
  # narrow: this one file, not a directory or a glob that could hide a real call site later.
  case "$f" in */self-arm-check.sh) continue ;; esac
  scanned=$((scanned+1))
  while IFS=: read -r ln body; do
    [ -n "$ln" ] || continue
    # PROSE FILTER. A refusal, a warning or a past-tense account is not an instruction. Without
    # this the check would fail on the very file that exists to refuse the mechanism.
    case "$body" in
      *"does not ship"*|*"deliberately not"*|*"never"*|*"Never"*|*"NOT ship"*|*"refuse"*|*"was removed"*|*"burned"*|*"runaway"*) continue ;;
    esac
    # An INSTRUCTION: an imperative to arm/schedule/re-arm a wakeup.
    case "$body" in
      *[Aa]rm*ScheduleWakeup*|*ScheduleWakeup*re-arm*|*"call ScheduleWakeup"*|*"invoke ScheduleWakeup"*|*"ScheduleWakeup {"*|*"re-arm the loop"*|*"re-arm, then end"*)
        printf '  SELF-ARM  %s:%s\n' "$f" "$ln"
        printf '            %s\n' "$(printf '%s' "$body" | cut -c1-100)"
        printf '            Compass ships the engine DOCTRINE, never a loop that restarts itself.\n'
        found=$((found+1)) ;;
    esac
  done <<EOF2
$(LC_ALL=C grep -niE "ScheduleWakeup|self-re-arming|re-arm" "$f" 2>/dev/null || true)
EOF2
done <<EOF
$(git ls-files -- 'plugins/compass/**' 2>/dev/null)
EOF

echo
if [ "$scanned" -eq 0 ]; then
  echo "self-arm-check: ERR — 0 shipped files scanned. A green over an empty set is not a signal."; exit 1
fi
printf 'self-arm-check: %s self-arming call site(s) across %s shipped files.\n' "$found" "$scanned"
printf '  MEASURED. shared/engine.md discusses the mechanism at length in order to REFUSE it and\n'
printf '  must pass; if this check ever fails on that file, the check is wrong, not the file.\n'
[ "$found" -eq 0 ] || exit 1
exit 0
