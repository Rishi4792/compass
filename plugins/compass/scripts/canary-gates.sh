#!/usr/bin/env bash
# v0.32.0 S35 — §12's CANARY: no historical build may be newly refused by a gate this build adds.
#
# WHY THIS EXISTS AS A SCRIPT AND NOT A SENTENCE. Compass has shipped this mistake before: v0.28's
# mode-gate armed on a MISSING header and refused 25 of 26 existing builds. §12 makes the pinned
# corpus the canary and says any historical build a new gate would newly refuse is a RELEASE
# BLOCKER, not a fixture to delete. A promise like that needs a run, and the run needs a record —
# so this prints one, and `--record <file>` writes it.
#
# WHAT IT RUNS: every gate v0.32 adds or changes, over every build folder on the tree, in every
# lifecycle stage the seam takes. It is read-only: no gate here writes to a build.
#
# Usage: canary-gates.sh [<repo-root>] [--record <file>]
# Exit: 0 nothing newly refused · 1 at least one refusal · 2 usage/no builds.
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
case "$ROOT" in --*) ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)" ;; *) shift 2>/dev/null || true ;; esac
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "canary-gates: cannot resolve root"; exit 2; }
REC=""; SAMPLE=0
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --record) [ $# -ge 2 ] || { echo "canary-gates: --record needs a value" >&2; exit 2; }
              REC="$2"; shift 2 ;;
    # A SAMPLE, for the suite. The full run is 374 gate calls and 41.7 seconds — it pushed the smoke
    # suite from 39s to 59.1s, past the 50.2s ceiling the contract states. Coverage is MOVED, not
    # deleted: the suite runs a sample every time and the RELEASE runs all of it. A sample says so
    # in its own output, so nobody can read it as the complete canary.
    --sample) [ $# -ge 2 ] || { echo "canary-gates: --sample needs a value" >&2; exit 2; }
              SAMPLE="${2:-6}"; shift 2 ;;
    --builds) [ $# -ge 2 ] || { echo "canary-gates: --builds needs a value" >&2; exit 2; }
              BUILDS_OVERRIDE="$2"; export BUILDS_OVERRIDE; shift 2 ;;
    --self-check) SELFCHECK=1; shift ;;
    *) shift ;;
  esac
done
case "$SAMPLE" in ''|*[!0-9]*) SAMPLE=0 ;; esac
SH="$ROOT/plugins/compass/scripts/compass.sh"
[ -f "$SH" ] || { echo "canary-gates: no compass.sh at $SH"; exit 2; }

# The gates v0.32 ADDS or CHANGES. Anything not in this list is untouched by this build and is not
# this canary's business — a canary that re-runs everything cannot tell a new refusal from an old one.
# Determined from `git show <v0.31 tag>:compass.sh` rather than from memory: these five functions
# did not exist before v0.32, and perf-budget-gate's rule changed in S22.
GATES="engine-gate review-disclose-gate cockpit-gate stage-end-gate perf-budget-gate"
# DELIBERATELY EXCLUDED, and said out loud rather than quietly dropped:
#   · progress-gate — it existed before v0.32 and this build did not change it. Its refusals on 9
#     legacy folders are pre-existing behaviour; a canary that cannot tell a NEW refusal from an old
#     one reports 41 problems and hides the one that matters.
#   · copy-gate — v0.32 changed it (S14), but it takes a FILE, not a build directory. It is
#     exercised over real files below instead of being fed a directory and refusing 30 times on a
#     usage error, which is what the first version of this script did.
EXCLUDED="progress-gate(pre-existing) copy-gate(takes-a-file,run-separately-below)"
STAGES="contract plan build review-contract review-plan review-build ship"

# ── THE POSITIVE CONTROL ──────────────────────────────────────────────────────────────────────
# `--self-check` plants a build that MUST be refused and requires this script to catch it. Without
# it, an independent reviewer deleted all three `refused=$((refused+1))` lines and the suite stayed
# green: "0 newly refused" was being asserted over a population where nothing refuses, which is the
# 0-out-of-0 shape this build has now named thirteen times.
if [ "${SELFCHECK:-0}" = 1 ]; then
  _sc="$(mktemp -d)"
  mkdir -p "$_sc/.claude/builds/planted-refuser"
  : > "$_sc/.claude/builds/planted-refuser/.compass-format"
  # A stamped build with a perf-budget carrying literals and NO run series behind them: S22 refuses
  # exactly this, so if the canary reports zero the canary is blind.
  printf '# c\n\nperf-budget: p95 latency 200 ms; peak-mem 256 MB; cost $0.00 per request; SLO healthy range 25-50s.\n' > "$_sc/.claude/builds/planted-refuser/contract.md"
  mkdir -p "$_sc/.claude/builds/ordinary"
  printf '# o\n\n**Status:** BUILDING\n' > "$_sc/.claude/builds/ordinary/progress.md"
  _sco="$(BUILDS_OVERRIDE="$_sc/.claude/builds" "$0" "$ROOT" --builds "$_sc/.claude/builds" 2>&1 || true)"
  _scn="$(printf '%s' "$_sco" | sed -nE 's/^canary-gates: .* · ([0-9]+) newly refused.*/\1/p' | head -1)"
  if [ "${_scn:-0}" -lt 1 ]; then
    echo "canary-gates: SELF-CHECK FAILED — a build planted to be refused was reported as 0 newly refused. The canary cannot see a refusal, so its zero means nothing."
    exit 1
  fi
  echo "canary-gates: self-check PASSED — a planted refusing build is caught (${_scn} refusal(s)), so a zero from this script is a measurement rather than a shape."
  rm -rf "$_sc"
  exit 0
fi

BUILDS="${BUILDS_OVERRIDE:-$ROOT/.claude/builds}"
[ -d "$BUILDS" ] || { echo "canary-gates: no .claude/builds at $BUILDS — nothing to canary. That is an ERR, not a pass: this directory is gitignored, so an empty run on a clean clone would otherwise read as 'nothing newly refused'."; exit 2; }
n_b=0; for d in "$BUILDS"/*/; do [ -d "$d" ] && n_b=$((n_b+1)); done
[ "$n_b" -gt 0 ] || { echo "canary-gates: ERR - zero build folders. An empty canary proves nothing."; exit 2; }

# A SAMPLE THAT ALWAYS TAKES THE SAME SIX IS NOT A SAMPLE. Alphabetical order put both
# `.compass-format` builds — the ONLY folders the new perf rule actually grades — outside it, so a
# refusal in either could never be seen by the suite. Worse, the refusal this canary found on its
# first run was in one of them. Every STAMPED build is always included; the rest fill the quota.
# NEWLINE-SEPARATED, NOT SPACE-SEPARATED. This repo lives under "Claude Code Projects", so a
# space-joined list word-splits every path: the canary ran 2 gate calls instead of 374. That is the
# defect that had just been found in the hook, committed again minutes later in another file.
_ordf="$(mktemp)"
for d in "$BUILDS"/*/; do [ -d "$d" ] && [ -f "$d/.compass-format" ] && printf '%s\n' "$d"; done > "$_ordf"
for d in "$BUILDS"/*/; do [ -d "$d" ] && [ ! -f "$d/.compass-format" ] && printf '%s\n' "$d"; done >> "$_ordf"

out=""; refused=0; calls=0; seen=0
while IFS= read -r d; do
  [ -n "$d" ] && [ -d "$d" ] || continue
  seen=$((seen+1))
  [ "$SAMPLE" -gt 0 ] && [ "$seen" -gt "$SAMPLE" ] && continue
  slug="$(basename "$d")"
  for g in $GATES; do
    calls=$((calls+1))
    if msg="$(bash "$SH" "$g" "$d" 2>&1)"; then :; else
      refused=$((refused+1))
      out="$out
  REFUSED $slug · $g · $(printf '%s' "$msg" | head -1 | cut -c1-140)"
    fi
  done
  # ...and the SEAM, which is what a real lifecycle crosses. A gate can pass standalone and refuse
  # here, or never be reached at all — both were real defects in this build.
  for st in $STAGES; do
    calls=$((calls+1))
    msg="$(bash "$SH" gate "$d" "$st" 2>&1 || true)"
    case "$msg" in
      *"engine-gate FAILED"*|*"review-disclose-gate FAILED"*|*"review-evidence-gate FAILED"*|*"perf-budget-gate FAILED"*|*"no RUN SERIES behind them"*|*"records no 'engine:' line"*|*"say nothing about independence"*)
        refused=$((refused+1))
        out="$out
  REFUSED $slug · gate/$st · $(printf '%s' "$msg" | head -1 | cut -c1-140)" ;;
    esac
  done
done < "$_ordf"
rm -f "$_ordf"

# copy-gate over real FILES — the argument it actually takes. Every reader-copy block on the tree.
#
# THE POPULATION WAS THE WHOLE PROBLEM. This said "every reader-copy block on the tree" and globbed
# ONE level of fixtures plus SKILL.md, so it graded 3 files and reported "0 refused" for a change
# that refuses SIXTEEN build contracts. A canary whose population excludes the thing that changed
# cannot see the change — it was green by construction. Real contracts live in .claude/builds, which
# is where the reader-copy blocks actually are, so they are swept here too.
cg_n=0; cg_bad=0
for f in "$ROOT/plugins/compass/scripts/fixtures"/*/*.md "$ROOT/plugins/compass/skills"/*/SKILL.md "$ROOT/.claude/builds"/*/contract.md; do
  [ -f "$f" ] || continue
  grep -q 'compass-format\|reader-copy\|## Reader copy' "$f" 2>/dev/null || continue
  cg_n=$((cg_n+1)); calls=$((calls+1))
  if ! msg="$(bash "$SH" copy-gate "$f" 2>&1)"; then
    cg_bad=$((cg_bad+1)); refused=$((refused+1))
    out="$out
  REFUSED $(basename "$(dirname "$f")")/$(basename "$f") · copy-gate · $(printf '%s' "$msg" | head -1 | cut -c1-140)"
  fi
done

_scope="all $n_b build folders"
if [ "$SAMPLE" -gt 0 ] && [ "$SAMPLE" -lt "$n_b" ]; then
  _scope="a SAMPLE of $SAMPLE of $n_b build folders (every .compass-format build first, since those are the only ones the new rules grade) — this is NOT the full canary; the release must run it without --sample"
fi
report="canary-gates: $calls gate calls over $_scope · $refused newly refused
  gates run  : $GATES
  excluded   : $EXCLUDED
  copy-gate  : $cg_n file(s) carrying a reader-copy block, $cg_bad refused"
[ -n "$out" ] && report="$report$out"
printf '%s\n' "$report"
if [ -n "$REC" ]; then
  { printf '# canary-gates run\n\n'; printf 'gates: %s\n' "$GATES"; printf 'stages: %s\n\n' "$STAGES"; printf '%s\n' "$report"; } > "$REC" 2>/dev/null \
    && printf 'canary-gates: recorded to %s\n' "$REC"
fi
[ "$refused" -eq 0 ] || exit 1
exit 0
