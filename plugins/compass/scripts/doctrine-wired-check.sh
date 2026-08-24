#!/usr/bin/env bash
# doctrine-wired-check — a standard nobody loads is not a standard. (v0.33, INV-DOCTRINE-WIRED)
#
# WHY IT EXISTS, measured on this repo at 735c14e before a line of it was written:
#   plugins/compass/shared/ holds 5 doctrine files. FOUR are referenced by no skill and no command.
#   feynman.md opens with "Loaded by the contract, plan and ship stages". ZERO stages load it. The
#   only mention of that filename anywhere in the plugin is a string inside an error message in
#   compass.sh. It has sat unread since v0.30 — three releases.
#   And skills/explain/SKILL.md instructs the model to invoke `skill: feynman-walkthrough`, a skill
#   this plugin does not ship, with no fallback. It works on its author's machine and nowhere else.
#
# TWO RULES, both MEASURED (they fail the run) because both are decidable from the tree:
#   1. Every file in shared/ has a MANIFEST line naming its consumer, and that consumer really
#      references it. An ERROR-MESSAGE STRING IS NEVER A CONSUMER — that is exactly how feynman.md
#      looked wired for three releases.
#   2. Every `skill: <name>` INVOCATION inside a code span names a skill this plugin ships, or
#      carries a stated fallback. Anchored on the code-span form, never the bare words: the naive
#      regex matches "the bundled `compass-visual` skill: generate `node ...`" and reports a
#      dangling delegation to a skill called `generate`.
#
# Usage: doctrine-wired-check.sh <repo-root>  Exit 0 clean · 1 unwired/dangling · 2 usage.
set -uo pipefail
R="${1:-.}"
cd "$R" 2>/dev/null || { echo "doctrine-wired-check: cannot enter '$R'"; exit 2; }
SHARED=plugins/compass/shared
[ -d "$SHARED" ] || { echo "doctrine-wired-check: not a compass repo root: $R"; exit 2; }
MANIFEST="$SHARED/MANIFEST"
CONSUMERS="plugins/compass/skills plugins/compass/commands"

files=0; unwired=0; dangling=0; skills_n=0; human=0

# ── rule 1 — every doctrine file is declared and really read ──────────────────────────────────
for f in "$SHARED"/*.md; do
  [ -f "$f" ] || continue
  b="$(basename "$f")"; files=$((files+1))
  line=""
  [ -f "$MANIFEST" ] && line="$(LC_ALL=C grep -E "^[[:space:]]*$b[[:space:]]*:" "$MANIFEST" 2>/dev/null | head -1)"
  if [ -z "$line" ]; then
    printf '  UNWIRED  %-20s no line in shared/MANIFEST. Declare its consumer:\n' "$b"
    printf '           "%s: <skill> [<skill>...]"  or  "%s: script-only <script>"\n' "$b" "$b"
    unwired=$((unwired+1)); continue
  fi
  decl="${line#*:}"
  case "$decl" in
    *human-reference*)
      # A THIRD declared state, and the file must CORROBORATE it. enforcement.md opens with
      # "Agents: do NOT read at runtime — human/maintainer overview only", so declaring it a stage
      # doctrine would have been false and wiring it would have contradicted the file. Two states
      # were not enough to be honest — the same shape as KNOWN-OPEN in the uncalled-gate check.
      #
      # The declaration alone is not trusted: the file itself must say so, in its own words. A
      # MANIFEST that could exempt any file by asserting it would be the honour system in a new
      # file, which is the defect this whole check exists to end.
      if LC_ALL=C grep -qiE 'do NOT read at runtime|human/maintainer|human reference' "$f"; then
        human=$((human+1)); continue
      fi
      printf '  UNWIRED  %-20s declared human-reference, but the file itself does not say so.\n' "$b"
      printf '           The declaration must be corroborated by the file, or any file could exempt itself.\n'
      unwired=$((unwired+1)); continue ;;
    *script-only*)
      sc="$(printf '%s' "$decl" | sed -E 's/.*script-only[[:space:]]+//' | awk '{print $1}')"
      if [ -n "$sc" ] && LC_ALL=C grep -q -F "$b" "plugins/compass/scripts/$sc" 2>/dev/null; then continue; fi
      printf '  UNWIRED  %-20s declared script-only "%s", but that script does not reference it.\n' "$b" "${sc:-<none named>}"
      unwired=$((unwired+1)); continue ;;
  esac
  bad=""
  for sk in $decl; do
    d="plugins/compass/skills/$sk"
    [ -d "$d" ] || { bad="$bad $sk(no-such-skill)"; continue; }
    # A real load line, NOT a mention inside an error string. Consumers are markdown; an error
    # string lives in a .sh, so scoping the search to the skill's own markdown is the whole guard.
    LC_ALL=C grep -q -F "$b" "$d"/*.md 2>/dev/null || bad="$bad $sk(does-not-reference-it)"
  done
  if [ -n "$bad" ]; then
    printf '  UNWIRED  %-20s MANIFEST names a consumer that does not read it:%s\n' "$b" "$bad"
    unwired=$((unwired+1))
  fi
done

# ── rule 2 — no delegation to a skill this plugin does not ship ───────────────────────────────
shipped="$(ls plugins/compass/skills 2>/dev/null | tr '\n' ' ')"
skills_n=$(printf '%s' "$shipped" | wc -w | tr -d ' ')
while IFS= read -r nm; do
  [ -n "$nm" ] || continue
  case " $shipped " in *" $nm "*) continue ;; esac
  where="$(git grep -l -F "\`skill: $nm\`" -- $CONSUMERS 2>/dev/null | tr '\n' ' ')"
  # A stated fallback makes it an enhancement rather than a dependency.
  if [ -n "$where" ] && git grep -h -A3 -F "\`skill: $nm\`" -- $CONSUMERS 2>/dev/null \
       | LC_ALL=C grep -qiE 'if (it is )?not (installed|available|present)|when absent|fall ?back|optional'; then
    continue
  fi
  printf '  DANGLING %-24s invoked in%s but this plugin does not ship it, and no fallback is stated.\n' "$nm" " ${where:-?}"
  dangling=$((dangling+1))
done <<EOF
$(git grep -hoE '\`skill: *[a-z][a-z0-9-]+\`' -- $CONSUMERS 2>/dev/null | sed -E 's/^`skill: *//; s/`$//' | LC_ALL=C sort -u)
EOF

echo
if [ "$files" -eq 0 ]; then
  echo "doctrine-wired-check: ERR — 0 doctrine files found. A green over an empty set is not a signal."; exit 1
fi
printf 'doctrine-wired-check: %s unwired of %s doctrine files (%s declared human-reference, corroborated by the file itself) · %s dangling delegation(s) across %s shipped skills.\n' \
  "$unwired" "$files" "$human" "$dangling" "$skills_n"
printf '  Both rules MEASURE — each is decidable from the tree, so each fails the run rather than\n'
printf '  reporting. A reference inside an error-message string is never counted as wired.\n'
[ "$unwired" -eq 0 ] && [ "$dangling" -eq 0 ] || exit 1
exit 0
