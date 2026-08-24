#!/usr/bin/env bash
# unwired-gate-check — a gate nobody calls is not a gate. (v0.33, INV-NO-UNWIRED-GATE)
#
# The rule, from the contract: a command is UNWIRED when its only references are its own definition,
# its dispatch arm, and the test suites. Computed by call graph, never by grepping for the name —
# grepping for a name finds the definition and calls it a caller.
#
# A human-typed utility legitimately has no automatic caller. That is declared in unwired-allow.txt
# rather than inferred, because from the outside a forensic tool and a dead gate look identical —
# which is exactly how six gates in this plugin came to exist and never fire.
#
# Usage: unwired-gate-check.sh <repo-root>   Exit 0 clean · 1 unwired found · 2 usage.
set -uo pipefail
R="${1:-.}"
cd "$R" 2>/dev/null || { echo "unwired-gate-check: cannot enter '$R'"; exit 2; }
SH=plugins/compass/scripts/compass.sh
[ -f "$SH" ] || { echo "unwired-gate-check: not a compass repo root: $R"; exit 2; }
ALLOW=plugins/compass/scripts/unwired-allow.txt
CALLERS="plugins/compass/skills plugins/compass/commands plugins/compass/hooks"

is_allowed() { LC_ALL=C grep -qE "^[[:space:]]*$1([[:space:]]|#|$)" "$ALLOW" 2>/dev/null; }

total=0; unwired=0; allowed=0
while IFS= read -r fn; do
  [ -n "$fn" ] || continue
  sub=$(printf '%s' "$fn" | sed -e 's/^cmd_//' -e 's/_/-/g')
  # Not a real subcommand if no dispatch arm names it — skip helpers that merely look like commands.
  LC_ALL=C grep -qE "^[[:space:]]*[a-z0-9|_-]*\b${sub}\b[a-z0-9|_-]*\)[[:space:]]+${fn}\b" "$SH" || continue
  total=$((total+1))
  # (a) called by another FUNCTION inside compass.sh — i.e. any use that is not the definition and
  #     not a dispatch arm.
  internal=$(LC_ALL=C grep -nE "(^|[^a-z_])${fn}\b" "$SH" \
             | grep -vE ":${fn}\(\)" \
             | grep -vcE "^[0-9]+:[[:space:]]*[a-z0-9|_-]*\)[[:space:]]+${fn}\b" || true)
  # (b) invoked by a skill, command or hook, by subcommand name
  external=$(git grep -l -- "compass.sh $sub" -- $CALLERS 2>/dev/null | wc -l | tr -d ' ')
  if [ "${internal:-0}" -gt 0 ] || [ "${external:-0}" -gt 0 ]; then continue; fi
  if is_allowed "$sub"; then allowed=$((allowed+1)); continue; fi
  printf '  UNWIRED  %-22s no caller in compass.sh, no skill, no command, no hook.\n' "$sub"
  printf '           Wire it, or declare it human-typed in %s with a reason.\n' "$ALLOW"
  unwired=$((unwired+1))
done <<EOF
$(LC_ALL=C grep -oE '^cmd_[a-z0-9_]+\(\)' "$SH" | sed 's/()$//' | LC_ALL=C sort -u)
EOF

echo
if [ "$total" -eq 0 ]; then
  echo "unwired-gate-check: ERR — 0 dispatchable commands found. A green over an empty set is not a signal."
  exit 1
fi
printf 'unwired-gate-check: %s unwired of %s dispatchable commands (%s declared human-typed).\n' \
  "$unwired" "$total" "$allowed"
[ "$unwired" -eq 0 ] || exit 1
exit 0
