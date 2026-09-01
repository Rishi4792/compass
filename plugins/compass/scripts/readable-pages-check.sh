#!/usr/bin/env bash
# readable-pages-check.sh — renders the in-scope Compass views over a fixture corpus and reports,
# per (page, metric), a figure and the population it was counted over.
#
# WHY IT REPORTS RATHER THAN GATES. Twenty-four independent reviewers across three rounds showed
# every mechanical zero-target on this surface either fires on correct work or is green on day one:
# most internal codes on a Compass page are VERIFY commands and file paths, which ARE the proof a
# reader needs; most (page, metric) pairs are legitimately empty; half the escaped tags are correct
# <code> quotations. So the counts inform, and the thing that gates readability is two people who
# did not write the page saying what it means.
#
# WHY IT RENDERS RATHER THAN SCANS. A disk scan measures pages made by older generators, and most
# HTML under a build folder was never produced by this generator at all. Rendering from a fixture is
# the only way a figure describes today's code.
#
# Usage:
#   readable-pages-check.sh [ROOT] [--corpus DIR] [--metric NAME] [--controls-only] [--help]
#
# Exit codes, defined here because an earlier draft used one code for three meanings:
#   0  ran; every MEASURE line passed (today every line is REPORT, so a clean run is 0)
#   1  a MEASURE line failed, or --controls-only found a control that stopped failing
#   2  usage
#   3  ERR — no verdict could be produced: the corpus is absent or empty, or a fixture would not
#      render. NOT a pass. See mechanical-suite wiring in the build plan: the suite has no ERR
#      channel today, so how this code reaches it is a decision that step records rather than
#      leaves to whoever runs it.
set -uo pipefail

ROOT="."; CORPUS=""; METRIC=""; CONTROLS_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --corpus)        CORPUS="${2:-}"; shift 2 ;;
    --metric)        METRIC="${2:-}"; shift 2 ;;
    --controls-only) CONTROLS_ONLY=1; shift ;;
    --*)             echo "readable-pages-check: unknown flag '$1'" >&2; exit 2 ;;
    *)               ROOT="$1"; shift ;;
  esac
done

cd "$ROOT" 2>/dev/null || { echo "readable-pages-check: cannot enter '$ROOT'" >&2; exit 2; }
[ -d plugins/compass ] || { echo "readable-pages-check: not a compass repo root" >&2; exit 2; }

D="plugins/compass/scripts"
GEN="plugins/compass/skills/compass-visual/gen.mjs"
MEASURE="$D/readable-pages-measure.mjs"
[ -z "$CORPUS" ] && CORPUS="$D/fixtures/pages"

# THE FOUR IN-SCOPE VIEWS. `review` left scope by the contract's own amendment: its content is
# derived from a findings ledger that does not exist when a contract locks, so contract-time reader
# copy cannot honestly serve it. Naming them in ONE place is deliberate — a set hand-typed at each
# use is how this build shipped three separate wrong populations.
VIEWS="brief brief-body plan-map release-card"

command -v node >/dev/null 2>&1 || { echo "readable-pages-check: ERR — node is required to render a page and is not on PATH."; echo "readable-pages-check: ERR (node absent)"; exit 3; }
[ -f "$MEASURE" ] || { echo "readable-pages-check: ERR — the measurer $MEASURE is missing."; echo "readable-pages-check: ERR (measurer absent)"; exit 3; }

# ── the corpus ──────────────────────────────────────────────────────────────────────────────────
# An absent corpus is an ERR, never a green. Three MEASURE rules in an earlier draft of this build's
# contract bound "the fixture corpus" while no such thing existed anywhere on disk.
if [ ! -d "$CORPUS" ]; then
  echo "readable-pages-check: ERR — no corpus at '$CORPUS'. Nothing was measured."
  echo "readable-pages-check: ERR (no corpus at $CORPUS)"
  exit 3
fi

MANIFEST="$CORPUS/MANIFEST"
FIXTURES=""
if [ -f "$MANIFEST" ]; then
  FIXTURES="$(LC_ALL=C sed -nE 's/^([a-z0-9-]+)[[:space:]]+[0-9a-f]{16}.*$/\1/p' "$MANIFEST")"
  # ── THE PINS ARE NOW VERIFIED. They were written and never checked: the sha was used only as a
  # format filter, so the integrity of a corpus created BECAUSE of a near-miss leak rested on a
  # comment. Two independent reviewers found it, and the repo's own doctrine says it in one line —
  # `cap-enforce-check.sh:2`, "a cap nobody checks is a wish".
  _pin_bad=""
  while IFS= read -r _ln; do
    case "$_ln" in ''|\#*) continue ;; esac
    _sl="$(printf '%s' "$_ln" | awk '{print $1}')"; _want="$(printf '%s' "$_ln" | awk '{print $2}')"
    [ -d "$CORPUS/$_sl" ] || { _pin_bad="$_pin_bad $_sl(absent)"; continue; }
    _got="$(cat "$CORPUS/$_sl"/*.md 2>/dev/null | shasum -a 256 | cut -c1-16)"
    [ "$_got" = "$_want" ] || _pin_bad="$_pin_bad $_sl(pin=$_want got=$_got)"
  done < "$MANIFEST"
  if [ -n "$_pin_bad" ]; then
    echo "readable-pages-check: ERR — a fixture no longer matches its pin:$_pin_bad"
    echo "readable-pages-check: ERR (corpus pin mismatch —$_pin_bad)"
    exit 3
  fi
else
  FIXTURES="$(cd "$CORPUS" 2>/dev/null && ls -1d */ 2>/dev/null | sed 's#/$##')"
fi
[ -n "$FIXTURES" ] || {
  echo "readable-pages-check: ERR — the corpus at '$CORPUS' names no fixture."
  echo "readable-pages-check: ERR (corpus names no fixture)"
  exit 3
}

# CONTROLS are the fixtures asserted to FAIL. They are NOT in the measured set: an earlier draft put
# them in one population with the pages being measured, which made a green require the controls to
# stop failing while the same section said that must ERR — unreachable by construction.
is_control() { case "$1" in ctl-*) return 0 ;; *) return 1 ;; esac; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
rendered=0; render_failed=0; err_pairs=0; measured_pairs=0; measure_failed=0
ctl_total=0; ctl_still_failing=0
OUT="$TMP/lines.tsv"; : > "$OUT"

printf '── readable pages ───────────────────────────────────────────────────\n'
for fx in $FIXTURES; do
  dir="$CORPUS/$fx"
  [ -d "$dir" ] || { echo "  ERR   fixture '$fx' is named in MANIFEST and absent on disk"; render_failed=$((render_failed+1)); continue; }
  if [ "$CONTROLS_ONLY" = 1 ] && ! is_control "$fx"; then continue; fi
  if [ "$CONTROLS_ONLY" = 0 ] && is_control "$fx"; then ctl_total=$((ctl_total+1)); fi
  for v in $VIEWS; do
    page="$TMP/$fx-$v.html"
    if ! node "$GEN" "$dir" "$v" --out "$page" >/dev/null 2>&1; then
      echo "  ERR   $fx/$v did not render"
      render_failed=$((render_failed+1)); continue
    fi
    rendered=$((rendered+1))
    if [ -n "$METRIC" ]; then
      node "$MEASURE" "$page" "$fx/$v" --metric "$METRIC" >> "$OUT" 2>/dev/null || true
    else
      node "$MEASURE" "$page" "$fx/$v" >> "$OUT" 2>/dev/null || true
    fi
  done
done

# ── report, one line per (page, metric), figure beside its population ───────────────────────────
while IFS=$'\t' read -r pg metric verdict figure population; do
  [ -n "${pg:-}" ] || continue
  case "$verdict" in
    ERR)     err_pairs=$((err_pairs+1));     printf '  ERR   %-28s %-6s %5s  %s\n' "$pg" "$metric" "$figure" "$population" ;;
    MEASURE) measured_pairs=$((measured_pairs+1))
             if [ "${figure:-0}" != "0" ]; then measure_failed=$((measure_failed+1)); printf '  FAIL  %-28s %-6s %5s  %s\n' "$pg" "$metric" "$figure" "$population"
             else printf '  ok    %-28s %-6s %5s  %s\n' "$pg" "$metric" "$figure" "$population"; fi ;;
    *)       measured_pairs=$((measured_pairs+1))
             if is_control "${pg%%/*}" && [ "${figure:-0}" != "0" ]; then ctl_still_failing=$((ctl_still_failing+1)); fi
             printf '  rep   %-28s %-6s %5s  %s\n' "$pg" "$metric" "$figure" "$population" ;;
  esac
done < "$OUT"

printf '─────────────────────────────────────────────────────────────────────\n'

# ── verdict ─────────────────────────────────────────────────────────────────────────────────────
if [ "$CONTROLS_ONLY" = 1 ]; then
  # COUNT CONTROLS, NOT LINES, AND NOTICE A MISSING ONE. This counted failing LINES, so neutralising
  # two of three controls left the third's lines carrying the total and the run still said "as
  # required" — and a control DELETED FROM DISK did the same, because render_failed was never read.
  _want_ctl="$(printf '%s\n' $FIXTURES | grep -c '^ctl-' || true)"
  _got_ctl="$(LC_ALL=C awk -F'\t' '$4+0 > 0 {split($1,a,"/"); print a[1]}' "$OUT" | grep '^ctl-' | sort -u | grep -c . || true)"
  if [ "$render_failed" -gt 0 ]; then
    echo "readable-pages-check: ERR — $render_failed control render(s) failed; a control that will not render proves nothing."
    echo "readable-pages-check: ERR (control render failure)"
    exit 3
  fi
  if [ "${_got_ctl:-0}" != "${_want_ctl:-0}" ]; then
    echo "readable-pages-check: ERR — ${_got_ctl:-0} of ${_want_ctl:-0} control(s) still fail their class. A control that stopped failing is a check that stopped checking."
    echo "readable-pages-check: ERR (${_got_ctl:-0} of ${_want_ctl:-0} controls failing)"
    exit 3
  fi
  echo "readable-pages-check: all ${_want_ctl} control(s) still fail their own class, each counted once, over $rendered render(s)."
  exit 1
fi
if [ "$render_failed" -gt 0 ]; then
  echo "readable-pages-check: ERR — $render_failed of $((rendered+render_failed)) render(s) failed; no verdict over an incomplete corpus."
  exit 3
fi
if [ "$rendered" -eq 0 ]; then
  echo "readable-pages-check: ERR — nothing rendered. An empty population is not a pass."
  exit 3
fi
# A metric that ERRs on EVERY page it applies to has lost its mechanism, not its data. Deleting the
# region stamp made all 40 `codes` lines ERR and this script still exited 0, the suite still said
# 10 of 10, and smoke still passed 1010. `err_pairs` was counted, printed, and never tested.
_metrics="$(LC_ALL=C awk -F'\t' '{print $2}' "$OUT" | sort -u | grep -v '^$' || true)"
_dead=""
for _m in $_metrics; do
  _tot="$(LC_ALL=C awk -F'\t' -v m="$_m" '$2==m' "$OUT" | grep -c . || true)"
  _err="$(LC_ALL=C awk -F'\t' -v m="$_m" '$2==m && $3=="ERR"' "$OUT" | grep -c . || true)"
  [ "${_tot:-0}" -gt 0 ] && [ "${_err:-0}" = "${_tot:-0}" ] && _dead="$_dead $_m"
done
if [ -n "$_dead" ]; then
  echo "readable-pages-check: ERR — these metric(s) reported NOTHING BUT ERR on every page:$_dead"
  echo "  A metric that never measures anywhere has lost the mechanism it reads, not merely its data."
  echo "readable-pages-check: ERR (metric(s) dead everywhere:$_dead)"
  exit 3
fi
if [ "$measure_failed" -gt 0 ]; then
  echo "readable-pages-check: $measure_failed MEASURE line(s) failed over $rendered render(s) of $(printf '%s' "$VIEWS" | wc -w | tr -d ' ') view(s)."
  exit 1
fi
echo "readable-pages-check: $measured_pairs reported and $err_pairs empty-population ERR(s) over $rendered render(s) across $(printf '%s' "$FIXTURES" | wc -w | tr -d ' ') fixture(s); every count REPORTS — the cold read is what gates."
exit 0
