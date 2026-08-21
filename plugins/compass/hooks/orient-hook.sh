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
# THIS IS THE ONLY PART OF v0.32 WHOSE BLAST RADIUS LEAVES THE REPO: a
# UserPromptSubmit hook registered "matcher": "*", running on every prompt in
# every project where Compass is installed once v0.32 publishes.
#
# THIRD VERSION. Two independent reviews found 14 and 11 defects. The one that
# forced this rewrite is architectural, not a bug: A LOOP IS PER BUILD, AND THE
# COUNTER WAS PER DIRECTORY. It looped over every unfinished build in the repo,
# so a stale build reported "wakeup 40 of 40" on wakeup 1 of a healthy one — and
# per long-build's own fences the correct response to that message is to STOP.
# A backstop that stops the wrong loop is worse than no backstop. It also cost
# 699 ms in a 31-build repo, 45x the budget, because it did ~10 forks per folder.
#
# THE FIX IS TO READ WHAT THE PROMPT ALREADY SAYS. long-build's wakeup template
# carries the state path verbatim — ".../.claude/builds/<name>/progress.md" — so
# the build is NAMED, absolutely, in the text that triggers the count. One build,
# no walk, no $PWD (the slow path below already distrusts $PWD; the counter used
# to trust it, and the two halves of this file cannot both be right).
# If the prompt names no build there is nothing to count, and nothing is written:
# a human typing `/long-build <task>` is STARTING one, and has no counter yet.
case "$payload" in
  # The prompt FIELD, tolerant of the whitespace real prompts carry — a pasted
  # wakeup with one leading space, a newline, pretty-printed JSON, or a
  # capitalised command all armed nothing in the previous version, which meant
  # the cap was off for that build's whole life.
  *'"prompt"'*'/long-build'*|*'"prompt"'*'/Long-build'*|*'"prompt"'*'/LONG-BUILD'*)
    # Only when the marker is in the PROMPT, never in `cwd`: take the text after
    # the prompt key and require the marker there.
    _wk_after="${payload#*'"prompt"'}"
    case "$_wk_after" in
      *'/long-build'*|*'/Long-build'*|*'/LONG-BUILD'*) : ;;
      *) _wk_after="" ;;
    esac
    # The state path the wakeup template carries. Fork-free.
    _wk_dir=""
    case "$_wk_after" in
      *'/.claude/builds/'*)
        _wk_tail="${_wk_after#*/.claude/builds/}"
        _wk_slugraw="${_wk_tail%%/*}"
        _wk_head="${_wk_after%%/.claude/builds/*}"
        # The path starts at the last quote, space or newline before it.
        _wk_head="${_wk_head##*\"}"; _wk_head="${_wk_head##* }"; _wk_head="${_wk_head##*$'\n'}"
        [ -n "$_wk_head" ] && [ -n "$_wk_slugraw" ] \
          && _wk_dir="$_wk_head/.claude/builds/$_wk_slugraw"
        ;;
    esac
    if [ -n "$_wk_dir" ] && [ -f "$_wk_dir/progress.md" ]; then
      _wk_msg=""
      _wk_b="$_wk_dir/"
      # "Is this build finished" reads the LAST status line, not the first. A
      # stage-log progress.md appends, so `head -1` returned its OLDEST status
      # and a build shipped at v0.7.0 was counted forever; a front-matter one
      # returned a stale stamp over a live gate-wait. Real files here carry up to
      # six status lines.
      # Both separators. Compass writes `**Status:** SHIPPED` in progress files and `status=shipped`
      # in the INDEX line, and a progress.md may carry either.
      _wk_st="$(LC_ALL=C sed -nE 's/^[[:space:]*_-]*[Ss]tatus[[:space:]*_]*[:=][[:space:]*]*(.*)$/\1/p' "$_wk_b/progress.md" 2>/dev/null | tail -1 | sed -E 's/^[^A-Za-z]*//' | tr 'a-z' 'A-Z')"
      _wk_fin=0
      case "$_wk_st" in
        SHIPPED|SHIPPED[^A-Z]*|CLOSED|CLOSED[^A-Z]*|ABANDONED|ABANDONED[^A-Z]*|ROLLED-BACK*) _wk_fin=1 ;;
      esac
      if [ "$_wk_fin" = 0 ]; then
        _wk_f="$_wk_b.compass-wakeups"
        # The fingerprint drops ONLY the engine's own bookkeeping, and only the
        # bookkeeping part of it. `grep -v` removed whole lines, so a step line
        # that happened to carry the word called real work a stall — on a build
        # whose subject IS the wakeup counter, that is most of them. Both
        # spellings long-build's SKILL.md uses are covered: `wakeups_used: N/40`
        # from its template and `stall: 1` from fence 3, singular, which the
        # previous filter missed entirely.
        _wk_sig="$(LC_ALL=C sed -E 's/wakeups_used[[:space:]]*:[[:space:]]*[0-9]+[[:space:]]*\/?[[:space:]]*[0-9]*//g; s/stalls?[[:space:]]*:[[:space:]]*[0-9]+//g' "$_wk_b/progress.md" 2>/dev/null | cksum 2>/dev/null | { read -r a b _; printf '%s-%s' "${a:-0}" "${b:-0}"; } || printf 'x')"
        _wk_prev=""; [ -f "$_wk_f" ] && _wk_prev="$(tail -1 "$_wk_f" 2>/dev/null || true)"
        _wk_prevsig="${_wk_prev##* }"
        _wk_stall=0
        if [ -n "$_wk_prev" ] && [ "$_wk_sig" = "$_wk_prevsig" ]; then
          _wk_stall="$(printf '%s' "$_wk_prev" | { read -r _ _ s _; printf '%s' "${s:-0}"; } 2>/dev/null || printf '0')"
          case "$_wk_stall" in ''|*[!0-9]*) _wk_stall=0 ;; esac
          _wk_stall=$((_wk_stall + 1))
        fi
        # COUNT = the higher of (lines, highest label). Labels are sanity-checked
        # before use: a leading-zero label ("08") made the shell abort mid-script
        # with "value too great for base", and an INT64-max label overflowed and
        # took the count DOWN, permanently disabling the cap.
        _wk_lines=0
        if [ -f "$_wk_f" ]; then _wk_lines="$(wc -l < "$_wk_f" 2>/dev/null || echo 0)"; fi
        _wk_lines="$(printf '%s' "${_wk_lines:-0}" | tr -d ' ')"
        case "$_wk_lines" in ''|*[!0-9]*) _wk_lines=0 ;; esac
        _wk_max=0
        if [ -f "$_wk_f" ]; then
          while IFS=' ' read -r _c _rest; do
            case "$_c" in ''|*[!0-9]*) continue ;; esac
            case "$_c" in 0*) continue ;; esac            # a leading zero is not a decimal label
            [ "${#_c}" -le 9 ] || continue                 # and neither is a number that cannot be compared
            [ "$_c" -gt "$_wk_max" ] && _wk_max="$_c"
          done < "$_wk_f" 2>/dev/null || true
        fi
        _wk_n="$_wk_lines"; [ "$_wk_max" -gt "$_wk_n" ] && _wk_n="$_wk_max"
        _wk_n=$(( _wk_n + 1 ))
        if printf '%s %s %s %s\n' "$_wk_n" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown')" "$_wk_stall" "$_wk_sig" >> "$_wk_f" 2>/dev/null; then
          _wk_lines="$(wc -l < "$_wk_f" 2>/dev/null || echo "$_wk_n")"
          _wk_lines="$(printf '%s' "${_wk_lines:-0}" | tr -d ' ')"
          case "$_wk_lines" in ''|*[!0-9]*) _wk_lines=0 ;; esac
          [ "$_wk_lines" -gt "$_wk_n" ] && _wk_n="$_wk_lines"
          # Bounded. It is re-read every wakeup; 20,000 lines cost 215 ms.
          if [ "$_wk_n" -gt 400 ]; then
            tail -200 "$_wk_f" > "$_wk_f.trim" 2>/dev/null && mv "$_wk_f.trim" "$_wk_f" 2>/dev/null || rm -f "$_wk_f.trim" 2>/dev/null
          fi
        else
          _wk_msg="Compass: the wakeup counter for this build could not be written (read-only?), so the cap cannot be enforced."
        fi
        _wk_cap="${COMPASS_WAKEUP_CAP:-40}"
        case "$_wk_cap" in ''|*[!0-9]*) _wk_cap=40 ;; esac
        # The slug is SANITISED. A build directory name was interpolated raw into
        # JSON, and a crafted one produced valid JSON carrying an attacker-chosen
        # `additionalContext` straight into the model's context.
        _wk_slug="$(printf '%s' "$_wk_slugraw" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_' | cut -c1-64)"
        if [ "$_wk_n" -ge "$_wk_cap" ]; then
          _wk_msg="Compass: wakeup $_wk_n of $_wk_cap for $_wk_slug — the cap is reached; the loop should stop and report."
        elif [ "$_wk_stall" -ge 2 ]; then
          _wk_msg="Compass: $_wk_stall consecutive wakeups with no real change to progress.md for $_wk_slug — that is the stall condition; stop the loop rather than re-arming."
        fi
      fi
      # ONE JSON object, always.
      [ -n "$_wk_msg" ] && printf '{"systemMessage":"%s"}\n' "$_wk_msg" 2>/dev/null
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
