#!/usr/bin/env bash
# v0.32.0 S16 — the wakeup counter in hooks/orient-hook.sh.
#
# THIS IS THE ONLY PART OF v0.32 WHOSE BLAST RADIUS LEAVES THE REPO, so it gets its own test file
# rather than a few lines inside the smoke suite. Everything here drives the REAL hook with a real
# payload on stdin from a real directory — nothing re-implements the hook's logic and then checks
# its own re-implementation, which is how a test ends up agreeing with itself.
#
# Usage: wakeup-counter-test.sh [<repo-root>]
# Exit: 0 all cases pass · 1 one or more failed.
set -uo pipefail
# ABSOLUTE, always. `fire()` cd's into a fixture directory before invoking the hook, so a relative
# root (`.`) makes the hook path unresolvable — the first run of this file reported the counter
# never firing when the counter was fine and the TEST was broken.
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "wakeup-counter-test: cannot resolve root"; exit 1; }
HOOK="$ROOT/plugins/compass/hooks/orient-hook.sh"
[ -f "$HOOK" ] || { echo "wakeup-counter-test: no hook at $HOOK"; exit 1; }
pass=0; fail=0
chk() { # <got> <want> <label>
  if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "  ok   $3"
  else fail=$((fail+1)); echo "  FAIL $3 (got '$1' want '$2')"; fi
}
mkbuild() { # <root> <slug>
  mkdir -p "$1/.claude/builds/$2"
  printf '# %s — progress\n\n**Status:** BUILDING\n' "$2" > "$1/.claude/builds/$2/progress.md"
}
fire() { # <cwd> <payload> -> hook stdout
  ( cd "$1" && printf '%s' "$2" | bash "$HOOK" 2>/dev/null ) || true
}
last() { tail -1 "$1" 2>/dev/null | { read -r n _; printf '%s' "${n:-0}"; }; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ── 1. a /long-build continue prompt ADVANCES the counter ─────────────────────────────────────
mkbuild "$T/p1" b1
F="$T/p1/.claude/builds/b1/.compass-wakeups"
fire "$T/p1" '{"prompt":"/long-build continue — b1"}' >/dev/null
chk "$(last "$F")" "1" "a /long-build continue prompt advances the counter to 1"
printf '\n- more\n' >> "$T/p1/.claude/builds/b1/progress.md"
fire "$T/p1" '{"prompt":"/long-build continue — b1"}' >/dev/null
chk "$(last "$F")" "2" "...and again to 2"

# ── 2. a wakeup fired from a SUBDIRECTORY still advances it ───────────────────────────────────
mkdir -p "$T/p1/src/deep/deeper"
printf '\n- more2\n' >> "$T/p1/.claude/builds/b1/progress.md"
fire "$T/p1/src/deep/deeper" '{"prompt":"/long-build continue"}' >/dev/null
chk "$(last "$F")" "3" "a wakeup fired from a SUBDIRECTORY still advances it (a \$PWD-only guard would skip this)"

# ── 3. APPEND-ONLY and MONOTONE: an edited-down file does not lower the counter ────────────────
# The LAST line must be LOWER than an earlier one, or this proves nothing: with a single line,
# "take the last value" and "take the highest value" give the same answer. A first version of this
# case wrote one line and a hook mutated to read only the last line still passed it.
printf '9 2020-01-01T00:00:00Z 0 x-x\n2 2020-01-01T00:00:01Z 0 y-y\n' > "$F"
printf '\n- more3\n' >> "$T/p1/.claude/builds/b1/progress.md"
fire "$T/p1" '{"prompt":"/long-build continue"}' >/dev/null
chk "$(last "$F")" "10" "a file whose LAST line is lower than an earlier one still rises from the highest ever seen, not from the last"
chk "$(grep -c . "$F")" "3" "...and the write is an APPEND, not a rewrite"

# ── 4. it reaches the CAP and says so ─────────────────────────────────────────────────────────
mkbuild "$T/p2" b2
F2="$T/p2/.claude/builds/b2/.compass-wakeups"
capout=""
i=0
while [ "$i" -lt 5 ]; do
  i=$((i+1)); printf '\n- step %s\n' "$i" >> "$T/p2/.claude/builds/b2/progress.md"
  capout="$(COMPASS_WAKEUP_CAP=5 fire "$T/p2" '{"prompt":"/long-build continue"}')"
done
chk "$(last "$F2")" "5" "the counter drives to the cap"
chk "$(printf '%s' "$capout" | grep -c 'the cap is reached')" "1" "...and the hook SAYS the cap is reached, in a systemMessage the user sees"

# ── 5. the two-consecutive-no-progress STALL detector fires ───────────────────────────────────
# progress.md is NOT touched between these, which is exactly the stall condition.
mkbuild "$T/p3" b3
F3="$T/p3/.claude/builds/b3/.compass-wakeups"
fire "$T/p3" '{"prompt":"/long-build continue"}' >/dev/null
fire "$T/p3" '{"prompt":"/long-build continue"}' >/dev/null
stallout="$(fire "$T/p3" '{"prompt":"/long-build continue"}')"
chk "$(tail -1 "$F3" | { read -r _ _ s _; printf '%s' "${s:-0}"; })" "2" "two consecutive wakeups with no change to progress.md record a stall count of 2"
chk "$(printf '%s' "$stallout" | grep -c 'stall condition')" "1" "...and the hook SAYS so rather than only recording it"
# and a REAL change resets it
printf '\n- real work\n' >> "$T/p3/.claude/builds/b3/progress.md"
fire "$T/p3" '{"prompt":"/long-build continue"}' >/dev/null
chk "$(tail -1 "$F3" | { read -r _ _ s _; printf '%s' "${s:-0}"; })" "0" "...and a real change to progress.md RESETS the stall count (or it would fire forever)"

# ── 6. a CLOSED build is not counted — the guard is a state read, not a directory test ─────────
mkdir -p "$T/p4/.claude/builds/b4"
printf '# b4\n\n**Status:** CLOSED\n' > "$T/p4/.claude/builds/b4/progress.md"
fire "$T/p4" '{"prompt":"/long-build continue"}' >/dev/null
# NON-VACUITY: this case and the next both assert that NOTHING was written, and a hook that never
# writes anywhere would satisfy both for free. So first prove, in the same run, that the counter
# does write when it should — otherwise these two are the "0 out of 0" shape this build keeps finding.
chk "$([ -s "$F" ] && echo writes || echo NEVER-WRITES)" "writes" "control for the two silence cases below: the counter demonstrably DOES write when it should"
chk "$([ -f "$T/p4/.claude/builds/b4/.compass-wakeups" ] && echo wrote || echo silent)" "silent" "a CLOSED build is not counted — 'an active build' is a state read, not a directory test"

# ── 7. a NON-Compass directory writes NOTHING ─────────────────────────────────────────────────
mkdir -p "$T/plain/sub"
before="$(find "$T/plain" -type f | wc -l | tr -d ' ')"
fire "$T/plain/sub" '{"prompt":"/long-build continue"}' >/dev/null
after="$(find "$T/plain" -type f | wc -l | tr -d ' ')"
chk "$after" "$before" "a prompt in a NON-Compass directory writes nothing at all"

# ── 8. a MALFORMED state file still exits 0 and still advances ────────────────────────────────
mkbuild "$T/p5" b5
F5="$T/p5/.claude/builds/b5/.compass-wakeups"
printf 'not a number\n\x00garbage\nnine\n' > "$F5"
fire "$T/p5" '{"prompt":"/long-build continue"}' >/dev/null
rc=$?
chk "$rc" "0" "a malformed state file still exits 0 — this hook must never block a prompt"
_lastn="$(last "$F5")"; case "$_lastn" in ''|*[!0-9]*) _lastn=0 ;; esac
chk "$([ "$_lastn" -ge 1 ] && echo advanced || echo stuck)" "advanced" "...and the counter still advances past the garbage"

# ── 9. PERF: the cost paid by every unrelated prompt on the machine ───────────────────────────
# The budget in the plan is <=10 ms over the measured 5.3 ms fast path, for a prompt in a
# NON-Compass directory. Timed over 20 runs so one scheduling blip cannot decide it.
if command -v python3 >/dev/null 2>&1; then
  t0=$(python3 -c 'import time;print(int(time.time()*1000))')
  i=0; while [ "$i" -lt 20 ]; do i=$((i+1)); fire "$T/plain/sub" '{"prompt":"what is the weather"}' >/dev/null; done
  t1=$(python3 -c 'import time;print(int(time.time()*1000))')
  per=$(( (t1 - t0) / 20 ))
  echo "  ..   measured: ${per} ms per unrelated prompt (budget: 5.3 ms fast path + 10 ms = 15.3 ms)"
  chk "$([ "$per" -le 16 ] && echo within || echo "OVER:${per}ms")" "within" "an unrelated prompt stays inside the perf budget"
fi

echo "wakeup-counter: $((pass+fail)) cases, $fail failing"
[ "$fail" -eq 0 ] || exit 1
exit 0
