#!/usr/bin/env bash
# Smoke test for compass.sh — legacy gates + the parallel-builds keystone.
# Runs in a throwaway repo whose path contains SPACES and PARENS (the K-17 case).
# Usage: bash compass.smoke.sh   (exits non-zero if any assertion fails)
set -uo pipefail
SH="$(cd "$(dirname "$0")" && pwd)/compass.sh"
T="/tmp/compass-smoke (paren)/repo"; rm -rf "/tmp/compass-smoke (paren)"; mkdir -p "$T"; cd "$T"
git init -q; git config user.email t@t.t; git config user.name t
mkdir -p "src/(dash)/active" src/email; echo a > "src/(dash)/active/p.tsx"; echo b > src/email/c.tsx; echo lk > package-lock.json
git add -A; git commit -qm init
mkdir -p .claude/builds
printf '%s\n' "cc · g · status=plan-LOCKED" "em · g · status=plan-LOCKED" > .claude/builds/INDEX

pass=0; fail=0
chk(){ if [ "$1" = "$2" ]; then echo "✓ $3"; pass=$((pass+1)); else echo "✗ $3 (got $1 want $2)"; fail=$((fail+1)); fi; }

# ── legacy teeth ──
mkdir -p .claude/builds/cc
printf '## RECEIPT — contract · cc · PASS\n- [x] ok\n' > .claude/builds/cc/receipts.md
( bash "$SH" gate .claude/builds/cc contract >/dev/null 2>&1 ); chk "$?" "0" "gate PASSES a complete receipt"
printf '## RECEIPT — contract · cc · PASS\n- [ ] missing\n' > .claude/builds/cc/receipts.md
( bash "$SH" gate .claude/builds/cc contract >/dev/null 2>&1 ); chk "$?" "1" "gate BLOCKS an unchecked box"
( bash "$SH" reconcile 974.88 974.88 0.1 >/dev/null 2>&1 ); chk "$?" "0" "reconcile within tolerance"
( bash "$SH" reconcile 638 974.88 0.1 >/dev/null 2>&1 ); chk "$?" "1" "reconcile FAILS out of tolerance"

# ── keystone ──
chk "$(bash "$SH" state-root)" "$T/.claude/builds" "state-root resolves to main checkout"
bash "$SH" install-guard >/dev/null
WT_CC="$(bash "$SH" worktree cc 2>/dev/null | tail -1)"
WT_EM="$(bash "$SH" worktree em 2>/dev/null | tail -1)"
chk "$(basename "$WT_CC")" "cc" "worktree created for cc"
( cd "$WT_CC" && bash "$SH" assert-worktree cc >/dev/null 2>&1 ); chk "$?" "0" "assert-worktree PASSES inside worktree"
( cd "$T" && bash "$SH" assert-worktree cc >/dev/null 2>&1 ); chk "$?" "1" "assert-worktree FAILS in main checkout"
( cd "$WT_CC" && bash "$SH" claim cc "src/(dash)/active/*" package-lock.json >/dev/null 2>&1 )
( cd "$WT_EM" && bash "$SH" claim em "src/email/*" "src/(dash)/active/*" package-lock.json >/dev/null 2>&1 )
( cd "$WT_CC" && bash "$SH" check-overlap cc >/dev/null 2>&1 ); chk "$?" "1" "check-overlap BLOCKS unacked overlap"
mkdir -p .claude/builds/.locks; printf '%s\n%s\n' "ack:cc+em:package-lock.json" "ack:cc+em:src/(dash)/active/p.tsx" >> .claude/builds/.locks/acks
( cd "$WT_CC" && bash "$SH" check-overlap cc >/dev/null 2>&1 ); chk "$?" "0" "check-overlap PASSES once acked"
( cd "$WT_CC" && echo x > src/email/c.tsx && git add src/email/c.tsx && git commit -qm bad >/dev/null 2>&1 ); chk "$?" "1" "guard BLOCKS out-of-claim commit in worktree"
( cd "$WT_CC" && git reset -q HEAD . && git checkout -q -- . 2>/dev/null )
( cd "$WT_CC" && echo y >> "src/(dash)/active/p.tsx" && git add "src/(dash)/active/p.tsx" && git commit -qm good >/dev/null 2>&1 ); chk "$?" "0" "guard ALLOWS in-claim commit in worktree"
( cd "$T" && echo z >> "src/(dash)/active/p.tsx" && git add "src/(dash)/active/p.tsx" && git commit -qm main >/dev/null 2>&1 ); chk "$?" "1" "guard BLOCKS main-checkout commit of a claimed file"
( cd "$T" && git reset -q HEAD . && git checkout -q -- . 2>/dev/null )
( bash "$SH" check-db-isolation cc 1 0 >/dev/null 2>&1 ); chk "$?" "1" "db-isolation REFUSES schema change w/o provision when others active"
( bash "$SH" check-db-isolation cc 1 1 >/dev/null 2>&1 ); chk "$?" "0" "db-isolation ALLOWS schema change WITH provision"
sed -i.bak 's/status=plan-LOCKED/status=CLOSED/' .claude/builds/INDEX
bash "$SH" gc >/dev/null 2>&1
git worktree list --porcelain | grep -qxF "worktree $WT_CC"; chk "$?" "1" "gc REMOVES terminal-build worktree"

echo "──────── $pass passed, $fail failed ────────"
cd /; rm -rf "/tmp/compass-smoke (paren)" 2>/dev/null
[ "$fail" = 0 ]
