#!/usr/bin/env bash
# Compass v0.28.0 — UserPromptSubmit hook. Delivers the orientation block.
#
# WHY THIS IS ITS OWN SCRIPT AND NOT A compass.sh SUBCOMMAND:
# this runs on EVERY user prompt in EVERY project where Compass is installed,
# and >99% of those prompts are not Compass front doors. Measured on the build
# machine: this script on the no-match path = 3.3 ms; loading the 3134-line
# compass.sh = 27.3 ms, and its state_root() shells out to git, which is
# unbounded on a large or network filesystem. So the match test happens FIRST,
# before any compass.sh load and before any filesystem or git access.
#
# WHY systemMessage AND NOT stdout: verified against the Claude Code hooks
# reference — plain stdout on exit 0 is added as CONTEXT Claude can see, and is
# NOT shown to the user. Only `systemMessage` reaches the user's transcript.
# Emitting the block on stdout would have rebuilt the exact INV-WELCOME failure:
# text that exists, that the user never sees.
#
# NEVER exit 2: for UserPromptSubmit, exit 2 blocks the prompt and ERASES it.
# A missing orientation block is a small problem; eating the user's typed prompt
# is a large one. Every path here exits 0 (fail-open).

set -u

payload="$(cat 2>/dev/null || true)"

# ── FAST PATH: the only work done for a non-Compass prompt ──────────────────
case "$payload" in
  *'/compass:go'*|*'/compass:status'*|*'/compass:resume'*) : ;;
  *) exit 0 ;;
esac

# ── Slow path (a real front door was typed) ─────────────────────────────────
[ -n "${COMPASS_QUIET:-}" ] && exit 0

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPASS_SH="$HERE/../scripts/compass.sh"
[ -f "$COMPASS_SH" ] || exit 0

cwd="$(printf '%s' "$payload" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("cwd","") or "")
except Exception: print("")' 2>/dev/null || true)"
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"

# INV-ORIENT-INERT: a project with no Compass state gets nothing at all — not a
# banner, not a hint, not a byte. Compass must be invisible where it is unused.
root="$cwd"
found=""
while [ "$root" != "/" ] && [ -n "$root" ]; do
  if [ -d "$root/.claude/builds" ]; then found="$root"; break; fi
  root="$(dirname "$root")"
done
[ -n "$found" ] || exit 0

block="$(cd "$found" && bash "$COMPASS_SH" orient 2>/dev/null || true)"
[ -n "$block" ] || exit 0

printf '%s' "$block" | python3 -c 'import json,sys
b = sys.stdin.read()
sys.stdout.write(json.dumps({"systemMessage": b, "additionalContext": b}))' 2>/dev/null || exit 0

exit 0
