#!/usr/bin/env bash
# suite-member: mechanical-suite — this line is how the suite proves its child list still NAMES this
# check. Removing the check from CHILDREN while this line stands makes the suite ERR. Delete both
# together and that is a deliberate removal, not an accident nobody noticed.
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

total=0; unwired=0; allowed=0; known=0
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
  if is_allowed "$sub"; then
    # A THIRD STATE, because two were not enough to be honest. "Wired" and "human-typed" leave no
    # way to say "this should run automatically, nothing does, and fixing it is not in scope yet".
    # Without it the only options are to fail the build or to call a monitor a CLI tool — and the
    # second is how a known gap becomes an unknown one.
    if LC_ALL=C grep -qE "^[[:space:]]*$sub[[:space:]]+#[[:space:]]*KNOWN-OPEN:" "$ALLOW" 2>/dev/null; then
      known=$((known+1))
      printf '  KNOWN-OPEN  %-20s declared unwired on purpose, and still unwired.\n' "$sub"
    else
      allowed=$((allowed+1))
    fi
    continue
  fi
  printf '  UNWIRED  %-22s no caller in compass.sh, no skill, no command, no hook.\n' "$sub"
  printf '           Wire it, or declare it human-typed in %s with a reason.\n' "$ALLOW"
  unwired=$((unwired+1))
done <<EOF
$(LC_ALL=C grep -oE '^cmd_[a-z0-9_]+\(\)' "$SH" | sed 's/()$//' | LC_ALL=C sort -u)
EOF

# ── v0.33 S11b — CHECKS THAT GO QUIET BECAUSE A DIRECTORY IS MISSING ─────────────────────────
# The sweep above finds a command nobody CALLS. This finds a command that is called and then
# silently declines to do its work, because it probes for something outside the plugin that is not
# there. From the outside the two are indistinguishable and both mean "this never runs".
#
# It was Review-2 that forced this half into existence (P2-02). The stage-end gate's plain-words
# check probes for a `feynman-walkthrough` DIRECTORY that Compass does not ship, so that half has
# never run on any installation — and the sweep as first written would have walked straight past
# it, because the command itself is called perfectly well.
#
# REPORTED, NEVER FAILED. Whether a probe is a legitimate optional enhancement or a rule that
# quietly retired is a judgment about intent, and a line scan cannot make it. What the check
# guarantees is that every one is VISIBLE on every run, with the file and line, so it cannot
# become invisible the way this one did for three releases.
probes=0
while IFS=: read -r pf pln _; do
  [ -n "$pln" ] || continue
  probes=$((probes+1))
  printf '  PROBE       %s:%s\n' "$(basename "$pf")" "$pln"
  printf '              a check declines its work when a directory outside the plugin is absent.\n'
done <<EOF_P
$(LC_ALL=C grep -nE '\[ ! -d "\$[a-z_]+" \]' plugins/compass/scripts/compass.sh 2>/dev/null | sed "s|^|plugins/compass/scripts/compass.sh:|")
EOF_P

echo
if [ "$total" -eq 0 ]; then
  echo "unwired-gate-check: ERR — 0 dispatchable commands found. A green over an empty set is not a signal."
  exit 1
fi
printf 'unwired-gate-check: %s unwired of %s dispatchable commands (%s human-typed, %s KNOWN-OPEN) · %s directory-probe(s) that can silently decline.\n' \
  "$unwired" "$total" "$allowed" "$known" "$probes"
[ "$known" -eq 0 ] || printf '  A KNOWN-OPEN entry is a gap this repo has decided not to close YET. It is printed every\n  run so it cannot quietly become permanent.\n'
[ "$unwired" -eq 0 ] || exit 1
exit 0
