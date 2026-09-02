#!/usr/bin/env bash
# argshift-check — a flag that takes a value must REFUSE to be given none, not spin forever.
#
#   usage: argshift-check.sh [repo-root]
#
# THE DEFECT, found live in v0.34. `shift 2` when only one argument remains CANNOT shift: it returns
# non-zero and leaves `$#` alone. Inside the usual `while [ $# -gt 0 ]` argument loop that means the
# loop never advances, and the script HANGS FOREVER. `readable-pages-check.sh --metric cuts --corpus`
# did exactly that, and so did `perf-cap-check.sh --runs`. A plan step's VERIFY line was one of these
# commands, which is how a ticked box came to hold a command that could never return.
#
# It is a CLASS, not an instance: at the moment it was found, 24 sites across 8 scripts used `shift 2`
# and only 3 guarded it. This check owns the class so the next one is caught by a script rather than
# by someone waiting at a prompt that never comes back.
#
# MEASURE, not report. A case arm that runs `shift 2` must contain `$# -ge 2` (or `$# -lt 2`). This is
# decidable by reading the arm, with no judgement, which is what makes it safe to fail a build on.
#
# exit 0  every value-taking flag guards its shift
# exit 1  at least one does not — file and flag named
# exit 2  usage / not a compass repo
set -uo pipefail

ROOT="${1:-.}"
case "$ROOT" in --help|-h) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
cd "$ROOT" 2>/dev/null || { echo "argshift-check: cannot enter '$ROOT'" >&2; exit 2; }
[ -d plugins/compass ] || { echo "argshift-check: not a compass repo root" >&2; exit 2; }

bad=0; checked=0
for f in plugins/compass/scripts/*.sh; do
  [ -f "$f" ] || continue
  # Walk each `--flag)` case arm to its `;;` and ask whether an arm that shifts two also guards two.
  # A case arm may be ONE line ("--x) die ... ;;") or many. The first draft of this awk skipped the
  # terminator check on the opening line, so a one-line arm never closed and swallowed the NEXT arm —
  # it then reported the wrong flag. It found a real defect anyway, under the wrong name. Flags may
  # also be alternations ("--wall|--sessions|--stages)"), which a `--[a-z-]+\)` pattern misses.
  out="$(LC_ALL=C awk -v file="$f" '
    function close_arm(   b) {
      if (buf ~ /shift 2/ && buf !~ /\$# -ge 2/ && buf !~ /\$# -lt 2/)
        printf "%s\t%s\n", file, flag
      inarm=0; buf=""
    }
    /^[[:space:]]*--[a-z0-9|-]+\)/ {
      if (inarm) close_arm()
      inarm=1; flag=$1; buf=$0
      if ($0 ~ /;;[[:space:]]*$/) close_arm()
      next
    }
    inarm { buf = buf "\n" $0; if ($0 ~ /;;[[:space:]]*$/) close_arm() }
    END { if (inarm) close_arm() }
  ' "$f")"
  n="$(printf '%s' "$out" | grep -c . || true)"
  checked=$((checked+1))
  if [ "${n:-0}" -gt 0 ]; then
    printf '%s\n' "$out" | while IFS=$'\t' read -r ff fl; do
      [ -n "${ff:-}" ] && printf '  UNGUARDED  %-42s %s\n' "$ff" "$fl"
    done
    bad=$((bad+n))
  fi
done

if [ "$checked" -eq 0 ]; then
  echo "argshift-check: ERR — no shell scripts found to check. An empty population is not a pass."
  exit 1
fi
if [ "$bad" -gt 0 ]; then
  echo "argshift-check: $bad value-taking flag(s) run 'shift 2' without proving two arguments exist."
  echo "  With one argument left, 'shift 2' cannot shift and the argument loop spins forever."
  echo "  Guard the arm: [ \$# -ge 2 ] || { echo '<script>: <flag> needs a value' >&2; exit 2; }"
  exit 1
fi
echo "argshift-check: every value-taking flag across $checked script(s) guards its shift."
exit 0
