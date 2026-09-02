#!/usr/bin/env bash
# suite-member: mechanical-suite — this line is how the suite proves its child list still NAMES this
# check. Removing the check from CHILDREN while this line stands makes the suite ERR. Delete both
# together and that is a deliberate removal, not an accident nobody noticed.
# incremental-check — value must not pile up unshipped. (v0.33, INV-INCREMENTAL)
#
# v0.32 ran roughly fifty commits on one branch before shipping. A single bad merge would have cost
# all of it. The cap is five unpushed commits, and this is what reads it.
#
# BOUNDARY CASES ARE FIXTURES, not confidence (P1-04): zero, exactly five, exactly six, and an
# upstream that cannot be read. The off-by-one is the whole point of a limit check — a limit that is
# off by one is a limit that is wrong.
#
# Usage: incremental-check.sh <repo-root> [--cap N] [--count N]
#        exit 0 within the cap · 1 over it · 2 usage.
set -uo pipefail
R="${1:-.}"; shift 2>/dev/null || true
CAP=5; FORCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --cap) [ $# -ge 2 ] || { echo "incremental-check: --cap needs a value" >&2; exit 2; }
           CAP="${2:-5}"; shift 2 ;;
    --count) [ $# -ge 2 ] || { echo "incremental-check: --count needs a value" >&2; exit 2; }
             FORCE="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cd "$R" 2>/dev/null || { echo "incremental-check: cannot enter '$R'"; exit 2; }
case "${CAP:-}" in ''|*[!0-9]*) echo "incremental-check: cap must be a non-negative integer."; exit 2 ;; esac

if [ -n "$FORCE" ]; then
  case "$FORCE" in ''|*[!0-9]*) echo "incremental-check: --count must be a non-negative integer."; exit 2 ;; esac
  n="$FORCE"; src="given (--count, for the boundary fixtures)"
else
  command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1 || {
    echo "incremental-check: N/A — not a git work tree, so there is no upstream to compare against."
    echo "  Stated, not passed silently: this is not a claim that nothing is unshipped."
    exit 0; }
  br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [ -z "$up" ]; then
    echo "incremental-check: N/A — branch '$br' has no upstream, so nothing has been pushed to compare against."
    echo "  Stated, not passed silently. Push it once and this check starts measuring."
    exit 0
  fi
  n="$(git rev-list --count "$up..HEAD" 2>/dev/null || echo "")"
  case "${n:-}" in ''|*[!0-9]*) echo "incremental-check: ERR — could not read the commit count against $up. Refusing to report a verdict."; exit 1 ;; esac
  src="$up..HEAD on '$br'"
fi

printf 'incremental-check: %s unshipped commit(s) against a cap of %s [%s].\n' "$n" "$CAP" "$src"
if [ "$n" -le "$CAP" ]; then
  printf '  Within the cap. Value is not accumulating where one bad merge would cost it.\n'; exit 0
fi
printf '  OVER by %s. Push before doing more — v0.32 ran ~50 commits on one branch before shipping.\n' "$((n-CAP))"
exit 1
