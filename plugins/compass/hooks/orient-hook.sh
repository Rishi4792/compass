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

# ── v0.32.0 S16 — THE WAKEUP COUNTER ────────────────────────────────────────
# THIS IS THE ONLY PART OF v0.32 WHOSE BLAST RADIUS LEAVES THE REPO. It ships
# inside a UserPromptSubmit hook registered "matcher": "*", so once v0.32 is
# published it runs on every prompt in every project where Compass is installed.
#
# A CORRECTION TO THE PLAN'S PREMISE, measured on this machine 2026-08-21. The
# plan says this file runs "the moment it is written". It does not. The live
# hook is the plugin's CACHED clone at
#   ~/.claude/plugins/marketplaces/compass/plugins/compass/hooks/orient-hook.sh
# pulled from GitHub — byte-identical today, but a different file. Editing the
# working tree changes nothing until v0.32 is published. The blast radius is
# real; the immediacy is not, and building to a false premise is this build's
# own subject.
#
# WHY IT SITS ABOVE THE MATCHER. The fast path below exits 0 for any prompt not
# naming a /compass front door. A `/long-build continue` wakeup is exactly such
# a prompt, so a counter placed after it would never fire and the cap would
# never trip — an unbounded loop, which is worse than no counter at all.
#
# WHAT IT COSTS EVERYONE ELSE: one `case` match on a string already in memory.
# No fork, no stat, no file read. The walk and the write happen only once the
# prompt has already been identified as a wakeup.
case "$payload" in
  *'/long-build'*|*'/loop'*)
    # Fork-free walk UP from the invocation directory. A $PWD-only test is
    # faster still and silently skips every wakeup fired from a subdirectory,
    # which is most of them. `dirname` in a loop measured 24.1 ms and the
    # python3 cwd parse 18.6 ms; parameter expansion is ~0.5 ms.
    _wk_p="$PWD"; _wk_root=""
    while [ -n "$_wk_p" ] && [ "$_wk_p" != "/" ]; do
      if [ -d "$_wk_p/.claude/builds" ]; then _wk_root="$_wk_p"; break; fi
      _wk_p="${_wk_p%/*}"
    done
    # "An ACTIVE build", which is a state read, not merely a directory test:
    # a tree whose builds are all closed gets nothing written.
    if [ -n "$_wk_root" ]; then
      for _wk_b in "$_wk_root"/.claude/builds/*/; do
        [ -f "$_wk_b/progress.md" ] || continue
        case "$(head -c 400 "$_wk_b/progress.md" 2>/dev/null || true)" in
          *CLOSED*|*'status=shipped'*) continue ;;
        esac
        _wk_f="$_wk_b.compass-wakeups"
        # APPEND-ONLY and MONOTONE. The next value is read from the last line
        # and always rises; a file that has been edited downward is not
        # silently accepted — the counter takes the highest value it has ever seen.
        _wk_n=0
        if [ -f "$_wk_f" ]; then
          while IFS=' ' read -r _c _rest; do
            case "$_c" in ''|*[!0-9]*) continue ;; esac
            [ "$_c" -gt "$_wk_n" ] && _wk_n="$_c"
          done < "$_wk_f" 2>/dev/null || true
        fi
        _wk_n=$((_wk_n + 1))
        # Progress fingerprint, for the two-consecutive-no-progress stall
        # detector. cksum, not shasum: change detection, not integrity.
        _wk_sig="$(cksum "$_wk_b/progress.md" 2>/dev/null | { read -r a b _; printf '%s-%s' "${a:-0}" "${b:-0}"; } || printf 'x')"
        _wk_prev="$(tail -1 "$_wk_f" 2>/dev/null || true)"
        _wk_prevsig="${_wk_prev##* }"
        _wk_stall=0
        if [ "$_wk_sig" = "$_wk_prevsig" ]; then
          _wk_stall="$(printf '%s' "$_wk_prev" | { read -r _ _ s _; printf '%s' "${s:-0}"; } 2>/dev/null || printf '0')"
          case "$_wk_stall" in ''|*[!0-9]*) _wk_stall=0 ;; esac
          _wk_stall=$((_wk_stall + 1))
        fi
        printf '%s %s %s %s\n' "$_wk_n" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown')" "$_wk_stall" "$_wk_sig" >> "$_wk_f" 2>/dev/null || true
        _wk_cap="${COMPASS_WAKEUP_CAP:-40}"
        case "$_wk_cap" in ''|*[!0-9]*) _wk_cap=40 ;; esac
        if [ "$_wk_n" -ge "$_wk_cap" ]; then
          printf '{"systemMessage":"Compass: wakeup %s of %s for %s — the cap is reached. The loop should stop and report."}\n' \
            "$_wk_n" "$_wk_cap" "$(basename "$_wk_b")" 2>/dev/null || true
        elif [ "$_wk_stall" -ge 2 ]; then
          printf '{"systemMessage":"Compass: %s consecutive wakeups with no change to progress.md for %s — that is the stall condition; stop the loop rather than re-arming."}\n' \
            "$_wk_stall" "$(basename "$_wk_b")" 2>/dev/null || true
        fi
      done
    fi
    ;;
esac

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
