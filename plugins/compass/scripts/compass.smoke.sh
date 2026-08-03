#!/usr/bin/env bash
# Smoke test for compass.sh — legacy gates + the parallel-builds keystone.
# Runs in a throwaway repo whose path contains SPACES and PARENS (the K-17 case).
# Usage: bash compass.smoke.sh   (exits non-zero if any assertion fails)
set -uo pipefail
SH="$(cd "$(dirname "$0")" && pwd)/compass.sh"
SMOKE_TMP="$(mktemp -d)"; SMOKE_BASE="$SMOKE_TMP/compass-smoke (paren)"   # unique per run (R3 fix:
# the fixed /tmp path let concurrent runs rm -rf each other's live sandbox — recon flaked); the
# parens/space stay in the path so the quoting coverage is retained.
T="$SMOKE_BASE/repo"; mkdir -p "$T"; cd "$T"
export COMPASS_WORKTREE_HOME="$SMOKE_BASE/.worktrees"   # v0.6.0: never pollute the real ~/.compass
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
R="$SMOKE_BASE/remote.git"; git init -q --bare "$R"
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

# ── v0.10.0 --auto autonomous loop wiring ──
disp=0; for c in auto-precheck auto-init budget-init budget-check check-session-chain fire-g2 auto-spawn can-advance; do
  grep -qE "^[[:space:]]+$c\)" "$SH" && disp=$((disp+1)); done
chk "$disp" "8" "v0.10 all 8 --auto subcommands wired in dispatch"
chk "$([ -f "$PLUGIN_ROOT/scripts/spawn-smoke.sh" ] && echo 1 || echo 0)" "1" "v0.10 spawn-smoke.sh present (S0 feasibility gate)"
chk "$(grep -q 'auto-closed:' "$SH" && echo 1 || echo 0)" "1" "v0.10 lifecycle-audit G-L2 accepts the auto-closed marker"
chk "$(grep -lq 'Autonomous mode' "$PLUGIN_ROOT/commands/start.md" && echo 1 || echo 0)" "1" "v0.10 start.md documents --auto autonomous mode"
chk "$(grep -lq 'budget.env\|NO JSON\|line-oriented' "$PLUGIN_ROOT/scripts/compass.sh" && echo 1 || echo 0)" "1" "v0.10 state is line-oriented (budget.env, no JSON)"

# ── v0.11.0 autonomous self-spawn wiring ──
d11=0; for c in fire-g1 gate-clear auto-start stage-continuable; do grep -qE "^[[:space:]]+$c\)" "$SH" && d11=$((d11+1)); done
chk "$d11" "4" "v0.11 all 4 new subcommands wired in dispatch (fire-g1/gate-clear/auto-start/stage-continuable)"
# the reorder: the .auto-mode branch must appear BEFORE the gated `is_mid_build || continue` in stop-guard
am=$(grep -n 'sr/\$slug/.auto-mode' "$SH" | head -1 | cut -d: -f1); im=$(grep -n 'is_mid_build "\$sr/\$slug" || continue' "$SH" | head -1 | cut -d: -f1)
chk "$([ -n "$am" ] && [ -n "$im" ] && [ "$am" -lt "$im" ] && echo 1 || echo 0)" "1" "v0.11 stop-guard: .auto-mode branch is BEFORE is_mid_build (fires at all stages — the fix)"
chk "$(grep -lq 'Gated or Autonomous' "$PLUGIN_ROOT/commands/start.md" && echo 1 || echo 0)" "1" "v0.11 start.md adds the interactive Gated/Autonomous prompt"
chk "$(grep -lq 'auto-start' "$PLUGIN_ROOT/commands/start.md" && echo 1 || echo 0)" "1" "v0.11 start.md documents the auto-start one-command trigger"

# ── v0.12.0 S6 (F-STATUS, contract: "asserted in smoke"): behavioral status-line asserts ──
FSD="$(mktemp -d)/fstat"; mkdir -p "$FSD"
printf '%s\n' '**Facets:** library' '**post-ship-loop:** on (clean 2 / cap 5)' > "$FSD/contract.md"
printf '**Status:** post-ship (round 1/5)\n' > "$FSD/progress.md"
printf '1|postship|1|CLEAN|aa|0\n' > "$FSD/loop.log"
: > "$FSD/.auto-suspended"
FSO="$(bash "$SH" status "$FSD" 2>/dev/null)"
chk "$(printf '%s' "$FSO" | grep -c 'Post-ship: round 1/5 · consecutive-clean 1/2 · open PS 0')" "1" "v0.12 F-STATUS: post-ship loop line renders (smoke, behavioral)"
chk "$(printf '%s' "$FSO" | grep -c 'auto: SUSPENDED (driver)')" "1" "v0.12 F-STATUS: suspended line renders (smoke, behavioral)"
rm -rf "$(dirname "$FSD")"

# ── v0.12.0 S8b: recon guard pinned-list content (the list is asserted, not just its mechanism) ──
for nm in INV-ENGINEFIX INV-GRAMMAR INV-PS-NOVERIFIER INV-PS-BUDGET INV-COLDGO INV-SUSPEND F-CONV F-STATUS INV-INTAKE INV-SKETCH INV-TEMPLATES INV-WIRED INV-WELCOME INV-BRIEF INV-LOCK INV-MODE INV-EXPLAIN INV-FEYNMAN INV-BUGBAR INV-REFUTE INV-DEDUPE INV-RESTORE INV-PARITY INV-FLAG INV-SECPIN INV-COMMSCAN INV-NO-LEAK INV-CANARY INV-BAKE INV-BURNRATE INV-WATCHER INV-ABORT INV-NA-EXPLICIT INV-BC INV-RBACSTRIDE-BLOCK INV-RBACSTRIDE-METHOD INV-RBACSTRIDE-RECEIPT INV-PLAN-RBAC INV-RBAC-NODEP INV-RBAC-BYTEINERT INV-EDGERACE-BLOCK INV-EDGERACE-METHOD INV-EDGERACE-RECEIPT INV-EDGERACE-BYTEINERT INV-PLAN-CONCURRENCY INV-PERFFMEA-BLOCK INV-PERFFMEA-METHOD INV-PERFFMEA-RECEIPT INV-PERFFMEA-BYTEINERT INV-PLAN-FMEA INV-SCHEMA-PIN INV-PERFBUDGET INV-CROSSTAB-BLOCK INV-CROSSTAB-METHOD INV-CROSSTAB-RECEIPT INV-CROSSTAB-BYTEINERT INV-PLAN-CROSSTAB INV-NA-CHALLENGE INV-EXPAND-CONTRACT INV-BACKFILL-RECON INV-ROLLBACK-FWDCOMPAT INV-GREEN-CI INV-PII-GATE INV-IMG-SECRET INV-PROGRAM-LEDGER INV-PROGRAM-ADVANCE-GUARD INV-PROGRAM-NEXT INV-PROGRAM-STALE INV-MUTATION-EXEC INV-MUTATION-RESTORE INV-REDGREEN; do
  chk "$(grep -cF "$nm" "$PLUGIN_ROOT/scripts/compass.recon.sh")" "1" "recon.sh pins INV group: $nm"
done
chk "$(grep -c 'FLOOR_SELFTEST=406' "$PLUGIN_ROOT/scripts/compass.recon.sh")" "1" "v0.16 recon.sh pins the selftest floor 406 (re-baselined for survive-cutover)"
chk "$(grep -c 'FLOOR_SMOKE=222' "$PLUGIN_ROOT/scripts/compass.recon.sh")" "1" "v0.16 recon.sh pins the smoke floor 222 (re-baselined for survive-cutover)"

# ── v0.13.0 S12 (P1/VZ-2 DURABLE template asserts): the contract skill must always carry ──
CSK="$PLUGIN_ROOT/skills/contract/SKILL.md"
chk "$(grep -c 'post-ship-loop: on (clean 2 / cap 5)' "$CSK")" "1" "v0.13 contract skill writes the post-ship-loop header for new builds (P1 durable)"
chk "$(grep -cF -- '- [x] post-ship-loop: <on (clean N / cap M)|off — reason>' "$CSK")" "1" "v0.13 contract skill pins the post-ship-loop receipt box (P1 durable)"
chk "$(grep -c 'cold-critic: on' "$CSK")" "1" "v0.13 contract skill writes cold-critic: on for web builds (VZ-2 durable header rule)"
chk "$(grep -c 'observation-channel:' "$CSK")" "1" "v0.13 contract skill writes the observation-channel declaration (durable)"

# ── v0.13.0 S14: INV-TEMPLATES — extract each SKILL-pinned template, instantiate via THE pinned ──
# placeholder map (alternations take their FIRST branch), feed its *_match parser via __match.
tpl() { # <skill-file> <template-name> — prints the template block (fenced lines, or one inline `…` line)
  awk -v m="<!-- TEMPLATE: $2 -->" '
    index($0,m)>0 { cap=1; next }
    cap && /^[[:space:]]*```/ { if (started) exit; next }
    cap && /<!-- TEMPLATE:/ { exit }
    cap {
      line=$0; sub(/^[[:space:]]*/,"",line)
      if (line=="" && !started) next
      if (line ~ /^`.*`.?$/) { gsub(/^`|`,?$/,"",line); print line; exit }   # inline backticked template
      if (started && line !~ /^#/ && line !~ /^-/) exit                       # prose after the block ends it
      print line; started=1
    }' "$1"
}
inst() { # THE pinned map (VZ-5): first-branch rule for alternations
  sed -e 's/<slug>/fixt/g' -e 's/<k>/1/g' -e 's/<CLEAN|MATERIAL>/CLEAN/g' -e 's/<GO|NO-GO>/GO/g'       -e 's/<git sha-12>/000000000000/g' -e 's/<sha>/000000000000/g'       -e 's/<PS ids>/PS-1-1/g' -e 's/<ISO ts>/2026-01-01T00:00:00Z/g'       -e 's/<command>/true/g' -e 's/<observed output>/OK/g'       -e 's|<prod url / system name — never a secret>|fixture-system|g'       -e 's|<dir>|/tmp/x|g' -e 's|<evidence path>|evidence/shot.png|g' -e 's/<facet>/library/g' -e 's/<capture-cmd>/true/g' -e 's|<file>|observe.txt|g'       -e 's/<on (clean N \/ cap M)|off — reason>/on (clean 1 \/ cap 5)/g'
}
SHIP="$PLUGIN_ROOT/skills/ship/SKILL.md"; BUILD="$PLUGIN_ROOT/skills/build/SKILL.md"; CSK2="$PLUGIN_ROOT/skills/contract/SKILL.md"
tpl "$SHIP" round-receipt | inst | bash "$SH" __match round_receipt_match
chk "$?" "0" "INV-TEMPLATES: ship round-receipt template (extracted+instantiated) accepted by round_receipt_match"
tpl "$SHIP" user-accepted | inst | bash "$SH" __match user_accepted_match
chk "$?" "0" "INV-TEMPLATES: user-accepted template accepted by user_accepted_match"
tpl "$BUILD" cold-critic-receipt | inst | bash "$SH" __match coldcritic_receipt_match
chk "$?" "0" "INV-TEMPLATES: cold-critic receipt template accepted by coldcritic_receipt_match"
tpl "$CSK2" postship-box | inst | bash "$SH" __match postship_box_match
chk "$?" "0" "INV-TEMPLATES: contract postship receipt box accepted by postship_box_match"
tpl "$CSK2" intake-box | inst | bash "$SH" __match intake_box_match
chk "$?" "0" "INV-TEMPLATES: contract intake receipt box accepted by intake_box_match"
tpl "$CSK2" sketch-box | inst | bash "$SH" __match sketch_box_match
chk "$?" "0" "INV-TEMPLATES: contract sketch receipt box accepted by sketch_box_match"
tpl "$SHIP" observation-box | inst | bash "$SH" __match observation_box_match
chk "$?" "0" "INV-TEMPLATES: ship observation box accepted by observation_box_match (the 7th pinned template)"

# ── v0.13.0 S14: INV-WIRED — every gate provably INVOKED (seam greps; behavioral pairs live in selftest) ──
ENG="$PLUGIN_ROOT/scripts/compass.sh"
chk "$(awk '/^cmd_gate\(\)/{f=1} f&&/cmd_intake_gate/{n++} f&&/^}/{exit} END{print n+0}' "$ENG")" "1" "INV-WIRED: cmd_gate contract seam invokes intake-gate"
chk "$(awk '/^cmd_gate\(\)/{f=1} f&&/cmd_sketch_gate/{n++} f&&/^}/{exit} END{print (n>=2)?1:0}' "$ENG")" "1" "INV-WIRED: cmd_gate invokes sketch-gate at BOTH contract + review-build seams"
chk "$(awk '/^cmd_lifecycle_audit\(\)/{f=1} f&&/cmd_loop_converged/{n++} f&&/^\}$/&&n{exit} END{print n+0}' "$ENG")" "1" "INV-WIRED: lifecycle-audit G-O1 invokes loop-converged"
chk "$(awk '/^cmd_loop_round\(\)/{f=1} f&&/^\}$/{f=0} f&&/cmd_budget_check/{n++} END{print n+0}' "$ENG")" "1" "INV-WIRED: loop-round owns the budget-check call"
chk "$(grep -c 'Post-ship: round' "$ENG")" "1" "INV-WIRED: cmd_status carries the loop line"
chk "$(grep -c 'coldgo-gate' "$PLUGIN_ROOT/skills/build/SKILL.md")" "1" "INV-WIRED: build skill invokes coldgo-gate (final web verify)"
chk "$(grep -c 'coldgo-gate' "$PLUGIN_ROOT/skills/review-build/SKILL.md")" "1" "INV-WIRED: review-build [C] invokes coldgo-gate"

# ── v0.14.0: bundled design system (neutralized) + generated gold + /compass:go front door ──
RK="$PLUGIN_ROOT/skills/rk-house-style"; CH="$PLUGIN_ROOT/skills/cinematic-hero"; REPO="$(cd "$PLUGIN_ROOT/../.." && pwd)"
CSKV="$PLUGIN_ROOT/skills/contract/SKILL.md"; BSKV="$PLUGIN_ROOT/skills/build/SKILL.md"; RTR="$PLUGIN_ROOT/commands/go.md"
# INV-BUNDLE — both skills ship with the plugin
chk "$([ -f "$CH/SKILL.md" ] && [ -f "$CH/template.html" ] && [ -f "$CH/render.sh" ] && echo 1 || echo 0)" "1" "v0.14 cinematic-hero bundled (SKILL+template+render)"
chk "$(grep -c '^name: cinematic-hero' "$CH/SKILL.md" 2>/dev/null)" "1" "v0.14 cinematic-hero frontmatter name"
chk "$([ -f "$RK/SKILL.md" ] && [ -f "$RK/SYSTEM.md" ] && [ -f "$RK/seeds-to-tokens.mjs" ] && echo 1 || echo 0)" "1" "v0.14 rk-house-style bundled (SKILL+SYSTEM+generator)"
chk "$([ -f "$RK/gates/anti-drift-grep.mjs" ] && [ -f "$RK/gates/compose-check.mjs" ] && echo 1 || echo 0)" "1" "v0.14 rk-house-style gates bundled"
chk "$([ -f "$RK/themes/neutral-indigo.json" ] && echo 1 || echo 0)" "1" "v0.14 neutral-indigo default theme present"
# INV-NEUTRAL — privacy, non-negotiable: zero GQ bytes in the bundled copy
chk "$(grep -rIiE 'grayquest|gq-stripe|gq_|my-performance|\bgq\b' "$RK" | wc -l | tr -d ' ')" "0" "v0.14 INV-NEUTRAL: 0 GQ strings in bundled rk-house-style (text only, incl. standalone GQ)"
chk "$([ -f "$RK/themes/gq-stripe-blue.json" ] && echo present || echo absent)" "absent" "v0.14 INV-NEUTRAL: private gq-stripe-blue theme absent"
chk "$(ls "$RK/gallery"/ref-*.png 2>/dev/null | wc -l | tr -d ' ')" "0" "v0.14 INV-NEUTRAL: real GQ gallery screenshots absent"
# INV-GOLD-EXISTS — the 3 neutral gold pages + PNGs
chk "$(ls "$RK/gallery"/*.html 2>/dev/null | wc -l | tr -d ' ')" "3" "v0.14 3 neutral gold HTML pages present"
chk "$(ls "$RK/gallery"/*.png 2>/dev/null | wc -l | tr -d ' ')" "3" "v0.14 3 neutral gold PNGs present"
# INV-CONTRACT-DESIGN
chk "$(grep -c 'Design aesthetic — ASK' "$CSKV")" "1" "v0.14 contract skill asks the design aesthetic"
chk "$( { grep -q 'rk-house-style' "$CSKV" && grep -q 'cinematic-hero' "$CSKV"; } && echo 1 || echo 0)" "1" "v0.14 contract skill routes to both bundled design skills"
# INV-BUILD-APPLIES
chk "$(grep -c 'Apply the design-standard' "$BSKV")" "1" "v0.14 build skill applies the design-standard on UI steps"
# INV-ROUTER
chk "$([ -f "$RTR" ] && echo 1 || echo 0)" "1" "v0.14 /compass:go router command exists"
chk "$(grep -c 'AskUserQuestion' "$RTR")" "1" "v0.14 router ALWAYS asks (AskUserQuestion)"
chk "$(grep -c '^description: .\+' "$RTR")" "1" "v0.14 router has a non-empty description"
chk "$(grep -cE 'INDEX|CURRENT|progress' "$RTR" | awk '{print ($1>=1)?1:0}')" "1" "v0.14 router reads build state"
chk "$(grep -c 'Edge states' "$RTR")" "1" "v0.14 router documents the edge states"
# INV-README
chk "$(grep -c 'simplest way in is .*compass:go' "$REPO/README.md")" "1" "v0.14.1 README leads with /compass:go"
chk "$(grep -c 'Every stage is still its own command' "$REPO/README.md")" "1" "v0.14 README keeps namespaced commands as advanced/optional"

# ── v0.15.0 slice ①: clarity/UX — welcome · compass-visual Brief · explicit lock · mode · explain · Feynman ──
GO15="$PLUGIN_ROOT/commands/go.md"; EXP15="$PLUGIN_ROOT/commands/explain.md"; VIS15="$PLUGIN_ROOT/skills/compass-visual"; CSK15="$PLUGIN_ROOT/skills/contract/SKILL.md"
# INV-WELCOME
chk "$(grep -c 'Welcome — how Compass works' "$GO15")" "1" "v0.15 INV-WELCOME: go.md carries the confidence welcome"
chk "$( { grep -q 'Contract-first' "$GO15" && grep -q 'assembly line' "$GO15"; } && echo 1 || echo 0)" "1" "v0.15 INV-WELCOME: go.md teaches the mental model (contract-first → assembly line)"
# INV-BRIEF (presence/structure + the pure-node house gates run below on the generated body; the PNG>5KB render stays build-time — Chrome not guaranteed on user machines)
chk "$([ -f "$VIS15/SKILL.md" ] && [ -f "$VIS15/gen.mjs" ] && echo 1 || echo 0)" "1" "v0.15 INV-BRIEF: compass-visual skill + gen.mjs bundled"
chk "$(grep -c '^name: compass-visual' "$VIS15/SKILL.md")" "1" "v0.15 INV-BRIEF: compass-visual frontmatter name"
VSMK="$(mktemp -d)/v"; mkdir -p "$VSMK"
printf '%s\n' '# Contract — vsmk' '## Goal & scope' 'A tiny fixture to exercise the generator.' '## Reconciliation' 'Numeric N/A.' '## Acceptance & INVARIANTs' '- **INV-X:** a bound.' '- **INV-Y:** guards the thing → CRITICAL. → *assert:* grep it.' '## Scope ladder' '- NOW: a' '- LATER: b' '- NEVER: c' > "$VSMK/contract.md"
node "$VIS15/gen.mjs" "$VSMK" brief-body --out "$VSMK/body.html" >/dev/null 2>&1
chk "$(head -1 "$VSMK/body.html" 2>/dev/null | grep -c '^<!doctype html>')" "1" "v0.15 INV-BRIEF/INV-NO-LEAK: generated body line-1 is doctype, not COMPASS-MOCK"
# INV-BRIEF durable house-gates (R3-M5): the pure-node gates run on the generated body IN THE SUITE (no Chrome)
RKG="$PLUGIN_ROOT/skills/rk-house-style"
( node "$RKG/gates/anti-drift-grep.mjs" "$VSMK/body.html" "$RKG/themes/neutral-indigo.json" >/dev/null 2>&1 ); chk "$?" "0" "v0.15 INV-BRIEF: generated brief-body passes rk-house-style anti-drift (durable gold, no Chrome)"
( node "$RKG/gates/compose-check.mjs" "$VSMK/body.html" >/dev/null 2>&1 ); chk "$?" "0" "v0.15 INV-BRIEF: generated brief-body passes rk-house-style compose-check (durable gold)"
# INV-BRIEF invariant completeness (R3-M2): keep the internal '→ CRITICAL', drop ONLY the '→ *assert:*' tail
node "$VIS15/gen.mjs" "$VSMK" brief --out "$VSMK/brief.html" >/dev/null 2>&1
chk "$( { grep -q 'INV-Y' "$VSMK/brief.html" && grep -q 'CRITICAL' "$VSMK/brief.html" && ! grep -q 'grep it' "$VSMK/brief.html"; } && echo 1 || echo 0)" "1" "v0.15 INV-BRIEF: Brief invariant summary keeps the binding '→ CRITICAL' tail and drops only the assert recipe"
# INV-BRIEF-LEAK (R3-M3 / R3-C2 regression): a shareable Brief with a gold FIGURE / never-show / secret HARD-STOPs, literals ABSENT
LKF="$(dirname "$VSMK")/leak"; mkdir -p "$LKF"
printf '%s\n' '# Contract — leak' '## Goal & scope' 'NAV $9,999,999.00 (42 crore), coverage 1.5 turns; partner AUM 12,00,000, FY rev 8 750 000 for the book; ops key sk-ABCD1234EFGH lives in the env.' '## Reconciliation' 'N/A for counts; gold = $9,999,999.00, i.e. 42 crore, coverage 1.5 turns, AUM 1,200,000, FY rev 8,750,000 (board-signed).' '## Security & data-sensitivity' 'never-show: SecretField' '## Acceptance & INVARIANTs' '- **INV-X:** a bound.' '## Scope ladder' '- NOW: a' '- LATER: b' '- NEVER: c' > "$LKF/contract.md"
( node "$VIS15/gen.mjs" "$LKF" brief --shareable --out "$LKF/share.html" >/dev/null 2>&1 ); chk "$?" "3" "v0.15 INV-BRIEF-LEAK: shareable Brief with gold figures (incl. 'N/A', a decimal, a comma-regrouped AND a SPACE-grouped restatement)/never-show/secret → HARD-STOP exit 3"
chk "$( { ! grep -q '9,999,999' "$LKF/share.html" && ! grep -q '42 crore' "$LKF/share.html" && ! grep -q '1\.5' "$LKF/share.html" && ! grep -q '12,00,000' "$LKF/share.html" && ! grep -q '8 750 000' "$LKF/share.html" && ! grep -qi 'SecretField' "$LKF/share.html" && ! grep -q 'sk-ABCD1234' "$LKF/share.html"; } && echo 1 || echo 0)" "1" "v0.15 INV-BRIEF-LEAK: shareable copy holds NEITHER the gold literals (currency/spelled-unit/decimal + comma-regrouped '12,00,000'↔'1,200,000' + SPACE-grouped '8 750 000'↔'8,750,000') NOR the never-show NOR the secret (R3-C2 + D2 + D1/D3 + D4-1 + R3-R5-D5-01)"
node "$VIS15/gen.mjs" "$LKF" brief --out "$LKF/local.html" >/dev/null 2>&1
chk "$( [ "$(grep -c '9,999,999' "$LKF/local.html")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.15 INV-BRIEF: the LOCAL Brief still renders the full gold literal (F-BRIEF two-variant, distinct from shareable)"
# INV-BRIEF security-card fidelity (post-ship PS-2-1): an N/A buried in a STRIDE/role line must NOT flip a
# PII/never-show block to a false green "no sensitive surface" badge (which would hide the binding surface).
SECF="$(dirname "$VSMK")/sec"; mkdir -p "$SECF" "$SECF/na"
printf '%s\n' '# c' '## Security & data-sensitivity' 'Per-field: card_pan (PII). never-show: card_pan. Role×view: guest → N/A. STRIDE-lite: Repudiation — N/A.' '## Goal & scope' 'x' '## Scope ladder' '- NOW: a' > "$SECF/contract.md"
node "$VIS15/gen.mjs" "$SECF" brief --out "$SECF/b.html" >/dev/null 2>&1
chk "$( { ! grep -q 'N/A — no sensitive surface' "$SECF/b.html" && grep -q 'card_pan' "$SECF/b.html"; } && echo 1 || echo 0)" "1" "v0.15 INV-BRIEF: a PII/never-show block with 'N/A' buried in a STRIDE line renders the classification, NOT a false green N/A badge (post-ship PS-2-1)"
printf '%s\n' '# c' '## Security & data-sensitivity' 'N/A — pure library, no sensitive surface.' '## Goal & scope' 'x' '## Scope ladder' '- NOW: a' > "$SECF/na/contract.md"
node "$VIS15/gen.mjs" "$SECF/na" brief --out "$SECF/na.html" >/dev/null 2>&1
chk "$(grep -c 'N/A — no sensitive surface' "$SECF/na.html")" "1" "v0.15 INV-BRIEF: a genuinely-N/A security block still renders the N/A badge (post-ship PS-2-1 keeps the true-N/A path)"
# post-ship PS-3 (never-show as a LIST) + PS-3b (off-spec confidential/restricted vocabulary): a block that
# leads with N/A but still declares a sensitive surface must NOT show a false green badge.
mkdir -p "$SECF/list" "$SECF/vocab"
printf '%s\n' '# c' '## Security & data-sensitivity' 'N/A — internal API, no external sensitive surface.' 'Never-show fields:' '- card_pan' '- ssn' '## Goal & scope' 'x' '## Scope ladder' '- NOW: a' > "$SECF/list/contract.md"
node "$VIS15/gen.mjs" "$SECF/list" brief --out "$SECF/list.html" >/dev/null 2>&1
chk "$( { ! grep -q 'N/A — no sensitive surface' "$SECF/list.html" && grep -q 'card_pan' "$SECF/list.html"; } && echo 1 || echo 0)" "1" "v0.15 INV-BRIEF: a never-show LIST + leading N/A renders the fields, not a false N/A badge (post-ship PS-3)"
( node "$VIS15/gen.mjs" "$SECF/list" brief --shareable --out "$SECF/list-share.html" >/dev/null 2>&1 ); chk "$?" "3" "v0.15 INV-BRIEF-LEAK: a LIST-format never-show is scrubbed in the shareable Brief → HARD-STOP exit 3 (post-ship PS-1 round4 — scrub covers list/per-field, not just inline)"
chk "$( { ! grep -q 'card_pan' "$SECF/list-share.html" && ! grep -q 'ssn' "$SECF/list-share.html"; } && echo 1 || echo 0)" "1" "v0.15 INV-BRIEF-LEAK: list-format never-show field names ABSENT from the shareable copy (post-ship PS-1 round4)"
printf '%s\n' '# c' '## Security & data-sensitivity' 'N/A for public pages. Internal: ssn → confidential, salary → restricted.' '## Goal & scope' 'x' '## Scope ladder' '- NOW: a' > "$SECF/vocab/contract.md"
node "$VIS15/gen.mjs" "$SECF/vocab" brief --out "$SECF/vocab.html" >/dev/null 2>&1
chk "$(node "$VIS15/gen.mjs" "$SECF/vocab" brief 2>/dev/null | grep -c 'N/A — no sensitive surface')" "0" "v0.15 INV-BRIEF: off-spec sensitivity vocabulary (confidential/restricted) + leading N/A shows no false badge (post-ship PS-3b)"
# post-ship PS-1r4-B: the LOCAL Brief must render the FULL body of the reconciliation + security sections —
# a figure/tolerance in a LATER paragraph, or the role×view matrix + STRIDE below the classification line, must NOT drop.
mkdir -p "$SECF/multi"
printf '%s\n' '# c' '## Reconciliation' 'The gold source is the ledger export, human-signed.' '' 'Expected settled total = $8,750,000.00' 'Tolerance: exact.' '## Security & data-sensitivity' 'Per-field: irr (commercial-sensitive). never-show: irr.' '' 'Role×view: CBO=all; KAM=masked.' 'STRIDE-lite: Spoofing — session guard.' '## Goal & scope' 'x' '## Scope ladder' '- NOW: a' > "$SECF/multi/contract.md"
node "$VIS15/gen.mjs" "$SECF/multi" brief --out "$SECF/multi.html" >/dev/null 2>&1
chk "$( { grep -q '8,750,000' "$SECF/multi.html" && grep -q 'Tolerance' "$SECF/multi.html" && grep -q 'CBO' "$SECF/multi.html" && grep -q 'STRIDE' "$SECF/multi.html"; } && echo 1 || echo 0)" "1" "v0.15 INV-BRIEF: LOCAL Brief renders the FULL reconciliation + security body (later-para figure/tolerance + role×view + STRIDE not dropped) (post-ship PS-1r4-B)"

# ── v0.17.0: brief-data fence — DECLARED-value certain scrub + fail-closed recognition + honest banner ──
BDF="$(dirname "$VSMK")/bd"; mkdir -p "$BDF/ds" "$BDF/grp" "$BDF/unit" "$BDF/add" "$BDF/malf" "$BDF/none" "$BDF/prose" "$BDF/pure" "$BDF/crlf" "$BDF/info" "$BDF/uncl" "$BDF/spc" "$BDF/dot" "$BDF/dbase" "$BDF/short" "$BDF/nbsp" "$BDF/cur" "$BDF/lsep" "$BDF/zpad"
# INV-BRIEF-DECLARED-SAFE — declared gold 8750000, Indian×NON-comma restatements in prose (the RP-C1 leak class) → exit 3, forms ABSENT
printf '%s\n' '# c' '## Goal & scope' 'NAV restated 87 50 000 and 87.50.000 and 8 750 000.' '## Reconciliation' 'N/A' '## Scope ladder' '- NOW: a' '' '```compass-brief-data' 'gold: 8750000' '```' > "$BDF/ds/contract.md"
( node "$VIS15/gen.mjs" "$BDF/ds" brief --shareable --out "$BDF/ds/s.html" >/dev/null 2>&1 ); chk "$?" "3" "v0.17 INV-BRIEF-DECLARED-SAFE: declared gold + Indian×non-comma (space/period) restatements → HARD-STOP exit 3 (RP-C1)"
chk "$( { ! grep -q '87 50 000' "$BDF/ds/s.html" && ! grep -q '87.50.000' "$BDF/ds/s.html" && ! grep -q '8 750 000' "$BDF/ds/s.html"; } && echo 1 || echo 0)" "1" "v0.17 INV-BRIEF-DECLARED-SAFE: Indian×non-comma declared forms ABSENT from the shareable copy"
# RP2-M1 — grouped/currency INPUT gold normalizes to the bare magnitude → same certain set
printf '%s\n' '# c' '## Goal & scope' 'Value 87 50 000 in prose.' '## Reconciliation' 'N/A' '## Scope ladder' '- NOW: a' '' '```compass-brief-data' 'gold: ₹87,50,000' '```' > "$BDF/grp/contract.md"
( node "$VIS15/gen.mjs" "$BDF/grp" brief --shareable --out /dev/null >/dev/null 2>&1 ); chk "$?" "3" "v0.17 INV-BRIEF-DECLARED-SAFE: grouped/currency INPUT gold (₹87,50,000) normalizes → exit 3 (RP2-M1)"
# RP-C2 — a declared unit/display token is scrubbed exact
printf '%s\n' '# c' '## Goal & scope' 'Book is 87.5 lakh.' '## Reconciliation' 'N/A' '## Scope ladder' '- NOW: a' '' '```compass-brief-data' 'gold: 87.5 lakh' '```' > "$BDF/unit/contract.md"
( node "$VIS15/gen.mjs" "$BDF/unit" brief --shareable --out /dev/null >/dev/null 2>&1 ); chk "$?" "3" "v0.17 INV-BRIEF-DECLARED-SAFE: a declared unit/display token (87.5 lakh) scrubbed exact → exit 3 (RP-C2)"
# INV-BRIEF-ADDITIVE — declared value seeds the normalized layer so an undeclared regroup is caught with Reconciliation N/A
printf '%s\n' '# c' '## Goal & scope' 'Partner AUM 1,200,000.00 in prose.' '## Reconciliation' 'N/A' '## Scope ladder' '- NOW: a' '' '```compass-brief-data' 'gold: 1200000' '```' > "$BDF/add/contract.md"
( node "$VIS15/gen.mjs" "$BDF/add" brief --shareable --out "$BDF/add/s.html" >/dev/null 2>&1 ); chk "$?" "3" "v0.17 INV-BRIEF-ADDITIVE: declared value seeds the normalized layer → undeclared regroup caught w/ Reconciliation N/A → exit 3 (RP-M5)"
chk "$( ! grep -q '1,200,000' "$BDF/add/s.html" && echo 1 || echo 0)" "1" "v0.17 INV-BRIEF-ADDITIVE: the undeclared trailing-zero-decimal restatement is ABSENT (RP2-m2)"
# INV-BRIEF-FAILCLOSED — malformed → exit 2 + error stub; brief-body --shareable is a shareable surface; LOCAL ignores the fence
printf '%s\n' '# c' '## Goal & scope' 'x' '## Reconciliation' 'N/A' '## Scope ladder' '- NOW: a' '' '```compass-brief-data' 'gold: 100' 'garbage-line' '```' > "$BDF/malf/contract.md"
( node "$VIS15/gen.mjs" "$BDF/malf" brief --shareable --out "$BDF/malf/s.html" >/dev/null 2>&1 ); chk "$?" "2" "v0.17 INV-BRIEF-FAILCLOSED: a MALFORMED fence on --shareable → HARD-STOP exit 2 (never fail-open, never silently absent)"
chk "$( { [ "$(grep -c 'MALFORMED' "$BDF/malf/s.html")" -ge 1 ] && ! grep -q 'Contract Brief' "$BDF/malf/s.html"; } && echo 1 || echo 0)" "1" "v0.17 INV-BRIEF-FAILCLOSED: malformed --out is an error stub (says MALFORMED, is NOT the rendered Brief) — RP-m7"
( node "$VIS15/gen.mjs" "$BDF/malf" brief-body --shareable --out /dev/null >/dev/null 2>&1 ); chk "$?" "2" "v0.17 INV-BRIEF-FAILCLOSED: brief-body --shareable is ALSO a shareable surface → malformed → exit 2 (RP-m9)"
node "$VIS15/gen.mjs" "$BDF/malf" brief --out "$BDF/malf/local.html" >/dev/null 2>&1; MRC=$?
chk "$( { [ "$MRC" = 0 ] && grep -q 'Contract Brief' "$BDF/malf/local.html"; } && echo 1 || echo 0)" "1" "v0.17 INV-BRIEF-LOCAL-FULL: LOCAL brief IGNORES the fence (a malformed fence does NOT break the lock surface)"
# 'none'/declared-nothing → best-effort exit 0 (distinct from malformed); prose-mention → absent exit 0
printf '%s\n' '# c' '## Goal & scope' 'x' '## Reconciliation' 'N/A' '## Scope ladder' '- NOW: a' '' '```compass-brief-data' 'none' '```' > "$BDF/none/contract.md"
( node "$VIS15/gen.mjs" "$BDF/none" brief --shareable --out /dev/null >/dev/null 2>&1 ); chk "$?" "0" "v0.17 INV-BRIEF-FAILCLOSED: a 'none'/declared-nothing fence → best-effort exit 0 (distinct from malformed, RP-M3)"
printf '%s\n' '# c' '## Goal & scope' 'We mention the compass-brief-data fence in prose only.' '## Reconciliation' 'N/A' '## Scope ladder' '- NOW: a' > "$BDF/prose/contract.md"
( node "$VIS15/gen.mjs" "$BDF/prose" brief --shareable --out /dev/null >/dev/null 2>&1 ); chk "$?" "0" "v0.17 INV-BRIEF-FAILCLOSED: a prose/inline MENTION (not a fence opener) → absent/best-effort exit 0 (no false hard-error, MINOR-2)"
# INV-BRIEF-HONEST — banner present in shareable, ABSENT from LOCAL
chk "$(node "$VIS15/gen.mjs" "$BDF/none" brief --shareable 2>/dev/null | grep -c 'Best-effort redaction')" "1" "v0.17 INV-BRIEF-HONEST: the shareable Brief carries the best-effort caveat banner"
chk "$(node "$VIS15/gen.mjs" "$BDF/none" brief 2>/dev/null | grep -c 'Best-effort redaction')" "0" "v0.17 INV-BRIEF-HONEST/LOCAL-FULL: the banner is ABSENT from the LOCAL lock surface (RP-m5)"
# INV-BRIEF-PURE — byte-identical with a fence present
printf '%s\n' '# c' '## Goal & scope' 'x' '## Reconciliation' 'N/A' '## Scope ladder' '- NOW: a' '' '```compass-brief-data' 'gold: 8750000' '```' > "$BDF/pure/contract.md"
node "$VIS15/gen.mjs" "$BDF/pure" brief > "$BDF/pure/a.html" 2>/dev/null; node "$VIS15/gen.mjs" "$BDF/pure" brief > "$BDF/pure/b.html" 2>/dev/null
chk "$(diff "$BDF/pure/a.html" "$BDF/pure/b.html" >/dev/null 2>&1 && echo 1 || echo 0)" "1" "v0.17 INV-BRIEF-PURE: byte-identical output with a brief-data fence present (deterministic parse)"
# INV-EMIT — the contract skill documents emitting the fence at LOCK
chk "$([ "$(grep -c 'compass-brief-data' "$CSK15")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.17 INV-EMIT: contract skill documents emitting the brief-data fence at LOCK"
# INV-BRIEF-DECLARED-SAFE COVERAGE (R3 F1) — drive off genForms: assert it emits the FULL promised set (independent expected list) AND every generated form actually scrubs (exit 3, 0 leaked). Catches a dropped separator/prefix that a hand-picked sample would miss.
cat > "$BDF/cov.mjs" <<'COVEOF'
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os"; import { join } from "node:path";
const GEN = process.argv[2];
const src = readFileSync(GEN, "utf8");
const grab=(n)=>{const i=src.indexOf("function "+n);let d=0,j=i;for(;j<src.length;j++){if(src[j]==="{")d++;else if(src[j]==="}"){d--;if(d===0){j++;break;}}}return src.slice(i,j);};
const gs = src.match(/const GROUP_SEPS = \[[^\]]*\];/)[0];
const { genForms } = await import("data:text/javascript,"+encodeURIComponent(gs+"\n"+grab("groupWestern")+"\n"+grab("groupIndian")+"\n"+grab("genForms")+"\nexport {genForms};"));
const NB="\u00a0", TH="\u2009", NA="\u202f", AP="\u2019";
const expected = ["8750000","8,750,000","87,50,000","8 750 000","87 50 000","8"+NB+"750"+NB+"000","87"+NB+"50"+NB+"000","8"+TH+"750"+TH+"000","8"+NA+"750"+NA+"000","87"+NA+"50"+NA+"000","8"+AP+"750"+AP+"000","87"+AP+"50"+AP+"000","8'750'000","87'50'000","8.750.000","87.50.000","$8,750,000","\u20b987,50,000","\u20ac8.750.000","\u00a38 750 000"];
const forms = genForms("8750000");
const missing = expected.filter(f => !forms.includes(f));
if (missing.length) { console.log("MISSING:"+missing.length); process.exit(0); }
const d = mkdtempSync(join(tmpdir(),"cov"));
writeFileSync(join(d,"contract.md"), "# c\n## Goal & scope\n"+forms.join(" ~ ")+"\n## Reconciliation\nN/A\n## Scope ladder\n- NOW: a\n\n\x60\x60\x60compass-brief-data\ngold: 8750000\n\x60\x60\x60\n");
let ec=0; try { execFileSync("node",[GEN,d,"brief","--shareable","--out",join(d,"s.html")],{stdio:"ignore"}); } catch(e){ ec=e.status||0; }
const out = readFileSync(join(d,"s.html"),"utf8");
const leaked = forms.filter(f => out.includes(f));
console.log(ec===3 && leaked.length===0 ? "PASS" : "FAIL:ec="+ec+":leaked="+leaked.length);
COVEOF
chk "$(node "$BDF/cov.mjs" "$VIS15/gen.mjs" 2>/dev/null)" "PASS" "v0.17 INV-BRIEF-DECLARED-SAFE COVERAGE: genForms emits the FULL promised set AND every form scrubs → exit 3, 0 leaked (coverage not sample, R3 F1)"
# R3 D-1 regression: a CRLF-line-ending fence is still recognized (never fail-open to absent) → declared gold scrubs → exit 3
printf '# c\r\n## Goal & scope\r\nNAV 8,750,000 restated here\r\n## Reconciliation\r\nN/A\r\n## Scope ladder\r\n- NOW: a\r\n\r\n```compass-brief-data\r\ngold: 8750000\r\n```\r\n' > "$BDF/crlf/contract.md"
( node "$VIS15/gen.mjs" "$BDF/crlf" brief --shareable --out /dev/null >/dev/null 2>&1 ); chk "$?" "3" "v0.17 INV-BRIEF-DECLARED-SAFE: a CRLF-line-ending fence is recognized (not fail-open to absent) → exit 3 (R3 D-1)"
# R3 D-2 regression: an info-string token after the tag is still recognized → declared gold scrubs → exit 3
printf '%s\n' '# c' '## Goal & scope' 'NAV 8,750,000 restated here' '## Reconciliation' 'N/A' '## Scope ladder' '- NOW: a' '' '```compass-brief-data json' 'gold: 8750000' '```' > "$BDF/info/contract.md"
( node "$VIS15/gen.mjs" "$BDF/info" brief --shareable --out /dev/null >/dev/null 2>&1 ); chk "$?" "3" "v0.17 INV-BRIEF-DECLARED-SAFE: an info-string token after the fence tag is still recognized (not absent) → exit 3 (R3 D-2)"
# RB2-m2: a space-separated OR dotted-.ext fence tag is still recognized (not fail-open to absent); an unrelated tag is NOT mis-recognized
printf '%s\n' '# c' '## Goal & scope' 'gold 1200000 restated 1,200,000 here' '## Reconciliation' 'N/A' '## Scope ladder' '- NOW: a' '' '```compass brief data' 'gold: 1200000' '```' > "$BDF/spc/contract.md"
( node "$VIS15/gen.mjs" "$BDF/spc" brief --shareable --out /dev/null >/dev/null 2>&1 ); chk "$?" "3" "v0.17 INV-BRIEF-FAILCLOSED: a space-separated fence tag (\`\`\`compass brief data) is recognized (not absent) → exit 3 (RB2-m2)"
printf '%s\n' '# c' '## Goal & scope' 'gold 1200000 restated 1,200,000 here' '## Reconciliation' 'N/A' '## Scope ladder' '- NOW: a' '' '```compass-brief-data.json' 'gold: 1200000' '```' > "$BDF/dot/contract.md"
( node "$VIS15/gen.mjs" "$BDF/dot" brief --shareable --out /dev/null >/dev/null 2>&1 ); chk "$?" "3" "v0.17 INV-BRIEF-FAILCLOSED: a dotted-.ext fence tag (\`\`\`compass-brief-data.json) is recognized (not absent) → exit 3 (RB2-m2)"
printf '%s\n' '# c' '## Goal & scope' 'unrelated 1,200,000 in prose' '## Reconciliation' 'N/A' '## Scope ladder' '- NOW: a' '' '```compass-brief-database' 'CREATE TABLE x;' '```' > "$BDF/dbase/contract.md"
( node "$VIS15/gen.mjs" "$BDF/dbase" brief --shareable --out /dev/null >/dev/null 2>&1 ); chk "$?" "0" "v0.17 INV-BRIEF-FAILCLOSED: an unrelated tag (\`\`\`compass-brief-database) is NOT mis-recognized as our fence → no false hard-error, exit 0 (RB2-m2)"
# RB2-M1: a short (<3-digit) declared gold is EXACT-only scrubbed (fail-safe over-redaction), NOT skipped (which would fail-OPEN)
printf '%s\n' '# c' '## Goal & scope' 'the value 42 here exactly' '## Reconciliation' 'N/A' '## Scope ladder' '- NOW: a' '' '```compass-brief-data' 'gold: 42' '```' > "$BDF/short/contract.md"
( node "$VIS15/gen.mjs" "$BDF/short" brief --shareable --out "$BDF/short/s.html" >/dev/null 2>&1 ); chk "$?" "3" "v0.17 INV-BRIEF-DECLARED-SAFE: a short (<3-digit) declared gold is exact-only scrubbed (fail-safe), NOT skipped-and-leaked → exit 3 (RB2-M1)"
chk "$( ! grep -q 'value 42 here' "$BDF/short/s.html" && echo 1 || echo 0)" "1" "v0.17 INV-BRIEF-DECLARED-SAFE: the short declared value is ABSENT from the shareable copy (RB2-M1 — no fail-open)"
# RB3 D-R3-1: a NBSP-separated fence tag (a common Word/Notion/PDF copy-paste artifact) is recognized (norm collapses ALL whitespace) → declared gold scrubs → exit 3
printf '# c\n## Goal & scope\nvaluation is 12345678 exactly here\n## Reconciliation\nNumeric N/A.\n## Scope ladder\n- NOW: a\n\n```compass\xc2\xa0brief\xc2\xa0data\ngold: 12345678\n```\n' > "$BDF/nbsp/contract.md"
( node "$VIS15/gen.mjs" "$BDF/nbsp" brief --shareable --out "$BDF/nbsp/s.html" >/dev/null 2>&1 ); chk "$?" "3" "v0.17 INV-BRIEF-FAILCLOSED: a NBSP-separated fence tag is recognized (not fail-open to absent) → exit 3 (RB3 D-R3-1)"
chk "$( ! grep -q '12345678' "$BDF/nbsp/s.html" && echo 1 || echo 0)" "1" "v0.17 INV-BRIEF-FAILCLOSED: the declared gold behind a NBSP-tag fence is ABSENT from the shareable copy (RB3 D-R3-1)"
# RB3 D-R3-2: a currency-prefixed SHORT declared gold also scrubs its BARE magnitude → a bare '42' restatement is caught → exit 3, absent
printf '%s\n' '# c' '## Goal & scope' 'valuation is 42 exactly here' '## Reconciliation' 'N/A' '## Scope ladder' '- NOW: a' '' '```compass-brief-data' 'gold: ₹42' '```' > "$BDF/cur/contract.md"
( node "$VIS15/gen.mjs" "$BDF/cur" brief --shareable --out "$BDF/cur/s.html" >/dev/null 2>&1 ); chk "$?" "3" "v0.17 INV-BRIEF-DECLARED-SAFE: a currency-prefixed short gold (₹42) also scrubs its bare magnitude → exit 3 (RB3 D-R3-2)"
chk "$( ! grep -q 'valuation is 42' "$BDF/cur/s.html" && echo 1 || echo 0)" "1" "v0.17 INV-BRIEF-DECLARED-SAFE: the bare magnitude of a currency-prefixed short gold is ABSENT from the shareable copy (RB3 D-R3-2)"
# RB4 D-R4-1: a U+2028 line-separator inside the fence tag is recognized (opener regex is dotAll, norm collapses it) → declared gold scrubs → exit 3 (no silent fail-open)
printf '# c\n## Goal & scope\ntarget is 12345678 here\n## Reconciliation\nNumeric N/A.\n## Scope ladder\n- NOW: a\n\n```compass\xe2\x80\xa8brief\xe2\x80\xa8data\ngold: 12345678\n```\n' > "$BDF/lsep/contract.md"
( node "$VIS15/gen.mjs" "$BDF/lsep" brief --shareable --out "$BDF/lsep/s.html" >/dev/null 2>&1 ); chk "$?" "3" "v0.17 INV-BRIEF-FAILCLOSED: a U+2028-separated fence tag is recognized (dotAll opener) → exit 3, not a silent fail-open (RB4 D-R4-1)"
chk "$( ! grep -q '12345678' "$BDF/lsep/s.html" && echo 1 || echo 0)" "1" "v0.17 INV-BRIEF-FAILCLOSED: the declared gold behind a U+2028-tag fence is ABSENT (RB4 D-R4-1)"
# RB4 D-R4-2: a zero-padded short gold (gold: 0042) is gated on significant digits → the bare '42' restatement is caught → exit 3
printf '%s\n' '# c' '## Goal & scope' 'the value 42 here' '## Reconciliation' 'N/A' '## Scope ladder' '- NOW: a' '' '```compass-brief-data' 'gold: 0042' '```' > "$BDF/zpad/contract.md"
( node "$VIS15/gen.mjs" "$BDF/zpad" brief --shareable --out "$BDF/zpad/s.html" >/dev/null 2>&1 ); chk "$?" "3" "v0.17 INV-BRIEF-DECLARED-SAFE: a zero-padded short gold (0042) scrubs its bare magnitude 42 → exit 3 (RB4 D-R4-2)"
chk "$( ! grep -q 'value 42 here' "$BDF/zpad/s.html" && echo 1 || echo 0)" "1" "v0.17 INV-BRIEF-DECLARED-SAFE: the bare magnitude of a zero-padded short gold is ABSENT (RB4 D-R4-2)"
# R3 F3: an UNCLOSED fence → malformed → exit 2
printf '%s\n' '# c' '## Goal & scope' 'x' '## Reconciliation' 'N/A' '## Scope ladder' '- NOW: a' '' '```compass-brief-data' 'gold: 8750000' > "$BDF/uncl/contract.md"
( node "$VIS15/gen.mjs" "$BDF/uncl" brief --shareable --out /dev/null >/dev/null 2>&1 ); chk "$?" "2" "v0.17 INV-BRIEF-FAILCLOSED: an UNCLOSED fence → malformed → exit 2 (R3 F3)"
# R3 F3: docs are gated — SKILL.md documents bounded-certainty + gen.mjs header notes exit-2 dual meaning
chk "$( { grep -qi 'certainty' "$VIS15/SKILL.md" && grep -q 'MALFORMED brief-data fence' "$VIS15/gen.mjs"; } && echo 1 || echo 0)" "1" "v0.17 INV-BRIEF-HONEST: SKILL.md documents bounded-certainty + gen.mjs header notes exit-2 dual meaning (R3 F3)"
rm -rf "$(dirname "$VSMK")"
# INV-LOCK
chk "$( { grep -q 'This is the contract — lock it' "$CSK15" && grep -qi 'produce the Contract Brief' "$CSK15"; } && echo 1 || echo 0)" "1" "v0.15 INV-LOCK: contract skill produces the Brief + requires an explicit lock"
# INV-MODE
chk "$( { grep -q '\*\*Auto\*\*' "$CSK15" && grep -q 'Human-gated' "$CSK15"; } && echo 1 || echo 0)" "1" "v0.15 INV-MODE: contract skill offers Auto vs Human-gated (each explained)"
# INV-EXPLAIN
chk "$([ -f "$EXP15" ] && grep -q '^description: .\+' "$EXP15" && grep -q 'feynman-walkthrough' "$EXP15" && echo 1 || echo 0)" "1" "v0.15 INV-EXPLAIN: commands/explain.md exists with description + teaching invocation"
# INV-FEYNMAN — unique markers, ordered feynman<confidence<GATE:START, non-blank window 1..28
feyn_ok() { local f="$1" fc cc fl cl gl nb
  fc=$(grep -c '<!-- FEYNMAN -->' "$f"); cc=$(grep -c '<!-- CONFIDENCE -->' "$f")
  [ "$fc" = 1 ] && [ "$cc" = 1 ] || return 1
  fl=$(grep -n '<!-- FEYNMAN -->' "$f" | head -1 | cut -d: -f1)
  cl=$(grep -n '<!-- CONFIDENCE -->' "$f" | head -1 | cut -d: -f1)
  gl=$(awk -v a="$fl" 'NR>a && /<!-- GATE:START -->/{print NR; exit}' "$f")
  [ -n "$gl" ] || return 1
  [ "$fl" -lt "$cl" ] && [ "$cl" -lt "$gl" ] || return 1
  nb=$(awk -v a="$fl" -v b="$gl" 'NR>a && NR<b && NF>0{c++} END{print c+0}' "$f")
  [ "$nb" -gt 0 ] && [ "$nb" -le 28 ] || return 1
  return 0; }
for s in contract review-contract plan review-plan build review-build ship; do
  feyn_ok "$PLUGIN_ROOT/skills/$s/SKILL.md"; chk "$?" "0" "v0.15 INV-FEYNMAN: $s carries a unique, ordered, ≤28-line Feynman + confidence block"
done
FFX15="$(mktemp -d)"
printf '%s\n' 'intro' '<!-- GATE:START -->' 'gate' '<!-- FEYNMAN -->' 'x' '<!-- CONFIDENCE -->' 'y' > "$FFX15/after.md"
feyn_ok "$FFX15/after.md"; chk "$?" "1" "v0.15 INV-FEYNMAN fixture: a marker placed AFTER GATE:START → FAIL (fail-closed)"
printf '%s\n' '<!-- FEYNMAN -->' 'a' '<!-- FEYNMAN -->' 'b' '<!-- CONFIDENCE -->' 'c' '<!-- GATE:START -->' > "$FFX15/dup.md"
feyn_ok "$FFX15/dup.md"; chk "$?" "1" "v0.15 INV-FEYNMAN fixture: a duplicate marker → FAIL"
rm -rf "$FFX15"

# ── v0.15.0 slice ②: review-integrity — severity bug-bar · self-refutation · dedupe/rank ──
RC15="$PLUGIN_ROOT/shared/review-core.md"
bugbar_n=0
for f in "$RC15" "$PLUGIN_ROOT/skills/review-contract/SKILL.md" "$PLUGIN_ROOT/skills/review-plan/SKILL.md" "$PLUGIN_ROOT/skills/review-build/SKILL.md"; do
  if grep -q 'a wrong number that ships' "$f" && grep -q 'drift-prone duplicated canonical set' "$f" && grep -q 'cosmetic' "$f"; then bugbar_n=$((bugbar_n+1)); fi
done
chk "$bugbar_n" "4" "v0.15 INV-BUGBAR: 3-clause severity rubric in review-core + all 3 review skills"
# INV-BUGBAR single-source equality (R3-M6): the rubric island must be byte-identical across the 3 review skills
bbisl(){ awk '/BUGBAR:START/{f=1} f{print} /BUGBAR:END/{f=0}' "$1"; }
chk "$( diff <(bbisl "$PLUGIN_ROOT/skills/review-contract/SKILL.md") <(bbisl "$PLUGIN_ROOT/skills/review-plan/SKILL.md") >/dev/null 2>&1 && diff <(bbisl "$PLUGIN_ROOT/skills/review-plan/SKILL.md") <(bbisl "$PLUGIN_ROOT/skills/review-build/SKILL.md") >/dev/null 2>&1 && [ -n "$(bbisl "$PLUGIN_ROOT/skills/review-build/SKILL.md")" ] && echo 1 || echo 0)" "1" "v0.15 INV-BUGBAR: severity-rubric island byte-identical across all 3 review skills (single-source, no silent drift)"
bbstart_n=0; for s in review-contract review-plan review-build; do bbstart_n=$((bbstart_n + $(grep -c 'BUGBAR:START' "$PLUGIN_ROOT/skills/$s/SKILL.md"))); done
chk "$bbstart_n" "3" "v0.15 INV-BUGBAR: exactly one BUGBAR island per review skill (3 total, no dup)"
refute_n=0
for s in review-contract review-plan review-build; do
  f="$PLUGIN_ROOT/skills/$s/SKILL.md"
  if grep -q 'reachable from a real entry point' "$f" && grep -q 'not already guarded' "$f"; then refute_n=$((refute_n+1)); fi
done
chk "$refute_n" "3" "v0.15 INV-REFUTE: self-refutation (reachable + not-already-guarded) in all 3 review skills"
dedupe_n=0
for s in review-contract review-plan review-build; do
  f="$PLUGIN_ROOT/skills/$s/SKILL.md"
  if grep -q 'top blocker' "$f" && grep -q 'Critical-first' "$f" && grep -q 'contract before' "$f"; then dedupe_n=$((dedupe_n+1)); fi
done
chk "$dedupe_n" "3" "v0.15 INV-DEDUPE: dedupe + Critical-first + top-blocker + contract-before-plan in all 3 review skills"

# ── v0.15.0 slice ③: prod-safety (restore-point/config-parity) · flag spine · security pin · commercial scan ──
FXP="$(cd "$(dirname "$SH")" && pwd)/fixtures"
( bash "$SH" restore-point "$FXP/restore-point/confirmed"  >/dev/null 2>&1 ); chk "$?" "0" "v0.15 INV-RESTORE: confirmed complete snapshot → 0"
( bash "$SH" restore-point "$FXP/restore-point/missing"    >/dev/null 2>&1 ); chk "$?" "1" "v0.15 INV-RESTORE: destructive + no snapshot → HARD STOP"
( bash "$SH" restore-point "$FXP/restore-point/incomplete" >/dev/null 2>&1 ); chk "$?" "1" "v0.15 INV-RESTORE: incomplete attestation → HARD STOP"
( bash "$SH" restore-point "$FXP/restore-point/na"         >/dev/null 2>&1 ); chk "$?" "0" "v0.15 INV-RESTORE: no destructive op declared → N/A-pass"
( bash "$SH" restore-point "$FXP/restore-point/undeclared-destructive" >/dev/null 2>&1 ); chk "$?" "0" "v0.15 INV-RESTORE: undeclared destructive → N/A-pass (documented honest boundary)"
( bash "$SH" restore-point "$FXP/restore-point/prose-destructive" >/dev/null 2>&1 ); chk "$?" "1" "v0.15 INV-RESTORE: declared-destructive via header prose ('yes → gloss', repo house-style) + no snapshot → HARD STOP (R3-C1 regression)"
( bash "$SH" restore-point "$FXP/restore-point/decoy-destructive" >/dev/null 2>&1 ); chk "$?" "1" "v0.15 INV-RESTORE: a leading-PROSE decoy above the real destructive header cannot steal the parse → HARD STOP (R3-R2-D1 anchor+union)"
( bash "$SH" restore-point "$FXP/restore-point/coerce-destructive" >/dev/null 2>&1 ); chk "$?" "1" "v0.15 INV-RESTORE: a truthy synonym (destructive-backfill: true) fails CLOSED, not soft-pass → HARD STOP (R3-R3-D2 coercion)"
( bash "$SH" config-parity "$FXP/config-parity/match"              >/dev/null 2>&1 ); chk "$?" "0" "v0.15 INV-PARITY: all referenced keys present in prod → 0"
( bash "$SH" config-parity "$FXP/config-parity/missing-key"        >/dev/null 2>&1 ); chk "$?" "1" "v0.15 INV-PARITY: a referenced key missing from prod → HARD STOP"
( bash "$SH" config-parity "$FXP/config-parity/no-prod-declaration" >/dev/null 2>&1 ); chk "$?" "1" "v0.15 INV-PARITY: keys referenced + no prod-keys declaration → HARD STOP"
( bash "$SH" config-parity "$FXP/config-parity/none-referenced"    >/dev/null 2>&1 ); chk "$?" "0" "v0.15 INV-PARITY: no new env keys referenced → N/A-pass"
( bash "$SH" config-parity "$FXP/config-parity/dup-none-stub"      >/dev/null 2>&1 ); chk "$?" "1" "v0.15 INV-PARITY: a stale 'env-keys-referenced: none' stub above real keys cannot hide them → HARD STOP (R3-R2-D3 union)"
( bash "$SH" config-parity "$FXP/config-parity/tab-indented"       >/dev/null 2>&1 ); chk "$?" "1" "v0.15 INV-PARITY: a TAB-indented env-keys-referenced header is not skipped → HARD STOP (post-ship PS-2-2, anchor parity with restore-point)"
( bash "$SH" config-parity "$FXP/config-parity/prod-comment"       >/dev/null 2>&1 ); chk "$?" "1" "v0.15 INV-PARITY: a key NAMED IN A COMMENT on prod-keys does not count as declared → HARD STOP (post-ship PS-1 soft-pass)"
SHIPSK="$PLUGIN_ROOT/skills/ship/SKILL.md"
chk "$( { grep -q 'restore-point' "$SHIPSK" && grep -q 'config-parity' "$SHIPSK" && grep -q 'without a redeploy' "$SHIPSK"; } && echo 1 || echo 0)" "1" "v0.15 INV-RESTORE/PARITY/FLAG: ship skill wires restore-point + config-parity + flag-OFF-without-redeploy"
PSD="$SMOKE_TMP/psd"; mkdir -p "$PSD"
printf '## RECEIPT — ship · x · PASS\n- [x] restore-point: exit 0\n- [x] config-parity: exit 0\n- [x] rollback-fwdcompat: exit 0\n' > "$PSD/receipts.md"
( bash "$SH" ship-prodsafety-receipt-match "$PSD" >/dev/null 2>&1 ); chk "$?" "0" "v0.15/v0.21 ship-prodsafety-receipt-match: restore-point + config-parity + rollback-fwdcompat exit lines present → 0"
printf '## RECEIPT — ship · x · PASS\n- [x] deployed\n' > "$PSD/receipts.md"
( bash "$SH" ship-prodsafety-receipt-match "$PSD" >/dev/null 2>&1 ); chk "$?" "1" "v0.15 ship-prodsafety-receipt-match: a silent skip (missing lines) → FAIL"
printf '## RECEIPT — ship · x · PASS\n- [x] restore-point: exit 0\n- [x] config-parity: exit 0\n' > "$PSD/receipts.md"
( bash "$SH" ship-prodsafety-receipt-match "$PSD" >/dev/null 2>&1 ); chk "$?" "1" "v0.21 RB-R1-M2: ship receipt with restore-point+config-parity but MISSING rollback-fwdcompat → FAIL (INV-ROLLBACK-FWDCOMPAT enforced at ship)"
CSK="$PLUGIN_ROOT/skills/contract/SKILL.md"; BSK="$PLUGIN_ROOT/skills/build/SKILL.md"
chk "$(grep -c 'Rollout & kill-switch' "$CSK")" "2" "v0.15 INV-FLAG: contract requires Rollout & kill-switch in BOTH mirrored required-section lists"
chk "$( { grep -q 'flag defaulted OFF' "$BSK" && grep -q 'both states' "$BSK"; } && echo 1 || echo 0)" "1" "v0.15 INV-FLAG: build skill has flag-off-default + both-states-verified rule"
chk "$(grep -c 'Security & data-sensitivity' "$CSK")" "2" "v0.15 INV-SECPIN: contract requires Security & data-sensitivity in BOTH mirrored lists"
chk "$( { grep -q 'role×view' "$CSK" && grep -q 'STRIDE' "$CSK"; } && echo 1 || echo 0)" "1" "v0.15 INV-SECPIN: contract security block names a role×view matrix + STRIDE-lite"
# R3-M1: the contract interview must ELICIT the machine-readable signals restore-point/config-parity consume
chk "$( { grep -q 'env-keys-referenced' "$CSK" && grep -q 'destructive-backfill' "$CSK"; } && echo 1 || echo 0)" "1" "v0.15 INV-PARITY/RESTORE: contract skill elicits the machine-readable env-keys-referenced + destructive-backfill signals (R3-M1 — gate had no input before)"
csisl(){ awk '/COMMSCAN:START/{f=1} f{print} /COMMSCAN:END/{f=0}' "$1"; }
chk "$( diff <(csisl "$PLUGIN_ROOT/skills/review-plan/SKILL.md") <(csisl "$PLUGIN_ROOT/skills/review-build/SKILL.md") >/dev/null 2>&1 && [ -n "$(csisl "$PLUGIN_ROOT/skills/review-plan/SKILL.md")" ] && echo 1 || echo 0)" "1" "v0.15 INV-COMMSCAN: COMMSCAN island byte-identical across review-plan + review-build"
chk "$(grep -c 'COMMSCAN:START' "$PLUGIN_ROOT/skills/review-plan/SKILL.md")" "1" "v0.15 INV-COMMSCAN: exactly one COMMSCAN island in review-plan (no drift/dup)"
chk "$( { csisl "$PLUGIN_ROOT/skills/review-plan/SKILL.md" | grep -q 'IRR' && csisl "$PLUGIN_ROOT/skills/review-build/SKILL.md" | grep -q 'IRR'; } && echo 1 || echo 0)" "1" "v0.15 INV-COMMSCAN: the island scans IRR / take-rate / gross-rev% / COF in both review skills"
# ── v0.18.0: RBACSTRIDE method island — STRIDE + role×resource RBAC-matrix + IDOR, byte-identical across review-plan [E] + review-build [D] (mirrors COMMSCAN) ──
rsisl(){ awk '/RBACSTRIDE:START/{f=1} f{print} /RBACSTRIDE:END/{f=0}' "$1"; }
RP18="$PLUGIN_ROOT/skills/review-plan/SKILL.md"; RB18="$PLUGIN_ROOT/skills/review-build/SKILL.md"
chk "$( diff <(rsisl "$RP18") <(rsisl "$RB18") >/dev/null 2>&1 && [ -n "$(rsisl "$RP18")" ] && echo 1 || echo 0)" "1" "v0.18 INV-RBACSTRIDE-BLOCK: RBACSTRIDE island byte-identical across review-plan + review-build"
chk "$(grep -c 'RBACSTRIDE:START' "$RP18")" "1" "v0.18 INV-RBACSTRIDE-BLOCK: exactly one RBACSTRIDE island in review-plan (no drift/dup)"
chk "$(grep -c 'RBACSTRIDE:START' "$RB18")" "1" "v0.18 INV-RBACSTRIDE-BLOCK: exactly one RBACSTRIDE island in review-build (no drift/dup)"
chk "$( { rsisl "$RP18" | grep -q 'resource matrix' && rsisl "$RP18" | grep -q 'against the contract' && rsisl "$RP18" | grep -q 'STRIDE' && rsisl "$RP18" | grep -q 'IDOR' && rsisl "$RP18" | grep -q '403'; } && echo 1 || echo 0)" "1" "v0.18 INV-RBACSTRIDE-METHOD: island carries role×resource matrix (asserted against the contract) + STRIDE + IDOR/403"
chk "$(rsisl "$RP18" | grep -c 'never trust a disprovable N/A')" "1" "v0.18 INV-RBACSTRIDE-METHOD: the UNDER-DECLARED guard is present via its UNIQUE phrase (R2-C2 — not a tautology on ambient N/A + CRITICAL tokens)"
chk "$(rsisl "$RP18" | grep -c 'blocks CLOSED')" "1" "v0.18 INV-RBACSTRIDE-METHOD: a failed IDOR probe / unasserted cell → CRITICAL that blocks CLOSED"
chk "$(rsisl "$RP18" | grep -c 'when present')" "1" "v0.18 INV-RBAC-NODEP: permission-matrix wired conditionally (when present) — no hard dependency"
chk "$(rsisl "$RP18" | grep -c 'no new view/endpoint')" "1" "v0.18 INV-RBAC-BYTEINERT: the method is byte-inert (N/A) for a build with no new view/endpoint"
chk "$( { grep -q 'RBACSTRIDE:.*asserted vs contract' "$RP18" && grep -q 'RBACSTRIDE:.*asserted vs contract' "$RB18"; } && echo 1 || echo 0)" "1" "v0.18 INV-RBACSTRIDE-RECEIPT: both review-plan + review-build receipts carry the RBACSTRIDE line (method applied / N/A)"
chk "$( { grep -q 'resource matrix' "$PLUGIN_ROOT/skills/plan/SKILL.md" && grep -qi 'threat-model' "$PLUGIN_ROOT/skills/plan/SKILL.md"; } && echo 1 || echo 0)" "1" "v0.18 INV-PLAN-RBAC: the plan skill requires a threat-model / RBAC-matrix design step for view/endpoint builds"
# ── v0.19.0: EDGERACE method island — boundary/edge + concurrency/TOCTOU, byte-identical across review-plan [A] + review-build [A] (mirrors RBACSTRIDE) ──
erisl(){ awk '/EDGERACE:START/{f=1} f{print} /EDGERACE:END/{f=0}' "$1"; }
EP19="$PLUGIN_ROOT/skills/review-plan/SKILL.md"; EB19="$PLUGIN_ROOT/skills/review-build/SKILL.md"
chk "$( diff <(erisl "$EP19") <(erisl "$EB19") >/dev/null 2>&1 && [ -n "$(erisl "$EP19")" ] && echo 1 || echo 0)" "1" "v0.19 INV-EDGERACE-BLOCK: EDGERACE island byte-identical across review-plan + review-build"
chk "$(grep -c 'EDGERACE:START' "$EP19")" "1" "v0.19 INV-EDGERACE-BLOCK: exactly one EDGERACE island in review-plan (no drift/dup)"
chk "$(grep -c 'EDGERACE:START' "$EB19")" "1" "v0.19 INV-EDGERACE-BLOCK: exactly one EDGERACE island in review-build (no drift/dup)"
chk "$( { erisl "$EP19" | grep -qF 'off-by-one' && erisl "$EP19" | grep -qF 'timezone' && erisl "$EP19" | grep -qF 'losing interleaving' && erisl "$EP19" | grep -qF 'assert the guard' && erisl "$EP19" | grep -qF 'blocks CLOSED' && erisl "$EP19" | grep -qF 'never wave off'; } && echo 1 || echo 0)" "1" "v0.19 INV-EDGERACE-METHOD: island carries both methods + teeth + challenge-N/A (off-by-one · timezone · losing interleaving · assert the guard · blocks CLOSED · never wave off)"
chk "$( { grep -q 'EDGERACE:.*applied' "$EP19" && grep -q 'EDGERACE:.*applied' "$EB19"; } && echo 1 || echo 0)" "1" "v0.19 INV-EDGERACE-RECEIPT: both review receipts carry the EDGERACE line (receipt-only anchor 'EDGERACE:.*applied', not the island markers — R2-m2)"
chk "$(grep -c 'losing interleaving' "$PLUGIN_ROOT/skills/plan/SKILL.md")" "1" "v0.19 INV-PLAN-CONCURRENCY: the plan skill requires a concurrency/TOCTOU analysis step (losing interleaving) for read-modify-write builds"
chk "$(erisl "$EP19" | grep -cF 'no boundary or read-modify-write surface')" "1" "v0.19 INV-EDGERACE-BYTEINERT: the method is byte-inert (N/A) for a build with no boundary or read-modify-write surface"
# R2-m3 guard: close the one non-self-caught name-sync leg — the smoke:181 name-loop must cover every recon.sh INV_NAMES
_rn19="$(sed -n 's/^INV_NAMES="\(.*\)"/\1/p' "$PLUGIN_ROOT/scripts/compass.recon.sh")"
_sl19="$(sed -n 's/^for nm in \(.*\); do/\1/p' "$PLUGIN_ROOT/scripts/compass.smoke.sh")"
_miss19=""; for _n19 in $_rn19; do case " $_sl19 " in *" $_n19 "*) ;; *) _miss19="$_miss19 $_n19";; esac; done
chk "$([ -z "$_miss19" ] && echo 1 || echo 0)" "1" "v0.19 INV-SUITES: the smoke:181 name-loop covers every recon.sh INV_NAMES (R2-m3 — the previously-unguarded name-sync leg is now guarded)"
# ── v0.20.0: PERFFMEA method island — per-dependency FMEA + anti-pattern hunt, byte-identical across review-plan + review-build (mirrors EDGERACE) ──
pfisl(){ awk '/PERFFMEA:START/{f=1} f{print} /PERFFMEA:END/{f=0}' "$1"; }
PP20="$PLUGIN_ROOT/skills/review-plan/SKILL.md"; PB20="$PLUGIN_ROOT/skills/review-build/SKILL.md"
chk "$( diff <(pfisl "$PP20") <(pfisl "$PB20") >/dev/null 2>&1 && [ -n "$(pfisl "$PP20")" ] && echo 1 || echo 0)" "1" "v0.20 INV-PERFFMEA-BLOCK: PERFFMEA island byte-identical across review-plan + review-build"
chk "$(grep -c 'PERFFMEA:START' "$PP20")" "1" "v0.20 INV-PERFFMEA-BLOCK: exactly one PERFFMEA island in review-plan (no drift/dup)"
chk "$(grep -c 'PERFFMEA:START' "$PB20")" "1" "v0.20 INV-PERFFMEA-BLOCK: exactly one PERFFMEA island in review-build (no drift/dup)"
chk "$( { pfisl "$PP20" | grep -qF 'no dependency called with no timeout' && pfisl "$PP20" | grep -qF 'paginationless' && pfisl "$PP20" | grep -qF 'query count' && pfisl "$PP20" | grep -qF 'blocks CLOSED' && pfisl "$PP20" | grep -qF 'never wave off a dependency or volume-sensitive loop'; } && echo 1 || echo 0)" "1" "v0.20 INV-PERFFMEA-METHOD: island carries FMEA + anti-pattern + teeth + challenge-N/A (no dependency called with no timeout · paginationless · query count · blocks CLOSED · never wave off a dependency or volume-sensitive loop)"
chk "$( { grep -q 'PERFFMEA:.*applied' "$PP20" && grep -q 'PERFFMEA:.*applied' "$PB20" && [ "$(pfisl "$PP20" | grep -c applied)" = "0" ]; } && echo 1 || echo 0)" "1" "v0.20 INV-PERFFMEA-RECEIPT: receipt-only anchor 'PERFFMEA:.*applied' in both AND the word 'applied' absent from the island body (R1-MIN-1 — the receipt anchor matches only the receipt line)"
chk "$(grep -c 'no dependency called with no timeout' "$PLUGIN_ROOT/skills/plan/SKILL.md")" "1" "v0.20 INV-PLAN-FMEA: the plan skill requires an FMEA/perf-budget design step (no dependency called with no timeout) for dependency builds"
chk "$(pfisl "$PP20" | grep -cF 'no external dependency or data-volume-sensitive loop')" "1" "v0.20 INV-PERFFMEA-BYTEINERT: the method is byte-inert (N/A) for a build with no external dependency or data-volume-sensitive loop"
# ── v0.21.0: CROSSTAB method island — cross-table invariant enforcement, byte-identical across review-plan [B] + review-build [B] (mirrors PERFFMEA) ──
ctisl(){ awk '/CROSSTAB:START/{f=1} f{print} /CROSSTAB:END/{f=0}' "$1"; }
CP21="$PLUGIN_ROOT/skills/review-plan/SKILL.md"; CB21="$PLUGIN_ROOT/skills/review-build/SKILL.md"
chk "$( diff <(ctisl "$CP21") <(ctisl "$CB21") >/dev/null 2>&1 && [ -n "$(ctisl "$CP21")" ] && echo 1 || echo 0)" "1" "v0.21 INV-CROSSTAB-BLOCK: CROSSTAB island byte-identical across review-plan + review-build"
chk "$(grep -c 'CROSSTAB:START' "$CP21")" "1" "v0.21 INV-CROSSTAB-BLOCK: exactly one CROSSTAB island in review-plan (no drift/dup)"
chk "$(grep -c 'CROSSTAB:START' "$CB21")" "1" "v0.21 INV-CROSSTAB-BLOCK: exactly one CROSSTAB island in review-build (no drift/dup)"
chk "$( { ctisl "$CP21" | grep -qF 'child-sums-to-parent' && ctisl "$CP21" | grep -qF 'no orphan FK' && ctisl "$CP21" | grep -qF 'one active generation' && ctisl "$CP21" | grep -qF 'DB-constraint' && ctisl "$CP21" | grep -qF 'zero-violators' && ctisl "$CP21" | grep -qF 'blocks CLOSED'; } && echo 1 || echo 0)" "1" "v0.21 INV-CROSSTAB-METHOD: island carries the cross-table method + teeth (child-sums-to-parent · no orphan FK · one active generation · DB-constraint · zero-violators · blocks CLOSED)"
chk "$( { grep -q 'CROSSTAB:.*applied' "$CP21" && grep -q 'CROSSTAB:.*applied' "$CB21" && [ "$(ctisl "$CP21" | grep -c applied)" = "0" ]; } && echo 1 || echo 0)" "1" "v0.21 INV-CROSSTAB-RECEIPT: receipt-only anchor 'CROSSTAB:.*applied' in both AND the word 'applied' absent from the island body (mirrors PERFFMEA-RECEIPT R1-MIN-1)"
chk "$(ctisl "$CP21" | grep -cF 'challenge the disprovable N/A for schema/migration/PII')" "1" "v0.21 INV-NA-CHALLENGE: the CROSSTAB island carries the load-bearing challenge-the-disprovable-N/A clause (smoke-asserted, not prose)"
chk "$(grep -cF 'child-sums-to-parent' "$PLUGIN_ROOT/skills/plan/SKILL.md")" "1" "v0.21 INV-PLAN-CROSSTAB: the plan skill requires a cross-table-invariant design step (child-sums-to-parent) for ≥2-related-table builds"
chk "$(ctisl "$CP21" | grep -cF 'no ≥2-related-table surface')" "1" "v0.21 INV-CROSSTAB-BYTEINERT: the method is byte-inert (N/A) for a build with no ≥2-related-table surface"
# ── v0.21.0 W3: rollback-fwdcompat honor-level re-challenge — smoke-asserted so the clause can't drift (parity with green-ci) ──
chk "$(grep -cF 're-challenge the recorded rollback data-safety line' "$CB21")" "1" "v0.21 INV-ROLLBACK-FWDCOMPAT: review-build [B] re-challenges the recorded rollback data-safety line (honor-level, never independent proof — smoke-asserted, not prose)"
# ── v0.21.0 W4: green-ci re-challenge + compliance/PII plan-step + image-secret-hygiene disclosure ──
chk "$(grep -cF 're-challenge the recorded green-ci merge-proof line' "$CB21")" "1" "v0.21 INV-GREEN-CI: review-build re-challenges the recorded green-ci merge-proof line (honor-level, smoke-asserted — RP-R1-M1 parity fix)"
chk "$(grep -cF 'no raw PII/secret in logs' "$PLUGIN_ROOT/skills/plan/SKILL.md")" "1" "v0.21 INV-PII-GATE: the plan skill requires a compliance/PII design step (no raw PII/secret in logs) for PII/financial builds"
chk "$( { grep -q 'secret-scan is text-only' "$PLUGIN_ROOT/skills/build/SKILL.md" && grep -q 'test-tenant' "$PLUGIN_ROOT/skills/build/SKILL.md" && grep -q 'secret-scan is text-only' "$PLUGIN_ROOT/skills/ship/SKILL.md" && grep -q 'test-tenant' "$PLUGIN_ROOT/skills/ship/SKILL.md"; } && echo 1 || echo 0)" "1" "v0.21 INV-IMG-SECRET: build+ship carry the image-secret-hygiene checklist (test-tenant) + 'secret-scan is text-only' disclosure (no image/OCR scanner — dependency-free)"
# INV-NO-LEAK durable coverage (R3-m3): recon-guard a clean secret-scan of the new fixtures + the compass-visual skill
( bash "$SH" secret-scan "$FXP" >/dev/null 2>&1 ); chk "$?" "0" "v0.15 INV-NO-LEAK: secret-scan on the prod-safety fixtures → 0 hits (now recon-guarded, R3-m3)"
( bash "$SH" secret-scan "$VIS15" >/dev/null 2>&1 ); chk "$?" "0" "v0.15 INV-NO-LEAK: secret-scan on skills/compass-visual → 0 hits (now recon-guarded, R3-m3)"

# ── v0.16.0 survive-the-cutover: cutover gates wired + behavioral ──
disp16=$(grep -cE '^[[:space:]]+(abort|abort-check|abort-clear|bake-gate|canary-analysis|watcher-check|ship-cutover-receipt-match)\)' "$PLUGIN_ROOT/scripts/compass.sh")
chk "$disp16" "7" "v0.16 all 7 cutover subcommands wired in dispatch"
( bash "$SH" abort-check "$FXP/abort/active" >/dev/null 2>&1 ); chk "$?" "3" "v0.16 INV-ABORT: active fixture → 3"
( bash "$SH" abort-check "$FXP/abort/clear"  >/dev/null 2>&1 ); chk "$?" "0" "v0.16 INV-ABORT: clear fixture → 0"
lh16="$(bash "$FXP/abort/loop-harness.sh" "$SH" 2>&1)"; chk "$(printf '%s' "$lh16" | grep -c 'HALTED-before-op-3 ran=2')" "1" "v0.16 INV-ABORT: loop-harness halts before the next mutating op"
( bash "$SH" bake-gate "$FXP/bake/in-bound"        >/dev/null 2>&1 ); chk "$?" "0" "v0.16 INV-BAKE: in-bound → 0"
( bash "$SH" bake-gate "$FXP/bake/no-reading-mem"  >/dev/null 2>&1 ); chk "$?" "1" "v0.16 INV-BAKE: absent mem reading is never in-bound → non-zero"
( bash "$SH" bake-gate "$FXP/bake/no-bound"        >/dev/null 2>&1 ); chk "$?" "1" "v0.16 INV-BAKE: window but no bound fail-closed → non-zero"
( bash "$SH" canary-analysis "$FXP/canary/green"              >/dev/null 2>&1 ); chk "$?" "0" "v0.16 INV-CANARY: independent green → 0"
( bash "$SH" canary-analysis "$FXP/canary/self-computed"      >/dev/null 2>&1 ); chk "$?" "1" "v0.16 INV-CANARY: self-computed green → non-zero"
( bash "$SH" canary-analysis "$FXP/canary/substituted-no-window" >/dev/null 2>&1 ); chk "$?" "1" "v0.16 INV-CANARY: SUBSTITUTED-BAKE requires a bake-window → non-zero"
( bash "$SH" canary-analysis "$FXP/canary/breach-no-rollback" >/dev/null 2>&1 ); chk "$?" "1" "v0.16 INV-BURNRATE: breach without rollback-fired → non-zero"
( bash "$SH" watcher-check "$FXP/watcher/named"          >/dev/null 2>&1 ); chk "$?" "0" "v0.16 INV-WATCHER: named + window → 0"
( bash "$SH" watcher-check "$FXP/watcher/auto-bare-armed" >/dev/null 2>&1 ); chk "$?" "1" "v0.16 INV-WATCHER: bare 'armed' is not proof → non-zero"
( bash "$SH" ship-cutover-receipt-match "$FXP/cutover-receipt/complete"            >/dev/null 2>&1 ); chk "$?" "0" "v0.16 INV-NA-EXPLICIT: all three recorded → 0"
( bash "$SH" ship-cutover-receipt-match "$FXP/cutover-receipt/deploy-inscope-all-na" >/dev/null 2>&1 ); chk "$?" "1" "v0.16 INV-NA-EXPLICIT: deploy in-scope all-N/A fail-open guard → non-zero"
( bash "$SH" bake-gate "$FXP/bake/na-not-declared" >/dev/null 2>&1 ); chk "$?" "0" "v0.16 INV-BC: byte-inert when unconfigured → 0"
chk "$(grep -c 'Step 0.7 — cutover safety net' "$PLUGIN_ROOT/skills/ship/SKILL.md")" "1" "v0.16 ship skill carries Step 0.7 (cutover safety net)"
chk "$(grep -c 'TEMPLATE: cutover-box' "$PLUGIN_ROOT/skills/ship/SKILL.md")" "1" "v0.16 ship skill pins the cutover-box template"
chk "$([ "$(grep -c 'ship-cutover-receipt-match' "$PLUGIN_ROOT/skills/ship/SKILL.md")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.16 ship skill references ship-cutover-receipt-match"
chk "$(grep -c 'abort-check <slug>' "$PLUGIN_ROOT/skills/build/SKILL.md")" "1" "v0.16 build skill wires abort-check into the per-step loop (INV-ABORT)"
# review-build regression (top attacks)
( bash "$SH" bake-gate "$FXP/bake/numeric-recon-prose" >/dev/null 2>&1 ); chk "$?" "1" "v0.16 RB-C1: numeric bound + 'reconciled' prose stays NUMERIC → non-zero"
( bash "$SH" canary-analysis "$FXP/canary/self-computed-ws" >/dev/null 2>&1 ); chk "$?" "1" "v0.16 RB-C2: gold≡slice modulo whitespace is self-computed → non-zero"
( bash "$SH" ship-cutover-receipt-match "$FXP/cutover-receipt/deploy-prose-outofscope" >/dev/null 2>&1 ); chk "$?" "1" "v0.16 RB-M2: 'out-of-scope' in deploy prose does not disable the guard → non-zero"

# ── v0.22.0: program ledger + real-tag guard, behavioral on a SPACE+PARENS path (K-17 quoting coverage) ──
SPG="$SMOKE_BASE/pg repo"; mkdir -p "$SPG/.claude/builds"
( cd "$SPG" && git init -q && git config user.email t@t && git config user.name t \
  && git config commit.gpgsign false && git config tag.gpgSign false \
  && mkdir -p plugins/compass/.claude-plugin \
  && printf '{ "version": "0.22.0" }\n' > plugins/compass/.claude-plugin/plugin.json \
  && git add -A && git commit -qm c && git tag -a v0.22.0 -m r ) >/dev/null 2>&1
SPGL="$SPG/.claude/builds/PROGRAM.md"
spgseed() { { printf '# Program \xe2\x80\x94 prog\n'; printf 'vision: smoke\n'; printf 'current: p1\n'
  printf 'phase 1/2 \xc2\xb7 p1 \xc2\xb7 status=in-flight\n'
  printf 'phase 2/2 \xc2\xb7 p2 \xc2\xb7 status=planned\n'; } > "$SPGL"; }
spgseed; ( cd "$SPG" && bash "$SH" program-advance prog p1 v0.22.0 ) >/dev/null 2>&1; chk "$?" "0" "v0.22 INV-PROGRAM-LEDGER: advance on a space+parens path → exit 0"
chk "$(grep -cE '^phase 1/2 .* status=shipped .* v0\.22\.0$' "$SPGL")" "1" "v0.22 INV-PROGRAM-LEDGER: row rewritten shipped on space+parens path"
spgseed; ( cd "$SPG" && bash "$SH" program-advance prog p1 not-a-real-tag ) >/dev/null 2>&1; chk "$?" "1" "v0.22 INV-PROGRAM-ADVANCE-GUARD: bogus tag rejected on space+parens path"
spgseed; ( cd "$SPG" && bash "$SH" program-ledger prog ) >/dev/null 2>&1; chk "$?" "0" "v0.22 INV-PROGRAM-STALE: clean ledger renders on space+parens path"
{ printf '# Program \xe2\x80\x94 prog\n'; printf 'vision: smoke\n'; printf 'current: p1\n'
  printf 'phase 1/2 \xc2\xb7 p1 \xc2\xb7 status=shipped \xc2\xb7 HEAD\n'
  printf 'phase 2/2 \xc2\xb7 p2 \xc2\xb7 status=planned\n'; } > "$SPGL"
( cd "$SPG" && bash "$SH" program-ledger prog ) >/dev/null 2>&1; chk "$?" "1" "v0.22 INV-PROGRAM-STALE: forged shipped-HEAD row FLAGged on space+parens path"
( cd "$SPG" && rm -f "$SPGL" && bash "$SH" program-next prog ) >/dev/null 2>&1; chk "$?" "1" "v0.22 INV-PROGRAM-NEXT: no ledger on space+parens path → clean non-zero (no set-e crash)"
# INV-MUTATION-EXEC guard-first N/A on a space+parens path (git-independent, byte-inert)
mkdir -p "$SPG/mc-none"; ( cd "$SPG" && bash "$SH" mutation-check mc-none ) >/dev/null 2>&1; chk "$?" "0" "v0.22 INV-MUTATION-EXEC: no receipts.md on space+parens path → N/A exit 0 (guard-first)"
# INV-REDGREEN behavioral (git-independent — reads receipts.md only)
( bash "$SH" redgreen-check "$FXP/redgreen/real" )  >/dev/null 2>&1; chk "$?" "0" "v0.22 INV-REDGREEN: adds-test:yes + real red-green value → PASS"
( bash "$SH" redgreen-check "$FXP/redgreen/empty" ) >/dev/null 2>&1; chk "$?" "1" "v0.22 INV-REDGREEN: adds-test:yes + empty red-green → FLAG"
( bash "$SH" redgreen-check "$FXP/redgreen/na" )    >/dev/null 2>&1; chk "$?" "0" "v0.22 INV-REDGREEN: adds-test:no → N/A-pass"
# INV-SUITES: the v0.22.0 waves added EXACTLY 7 new INV names (64 baseline → 71). A count, not a 4th name copy.
_c22n="$(sed -n 's/^INV_NAMES="\(.*\)"/\1/p' "$PLUGIN_ROOT/scripts/compass.recon.sh")"
chk "$(printf '%s' "$_c22n" | wc -w | tr -d ' ')" "71" "v0.22 INV-SUITES: recon INV_NAMES rose to exactly 71 (64 baseline + 7 new v0.22.0 names)"
# ── v0.22.0 Wave D: skills/commands/release wiring present (grep-enforced — can't silently drift) ──
CSK22="$PLUGIN_ROOT/skills/contract/SKILL.md"; BSK22="$PLUGIN_ROOT/skills/build/SKILL.md"; SSK22="$PLUGIN_ROOT/skills/ship/SKILL.md"
RPK22="$PLUGIN_ROOT/skills/review-plan/SKILL.md"; RBK22="$PLUGIN_ROOT/skills/review-build/SKILL.md"
GO22="$PLUGIN_ROOT/commands/go.md"; RES22="$PLUGIN_ROOT/commands/resume.md"; RR22="$PLUGIN_ROOT/../.."
chk "$(grep -c 'program: <program-name>' "$CSK22")" "1" "v0.22 W-D1: contract skill documents the program: header"
chk "$(grep -c 'TEMPLATE: program-box' "$CSK22")" "1" "v0.22 W-D1: contract skill pins the program-box receipt template"
chk "$([ "$(grep -c 'adds-test:' "$CSK22")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.22 W-D1: contract skill documents the adds-test: field"
chk "$([ "$(grep -c 'mutation-check' "$BSK22")" -ge 1 ] && [ "$(grep -c 'redgreen-check' "$BSK22")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.22 W-D2: build skill runs mutation-check + redgreen-check before the receipt"
chk "$([ "$(grep -c 'red-green:' "$BSK22")" -ge 1 ] && [ "$(grep -c 'mutation:' "$BSK22")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.22 W-D2: build receipt records the red-green:/mutation: lines"
chk "$(grep -c 'git rev-parse -q --verify' "$SSK22")" "1" "v0.22 W-D3: ship skill creates the release tag idempotently (tag before advance)"
chk "$([ "$(grep -c 'program-advance' "$SSK22")" -ge 1 ] && [ "$(grep -c 'hdr_get .* program:' "$SSK22")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.22 W-D3: ship guards program-advance on the program: header (INV-BC)"
chk "$([ "$(grep -c 'program-ledger' "$GO22")" -ge 1 ] && [ "$(grep -c 'program-next' "$GO22")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.22 W-D4: go.md surfaces program-ledger + program-next on the empty branch"
chk "$([ "$(grep -c 'program-ledger' "$RES22")" -ge 1 ] && [ "$(grep -c 'program-next' "$RES22")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.22 W-D4: resume.md surfaces program-ledger + program-next on the 0-active branch"
chk "$([ "$(grep -c 'red-green' "$RPK22")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.22 W-D5: review-plan requires a red-green RED-evidence step"
chk "$([ "$(grep -c 'red-green' "$RBK22")" -ge 1 ] && [ "$(grep -c 'mutation-check' "$RBK22")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.22 W-D5: review-build re-runs mutation-check + re-challenges red-green"
chk "$(grep -c '0.22.0' "$PLUGIN_ROOT/.claude-plugin/plugin.json")" "1" "v0.22 W-D6: plugin.json bumped to 0.22.0"
chk "$(grep -c '0.22.0' "$RR22/.claude-plugin/marketplace.json")" "1" "v0.22 W-D6: marketplace.json bumped to 0.22.0"
chk "$(grep -c '## \[0.22.0\]' "$RR22/CHANGELOG.md")" "1" "v0.22 W-D6: CHANGELOG carries the 0.22.0 entry"

echo "──────── $pass passed, $fail failed ────────"
cd /; rm -rf "$SMOKE_TMP" 2>/dev/null
[ "$fail" = 0 ]
