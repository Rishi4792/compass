#!/usr/bin/env bash
# spawn-smoke.sh — Compass v0.10.0 Phase-0 (S0) feasibility gate for F6 cross-session spawn.
# Proves the DETACH MECHANISM (nohup + background, parent exits, child survives & writes a
# sentinel) and reports whether the `claude` CLI is present. It deliberately does NOT launch a
# real recursive `claude -p` (that is runtime-only, behind --auto opt-in + budget guardrails —
# triggering a self-spawning agent from a build/test is exactly the runaway risk we guard against).
#
# Exit 0  → F6=full: the real `nohup claude -p` launch line may ship in S5.
# Exit 3  → F6=degraded: claude not found OR detach mechanism unavailable → S5 ships GUARD logic
#           only (refusals/cap/no-bypass) + a LOUD stop; the real launch line is omitted.
set -euo pipefail

verdict_full() { echo "SPAWN-SMOKE: PASS — claude present + detach mechanism works → F6=full"; exit 0; }
verdict_degraded() { echo "SPAWN-SMOKE: DEGRADED — $1 → F6=degraded (loud-stop-only)"; exit 3; }

# (a) is the claude CLI available for a real spawn?
claude_present=0
if command -v claude >/dev/null 2>&1; then claude_present=1; fi

# (b) detach mechanism: nohup a background child that writes a sentinel AFTER this shell would
#     return; confirm the parent can fire-and-forget and the child's write lands.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
sentinel="$tmp/sentinel"
# child writes the sentinel; redirect ALL output (mirrors S5's stdout discipline).
nohup sh -c 'sleep 0.2; printf ok > "$0"' "$sentinel" >/dev/null 2>&1 &
child=$!
# parent does not wait on the child's work loop; poll briefly for the detached write.
detached_ok=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  [ -f "$sentinel" ] && [ "$(cat "$sentinel" 2>/dev/null || true)" = "ok" ] && { detached_ok=1; break; }
  sleep 0.1
done
wait "$child" 2>/dev/null || true

if [ "$detached_ok" -ne 1 ]; then verdict_degraded "nohup detach did not produce the sentinel"; fi
if [ "$claude_present" -ne 1 ]; then verdict_degraded "claude CLI not on PATH"; fi
verdict_full
