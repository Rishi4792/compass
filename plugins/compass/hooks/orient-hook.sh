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
# REWRITTEN AFTER AN INDEPENDENT REVIEW FOUND 14 DEFECTS IN THE FIRST VERSION.
# The three that made it dangerous on a machine with nothing to do with Compass:
#   · the matcher was a bare substring over the WHOLE hook payload — which carries
#     `cwd` — so "fix the bug in src/loop.js" armed it, a project directory named
#     `loops` armed it on EVERY prompt forever, and the built-in `/loop` command
#     armed it too. Measured cost was 330 ms, not the 5 ms claimed, rising with
#     the number of build folders (60 folders -> 714 ms).
#   · a build DIRECTORY NAME was interpolated raw into the JSON on stdout, so a
#     crafted folder name in a cloned repo became attacker-chosen
#     `additionalContext` injected into the model's context.
#   · with more than one build folder the hook printed several JSON objects, which
#     is INVALID JSON — Claude Code then treats stdout as plain context and the
#     user never sees the cap or stall warning. That is precisely the INV-WELCOME
#     failure this file's own header warns about, rebuilt.
#
# A CORRECTION TO THE PLAN'S PREMISE, measured 2026-08-21: the plan says this file
# runs "the moment it is written". It does not. The live hook is the plugin's
# CACHED clone under ~/.claude/plugins/marketplaces/, pulled from GitHub —
# byte-identical today, but a different file.
#
# WHY IT SITS ABOVE THE MATCHER: the fast path below exits 0 for any prompt not
# naming a /compass front door, and a `/long-build continue` wakeup is exactly
# such a prompt. Below it the cap could never trip.
case "$payload" in
  # ONLY the prompt FIELD, and only at its start. Matching the raw payload matched
  # `cwd` as well; requiring the marker to open the prompt is what separates a
  # wakeup from a sentence that mentions one. `/loop` is NOT matched at all — it is
  # a built-in Claude Code command and the collision armed this on unrelated work.
  *'"prompt":"/long-build'*|*'"prompt": "/long-build'*)
    _wk_p="$PWD"; _wk_root=""
    # Fork-free walk UP, but never above $HOME: a non-Compass project nested under
    # a directory that happens to hold .claude/builds was inheriting it, and the
    # hook wrote five levels up into the home directory while the test's `find`
    # looked only at the project and reported "writes nothing at all".
    while [ -n "$_wk_p" ] && [ "$_wk_p" != "/" ]; do
      if [ -d "$_wk_p/.claude/builds" ]; then _wk_root="$_wk_p"; break; fi
      [ "$_wk_p" = "${HOME:-/nonexistent}" ] && break
      _wk_p="${_wk_p%/*}"
    done
    if [ -n "$_wk_root" ]; then
      _wk_msg=""
      for _wk_b in "$_wk_root"/.claude/builds/*/; do
        [ -f "$_wk_b/progress.md" ] || continue
        _wk_head="$(head -c 400 "$_wk_b/progress.md" 2>/dev/null || true)"
        # SHIPPED was missing here while the two gates written the same day both had
        # it: 25 of this repo's 30 progress files spell it that way and every one of
        # them was being counted and generating false stall warnings.
        case "$_wk_head" in *SHIPPED*|*CLOSED*|*'status=shipped'*) continue ;; esac
        _wk_f="$_wk_b.compass-wakeups"
        # NO LOCK, BECAUSE THE COUNT IS THE FILE. `>>` is atomic for lines this short (verified
        # by an independent reviewer: twenty concurrent appends, zero torn lines), so ONE WAKEUP
        # LEAVES ONE LINE and the authoritative count is how many lines there are.
        # The first version did a read-modify-write of a stored maximum, and two sessions in one
        # repo both read the same value: fifty real wakeups reached twenty-five, so N sessions
        # multiplied the cap by N. The second version took an mkdir lock and had losers `continue`
        # — which traded double-counting for UNDER-counting, and twenty-four wakeups reached six.
        # Counting lines has neither failure: the number in column one is a label, and the cap is
        # checked against `wc -l`.
        # The fingerprint IGNORES the engine's own bookkeeping line. long-build's SKILL.md mandates
        # incrementing `wakeups_used: N/40` in progress.md every single wakeup, so a whole-file
        # checksum always changed and the stall detector could never fire on a genuinely dead loop
        # — nine consecutive no-progress wakeups produced zero warnings.
        _wk_sig="$(grep -v -e 'wakeups_used' -e 'stalls:' "$_wk_b/progress.md" 2>/dev/null | cksum 2>/dev/null | { read -r a b _; printf '%s-%s' "${a:-0}" "${b:-0}"; } || printf 'x')"
        _wk_prev="$(tail -1 "$_wk_f" 2>/dev/null || true)"
        _wk_prevsig="${_wk_prev##* }"
        _wk_stall=0
        if [ "$_wk_sig" = "$_wk_prevsig" ]; then
          _wk_stall="$(printf '%s' "$_wk_prev" | { read -r _ _ s _; printf '%s' "${s:-0}"; } 2>/dev/null || printf '0')"
          case "$_wk_stall" in ''|*[!0-9]*) _wk_stall=0 ;; esac
          _wk_stall=$((_wk_stall + 1))
        fi
        # THE HIGHER OF (lines, highest label). Lines alone is correct under concurrency but a file
        # edited DOWN would lower the count and dodge the cap; the highest label alone is correct
        # against that edit but wrong under concurrency. Both together are right in both cases.
        _wk_lines="$(wc -l < "$_wk_f" 2>/dev/null || echo 0)"; _wk_lines="$(printf '%s' "${_wk_lines:-0}" | tr -d ' ')"
        case "$_wk_lines" in ''|*[!0-9]*) _wk_lines=0 ;; esac
        _wk_max=0
        if [ -f "$_wk_f" ]; then
          while IFS=' ' read -r _c _rest; do
            case "$_c" in ''|*[!0-9]*) continue ;; esac
            [ "$_c" -gt "$_wk_max" ] && _wk_max="$_c"
          done < "$_wk_f" 2>/dev/null || true
        fi
        _wk_n="$_wk_lines"; [ "$_wk_max" -gt "$_wk_n" ] && _wk_n="$_wk_max"
        _wk_n=$(( _wk_n + 1 ))
        if printf '%s %s %s %s\n' "$_wk_n" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown')" "$_wk_stall" "$_wk_sig" >> "$_wk_f" 2>/dev/null; then
          # The CAP is read from the file, not from the label just written — under concurrency the
          # labels can repeat and the line count cannot.
          _wk_lines="$(wc -l < "$_wk_f" 2>/dev/null || echo 0)"; _wk_lines="$(printf '%s' "${_wk_lines:-0}" | tr -d ' ')"
          case "$_wk_lines" in ''|*[!0-9]*) _wk_lines=0 ;; esac
          [ "$_wk_lines" -gt "$_wk_n" ] && _wk_n="$_wk_lines"
          # Keep the file bounded. It was append-only and never pruned, and it is re-read on every
          # wakeup — 20,000 lines cost 215 ms. Trimming keeps the LABELS, so the cap is not reset:
          # the retained lines still carry their original numbers.
          if [ "$_wk_n" -gt 400 ]; then
            tail -200 "$_wk_f" > "$_wk_f.trim" 2>/dev/null && mv "$_wk_f.trim" "$_wk_f" 2>/dev/null || rm -f "$_wk_f.trim" 2>/dev/null
            _wk_lbl="$(tail -1 "$_wk_f" 2>/dev/null | { read -r a _; printf '%s' "${a:-0}"; })"
            case "$_wk_lbl" in ''|*[!0-9]*) : ;; *) [ "$_wk_lbl" -gt "$_wk_n" ] && _wk_n="$_wk_lbl" ;; esac
          fi
        else
          # A read-only build dir used to fail OPEN in silence — the cap could never trip and
          # nothing said so. Say it instead.
          _wk_msg="$_wk_msg Compass: the wakeup counter for a build here could not be written (read-only?), so the cap cannot be enforced."
        fi
        _wk_cap="${COMPASS_WAKEUP_CAP:-40}"
        case "$_wk_cap" in ''|*[!0-9]*) _wk_cap=40 ;; esac
        # The slug is SANITISED before it reaches stdout. A directory name was being
        # interpolated raw into JSON: a crafted one produced valid JSON with an
        # attacker-chosen additionalContext, and an ordinary one with a quote or a
        # newline produced invalid JSON.
        _wk_slug="$(printf '%s' "$(basename "$_wk_b")" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_' | cut -c1-64)"
        if [ "$_wk_n" -ge "$_wk_cap" ]; then
          _wk_msg="$_wk_msg Compass: wakeup $_wk_n of $_wk_cap for $_wk_slug — the cap is reached; the loop should stop and report."
        elif [ "$_wk_stall" -ge 2 ]; then
          _wk_msg="$_wk_msg Compass: $_wk_stall consecutive wakeups with no real change to progress.md for $_wk_slug — that is the stall condition; stop the loop rather than re-arming."
        fi
      done
      # ONE JSON object, always. Several concatenated objects are not JSON, and
      # Claude Code then treats stdout as plain context the user never sees.
      [ -n "$_wk_msg" ] && printf '{"systemMessage":"%s"}\n' "${_wk_msg# }" 2>/dev/null
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
