#!/usr/bin/env bash
# suite-member: mechanical-suite — this line is how the suite proves its child list still NAMES this
# check. Removing the check from CHILDREN while this line stands makes the suite ERR. Delete both
# together and that is a deliberate removal, not an accident nobody noticed.
# dup-fact-check — one fact, one source. (v0.33, INV-NO-DUPLICATED-FACT)
#
# WHAT COUNTS AS A DUPLICATED FACT is enumerated by the contract, not decided here: a version
# string, a gate name, a review stream id, a pinned numeric floor, and a hardcoded path root in a
# script that already has a root variable. The contract's first wording was "a literal appearing
# more than once where one source would do"; the review removed that clause because no scan can
# evaluate "would do" -- it is the judgment this build exists to stop paying for.
#
# Usage: dup-fact-check.sh <repo-root>   Exit 0 clean - 1 duplicates found - 2 usage.
set -uo pipefail
R="${1:-.}"
cd "$R" 2>/dev/null || { echo "dup-fact-check: cannot enter '$R'"; exit 2; }
[ -d plugins/compass ] || { echo "dup-fact-check: not a compass repo root: $R"; exit 2; }
ALLOW="plugins/compass/scripts/dup-allow.txt"
bad=0; checked=0

allowed() { # <class> <value> <file>
  [ -f "$ALLOW" ] || return 1
  local c="$1" v="$2" f="$3" line rest glob
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    line="${line%%#*}"; line="${line%"${line##*[![:space:]]}"}"
    [ "${line%%:*}" = "$c" ] || continue
    rest="${line#*:}"; [ "${rest%%:*}" = "$v" ] || continue
    glob="${rest#*:}"
    # shellcheck disable=SC2254
    case "$f" in $glob) return 0 ;; esac
  done < "$ALLOW"
  return 1
}
report() { # <class> <value> <what> <files...>
  printf '  DUP  [%s] %s — %s\n' "$1" "$2" "$3"; shift 3
  for f in "$@"; do printf '         %s\n' "$f"; done
  bad=$((bad+1))
}

# ── class: version — the manifests and the changelog must agree on ONE number ────────────────
checked=$((checked+1))
vers=""
for m in .claude-plugin/marketplace.json plugins/compass/.claude-plugin/plugin.json; do
  [ -f "$m" ] || continue
  v=$(LC_ALL=C sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$m" | head -1)
  [ -n "$v" ] && vers="$vers$v
"
done
distinct=$(printf '%s' "$vers" | LC_ALL=C sort -u | grep -c . || true)
if [ "${distinct:-0}" -gt 1 ]; then
  report version "$(printf '%s' "$vers" | LC_ALL=C sort -u | tr '\n' ' ')" \
    "the manifests state more than one version — one fact, more than one source"
fi

# ── class: gate — every gate function gets EXACTLY ONE dispatch arm ──────────────────────────
checked=$((checked+1))
SH=plugins/compass/scripts/compass.sh
if [ -f "$SH" ]; then
  while IFS= read -r fn; do
    [ -n "$fn" ] || continue
    sub=$(printf '%s' "$fn" | sed -e 's/^cmd_//' -e 's/_/-/g')
    # count DISPATCH arms only: a line of the form `<sub>)` or `<sub>|...)` calling the function.
    n=$(LC_ALL=C grep -cE "^[[:space:]]*[a-z0-9|_-]*\b${sub}\b[a-z0-9|_-]*\)[[:space:]]+${fn}\b" "$SH" || true)
    [ "${n:-0}" -le 1 ] && continue
    allowed gate "$sub" "$SH" && continue
    report gate "$sub" "$n dispatch arms call the same gate — a second arm drifts silently" "$SH"
  done <<EOF
$(LC_ALL=C grep -oE '^cmd_[a-z0-9_]+_(gate|check)\(\)' "$SH" | sed 's/()$//' | LC_ALL=C sort -u)
EOF
fi

# ── class: stream — the declared list is the ONLY source of stream ids ───────────────────────
checked=$((checked+1))
for sk in review-contract review-plan review-build; do
  f="plugins/compass/skills/$sk/SKILL.md"
  [ -f "$f" ] || continue
  n=$(LC_ALL=C grep -c '^`streams: ' "$f" || true)
  [ "${n:-0}" -le 1 ] && continue
  allowed stream "$sk" "$f" && continue
  report stream "$sk" "$n declared stream lists in one skill — the gate reads the first and the rest rot" "$f"
done

# ── class: floor — each pinned numeric floor appears once in the tracked tree ─────────────────
# THIS CLASS WAS VACUOUS FOR ITS FIRST FIVE COMMITS. The pattern read SELFTEST_FLOOR / SMOKE_FLOOR;
# recon.sh actually declares FLOOR_SELFTEST and FLOOR_SMOKE. The words were reversed, so the loop
# iterated over nothing and the class reported clean by measuring an empty set — the exact defect
# vacuous-assert-check exists to catch, committed inside the duplicate-fact check. It was found by
# trying to prove its RED and discovering there was no literal to plant against.
checked=$((checked+1))
RECON=plugins/compass/scripts/compass.recon.sh
if [ -f "$RECON" ]; then
  while IFS= read -r fl; do
    [ -n "$fl" ] || continue
    hits=$(git ls-files -z -- 'plugins/compass/scripts/*.sh' 2>/dev/null | xargs -0 grep -l -F -- "$fl" 2>/dev/null | tr '\n' ' ')
    n=$(printf '%s' "$hits" | wc -w | tr -d ' ')
    [ "${n:-0}" -le 1 ] && continue
    allowed floor "$fl" "$RECON" && continue
    report floor "$fl" "a pinned floor stated in $n files — lifting it in one leaves the others lying" $hits
  done <<EOF
$(LC_ALL=C grep -oE '\bFLOOR_[A-Z]+=[0-9]+' "$RECON" 2>/dev/null | LC_ALL=C sort -u)
EOF
fi

# ── class: path — a script with a root variable should not also hardcode the root ─────────────
checked=$((checked+1))
while IFS= read -r f; do
  [ -f "$f" ] || continue
  LC_ALL=C grep -qE '^[[:space:]]*(PLUGIN_ROOT|PLUGIN)=' "$f" || continue
  n=$(LC_ALL=C grep -oE '"plugins/compass/[a-z]' "$f" 2>/dev/null | wc -l | tr -d ' ')
  [ "${n:-0}" -eq 0 ] && continue
  allowed path "plugins/compass" "$f" && continue
  report path "plugins/compass" "$n hardcoded root(s) in a file that already defines a root variable" "$f"
done <<EOF
$(git ls-files -- 'plugins/compass/scripts/*.sh' 2>/dev/null)
EOF

echo
# VACUITY GUARD: a run that checked no class is never a pass.
if [ "$checked" -eq 0 ]; then
  echo "dup-fact-check: ERR — 0 classes checked. A green over an empty set is not a signal."; exit 1
fi
if [ "$bad" -eq 0 ]; then
  echo "dup-fact-check: 0 duplicated facts across $checked enumerated classes over the tracked plugin tree."
  exit 0
fi
echo "dup-fact-check: $bad duplicated fact(s) across $checked classes. Each is one fact with more than one source."
exit 1
