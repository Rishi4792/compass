#!/usr/bin/env bash
# session-trailer-check — no NEW commit may carry a session link in its message.
#
# WHY. Commit messages in this repository ended with a link to the assistant session that wrote them.
# 150 commits carry one, across 8 distinct session ids, from 2026-07-21 to 2026-09-03, and 132 of
# those are on public `main`. They cannot be recalled: a published git history is published. What can
# be done is stop it, say so plainly, and make the stopping mechanical — because a policy that lives
# only in a person's memory is a policy that comes back the next time somebody is in a hurry.
#
# WHY IT IS DATED RATHER THAN ABSOLUTE. Failing on the whole history would fail for ever on commits
# nobody can change, and a check that can never pass is a check somebody deletes. So it draws a line
# at a date: every commit authored on or after the policy date must be clean, and the ones before it
# are COUNTED AND REPORTED so the number stays visible instead of quietly fading. Rewriting the older
# ones was considered and rejected — 132 are already public, so rewriting the remaining 18 would
# change every commit sha this release has pinned its measurements to and buy almost nothing.
#
# WHAT COUNTS AS A LINK. The host and path, in any form. It deliberately does NOT try to match the
# id itself: ids change shape, and a check keyed to one shape is a check that misses the next.
#
# Usage: session-trailer-check.sh [<git-range>] [--policy-date YYYY-MM-DD]
#        Default range: origin/main..HEAD when it resolves, else HEAD.
# Exit:  0 no post-policy commit carries one · 1 at least one does · 2 usage / not a git repo.
set -uo pipefail

POLICY="2026-09-05"
RANGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --policy-date) [ $# -ge 2 ] || { echo "session-trailer-check: --policy-date needs a value" >&2; exit 2; }
                   POLICY="$2"; shift 2 ;;
    --help|-h)     sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)            echo "session-trailer-check: unknown option '$1'" >&2; exit 2 ;;
    *)             RANGE="$1"; shift ;;
  esac
done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "session-trailer-check: not a git repo." >&2; exit 2; }
if [ -z "$RANGE" ]; then
  if git rev-parse --verify -q origin/main >/dev/null 2>&1; then RANGE="origin/main..HEAD"; else RANGE="HEAD"; fi
fi
git rev-list --quiet "$RANGE" -- >/dev/null 2>&1 || { echo "session-trailer-check: bad range '$RANGE'." >&2; exit 2; }

PAT='claude\.ai/code/session'
bad=0; old=0; total=0
while IFS='|' read -r sha adate; do
  [ -n "$sha" ] || continue
  total=$((total+1))
  git log -1 --format='%B' "$sha" 2>/dev/null | grep -qE "$PAT" || continue
  # String comparison is correct here: ISO dates sort lexically in date order.
  if [ "$adate" \< "$POLICY" ]; then
    old=$((old+1))
  else
    [ "$bad" -eq 0 ] && echo "session-trailer-check: FAIL — a session link in a commit message written on or after $POLICY:"
    printf '  %s  %s  %s\n' "$sha" "$adate" "$(git log -1 --format='%s' "$sha" | cut -c1-72)"
    bad=$((bad+1))
  fi
done <<EOF
$(git log --format='%H|%ad' --date=short "$RANGE" 2>/dev/null)
EOF

if [ "$bad" -gt 0 ]; then
  echo "  $bad commit(s). Drop the trailer and amend, or rebase the range, before this is published."
  echo "  The $old older one(s) in this range predate the policy and are disclosed, not silently kept."
  exit 1
fi
printf 'session-trailer-check: clean over %s commit(s) in %s' "$total" "$RANGE"
if [ "$old" -gt 0 ]; then
  printf ' — %s predate the %s policy and are DISCLOSED, not hidden (see SECURITY.md).\n' "$old" "$POLICY"
else
  printf '.\n'
fi
exit 0
