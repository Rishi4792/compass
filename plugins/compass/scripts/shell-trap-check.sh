#!/usr/bin/env bash
# shell-trap-check — the five shell mistakes v0.32's reviewers found BY HAND. (v0.33)
#
# Every one of these cost an expensive adversarial reviewer's attention in v0.32 and none of them
# needed judgment. They are the clearest case in the whole build for "a checker, not a reviewer".
#
#   T1  grep -c counts LINES, not occurrences. Two matches on one line count as 1.
#   T2  a read that can fail, unguarded, under set -e — the script dies mid-check and the caller
#       cannot tell a refusal from a crash.
#   T3  an unescaped variable inside a regex or a sed program — a dot or a slash in the value
#       silently changes what is matched.
#   T4  a literal apostrophe inside a single-quoted awk program, which closes the program early.
#       v0.32 committed this one in the comment explaining the fix for it.
#   T5  a space-joined path list, in a repository that lives under "Claude Code Projects".
#
# Usage: shell-trap-check.sh <repo-root> [--fixtures <dir>]  Exit 0 clean · 1 traps found · 2 usage.
set -uo pipefail
R="${1:-.}"
cd "$R" 2>/dev/null || { echo "shell-trap-check: cannot enter '$R'"; exit 2; }
[ -d plugins/compass ] || { echo "shell-trap-check: not a compass repo root: $R"; exit 2; }
ALLOW=plugins/compass/scripts/shell-trap-allow.txt
traps=0; scanned=0; t1=0; t2=0; t4=0

# T4 helper. PARITY, not a pattern. The first rule looked for letter-apostrophe-letter not preceded
# by a double quote and it NEVER FIRED — the planted trap sat inside a double-quoted string, so the
# rule walked past its own test case and shipped green as an unproven check.
#
# A well-formed single-quoted awk program has an EVEN number of apostrophes on its line: the opener,
# the closer, and four more for each shell-escape idiom. An ODD count means one closed the program
# early. Arithmetic cannot walk past its own case.
_t4_parity() {
  LC_ALL=C awk '
    index($0, "awk ") > 0 && index($0, sprintf("%c", 39)) > 0 {
      n = gsub(sprintf("%c", 39), "&")
      # >= 2, not just odd. A MULTI-LINE awk invocation opens with exactly one apostrophe and
      # closes several lines later — perfectly correct, and 23 of them exist in this tree. Only a
      # program that opens AND closes on one line can have an apostrophe close it early, and that
      # needs at least two. Without this floor the rule failed 23 correct lines: the fourth time in
      # this build that a "mechanical" rule turned out to need a narrower target than it first had.
      if (n >= 2 && n % 2 == 1) print NR
    }
  ' "$1" 2>/dev/null || true
}

allowed() { LC_ALL=C grep -qE "^[[:space:]]*$1:$2([[:space:]]|#|$)" "$ALLOW" 2>/dev/null; }
hit() { # <file> <line> <trap> <why>
  allowed "$3" "$1" && return 0
  printf '  %s  %s:%s\n         %s\n' "$3" "$1" "$2" "$4"; traps=$((traps+1))
}

while IFS= read -r f; do
  [ -f "$f" ] || continue
  scanned=$((scanned+1))

  # T1 — REPORTED, NEVER FAILED, and the first version of this script got it wrong in the exact way
  # this build keeps finding. It flagged 40 lines and ALL FORTY WERE CORRECT: every one was
  # `grep -c ... -ge 1`, i.e. grep -c used as a BOOLEAN, where counting lines is the right thing.
  # The real trap needs the pattern to be able to match twice on ONE line — and whether it can is a
  # judgment about the pattern, not a shape in the source. So the count is reported and a person
  # decides. A check that fires on correct work gets disabled within a week.
  n=$(LC_ALL=C grep -cE 'grep -c[^|]*\)"?[[:space:]]*(-eq|=)[[:space:]]*"?[0-9]' "$f" 2>/dev/null || true)
  t1=$((t1+${n:-0}))

  # T4 — REPORTED, NEVER FAILED. Three rules were tried and every one failed on the real tree:
  #   1. letter-apostrophe-letter not preceded by a double quote — NEVER FIRED. The planted trap sat
  #      inside a double-quoted string, so the rule walked past its own test case and shipped green
  #      for one commit as an unproven check.
  #   2. odd apostrophe count — fired on 23 correct lines. A MULTI-LINE awk opens with exactly one
  #      apostrophe and closes several lines later; that is normal and correct.
  #   3. odd AND at least two — still fired on 8 correct lines, because `awk -F'|' '` has three
  #      apostrophes in three correct positions, as does `printf '%s' x | awk '`.
  # Apostrophe parity on a single line is not sound in shell: apostrophes appear in many correct
  # paired positions and a line scan cannot tell which pair is which. Reported with its count.
  t4=$((t4+$(_t4_parity "$f" | grep -c . || true)))

  # T5 — a path list joined by spaces then re-split by the shell. Fatal in a repo whose own path
  # contains spaces, which is this one.
  while IFS=: read -r ln _; do
    [ -n "$ln" ] || continue
    hit "$f" "$ln" T5 "a space-joined path list re-splits on the spaces inside a path. Use -print0/-z with xargs -0."
  done <<EOF2
$(LC_ALL=C grep -nE 'for [a-z_]+ in \$\((ls|find|git ls-files)[^)]*\)' "$f" 2>/dev/null | LC_ALL=C grep -v -- '-z\|print0' || true)
EOF2

  # T2 — `set -e` in force and a read with no guard. Reported per FILE, not per line: whether a
  # given read can fail is a judgment, and flagging every one would bury the real cases.
  if LC_ALL=C grep -qE '^set -[a-z]*e' "$f"; then
    n=$(LC_ALL=C grep -cE '^[[:space:]]*(read|IFS=[^ ]* read)[^|]*$' "$f" 2>/dev/null || true)
    t2=$((t2+${n:-0}))
  fi
done <<EOF
$(git ls-files -- 'plugins/compass/scripts/*.sh' 'plugins/compass/hooks/*.sh' 2>/dev/null)
EOF

echo
if [ "$scanned" -eq 0 ]; then
  echo "shell-trap-check: ERR — 0 shell files scanned. A green over an empty set is not a signal."; exit 1
fi
printf 'shell-trap-check: %s trap(s) across %s shell file(s).\n' "$traps" "$scanned"
printf '  MEASURED (this fails the run): T5 a space-joined path list, fatal in a repo whose own\n'
printf '    path contains spaces. A definite SHAPE in the source. Nothing to decide.\n'
printf '  REPORTED, NEVER FAILED — each needs a person, and saying so is the point:\n'
printf '    T1  %s grep -c compared for equality. The trap needs the pattern to match twice on ONE\n' "$t1"
printf '        line; whether it can is a judgment about the pattern. The first version of this\n'
printf '        check failed 40 lines and every one was correct.\n'
printf '    T2  %s read(s) under set -e. Whether a given read can fail at EOF is a judgment.\n' "$t2"
printf '    T4  %s line(s) with odd apostrophe parity around an awk program. THREE rules were tried;\n' "$t4"
printf '        all three failed on correct code. Apostrophes appear in many correct paired\n'
printf '        positions and a line scan cannot tell which pair is which.\n'
printf '    T3  unescaped variable inside a regex — not scanned at all: whether a value can carry a\n'
printf '        metacharacter is a judgment about the value, not a shape in the line.\n'
printf '  ONLY ONE OF FIVE TRAP CLASSES IS SOUNDLY MECHANICAL BY A LINE SCAN. The other four were\n'
printf '  each attempted and each failed on correct code. That materially qualifies this build own\n'
printf '  gold: "mechanical" in the classification meant a script COULD catch it in principle, not\n'
printf '  that a line scanner catches it soundly. Recorded in the classification file, not buried.\n'
[ "$traps" -eq 0 ] || exit 1
exit 0
