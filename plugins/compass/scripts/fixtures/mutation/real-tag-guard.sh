#!/usr/bin/env bash
# Self-contained mutation-check dogfood target (v0.22.0, RP2-M4).
# A tiny, dependency-free real-tag validator PLUS its own assertions — it needs no git, no sibling
# script, and no repo layout, so a copy of it runs correctly inside mutation-check's temp sandbox
# (a compass.sh subcommand can NOT: it needs git + sibling scripts absent in the sandbox).
# Running `bash real-tag-guard.sh` self-tests the guard and exits 0 iff the guard is intact.
# mutation-check's dogfood recipe deletes the GUARD line (the break) and re-runs this red: with the
# discriminating line gone, is_real_tag can never accept a real tag, so the assertions fail (exit 1)
# — proving the mutation gate actually BITES on a real guard, not decorative scaffolding.
set -u

is_real_tag() {
  case "$1" in
    v[0-9]*.[0-9]*.[0-9]*) return 0 ;;   # GUARD: only a vX.Y.Z shape is a real release tag
  esac
  return 1
}

# assertions (the "red"): a real tag is accepted; HEAD / a branch are rejected.
is_real_tag v1.2.3 || exit 1
is_real_tag HEAD    && exit 1
is_real_tag main    && exit 1
exit 0
