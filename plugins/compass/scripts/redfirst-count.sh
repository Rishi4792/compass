#!/usr/bin/env bash
# v0.32 S20 — RE-RUN every recorded RED, and require it to still go red.
#
# WHY THIS EXISTS. `compass.sh redfirst-check` asks whether a red-first record was machine-produced.
# It cannot ask whether the record is still TRUE. Counting rows in a markdown file proves nothing:
# a fix can be reverted, an anchor can move, and the record sits there reading like evidence.
#
# So each reproduction is a small tracked file carrying two things: a MUTATION that puts the defect
# back, and an ASSERT that must pass on a healthy tree and FAIL on the mutated one. Both directions
# are required, and that is the point — an assert that fails on the healthy tree is broken, and one
# that passes on the mutated tree is not testing what it claims.
#
# The reproductions are TRACKED (`fixtures/redfirst/repro/`), so a clean clone can run them. The
# narrative record (`red-first-evidence.md`) lives in the gitignored build state and is for people;
# this is the part a machine can re-run.
#
# Exit: 0 every reproduction still reproduces · 1 one or more do not · 2 setup error.
set -uo pipefail
ROOT="${1:-.}"; ROOT="$(cd "$ROOT" && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPRO="$HERE/fixtures/redfirst/repro"
[ -d "$REPRO" ] || { echo "redfirst-count: ERR - no reproductions at $REPRO"; exit 2; }
have=0; for f in "$REPRO"/*.sh; do [ -f "$f" ] && have=1; done
[ "$have" = 1 ] || { echo "redfirst-count: ERR - zero reproductions. An empty registry proves nothing and is never a pass."; exit 2; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
n=0; bad=0
for f in "$REPRO"/*.sh; do
  [ -f "$f" ] || continue
  n=$((n+1))
  REPRO_ID=""; REPRO_WHAT=""
  unset -f repro_mutate repro_assert 2>/dev/null || true
  # shellcheck disable=SC1090
  . "$f" || { echo "  FAIL $(basename "$f") - does not source"; bad=$((bad+1)); continue; }
  id="${REPRO_ID:-$(basename "$f" .sh)}"
  if ! declare -f repro_mutate >/dev/null || ! declare -f repro_assert >/dev/null; then
    echo "  FAIL $id - must define repro_mutate() and repro_assert()"; bad=$((bad+1)); continue
  fi

  # DIRECTION 1 — GREEN on the tree as it stands. An assert that cannot pass is not a check.
  if ! repro_assert "$ROOT" >/dev/null 2>&1; then
    echo "  FAIL $id - its assert does NOT pass on the current tree, so the fix it records is GONE or the assert is broken."
    echo "         $REPRO_WHAT"
    bad=$((bad+1)); continue
  fi

  # DIRECTION 2 — RED once the defect is put back. This is the half a markdown row cannot give you.
  work="$TMP/$id"; mkdir -p "$work/plugins/compass"
  cp -R "$ROOT/plugins/compass/." "$work/plugins/compass/" 2>/dev/null
  if ! repro_mutate "$work" >"$TMP/$id.mut.log" 2>&1; then
    echo "  FAIL $id - the recorded mutation no longer applies (the code moved under it): $(tail -1 "$TMP/$id.mut.log")"
    bad=$((bad+1)); continue
  fi
  if repro_assert "$work" >/dev/null 2>&1; then
    echo "  FAIL $id - PUTTING THE DEFECT BACK DID NOT GO RED. The record reads like evidence and is not."
    echo "         $REPRO_WHAT"
    bad=$((bad+1)); continue
  fi
  echo "  ok   $id - still reproduces: green on this tree, RED with the defect put back"
done

echo "redfirst-count: $n reproductions re-run, $bad failing"
exit $([ "$bad" -eq 0 ] && echo 0 || echo 1)
