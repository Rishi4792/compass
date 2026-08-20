#!/usr/bin/env bash
# assert-invariants.sh — the INVARIANT assertions as EXECUTABLE CODE, never as prose.
#
# WHY THIS FILE EXISTS:
# The same defect recurred five times across three review rounds on the v0.30 build —
# an assertion command that could not go red:
#   1. INV-5  `grep -cE 'A\|B'`  — escaped pipes are LITERAL in ERE; returned 0 on an untouched tree
#   2. the fix shipped that same escaped pattern, annotated "(unescaped)"
#   3. INV-11 carried the identical bug three rows below the one being fixed; and the
#      pattern fixture was stored inside the directory it searched, so it matched itself
#   4. step 20 re-introduced `grep -rEc` (emits path:count, never a scalar) forty lines
#      below the note documenting that exact trap
#   5. red-first-evidence.md — the file proving the bug was fixed — stored the escaped form
#
# EVERY instance was a command living in a markdown table, where `\|` (table escaping) is
# byte-identical to the ERE bug and nothing ever executes the cell. INV-0 (RED-FIRST) was
# the right rule implemented in the wrong medium. So: the commands live HERE, they run, and
# their exit codes are the evidence. A plan may reference an assertion by name; it may not
# restate it in prose.
#
# Usage:
#   assert-invariants.sh <repo-root> [--json] [--self-test] [--assert-red|--assert-pass]
# Exit: 0 = every assertion evaluated (see per-line PASS/RED); 2 = usage/precondition failure.
# Each assertion prints:  <INV> <value> <target> <RED|PASS>
# RED  = value differs from target  → the assertion can fail, INV-0 satisfied
# PASS = value equals target        → work done, or the assertion is decoration (check RED-first history)

set -uo pipefail

ROOT="${1:-}"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "usage: assert-invariants.sh <repo-root> [--json]" >&2; exit 2; }
# NORMALISE. A caller passing "$PLUGIN_ROOT/../.." is passing a perfectly valid directory, but the
# un-normalised string broke half the guards downstream (6 of 13 fired). A path is not a string.
ROOT="$(cd "$ROOT" && pwd)" || { echo "assert-invariants: cannot resolve '$ROOT'" >&2; exit 2; }
P="$ROOT/plugins/compass"
[ -d "$P" ] || { echo "assert-invariants: no plugins/compass under '$ROOT'" >&2; exit 2; }

# Flags parsed by SCAN, not by position: --self-test was readable only as $2, so it could never
# co-exist with --json (R2-8).
MODE=""; WANT_JSON=""; SELFTEST=""
for a in "$@"; do
  case "$a" in
    --json) WANT_JSON=1 ;;
    --self-test) SELFTEST=1 ;;
    --assert-red) MODE=assert-red ;;
    --assert-pass) MODE=assert-pass ;;
  esac
done

rows=()

# Printed once, before the first row. `redfirst-check` requires it: it is what separates a file
# produced by RUNNING this script from a file someone typed to satisfy a gate. Round 2 defeated
# the old check with a single hand-written line naming five invariants at once, and the gate
# reported it as "machine=5".
_emit_header() {
  [ "${_HDR_DONE:-0}" = 1 ] && return 0
  _HDR_DONE=1
  local sha dirty; sha="$(cd "$ROOT" 2>/dev/null && git rev-parse HEAD 2>/dev/null || true)"
  # Say when the working tree is NOT the commit. Stamping a bare sha over uncommitted changes names
  # a tree that was not the one measured, and `redfirst-check` reads this header as provenance.
  dirty="$(cd "$ROOT" 2>/dev/null && git status --porcelain 2>/dev/null | grep -c . | tr -d ' ' || echo 0)"
  if [ -n "$sha" ] && [ "${dirty:-0}" != "0" ]; then
    printf 'ASSERT-INVARIANTS-RUN root=%s tree=%s+dirty(%s uncommitted)\n' "$ROOT" "$sha" "$dirty"
  else
    printf 'ASSERT-INVARIANTS-RUN root=%s tree=%s\n' "$ROOT" "${sha:-no-git}"
  fi
}
emit() { # <inv> <value> <target>
  _emit_header
  local inv="$1" val="$2" tgt="$3" verdict
  if [ "$val" = "$tgt" ]; then verdict="PASS"; else verdict="RED"; fi
  printf '%-8s value=%-6s target=%-6s %s\n' "$inv" "$val" "$tgt" "$verdict"
  rows+=("{\"inv\":\"$inv\",\"value\":\"$val\",\"target\":\"$tgt\",\"verdict\":\"$verdict\"}")
}

# Guarded counter: a missing file or a grep ERROR (exit 2) must never look like the pass target.
# `grep | wc -l` swallows exit 2, so a typo'd path silently reports 0 — which IS the target for
# most of these. That is finding #6 and it is why every count goes through here.
# POSITIVE CONTROL (the half INV-0 was missing).
# "Prove the assertion can fail" was measured against the CURRENT tree — a moving target.
# So every guard I wrote checked a PROXY for the property rather than the property:
#   "pattern file exists / is non-empty"  proxied for  "the pattern actually matches"
#   "-R is in the command"                proxied for  "the search actually descended"
# Both proxies held while the assertion was dead. A fixed, known-violating input closes it:
# if the pattern stops matching the control, something is broken and we say so LOUDLY —
# CRLF endings, a substituted file, the wrong grep flavour, an undescended symlink, all of it.
# A TOTAL threshold lets individual pattern lines rot unnoticed: the control had 5 matching lines
# against a `-ge 4` bar, so deleting any ONE pattern line outright left the control still
# "passing" at 4 while a real violation — a peer-to-peer file send to a named personal machine —
# went undetected and INV-5 reported its PASS target. (This comment deliberately does not spell
# the removed literal: naming it here would itself trip INV-5, which is the point of INV-5.)
# Every pattern line must now prove itself
# against the control, so a rotted line is named rather than absorbed by its neighbours.
# Takes the CLEANED pattern file to read lines from, and — explicitly — the directory the real
# fixtures live in. It used to derive that directory from its own first parameter with
# `local pat="$1" ctl="${pat%/*}/positive-control.txt"`, which does not do what it reads like:
# bash expands every word on a `local` line BEFORE the assignments take effect, so `${pat%/*}`
# expanded the CALLER's `pat` (dynamic scope), not the parameter. The control lookup therefore
# worked by accident, and the variants lookup added later — a separate statement, so it correctly
# saw the temp path — silently found nothing and skipped the check entirely. Passing the directory
# explicitly removes the accident in both directions.
_control_ok() { # <clean-pattern-file> <fixtures-dir>  → 0 if EVERY pattern line still proves itself
  local cpat="$1" fxd="$2" line
  local ctl="$fxd/positive-control.txt"
  [ -f "$ctl" ] || return 1
  local any=0
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    any=1
    grep -qE -- "$line" "$ctl" 2>/dev/null || { CONTROL_DEAD_LINE="$line"; return 1; }
  done < "$cpat"
  [ "$any" = 1 ] || return 1
  # A pattern must also GENERALISE. Round 2 rewrote each pattern line to the control's own literal
  # text — a line copied from the control always matches the control, so per-line coverage passed
  # while three real violations shipped undetected, and the line-count pin below saw no change
  # because no line was removed. A second control carries the same violations phrased differently
  # and shares no verbatim string with the first; a pattern that matches only the text it was
  # copied from fails here.
  # An ABSENT second control is not "no generalisation requirement" — it is a requirement that
  # stopped being checked. The file was untracked for a whole round, so on a fresh clone this
  # guard silently vanished and round 2's defeat worked again. Absence is now an error.
  local var="$fxd/variants.txt"
  [ -f "$var" ] || { CONTROL_DEAD_LINE="missing second control $var"; return 1; }
  if [ -f "$var" ]; then
    while IFS= read -r line; do
      case "$line" in ''|'#'*) continue ;; esac
      grep -qE -- "$line" "$var" 2>/dev/null || { CONTROL_DEAD_LINE="does not generalise: $line"; return 1; }
    done < "$cpat"
  fi
  # Per-line coverage catches a pattern that BROKE. It cannot catch one that was DELETED — the
  # survivors all still match, the control is happy, and the class simply stops being checked.
  # So the control PINS how many patterns it expects, in its own header. Changing what the gate
  # covers now means editing the pin, which is a visible decision instead of a silent deletion.
  local want; want="$(sed -n 's/^# expects:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$ctl" | head -1)"
  if [ -n "$want" ]; then
    local have; have="$(grep -cE '^[^#[:space:]]' "$cpat" 2>/dev/null || echo 0)"
    [ "${have:-0}" = "$want" ] || { CONTROL_DEAD_LINE="pattern-count $have, control expects $want"; return 1; }
  fi
  return 0
}

count_matches() { # <pattern-file> <path...>
  local pat="$1"; shift
  [ -f "$pat" ] || { echo "ERR-no-pattern-file"; return; }
  # An EMPTY pattern file is the dangerous case, not a missing one: `grep -f /dev/null` matches
  # NOTHING and returns 0 — which IS the pass target. Emptying this file would turn INV-5 green
  # with every defect still shipping. Caught by attack #2.
  [ -s "$pat" ] || { echo "ERR-empty-pattern"; return; }
  grep -qE '[^[:space:]]' "$pat" || { echo "ERR-blank-pattern"; return; }
  # Strip CR before use. A CRLF pattern file gives every pattern a trailing \r, so nothing
  # matches and INV-5 reads its PASS target with every violation still shipping (R3-2).
  local clean; clean="$(mktemp)"; tr -d '\r' < "$pat" > "$clean"
  _control_ok "$clean" "$(dirname "$pat")" || { rm -f "$clean"; echo "ERR-control-not-matched${CONTROL_DEAD_LINE:+:$CONTROL_DEAD_LINE}"; return; }
  local out rc
  # --exclude-dir=fixtures is LOAD-BEARING and must be in the CODE, not only in a comment:
  # the pattern file lives under scripts/fixtures/, which is inside the searched tree, so
  # without this it matches itself and the target becomes unreachable. This guard was
  # documented-but-not-implemented in the first draft — the sixth recurrence of "the note
  # describes the fix, the code does not have it". Caught by attack #3.
  # -R (not -r) so a symlinked skills/ or a dev checkout linked into ~/.claude/plugins is
  # actually descended; -r skips symlinked dirs on both BSD and GNU, and the undercount looks
  # like a legitimate low number (R2-6).
  # find -L, not grep -R: BSD grep -R does NOT descend a symlinked dir passed as a bare path
  # (only with a trailing slash), so a dev checkout symlinked into ~/.claude/plugins silently
  # dropped the whole skills/ tree and INV-5 read 0 = PASS (R3-1). Worse, the answer depended on
  # WHICH grep was first on PATH — ugrep returned 3 where /usr/bin/grep returned 0 on the same
  # input, which is precisely the "works on a stranger's machine" property INV-5 exists to assert.
  # find -L follows symlinks identically everywhere and removes the grep-flavour dependency.
  # Exclude only THIS script's own fixtures (scripts/fixtures/), which must be skipped because the
  # pattern file lives there and would match itself. The old glob '*/fixtures/*' skipped EVERY
  # directory named fixtures anywhere in the tree — including the ones the plugin ships under
  # skills/ — so a real violation planted in skills/compass-visual/fixtures/ read as 0 = PASS.
  # An exclusion wider than its reason is a hiding place.
  # Exclude exactly ONE directory: the one the pattern file in use actually lives in, which is the
  # only reason an exclusion exists (the pattern would otherwise match itself).
  # Two wrong versions preceded this. `*/fixtures/*` skipped every directory named fixtures in the
  # tree, hiding real violations under skills/. Anchoring it to "$P/scripts/fixtures" then made the
  # exclusion absolute to the REAL plugin — so it could never apply to the self-test's temp tree,
  # and the runner's own self-test went red while the exclusion looked more precise. Deriving it
  # from "$pat" makes it precise AND correct wherever the runner is pointed.
  local fxdir; fxdir="$(cd "$(dirname "$pat")" 2>/dev/null && pwd || echo "/nonexistent")"
  local files; files="$(find -L "$@" -type f -not -path "$fxdir/*" 2>/dev/null)"
  if [ -z "$files" ]; then rm -f "$clean"; echo 0; return; fi
  out="$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -IEhf "$clean" 2>/dev/null)"; rc=$?
  rm -f "$clean"
  if [ "$rc" -gt 1 ]; then echo "ERR-grep-$rc"; return; fi
  [ -z "$out" ] && { echo 0; return; }
  printf '%s\n' "$out" | wc -l | tr -d ' '
}
count_re() { # <ere> <path...>
  local re="$1"; shift
  local p seen=0
  for p in "$@"; do
    [ -e "$p" ] || continue
    [ -r "$p" ] || { echo "ERR-unreadable-target"; return; }
    # Existence is not content: an existing-but-empty file yields 0 = the pass target (R2-9).
    if [ -f "$p" ]; then [ -s "$p" ] && seen=1; else seen=1; fi
  done
  # Nothing to search is NOT the same as nothing found. Reporting 0 here would be the vacuous
  # class this whole runner exists to kill.
  [ "$seen" = 1 ] || { echo "ERR-no-target"; return; }
  # The SAME three fixes count_matches has, which this sibling never received:
  #  · exclude only the runner's own fixtures dir, not every directory named `fixtures` (a planted
  #    violation in skills/compass-visual/fixtures/ read PASS here while INV-5 caught it);
  #  · `find -L`, because BSD `grep -R` does not descend a bare symlinked dir — the dev-checkout
  #    layout — so a symlinked commands/ hid a real violation;
  #  · never report a count when the search could not run.
  # Fixing one helper and not its twin in the same file is how a fix looks complete and is not.
  local out rc files
  files="$(find -L "$@" -type f -not -path "$P/scripts/fixtures/*" 2>/dev/null)"
  if [ -z "$files" ]; then echo 0; return; fi
  out="$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -IEh -- "$re" 2>/dev/null)"; rc=$?
  if [ "$rc" -gt 1 ]; then echo "ERR-grep-$rc"; return; fi
  [ -z "$out" ] && { echo 0; return; }
  printf '%s\n' "$out" | wc -l | tr -d ' '
}

# ── INV-2 BUTTONS — the typed lock phrase must be gone ────────────────────────
# The WHOLE plugin, not one file. This greped `skills/contract/SKILL.md` alone, so planting the
# typed lock phrase in shared/gate.md, commands/go.md or skills/plan/SKILL.md read value=0 PASS —
# the same three directories INV-5 was widened to cover in round 2, while INV-2 was left behind.
# Widening one invariant and not its siblings is how a fix looks complete and is not.
# The literal lives in ONE place — a fixture inside the excluded directory — and both this runner
# and the smoke suite read it from there. Writing it inline made the assertion match its own
# definition: widening INV-2 from one file to the plugin turned it RED on the two lines that
# SEARCH for the phrase. That is the fifth time in this build that prose re-introduced the thing
# it removes. A pattern that can match its own source is a pattern that reports its author.
emit INV-2 "$(count_re "$(cat "$P/scripts/fixtures/lockphrase.txt")" "$P")" 0

# ── INV-5 PORTABLE — no macOS-only / personal delivery path anywhere ──────────
# Pattern lives in a fixture OUTSIDE the searched tree is impossible here (the fixture must ship
# with the plugin), so the search explicitly excludes the fixtures dir — finding R3-1.
# Search the WHOLE plugin, not a hand-listed subset. The list said scripts/hooks/skills and the
# plugin ships FIVE top-level dirs — `shared/` (the byte-locked gate text every stage inherits) and
# `commands/` (the front door a user actually types) were never searched at all, so four planted
# violations read value=0 PASS. A hand-maintained list of places to look is a list that goes stale
# the first time someone adds a directory; INV-5's property is about the plugin, so search the
# plugin. `_scope_dirs` below fails loudly if the top-level shape changes underneath it.
emit INV-5 "$(count_matches "$P/scripts/fixtures/portable/pattern.txt" "$P" 2>/dev/null)" 0

# ── INV-6 ONE-DOCUMENT — generated artefacts are body fragments ───────────────
# Is this first line a full document rather than a fragment? Its own function so the self-test can
# exercise the DECISION directly. When _frag_violations was rescoped to render fresh (step 10), the
# self-test rows that planted BOM/whitespace files silently stopped reaching this logic — they kept
# passing while testing nothing.
# A `^<!doctype` anchor is defeated by a UTF-8 BOM or by leading whitespace, both legal HTML and
# both produced by ordinary editors, and the full document then reads as a compliant fragment.
_is_document() { # <first-line>
  local first="${1-}"
  first="${first#$'\xef\xbb\xbf'}"
  first="$(printf '%s' "$first" | sed 's/^[[:space:]]*//')"
  grep -qi '^<!doctype\|^<html' <<<"$first"
}

# INV-6 could not go red. It fed `head -1` to _is_document, and EVERY page gen.mjs emits begins
# with a <title> line — so the doctype anchor was unreachable for any output the generator can
# actually produce, and the five self-test rows never noticed because they feed _is_document a
# line in isolation. A document marker anywhere in the head is a document; scan the head.
_frag_violations() {
  # SCOPE: what the CURRENT generator emits — not every .html that has ever existed under
  # .claude/builds. Artefacts written by v0.29 are legitimately full documents; counting them
  # made INV-6 unclearable without rewriting historical build records, which would be falsifying
  # the archive to make a gate go green. The invariant is "gen.mjs emits fragments", so generate
  # fresh and check those.
  local gen="$P/skills/compass-visual/gen.mjs"
  [ -f "$gen" ] || { echo "ERR-no-generator"; return; }
  command -v node >/dev/null 2>&1 || { echo "ERR-no-node"; return; }
  local src="" b
  for b in "$ROOT"/.claude/builds/*/contract.md; do [ -f "$b" ] && { src="$(dirname "$b")"; break; }; done
  [ -n "$src" ] || { echo "ERR-no-build-to-render"; return; }
  local d n=0 seen=0 head_ v
  d="$(mktemp -d)"
  # ALL FIVE shipped views, not four: `review` was never drift- or fragment-checked at all.
  for v in brief brief-body plan-map release-card review; do
    node "$gen" "$src" "$v" --out "$d/$v.html" >/dev/null 2>&1 || continue
    [ -s "$d/$v.html" ] || continue
    seen=$((seen+1))
    # Scan the WHOLE page for a document wrapper, not line 1 and not a fixed head window.
    # Two wrong versions preceded this. `head -1` could never fire, because every page gen.mjs
    # emits opens with a <title> line — the doctype anchor sat where the check never looked, and
    # INV-6 could not go red for ANY generator output. `head -20` then missed it too: the wrapper
    # lands after the inlined CSS, hundreds of lines down. The property is "this page is a body
    # FRAGMENT", and a document wrapper anywhere in it breaks that, so look everywhere — minus
    # code samples, where such a tag is content a reader is meant to see rather than markup.
    # NO PIPE INTO `grep -q`. This file runs under `set -o pipefail`, and `grep -q` exits the
    # instant it matches — which SIGPIPEs the upstream `sed`, making the pipeline return 141, which
    # the `if` reads as "no match". The failure is perfectly inverted: it only happens when there
    # IS an early match, i.e. exactly when the check should fire, and only on files big enough that
    # sed still has data to write (all five real pages are 20-45 KB). Every previous version of
    # INV-6 was defeated by its anchor; this one was defeated by its plumbing, and both looked
    # identical from outside: value=0 PASS. Capture first, match with a here-string.
    local _pg
    _pg="$(sed -e 's/<code>[^<]*<\/code>/ /g' "$d/$v.html" 2>/dev/null | tr -d '\r')"
    if grep -qiE '<!doctype|<html[ >]|<head[ >]|</head>|<body[ >]' <<<"$_pg"; then n=$((n+1)); fi
  done
  rm -rf "$d"
  # Nothing rendered is NOT the same as everything compliant — and neither is SOME rendered.
  # A view that fails to render was silently skipped: breaking the release card outright still
  # read value=0 PASS because the other four views rendered and `seen` only had to be > 0. A view
  # that cannot render is a defect, not an exemption from the check.
  [ "$seen" -gt 0 ] || { echo "ERR-nothing-rendered"; return; }
  [ "$seen" -eq 5 ] || { echo "ERR-only-$seen-of-5-views-rendered"; return; }
  echo "$n"
}
emit INV-6 "$(_frag_violations)" 0

# ── INV-9 NO-JARGON — the copy gate, scoped to the reader-copy block ─────────
_copy_gate_state() {
  local sh="$P/scripts/compass.sh" fx="$P/scripts/fixtures/copy"
  [ -f "$sh" ] || { echo "ERR-no-compass-sh"; return; }
  [ -f "$fx/jargon.txt" ] && [ -f "$fx/positive-control.txt" ] || { echo "ERR-no-copy-fixtures"; return; }
  local d; d="$(mktemp -d)"
  { echo '```compass-reader-copy'; tail -7 "$fx/positive-control.txt"; echo '```'; } > "$d/dirty.md"
  { echo '```compass-reader-copy'; cat "$fx/clean.txt" 2>/dev/null; echo '```'; } > "$d/clean.md"
  local bad=0
  bash "$sh" copy-gate "$d/dirty.md" >/dev/null 2>&1 && bad=$((bad+1))   # must FAIL
  bash "$sh" copy-gate "$d/clean.md" >/dev/null 2>&1 || bad=$((bad+1))   # must PASS
  rm -rf "$d"; echo "$bad"
}
emit INV-9 "$(_copy_gate_state)" 0

# ── INV-11 DESIGN-PINNED — asserted on the OUTPUT, not by grepping the source ──
# The source grep was a PROXY and it false-positived on `breakColors`, a SANITISER whose regexes
# match hex by design, while missing anything composed at runtime. The property is "every colour
# and face in the generated artefact comes from the pinned token file" — so check the artefact.
# anti-drift-grep already normalises hex/rgb/rgba/hsl before comparing, so an off-theme rgb()
# cannot slip past a hex-only pattern.
_theme_drift() {
  local gen="$P/skills/compass-visual/gen.mjs" theme="$P/skills/compass-visual/themes/compass-artefact.json"
  local drift="$P/skills/rk-house-style/gates/anti-drift-grep.mjs"
  for f in "$gen" "$theme" "$drift"; do [ -f "$f" ] || { echo "ERR-missing-$(basename "$f")"; return; }; done
  command -v node >/dev/null 2>&1 || { echo "ERR-no-node"; return; }
  # The build dir was HARD-CODED to one slug. Archive, rename or gc that build — or run this in any
  # other repo — and every render silently `continue`d, leaving n=0, which IS the pass target. The
  # invariant reported PASS while checking nothing: gutting the theme file entirely still read
  # "value=0 PASS". Discover a real build dir, and count what was actually rendered.
  local bdir=""
  for cand in "$ROOT"/.claude/builds/*/; do
    [ -f "$cand/contract.md" ] || continue
    bdir="$cand"
    # prefer a build that carries a reader-copy block, so the render exercises the real path
    grep -q 'compass-reader-copy' "$cand/contract.md" 2>/dev/null && break
  done
  [ -n "$bdir" ] || { echo "ERR-no-build-dir"; return; }
  local d out n=0 seen=0
  d="$(mktemp -d)"
  # ALL FIVE shipped views. This rendered brief-body and plan-map only, so three of five pages
  # were never drift-checked at all: making `review` emit #ff00ff and Comic Sans still read
  # value=0 PASS. gen.mjs already exports the view list; there was never a reason to hand-pick two.
  for v in brief brief-body plan-map release-card review; do
    node "$gen" "$bdir" "$v" --out "$d/$v.html" >/dev/null 2>&1 || continue
    [ -s "$d/$v.html" ] || continue
    seen=$((seen+1))
    out="$(node "$drift" "$d/$v.html" "$theme" 2>&1 || true)"
    case "$out" in *"0 off-theme"*) : ;; *) n=$((n+1)) ;; esac
  done
  rm -rf "$d"
  # The same guard _frag_violations has — including the part that was NOT copied across when
  # _frag_violations moved to `seen == 5`. This stayed on `> 0`, so breaking one view left the
  # other four to report value=0 PASS with `review` never drift-checked at all.
  [ "$seen" -gt 0 ] || { echo "ERR-nothing-rendered"; return; }
  [ "$seen" -eq 5 ] || { echo "ERR-only-$seen-of-5-views-rendered"; return; }
  echo "$n"
}
emit INV-11 "$(_theme_drift)" 0

# ── self-test: prove each guard actually fires (INV-0 applied to the runner itself) ──
if [ -n "${SELFTEST:-}" ]; then
  t="$(mktemp -d)"; fail=0
  mkdir -p "$t/plugins/compass/scripts/fixtures/portable" "$t/plugins/compass/skills" "$t/plugins/compass/hooks"
  # the positive control must travel with the pattern — the guard reads it as a sibling
  # BOTH controls. The self-test copied only the first, so once a missing variants.txt became an
  # ERR (correctly — an absent control is a check that stopped running), the harness started
  # failing on its own incomplete setup rather than on anything real.
  cp "$P/scripts/fixtures/portable/positive-control.txt" "$t/plugins/compass/scripts/fixtures/portable/" 2>/dev/null || true
  cp "$P/scripts/fixtures/portable/variants.txt" "$t/plugins/compass/scripts/fixtures/portable/" 2>/dev/null || true
  chk() { # <label> <expected-substring> <actual>
    case "$3" in
      *"$2"*) printf '  ok   %s\n' "$1" ;;
      *)      printf '  FAIL %s (got: %s)\n' "$1" "$3"; fail=1 ;;
    esac
  }
  chk "missing pattern file → ERR (not 0)" "ERR-no-pattern-file" \
     "$(count_matches "$t/nope.txt" "$t/plugins/compass/scripts")"
  : > "$t/plugins/compass/scripts/fixtures/portable/pattern.txt"
  chk "EMPTY pattern file → ERR (not 0)" "ERR-empty-pattern" \
     "$(count_matches "$t/plugins/compass/scripts/fixtures/portable/pattern.txt" "$t/plugins/compass/scripts")"
  printf '   \n' > "$t/blank.txt"
  chk "blank-only pattern → ERR (not 0)" "ERR-blank-pattern" "$(count_matches "$t/blank.txt" "$t/plugins")"
  chk "no search target → ERR (not 0)" "ERR-no-target" "$(count_re 'x' "$t/does-not-exist")"
  cp "$P/scripts/fixtures/portable/pattern.txt" "$t/plugins/compass/scripts/fixtures/portable/pattern.txt"
  chk "fixture excluded from its own search" "0" \
     "$(count_matches "$t/plugins/compass/scripts/fixtures/portable/pattern.txt" "$t/plugins/compass/scripts")"
  # positive control — the half INV-0 was missing (R3-1/R3-2)
  printf 'zzzz-no-such-string\n' > "$t/plugins/compass/scripts/fixtures/portable/pattern.txt"
  chk "substituted pattern → ERR (control stops matching)" "ERR-control-not-matched" \
     "$(count_matches "$t/plugins/compass/scripts/fixtures/portable/pattern.txt" "$t/plugins/compass/scripts")"
  perl -pe 's/\n/\r\n/' "$P/scripts/fixtures/portable/pattern.txt" > "$t/plugins/compass/scripts/fixtures/portable/pattern.txt" 2>/dev/null
  mkdir -p "$t/real/contract"; tail -4 "$P/scripts/fixtures/portable/positive-control.txt" > "$t/real/contract/SKILL.md"
  rm -rf "$t/plugins/compass/skills"; ln -s "$t/real" "$t/plugins/compass/skills"
  chk "CRLF pattern file still matches (CR stripped)" "4" \
     "$(count_matches "$t/plugins/compass/scripts/fixtures/portable/pattern.txt" "$t/plugins/compass/skills")"
  cp "$P/scripts/fixtures/portable/pattern.txt" "$t/plugins/compass/scripts/fixtures/portable/pattern.txt"
  chk "symlinked dir IS descended (find -L, not grep -R)" "4" \
     "$(count_matches "$t/plugins/compass/scripts/fixtures/portable/pattern.txt" "$t/plugins/compass/skills")"
  # INV-6 normalisation — these exercise _is_document DIRECTLY. They used to plant files for
  # _frag_violations, which stopped reading them when it was rescoped to render fresh (step 10):
  # the rows kept passing while testing nothing, which is the exact class this build removes.
  _doc() { _is_document "$1" && echo document || echo fragment; }
  chk "BOM before doctype is still a document" "document" "$(_doc "$(printf '\xef\xbb\xbf<!doctype html>')")"
  chk "leading whitespace before doctype ditto" "document" "$(_doc '   <!doctype html>')"
  chk "bare <html> with no doctype ditto" "document" "$(_doc '  <html lang="en">')"
  chk "a genuine fragment is not a document" "fragment" "$(_doc '<style>x</style>')"
  chk "CRLF doctype is still a document" "document" "$(_doc "$(printf '<!doctype html>\r')")"
  rm -rf "$t"
  [ "$fail" = 0 ] && echo "self-test: all guards fire" || echo "self-test: FAILED"
  exit "$fail"
fi

# ── v0.31 (R4-C7): the gold checks existed for three review rounds and NOTHING CALLED THEM. Every
# baseline in that build was a number a human ran by hand, which is the same defect class as a gate
# that is never invoked. They run here now, so their exit codes gate like every other invariant.
#
# They cost ~24s (140 pages rendered twice), so they are behind --with-gold rather than in the 0.9s
# default path. `--assert-red` / `--assert-pass` still see them when the flag is on, and CI/ship use
# the flag. A skipped check is NEVER reported as a pass: without the flag they are not emitted at
# all, so nothing can read their absence as green.
if [ -n "${WITH_GOLD:-}" ]; then
  _gout="$(bash "$P/scripts/proven-numbers.sh" "$ROOT" 2>&1)"; _grc=$?
  _g="$(printf '%s\n' "$_gout" | grep '^dirs=' | tail -1)"
  # The gold's EXIT CODE carries every structural guard the counters do not: checksum drift, the
  # page/dir/distinct/token pins, the split, and every diagnostic line. Reading only the counters
  # meant a tampered build dir reported all-PASS.
  emit "INV-GOLD-EXIT" "$_grc" 0
  printf '%s\n' "$_gout" | grep -E '^gold: (ERR|[a-z-]+ )' | sed 's/^/    /' || true
  _val() { printf '%s' "$_g" | tr ' |' '\n\n' | sed -n "s/^$1=//p" | head -1; }
  # Row names ARE the contract's invariant ids, so `redfirst-check` can tie evidence to an
  # invariant. `GOLD-*` was a private naming no gate could read, and bare `INV-1`/`INV-2` collided
  # with ids this runner already uses.
  for _k in unmarked mismatch bogus noblock unsaid nested mislabelled badprov fabricated; do
    _v="$(_val "$_k")"
    case "$_k" in
      unmarked|nested|mislabelled) _n=INV-MARKED ;;
      unsaid)                      _n=INV-DISCLOSED ;;
      mismatch|bogus|noblock|badprov|fabricated) _n=INV-DECLARED ;;
      *)                           _n=INV-MARKED ;;
    esac
    emit "$_n" "${_v:-ERR-no-value}" 0
  done
  # The DECLARED half, on real rendered pages. R6-C8/R7 both found `mismatch`/`bogus` had never
  # scored one — their only witness was a unit test of the auditor by itself.
  _dc=0; bash "$P/scripts/declared-check.sh" "$ROOT" >/dev/null 2>&1 || _dc=1
  emit "INV-DECLARED" "$_dc" 0
  _d="$(bash "$P/scripts/defeat-corpus-check.sh" "$ROOT" 2>&1 | sed -n 's/.*), \([0-9][0-9]*\) failing.*/\1/p' | tail -1)"
  emit "INV-REFUSE" "${_d:-ERR-no-value}" 0
  emit "INV-CORPUS" "${_d:-ERR-no-value}" 0
  # The auditors' own controls: a checker whose controls are not all firing is not a checker.
  _ac=0; node "$P/scripts/page-audit.mjs" --controls >/dev/null 2>&1 || _ac=1
  _rc=0; node "$P/scripts/page-number.mjs" --controls >/dev/null 2>&1 || _rc=1
  emit "INV-CONTROLS" "$_ac" 0
  emit "INV-CONTROLS" "$_rc" 0
fi

if [ -n "${WANT_JSON:-}" ]; then
  printf '[%s]\n' "$(IFS=,; echo "${rows[*]}")"
fi

# ── exit contract (R2-3) — the header claimed "their exit codes are the evidence" while the
# script always exited 0, so nothing could ever gate on it. Now it can:
#   --assert-red   every assertion must be RED   (INV-0: pre-change, proves each can fail)
#   --assert-pass  every assertion must be PASS  (acceptance: the work is done)
# Any ERR-* value is neither and always fails both, by construction.
n_red=0; n_pass=0; n_err=0
for r in "${rows[@]}"; do
  case "$r" in *'"verdict":"RED"'*) n_red=$((n_red+1)) ;; *) n_pass=$((n_pass+1)) ;; esac
  case "$r" in *'"value":"ERR'*) n_err=$((n_err+1)) ;; esac
done
case "${MODE:-}" in
  assert-red)
    [ "$n_pass" -eq 0 ] || { echo "assert-red: $n_pass assertion(s) already at target — decoration, not a check" >&2; exit 1; }
    [ "$n_err"  -eq 0 ] || { echo "assert-red: $n_err assertion(s) returned ERR — precondition broken" >&2; exit 1; }
    echo "assert-red: all $n_red assertions RED (each proven able to fail)" ;;
  assert-pass)
    [ "$n_err" -eq 0 ] || { echo "assert-pass: $n_err assertion(s) returned ERR — precondition broken" >&2; exit 1; }
    [ "$n_red" -eq 0 ] || { echo "assert-pass: $n_red assertion(s) still RED" >&2; exit 1; }
    echo "assert-pass: all $n_pass assertions at target" ;;
esac
exit 0
