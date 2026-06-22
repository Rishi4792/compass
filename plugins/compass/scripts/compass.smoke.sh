#!/usr/bin/env bash
# Smoke test for compass.sh — legacy gates + the parallel-builds keystone.
# Runs in a throwaway repo whose path contains SPACES and PARENS (the K-17 case).
# Usage: bash compass.smoke.sh   (exits non-zero if any assertion fails)
set -uo pipefail
SH="$(cd "$(dirname "$0")" && pwd)/compass.sh"
T="/tmp/compass-smoke (paren)/repo"; rm -rf "/tmp/compass-smoke (paren)"; mkdir -p "$T"; cd "$T"
export COMPASS_WORKTREE_HOME="/tmp/compass-smoke (paren)/.worktrees"   # v0.6.0: never pollute the real ~/.compass
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

# ── v0.5.0: design-fidelity gate + status (the anti-ceremony teeth) ──
FX="$(cd "$(dirname "$SH")" && pwd)/fixtures/design-drift"
# status prints the where-am-I fields
mkdir -p .claude/builds/s5
printf '%s\n%s\n%s\n' '**Status:** building' '**Stage:** ⑤ build step 3/18' '**Next:** S4 — run `compass.sh design-style-diff`' > .claude/builds/s5/progress.md
( bash "$SH" status .claude/builds/s5 >/dev/null 2>&1 ); chk "$?" "0" "status exits 0"
chk "$(bash "$SH" status .claude/builds/s5 2>/dev/null | grep -c 'Next:')" "1" "status prints the Next action"
# design-style-diff — both directions + missing-token + usage error (the catch-the-drift proof)
( bash "$SH" design-style-diff "$FX/mockup.html" "$FX/build-faithful.html" --accent >/dev/null 2>&1 ); chk "$?" "0" "design-style-diff PASSES the faithful build"
( bash "$SH" design-style-diff "$FX/mockup.html" "$FX/build-drifted.html" --accent >/dev/null 2>&1 ); chk "$?" "1" "design-style-diff CATCHES a real token drift"
( bash "$SH" design-style-diff "$FX/mockup.html" "$FX/build-missing.html" --accent >/dev/null 2>&1 ); chk "$?" "1" "design-style-diff CATCHES a missing token"
( bash "$SH" design-style-diff "$FX/mockup.html" "$FX/build-faithful.html" --nope >/dev/null 2>&1 ); chk "$?" "2" "design-style-diff usage-errors when token absent in REF"
# design-drift-gate — scope-aware ledger discipline
mkdir -p .claude/builds/lib1; printf '%s\n' "lib1 · g · status=draft · facets=library · touches=x" >> .claude/builds/INDEX
( bash "$SH" design-drift-gate .claude/builds/lib1 >/dev/null 2>&1 ); chk "$?" "0" "drift-gate N/A pass for a non-web build with no ledger"
mkdir -p .claude/builds/web1; printf '%s\n' "web1 · g · status=draft · facets=web+pipeline · touches=x" >> .claude/builds/INDEX
( bash "$SH" design-drift-gate .claude/builds/web1 >/dev/null 2>&1 ); chk "$?" "1" "drift-gate FAILS a design-scoped build with NO ledger (back-door closed)"
printf '%s\n%s\n%s\n' '# dl' '<!-- design-review: complete -->' '| D1 | x | MAJOR | y | OPEN |' > .claude/builds/web1/design-ledger.md
( bash "$SH" design-drift-gate .claude/builds/web1 >/dev/null 2>&1 ); chk "$?" "1" "drift-gate FAILS an OPEN design-drift row (one drift = FAIL)"
printf '%s\n%s\n%s\n' '# dl' '<!-- design-review: complete -->' '| D1 | x | MAJOR | y | FIXED |' > .claude/builds/web1/design-ledger.md
( bash "$SH" design-drift-gate .claude/builds/web1 >/dev/null 2>&1 ); chk "$?" "0" "drift-gate PASSES a complete + resolved ledger"
# converge-gate — both ledgers must be clean
( bash "$SH" converge-gate .claude/builds/web1 >/dev/null 2>&1 ); chk "$?" "0" "converge-gate PASSES when correctness + design both clean"
printf '%s\n' "| C1 | x | MAJOR | y | OPEN |" >> .claude/builds/web1/review-ledger.md
( bash "$SH" converge-gate .claude/builds/web1 >/dev/null 2>&1 ); chk "$?" "1" "converge-gate FAILS an open correctness Critical/Major"

# ── v0.6.0: elegant parallel builds (centralized home + identification + merge-consequence) ──
# INV-1: worktree lands in the centralized home, NOT a project sibling
sib_before="$(ls -1d "$(dirname "$T")"/* 2>/dev/null | wc -l | tr -d ' ')"
WT_V6="$(bash "$SH" worktree v6a 2>/dev/null | tail -1)"
case "$WT_V6" in "$COMPASS_WORKTREE_HOME"/*) chk 0 0 "worktree lands in centralized home (not a sibling)";; *) chk 1 0 "worktree in home (got $WT_V6)";; esac
chk "$(ls -1d "$(dirname "$T")"/* 2>/dev/null | wc -l | tr -d ' ')" "$sib_before" "no new project sibling dir created"
# INV-2: project-id = <basename>-<cksum digits>
( echo "$WT_V6" | grep -qE '/repo-[0-9]+/v6a$' ); chk "$?" "0" "project-id = basename-<cksum>"
# RC-2: base anchor recorded at creation
chk "$([ -f "$T/.claude/builds/.locks/v6a.base" ] && echo yes || echo no)" "yes" "base anchor recorded at worktree creation"
# INV-3: state-root resolves from inside the centralized worktree (normalize symlinks via pwd -P)
chk "$(cd "$WT_V6" && bash "$SH" state-root)" "$(cd "$T" && pwd -P)/.claude/builds" "state-root resolves from centralized worktree"
# INV-7: builds lists in-flight, not terminal
printf '%s\n%s\n' "v6live · g · status=plan-LOCKED" "v6done · g · status=SHIPPED" >> .claude/builds/INDEX
out="$(bash "$SH" builds 2>/dev/null)"
( echo "$out" | grep -q 'v6live' ); chk "$?" "0" "builds lists an in-flight build"
( echo "$out" | grep -q 'v6done' ); chk "$?" "1" "builds omits a terminal build"
# INV-8/9: post-merge-check vs a REAL origin (bare remote)
R="/tmp/compass-smoke (paren)/remote.git"; git init -q --bare "$R"
git remote add origin "$R" 2>/dev/null; git push -q origin HEAD:main 2>/dev/null
WT_PM="$(bash "$SH" worktree v6pm 2>/dev/null | tail -1)"   # base defaults to origin/main
( cd "$WT_PM" && bash "$SH" claim v6pm "src/email/*" >/dev/null 2>&1 )
( bash "$SH" post-merge-check v6pm >/dev/null 2>&1 ); chk "$?" "0" "post-merge-check: base current → 0"
( cd "$T" && echo adv > advfile.txt && git add advfile.txt && git commit -q -m adv >/dev/null 2>&1 && git push -q origin HEAD:main 2>/dev/null )
( bash "$SH" post-merge-check v6pm >/dev/null 2>&1 ); chk "$?" "1" "post-merge-check: origin/main advanced → 1 (must integrate)"
# no-upstream → graceful skip (exit 0)
( cd "$T" && git remote remove origin 2>/dev/null )
( bash "$SH" post-merge-check v6pm >/dev/null 2>&1 ); chk "$?" "0" "post-merge-check: no remote → graceful skip 0"
git remote add origin "$R" 2>/dev/null
# INV-4: doctor classifies managed vs stray (+main) — capture then match (avoid SIGPIPE under pipefail)
out_d="$(bash "$SH" doctor 2>/dev/null || true)"
case "$out_d" in *"[managed] v6a"*) chk 0 0 "doctor classifies a managed worktree" ;; *) chk 1 0 "doctor classifies a managed worktree" ;; esac
# INV-5/6: close is dirty-SAFE — a dirty worktree survives close (NEVER force-removed)
echo dirty > "$WT_V6/uncommitted.txt"
sed -i.bak 's/^v6a · /v6a · /' .claude/builds/INDEX 2>/dev/null; rm -f .claude/builds/INDEX.bak
( bash "$SH" close .claude/builds/v6a v6a --abandon >/dev/null 2>&1 )
( git worktree list --porcelain | grep -q '/v6a$' ); chk "$?" "0" "close LEAVES a dirty worktree (no force-remove — the v0.5.0 incident fix)"

# ── v0.9.1: namespaced stage wrappers + always-on gate (single canonical source) ──
PLUGIN_ROOT="$(cd "$(dirname "$SH")/.." && pwd)"
xblk(){ awk '/<!-- GATE:START -->/{f=1} f{print} /<!-- GATE:END -->/{f=0}' "$1"; }
GATE="$PLUGIN_ROOT/shared/gate.md"
STAGES="contract review-contract plan review-plan build review-build ship"
# INV-1: all 10 command files exist (3 commands + 7 stage wrappers), each with a non-empty description
c1=0; for c in start resume status $STAGES; do [ -f "$PLUGIN_ROOT/commands/$c.md" ] && c1=$((c1+1)); done
chk "$c1" "10" "INV-1 all 10 command files exist (3 commands + 7 stage wrappers)"
bd=0; for c in "$PLUGIN_ROOT"/commands/*.md; do grep -qE '^description: .+' "$c" || bd=$((bd+1)); done
chk "$bd" "0" "INV-1 every command has a non-empty description"
# INV-3: canonical gate defines 4 option labels + uses AskUserQuestion
gl=0; for l in Approve Revise Amend Pause; do grep -q "$l" "$GATE" && gl=$((gl+1)); done
chk "$gl" "4" "INV-3 canonical gate.md defines all 4 option labels"
( grep -q AskUserQuestion "$GATE" ); chk "$?" "0" "INV-3 canonical gate uses AskUserQuestion"
# INV-2: each of 7 stage skills presents the gate; old text-only tail removed (R2-01)
g2=0; for s in $STAGES; do grep -q AskUserQuestion "$PLUGIN_ROOT/skills/$s/SKILL.md" && g2=$((g2+1)); done
chk "$g2" "7" "INV-2 all 7 stage skills present the gate (AskUserQuestion)"
( grep -rq "; don't invoke it" "$PLUGIN_ROOT"/skills/*/SKILL.md ); chk "$?" "1" "INV-2 old text-only standalone-stop tail removed (R2-01)"
# INV-4: each wrapper delegates to its skill and adds no second gate
g4=0; for s in $STAGES; do w="$PLUGIN_ROOT/commands/$s.md"; if grep -q "compass:$s" "$w" && ! grep -q AskUserQuestion "$w"; then g4=$((g4+1)); fi; done
chk "$g4" "7" "INV-4 all 7 wrappers delegate to their skill with no double-gate"
# INV-7: canonical gate block byte-identical across 7 skills + start.md (8 consumers)
canon="$(xblk "$GATE")"
chk "$([ -n "$canon" ] && echo 1 || echo 0)" "1" "INV-7 canonical gate block is non-empty (no vacuous match)"
g7=0; for t in skills/contract/SKILL.md skills/review-contract/SKILL.md skills/plan/SKILL.md skills/review-plan/SKILL.md skills/build/SKILL.md skills/review-build/SKILL.md skills/ship/SKILL.md commands/start.md; do
  [ "$(xblk "$PLUGIN_ROOT/$t")" = "$canon" ] && g7=$((g7+1))
done
chk "$g7" "8" "INV-7 canonical gate block byte-identical across 7 skills + start.md"
# RECONCILE: stage wrappers == 7 AND gated stage-skills == 7 (gold=7, exact)
rw=0; for s in $STAGES; do [ -f "$PLUGIN_ROOT/commands/$s.md" ] && rw=$((rw+1)); done
chk "$rw" "7" "RECONCILE stage-wrapper count == 7 (gold)"
chk "$g2" "7" "RECONCILE gated stage-skill count == 7 (gold)"

echo "──────── $pass passed, $fail failed ────────"
cd /; rm -rf "/tmp/compass-smoke (paren)" 2>/dev/null
[ "$fail" = 0 ]
