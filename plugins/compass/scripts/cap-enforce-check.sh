#!/usr/bin/env bash
# suite-member: mechanical-suite — this line is how the suite proves its child list still NAMES this
# check. Removing the check from CHILDREN while this line stands makes the suite ERR. Delete both
# together and that is a deliberate removal, not an accident nobody noticed.
# cap-enforce-check — a cap nobody checks is a wish. (v0.33, INV-CAP-ENFORCED)
#
# GUARD-FIRST, measured before the rule was written:
#   The post-ship loop's round cap IS enforced, at compass.sh:3119 — `[ "$round" -le "$cap" ] ||
#   _refuse cap`. The THREE REVIEW ROUND CAPS ARE NOT. review-contract says cap 2, review-plan cap
#   3, review-build cap 5, and those numbers live in prose in the skills with nothing reading them.
#
# THE OVERRIDE PATH, and why it is not a loophole. This build ran FOUR rounds of review-contract
# against a cap of two, and four of review-plan against three — both times because Rishi was asked
# and said to continue. A cap check without a recorded-override path would have refused the build
# that wrote it, and the only workaround would be disabling the check, which is how gates die.
#
# So: an excess with NO recorded decision is REFUSED. An excess WITH one — naming who, when, and
# which cap — is allowed and stays visible on every run afterwards. A cap bounds drift, not the
# person who owns the build.
#
#   - [x] cap-raise: <review> <old> -> <new> · by <who> · <date> · reason=<why>
#
# Usage: cap-enforce-check.sh <repo-root> [<build-dir>]  Exit 0 clean · 1 unrecorded excess · 2 usage.
set -uo pipefail
R="${1:-.}"; DIR="${2:-}"
cd "$R" 2>/dev/null || { echo "cap-enforce-check: cannot enter '$R'"; exit 2; }
[ -d plugins/compass ] || { echo "cap-enforce-check: not a compass repo root: $R"; exit 2; }
[ -n "$DIR" ] || DIR="$(cat .claude/builds/CURRENT 2>/dev/null | head -1 | sed 's|^|.claude/builds/|')"

caps=0; unenforced=0; excess=0; recorded=0; checked=0; readable=0

# ── 1. every declared behaviour cap, and whether anything enforces it ─────────────────────────
for sk in review-contract review-plan review-build; do
  f="plugins/compass/skills/$sk/SKILL.md"; [ -f "$f" ] || continue
  cap="$(LC_ALL=C grep -oiE 'cap \*?\*?[0-9]+' "$f" | head -1 | grep -oE '[0-9]+')"
  [ -n "$cap" ] || continue
  caps=$((caps+1))
  # ENFORCED BY THIS FILE. The first version of this loop printed "no script reads it" for all
  # three caps while itself being the script that reads them — a check reporting a gap it had just
  # closed. What is genuinely worth flagging is a cap this check CANNOT read, because that is the
  # one still living on the honour system.
  if [ -n "$cap" ]; then
    readable=$((readable+1))
  else
    unenforced=$((unenforced+1))
    printf '  UNREADABLE  %-16s declares a cap this check cannot parse, so nothing reads it.\n' "$sk"
  fi
done

# ── 2. for a real build, compare rounds run against the cap ───────────────────────────────────
if [ -n "$DIR" ] && [ -d "$DIR" ] && [ -f "$DIR/receipts.md" ]; then
  for sk in review-contract review-plan review-build; do
    f="plugins/compass/skills/$sk/SKILL.md"; [ -f "$f" ] || continue
    cap="$(LC_ALL=C grep -oiE 'cap \*?\*?[0-9]+' "$f" | head -1 | grep -oE '[0-9]+')"
    [ -n "$cap" ] || continue
    rounds="$(LC_ALL=C sed -nE "s/.*streams: *$sk +r([0-9]+) +->.*/\1/p" "$DIR/receipts.md" | LC_ALL=C sort -n | tail -1)"
    [ -n "$rounds" ] || continue
    checked=$((checked+1))
    [ "$rounds" -le "$cap" ] && continue
    excess=$((excess+1))
    if LC_ALL=C grep -qE "^- \[x\] cap-raise: *$sk " "$DIR/receipts.md"; then
      recorded=$((recorded+1))
      printf '  RAISED      %-16s %s rounds against cap %s — recorded:\n' "$sk" "$rounds" "$cap"
      printf '              %s\n' "$(LC_ALL=C grep -E "^- \[x\] cap-raise: *$sk " "$DIR/receipts.md" | head -1 | cut -c1-104)"
    else
      printf '  UNRECORDED  %-16s %s rounds against cap %s, and NO cap-raise line in receipts.md.\n' "$sk" "$rounds" "$cap"
      printf '              A cap bounds drift, not the person who owns the build — so exceeding it is\n'
      printf '              allowed, and exceeding it SILENTLY is not. Record who decided and when:\n'
      printf '              - [x] cap-raise: %s %s -> %s · by <who> · <date> · reason=<why>\n' "$sk" "$cap" "$rounds"
    fi
  done
fi

echo
if [ "$caps" -eq 0 ]; then
  echo "cap-enforce-check: ERR — 0 caps found. A green over an empty set is not a signal."; exit 1
fi
printf 'cap-enforce-check: %s behaviour cap(s) declared, %s readable and enforced by this check · %s unreadable · %s exceeded (%s recorded, %s NOT) over %s review(s) in %s.\n' \
  "$caps" "$readable" "$unenforced" "$excess" "$recorded" "$((excess-recorded))" "$checked" "${DIR:-<no build dir>}"
printf '  MEASURED: an excess with no recorded decision fails. REPORTED: which caps no script reads.\n'
[ "$((excess-recorded))" -eq 0 ] || exit 1
exit 0
