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

# ── v0.31: assert on what the page SAYS, not on how its markup is written ────────────────────────
# Every number a page states now sits inside a provenance marker (`<span data-prov="counted">3</span>
# findings`), so `grep '3 findings' page.html` stops matching a page that plainly says 3 findings.
# These assertions were always about the rendered text; matching raw markup was incidental. `psays`
# strips tags and collapses whitespace, so it tests the sentence a reader actually reads — which is
# both what the assertion meant and what survives the next markup change.
psays() { # <html-file> <text>  → 0 if the rendered text contains <text>
  # Tags become a SPACE, not a boundary marker. A reviewer proposed matching `page-number.mjs`'s
  # rule (block tags -> `|`) so the two readers could not disagree, and I tried it: it broke 24
  # assertions, because the phrases they check legitimately span elements — the decision chip line
  # `20 steps · 7 done` is three sibling elements and ONE visual line to a reader.
  #
  # The two readers answer different questions and are right to differ. `page-number.mjs` asks "what
  # number does this page state for X?", where fusing across a table cell would invent a number that
  # is not there. `psays` asks "does the rendered text contain this phrase?", where refusing to read
  # across a `<span>` boundary would deny a sentence the reader plainly sees. Same page, two
  # questions. The boundary-fusion risk is real for the first and not for the second.
  LC_ALL=C sed -e 's/<[^>]*>/ /g' "$1" 2>/dev/null \
    | tr '\n' ' ' | sed -e 's/&nbsp;/ /g' -e 's/&amp;/\&/g' -e 's/  */ /g' \
    | grep -qF "$2"
}

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

# ── v0.32 §17-8: the suite must not modify its own TRACKED inputs ────────────────────────────
# `_orient_log` appends an observability line into the same directory as the artefact it just
# observed. Six of those logs were committed, so a full suite run left six TRACKED files modified
# and "is the tree clean?" stopped meaning anything — every later step in this build would have
# rested on a signal that was already false. Two of them had reached the 500-line rotation cap
# INSIDE the repository, so past commits were silently rewriting tracked files.
#
# The naive guard ("fixtures/ is clean at the end") is wrong: it goes red for anyone with a
# legitimate half-finished fixture edit, which trains people to ignore it. The invariant is
# narrower and is about THIS SUITE — take the tracked-fixture state before the run and compare it
# after. A difference is something the suite did. Pre-existing dirt cancels out.
# Guard-first N/A-pass: a tarball install with no git still runs the whole suite.
_v32fx="$PLUGIN_ROOT/scripts/fixtures"
_v32_fxstate() { # → one line per tracked fixture file that differs from the index/HEAD
  git -C "$PLUGIN_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "__nogit__"; return 0; }
  git -C "$PLUGIN_ROOT" status --porcelain -- "$_v32fx" 2>/dev/null | sort
}
_V32_FX_BEFORE="$(_v32_fxstate)"
xblk(){ awk '/<!-- GATE:START -->/{f=1} f{print} /<!-- GATE:END -->/{f=0}' "$1"; }
GATE="$PLUGIN_ROOT/shared/gate.md"
STAGES="contract review-contract plan review-plan build review-build ship"
# INV-1: exactly 3 command files (go/status/resume — the only / menu doors), each with a non-empty description
c1=$(ls "$PLUGIN_ROOT"/commands/*.md | wc -l | tr -d ' ')
chk "$c1" "3" "INV-1 exactly 3 command files remain (the / menu doors)"
cset=$(for c in "$PLUGIN_ROOT"/commands/*.md; do basename "$c" .md; done | sort | xargs)
chk "$cset" "go resume status" "INV-1 the 3 command files are exactly go/resume/status"
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
# INV-4: the 2 migrated skills (start, explain) exist, are hidden from the / menu, with a description
g4=0; for s in start explain; do sk="$PLUGIN_ROOT/skills/$s/SKILL.md"; if [ -f "$sk" ] && grep -q '^user-invocable: false' "$sk" && grep -qE '^description: .+' "$sk"; then g4=$((g4+1)); fi; done
chk "$g4" "2" "INV-4 migrated skills start+explain exist, hidden (user-invocable:false), with a description"
# INV-7: canonical gate block byte-identical across the 7 stage skills (gate.md = canonical source, not a consumer)
canon="$(xblk "$GATE")"
chk "$([ -n "$canon" ] && echo 1 || echo 0)" "1" "INV-7 canonical gate block is non-empty (no vacuous match)"
g7=0; for t in skills/contract/SKILL.md skills/review-contract/SKILL.md skills/plan/SKILL.md skills/review-plan/SKILL.md skills/build/SKILL.md skills/review-build/SKILL.md skills/ship/SKILL.md; do
  [ "$(xblk "$PLUGIN_ROOT/$t")" = "$canon" ] && g7=$((g7+1))
done
chk "$g7" "7" "INV-7 canonical gate block byte-identical across the 7 stage skills"
# RECONCILE: gated stage-skills == 7 (gold=7, exact)
rw=0; for s in $STAGES; do [ -f "$PLUGIN_ROOT/skills/$s/SKILL.md" ] && rw=$((rw+1)); done
chk "$rw" "7" "RECONCILE stage-skill count == 7 (gold)"
chk "$g2" "7" "RECONCILE gated stage-skill count == 7 (gold)"

# ── v0.10.0 --auto autonomous loop wiring ──
disp=0; for c in auto-precheck auto-init budget-init budget-check check-session-chain fire-g2 auto-spawn can-advance; do
  grep -qE "^[[:space:]]+$c\)" "$SH" && disp=$((disp+1)); done
chk "$disp" "8" "v0.10 all 8 --auto subcommands wired in dispatch"
chk "$([ -f "$PLUGIN_ROOT/scripts/spawn-smoke.sh" ] && echo 1 || echo 0)" "1" "v0.10 spawn-smoke.sh present (S0 feasibility gate)"
chk "$(grep -q 'auto-closed:' "$SH" && echo 1 || echo 0)" "1" "v0.10 lifecycle-audit G-L2 accepts the auto-closed marker"
chk "$(grep -lq 'Autonomous mode' "$PLUGIN_ROOT/skills/start/SKILL.md" && echo 1 || echo 0)" "1" "v0.10 start skill documents --auto autonomous mode"
chk "$(grep -lq 'budget.env\|NO JSON\|line-oriented' "$PLUGIN_ROOT/scripts/compass.sh" && echo 1 || echo 0)" "1" "v0.10 state is line-oriented (budget.env, no JSON)"

# ── v0.11.0 autonomous self-spawn wiring ──
d11=0; for c in fire-g1 gate-clear auto-start stage-continuable; do grep -qE "^[[:space:]]+$c\)" "$SH" && d11=$((d11+1)); done
chk "$d11" "4" "v0.11 all 4 new subcommands wired in dispatch (fire-g1/gate-clear/auto-start/stage-continuable)"
# the reorder: the .auto-mode branch must appear BEFORE the gated `is_mid_build || continue` in stop-guard
am=$(grep -n 'sr/\$slug/.auto-mode' "$SH" | head -1 | cut -d: -f1); im=$(grep -n 'is_mid_build "\$sr/\$slug" || continue' "$SH" | head -1 | cut -d: -f1)
chk "$([ -n "$am" ] && [ -n "$im" ] && [ "$am" -lt "$im" ] && echo 1 || echo 0)" "1" "v0.11 stop-guard: .auto-mode branch is BEFORE is_mid_build (fires at all stages — the fix)"
chk "$(grep -lq 'Gated or Autonomous' "$PLUGIN_ROOT/skills/start/SKILL.md" && echo 1 || echo 0)" "1" "v0.11 start skill documents the Gated/Autonomous at-lock choice"
chk "$(grep -lq 'auto-start' "$PLUGIN_ROOT/skills/start/SKILL.md" && echo 1 || echo 0)" "1" "v0.11 start skill documents the auto-start one-command trigger"

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
for nm in INV-ENGINEFIX INV-GRAMMAR INV-PS-NOVERIFIER INV-PS-BUDGET INV-COLDGO INV-SUSPEND F-CONV F-STATUS INV-INTAKE INV-SKETCH INV-TEMPLATES INV-WIRED INV-ORIENT INV-BRIEF INV-LOCK INV-MODE INV-EXPLAIN INV-FEYNMAN INV-BUGBAR INV-REFUTE INV-DEDUPE INV-RESTORE INV-PARITY INV-FLAG INV-SECPIN INV-COMMSCAN INV-NO-LEAK INV-CANARY INV-BAKE INV-BURNRATE INV-WATCHER INV-ABORT INV-NA-EXPLICIT INV-BC INV-RBACSTRIDE-BLOCK INV-RBACSTRIDE-METHOD INV-RBACSTRIDE-RECEIPT INV-PLAN-RBAC INV-RBAC-NODEP INV-RBAC-BYTEINERT INV-EDGERACE-BLOCK INV-EDGERACE-METHOD INV-EDGERACE-RECEIPT INV-EDGERACE-BYTEINERT INV-PLAN-CONCURRENCY INV-PERFFMEA-BLOCK INV-PERFFMEA-METHOD INV-PERFFMEA-RECEIPT INV-PERFFMEA-BYTEINERT INV-PLAN-FMEA INV-SCHEMA-PIN INV-PERFBUDGET INV-CROSSTAB-BLOCK INV-CROSSTAB-METHOD INV-CROSSTAB-RECEIPT INV-CROSSTAB-BYTEINERT INV-PLAN-CROSSTAB INV-NA-CHALLENGE INV-EXPAND-CONTRACT INV-BACKFILL-RECON INV-ROLLBACK-FWDCOMPAT INV-GREEN-CI INV-PII-GATE INV-IMG-SECRET INV-PROGRAM-LEDGER INV-PROGRAM-ADVANCE-GUARD INV-PROGRAM-NEXT INV-PROGRAM-STALE INV-MUTATION-EXEC INV-MUTATION-RESTORE INV-REDGREEN INV-DORA-RECORD INV-DORA-LEDGER INV-DRIFT INV-HERMETIC-BLOCK INV-HERMETIC-METHOD INV-HERMETIC-RECEIPT INV-DURABILITY INV-ONE-DOOR INV-SURFACE-3 INV-PUSH-STAGE INV-PUSH-RESUME INV-ASCII-CHEAP INV-PERF-ASCII INV-PROGRAM-COCKPIT INV-MULTI-CONTRACT INV-MODE-AT-LOCK INV-ARTIFACT-MILESTONES INV-NO-LIFECYCLE-CHANGE INV-SUITES-GREEN INV-MENU-3 INV-START-SKILL INV-EXPLAIN-SKILL INV-GATE-FOOTER-GO INV-GO-ROUTES INV-NO-DEAD-REF INV-GEN-PARSE INV-BRIEF-IA INV-RENDER-REAL INV-MILESTONE-DELIVERY INV-BRIEF-SHAREABLE INV-VIEW-IA INV-VIEW-DETERMINISTIC INV-VIEW-GATES INV-ORIENT-DELIVERED INV-ORIENT-INERT INV-ORIENT-NOREPEAT INV-CARD INV-CARD-HONEST INV-CARD-CAP INV-CARD-GATE INV-CARD-RECEIPT INV-ONE-RENDERER INV-STATUSLINE INV-MODE-ASKED INV-MODE-VISIBLE INV-NOT-BYTEINERT INV-LOCALE-SAFE INV-TERMINAL-STATUS INV-FENCE-BLIND INV-BANDS INV-LOGIC-BLOCK INV-VERIFY-SHOWN INV-COUNTS-MATCH INV-NO-TRUNCATION INV-COMPLETE-PLAN INV-STRUCTURE INV-FRESH INV-DELIVERED INV-HOUSE; do
  chk "$(grep -cF "$nm" "$PLUGIN_ROOT/scripts/compass.recon.sh")" "1" "recon.sh pins INV group: $nm"
done
chk "$(grep -c 'FLOOR_SELFTEST=556' "$PLUGIN_ROOT/scripts/compass.recon.sh")" "1" "v0.30 recon.sh pins the selftest floor 556 (actual 561) — re-pinned with the assertions that pin it, in the same change"
chk "$(grep -c 'FLOOR_SMOKE=568' "$PLUGIN_ROOT/scripts/compass.recon.sh")" "1" "v0.30 recon.sh pins the smoke floor 568 (actual 573) — re-pinned with the assertions that pin it, in the same change"

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
chk "$(grep -c 'Three doors, everything else driven for you' "$REPO/README.md")" "1" "v0.25 README: the / menu is three doors (namespaced stage commands removed)"

# ── v0.15.0 slice ①: clarity/UX — welcome · compass-visual Brief · explicit lock · mode · explain · Feynman ──
GO15="$PLUGIN_ROOT/commands/go.md"; EXP15="$PLUGIN_ROOT/skills/explain/SKILL.md"; VIS15="$PLUGIN_ROOT/skills/compass-visual"; CSK15="$PLUGIN_ROOT/skills/contract/SKILL.md"
# INV-ORIENT
# v0.29.2 — the two asserts that USED to live here were:
#   grep -c 'Welcome — how Compass works' go.md   == 1
#   grep -q 'Contract-first' && grep -q 'assembly line' go.md
# They passed for twelve versions while the welcome printed 0 times in 30 real
# /compass:go invocations, because they tested that BYTES EXIST IN A FILE, not
# that anything ever reached a user. They are DELETED, not supplemented — a
# byte-presence assert next to a behaviour assert still reports false coverage.
# What replaces them asserts the BEHAVIOUR: the renderer produces the block, and
# the shipped hook actually delivers it on a real payload.
chk "$(bash "$SH" orient --new | grep -c 'Three doors:')" "1" "v0.28 INV-ORIENT: orient --new renders the NEW-BUILD block"
chk "$(bash "$SH" orient --new | diff -q - "$PLUGIN_ROOT/scripts/fixtures/orient/empty/expected.txt" >/dev/null 2>&1 && echo 1 || echo 0)" "1" "v0.28 INV-ORIENT: NEW block is byte-identical to its pinned fixture"
# INV-BRIEF (presence/structure + the pure-node house gates run below on the generated body; the PNG>5KB render stays build-time — Chrome not guaranteed on user machines)
chk "$([ -f "$VIS15/SKILL.md" ] && [ -f "$VIS15/gen.mjs" ] && echo 1 || echo 0)" "1" "v0.15 INV-BRIEF: compass-visual skill + gen.mjs bundled"
chk "$(grep -c '^name: compass-visual' "$VIS15/SKILL.md")" "1" "v0.15 INV-BRIEF: compass-visual frontmatter name"
VSMK="$(mktemp -d)/v"; mkdir -p "$VSMK"
printf '%s\n' '# Contract — vsmk' '## Goal & scope' 'A tiny fixture to exercise the generator.' '## Reconciliation' 'Numeric N/A.' '## Acceptance & INVARIANTs' '- **INV-X:** a bound.' '- **INV-Y:** guards the thing → CRITICAL. → *assert:* grep it.' '## Scope ladder' '- NOW: a' '- LATER: b' '- NEVER: c' > "$VSMK/contract.md"
node "$VIS15/gen.mjs" "$VSMK" brief-body --out "$VSMK/body.html" >/dev/null 2>&1
# v0.30 INV-6: artefacts are BODY FRAGMENTS (the Artifact host supplies the skeleton), so line 1
# is no longer a doctype. REWRITTEN to the property that actually mattered and still does — line 1
# is never a COMPASS-MOCK leak marker — plus the new shape. Deleting it would drop the leak tracer.
chk "$( { ! head -1 "$VSMK/body.html" 2>/dev/null | grep -q '^<!-- COMPASS-MOCK' && head -1 "$VSMK/body.html" 2>/dev/null | grep -qE '^<title>|^<style'; } && echo 1 || echo 0)" "1" "v0.30 INV-6/INV-NO-LEAK: generated body line-1 is a fragment start, never a COMPASS-MOCK marker"
# INV-BRIEF durable house-gates (R3-M5): the pure-node gates run on the generated body IN THE SUITE (no Chrome)
RKG="$PLUGIN_ROOT/skills/rk-house-style"
# v0.30: ARTEFACT views are scored against the PINNED artefact theme, not neutral-indigo.
# REWRITTEN, not deleted — the property ("generated output carries no off-theme colour or face")
# is unchanged; only the theme it is scored against moved, because Compass's own artefacts and the
# product UIs Compass builds are now two systems for two audiences. neutral-indigo stays asserted
# at :248 as the rk-house-style default, which is still true and still matters.
CATH="$PLUGIN_ROOT/skills/compass-visual/themes/compass-artefact.json"
( node "$RKG/gates/anti-drift-grep.mjs" "$VSMK/body.html" "$CATH" >/dev/null 2>&1 ); chk "$?" "0" "v0.15 INV-BRIEF: generated brief-body passes rk-house-style anti-drift (durable gold, no Chrome)"
( node "$RKG/gates/compose-check.mjs" "$VSMK/body.html" >/dev/null 2>&1 ); chk "$?" "0" "v0.15 INV-BRIEF: generated brief-body passes rk-house-style compose-check (durable gold)"
# INV-BRIEF invariant completeness (R3-M2): keep the internal '→ CRITICAL', drop ONLY the '→ *assert:*' tail
node "$VIS15/gen.mjs" "$VSMK" brief --out "$VSMK/brief.html" >/dev/null 2>&1
# v0.32 S7 CHANGED THIS ASSERTION, deliberately. It used to require the assert recipe to be ABSENT
# from the page — correct while the recipe was DESTROYED, and wrong now that it is DISCLOSED in the
# row's own control. The property that matters is unchanged and is now stated more strongly: the
# recipe must not sit inline in the summary, and it MUST be reachable in that row's control.
chk "$( { grep -q 'INV-Y' "$VSMK/brief.html" && grep -q 'CRITICAL' "$VSMK/brief.html"; } && echo 1 || echo 0)" "1" "v0.15 INV-BRIEF: the Brief keeps the invariant and its binding CRITICAL tail"
chk "$(sed -e 's|<details class="rest">|\n@@CTRL@@|g' "$VSMK/brief.html" | grep -v '@@CTRL@@' | grep -c 'grep it' || true)" "0" "v0.15/v0.32 INV-BRIEF: the assert recipe is NOT inline in the summary"
chk "$([ "$(grep -c 'grep it' "$VSMK/brief.html" || true)" -ge 1 ] && echo 1 || echo 0)" "1" "v0.32 S7: ...and it IS on the page, inside a disclosure control — destroyed before, reachable now"
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
# v0.30 INV-2 (BUTTONS): REWRITTEN, not deleted. The old form asserted the typed lock phrase was
# PRESENT; v0.30 removes it because it sat in front of both AskUserQuestion moments and neither
# fired. The property that survives is the one that mattered: the lock is an explicit human
# checkpoint at the Brief seam — now a button, not a sentence.
chk "$( { ! grep -qF "$(cat "$PLUGIN_ROOT/scripts/fixtures/lockphrase.txt")" "$CSK15" && grep -qi 'produce the Contract Brief' "$CSK15" && grep -q 'AskUserQuestion' "$CSK15"; } && echo 1 || echo 0)" "1" "v0.30 INV-2: lock seam is buttons (typed phrase gone, AskUserQuestion present, Brief still produced)"
# INV-MODE
chk "$( { grep -q '\*\*Auto\*\*' "$CSK15" && grep -q 'Human-gated' "$CSK15"; } && echo 1 || echo 0)" "1" "v0.15 INV-MODE: contract skill offers Auto vs Human-gated (each explained)"
# INV-EXPLAIN
chk "$([ -f "$EXP15" ] && grep -q '^description: .\+' "$EXP15" && grep -q 'feynman-walkthrough' "$EXP15" && echo 1 || echo 0)" "1" "v0.15 INV-EXPLAIN: explain skill exists with description + teaching invocation"
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
# ── v0.23.0: HERMETIC review-method island — byte-identical across review-plan + review-build (mirrors PERFFMEA) ──
hisl(){ awk '/HERMETIC:START/{f=1} f{print} /HERMETIC:END/{f=0}' "$1"; }
PP23="$PLUGIN_ROOT/skills/review-plan/SKILL.md"; PB23="$PLUGIN_ROOT/skills/review-build/SKILL.md"
chk "$( diff <(hisl "$PP23") <(hisl "$PB23") >/dev/null 2>&1 && [ -n "$(hisl "$PP23")" ] && echo 1 || echo 0)" "1" "v0.23 INV-HERMETIC-BLOCK: HERMETIC island byte-identical across review-plan + review-build"
chk "$(grep -c 'HERMETIC:START' "$PP23")" "1" "v0.23 INV-HERMETIC-BLOCK: exactly one HERMETIC island in review-plan (no drift/dup)"
chk "$(grep -c 'HERMETIC:START' "$PB23")" "1" "v0.23 INV-HERMETIC-BLOCK: exactly one HERMETIC island in review-build (no drift/dup)"
chk "$( { hisl "$PP23" | grep -qF 'pin the clock' && hisl "$PP23" | grep -qF 'stub the network' && hisl "$PP23" | grep -qF 'run twice' && hisl "$PP23" | grep -qF 'blocks CLOSED' && hisl "$PP23" | grep -qF 'never wave off'; } && echo 1 || echo 0)" "1" "v0.23 INV-HERMETIC-METHOD: island carries pin-clock/stub-network/run-twice + challenge-N/A (never wave off) + blocks-CLOSED"
chk "$( { grep -q 'HERMETIC:.*applied' "$PP23" && grep -q 'HERMETIC:.*applied' "$PB23" && [ "$(hisl "$PP23" | grep -c applied)" = "0" ]; } && echo 1 || echo 0)" "1" "v0.23 INV-HERMETIC-RECEIPT: receipt-anchor 'HERMETIC:.*applied' in both AND the word 'applied' absent from the island body"
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
# v0.23.0 DORA — behavioral on the space+parens path (K-17 quoting coverage)
mkdir -p "$SPG/.claude/builds/dm"
( cd "$SPG" && bash "$SH" dora-record .claude/builds/dm SHIPPED ) >/dev/null 2>&1; chk "$?" "0" "v0.23 INV-DORA-RECORD: record on a space+parens path → exit 0"
chk "$([ "$(grep -c '^dora: dm · outcome=SHIPPED · ' "$SPG/.claude/builds/DORA.md" 2>/dev/null || echo 0)" -ge 1 ] && echo 1 || echo 0)" "1" "v0.23 INV-DORA-RECORD: row appended on space+parens path"
( cd "$SPG" && bash "$SH" dora-ledger ) >/dev/null 2>&1; chk "$?" "0" "v0.23 INV-DORA-LEDGER: renders on space+parens path"
rm -f "$SPG/.claude/builds/DORA.md"; ( cd "$SPG" && bash "$SH" dora-ledger ) >/dev/null 2>&1; chk "$?" "0" "v0.23 INV-DORA-LEDGER: no DORA.md → N/A exit 0 (byte-inert)"
# v0.23.0 W-E: dora-record wired into close (subshell, additive) + the ship-skill instruction
printf 'abn · goal · status=plan · facets=library · touches=x\n' > "$SPG/.claude/builds/INDEX"; mkdir -p "$SPG/.claude/builds/abn"
( cd "$SPG" && bash "$SH" close .claude/builds/abn abn --abandon ) >/dev/null 2>&1; chk "$?" "0" "v0.23 INV-BC: close --abandon exit 0 (dora-record subshell — never fails the close)"
chk "$([ "$(grep -c '^dora: abn · outcome=ROLLED-BACK · ' "$SPG/.claude/builds/DORA.md" 2>/dev/null || echo 0)" -ge 1 ] && echo 1 || echo 0)" "1" "v0.23 INV-DORA-RECORD: close --abandon appended a ROLLED-BACK DORA row (close wiring)"
chk "$([ "$(grep -c 'dora-record' "$PLUGIN_ROOT/skills/ship/SKILL.md")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.23 W-E: ship skill records SHIPPED to the DORA ledger after the SHIPPED write"
# v0.23.0 INV-DURABILITY: contract skill pins the 4 durability template anchors
_dcsk="$PLUGIN_ROOT/skills/contract/SKILL.md"
chk "$( { grep -qF '## Glossary' "$_dcsk" && grep -qF 'alternatives-considered:' "$_dcsk" && grep -qF 'one-way-door:' "$_dcsk" && grep -qF 'RACI:' "$_dcsk"; } && echo 1 || echo 0)" "1" "v0.23 INV-DURABILITY: contract skill pins the 4 durability anchors (## Glossary · alternatives-considered: · one-way-door: · RACI:)"
chk "$(grep -c 'TEMPLATE: durability-box' "$_dcsk")" "1" "v0.23 INV-DURABILITY: contract skill pins the durability-box receipt template"
_c22n="$(sed -n 's/^INV_NAMES="\(.*\)"/\1/p' "$PLUGIN_ROOT/scripts/compass.recon.sh")"
chk "$(printf '%s' "$_c22n" | wc -w | tr -d ' ')" "130" "v0.29 INV-SUITES-GREEN: recon INV_NAMES == 130 (119 + the 11 v0.29 visual-artefact names)"
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
# v0.32 INSTRUMENT REPAIR: these three pins were three INDEPENDENT hardcoded literals, so they
# could — and did — drift apart. Commit 8e1fc84 corrected marketplace.json to 0.31.0 and left the
# assertion greping for 0.29.2, so the suite was RED at HEAD (686/1) and no round of any build
# could honestly be called clean. The CHANGELOG pin was worse: it asserted an OLD entry still
# exists, and a CHANGELOG only ever grows, so that assertion could never fail.
# Now all three DERIVE from one source (plugin.json) and assert agreement — a behaviour test
# ("these files say the same thing") instead of three prose greps for a literal. It survives the
# next version bump instead of breaking on it.
_v32rel="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
chk "$([ -n "$_v32rel" ] && echo 1 || echo 0)" "1" "v0.32 W-F: plugin.json declares a version (the single source the other pins derive from)"
chk "$(grep -c "\"$_v32rel\"" "$RR22/.claude-plugin/marketplace.json")" "1" "v0.32 W-F: marketplace.json agrees with plugin.json ($_v32rel)"
chk "$(grep -c "## \[$_v32rel\]" "$RR22/CHANGELOG.md")" "1" "v0.32 W-F: CHANGELOG carries the $_v32rel entry"

# ══ v0.24.0 clarity-simplicity — behavioral teeth ══════════════════════════════════════════════
CURSH="$PLUGIN_ROOT/scripts/compass.sh"
V24="$(mktemp -d)"; mkdir -p "$V24/.claude/builds/b"
cat > "$V24/.claude/builds/PROGRAM.md" <<'PEOF'
# Program — demo24
current: p2
phase 1/2 · p1 · status=shipped · v0.1.0
  contract: p1-a · status=shipped
  contract: p1-b · status=shipped
phase 2/2 · p2 · status=in-flight
  contract: p2-a · status=shipped
  contract: p2-b · status=in-flight
PEOF
printf '# Contract\n- **program:** demo24\n' > "$V24/.claude/builds/b/contract.md"
printf '**Next:** build\n' > "$V24/.claude/builds/b/progress.md"
printf '## RECEIPT — contract · b · PASS\n## RECEIPT — review-contract · b · PASS\n' > "$V24/.claude/builds/b/receipts.md"
printf -- '- [x] **1. a**\n- [ ] **2. b**\n' > "$V24/.claude/builds/b/plan.md"
COUT="$("$SH" cockpit "$V24/.claude/builds/b" 2>/dev/null || true)"

# INV-COCKPIT / INV-PUSH-STAGE — the pushed strip renders
chk "$(printf '%s' "$COUT" | grep -cE 'BUILD ·')" "1" "v0.24 INV-COCKPIT: cockpit prints the BUILD strip"
chk "$(printf '%s' "$COUT" | grep -c '▲ plan')" "1" "v0.24 INV-PUSH-STAGE: marker lands on the correct stage from CANONICAL receipts (contract+review-contract PASS → plan) — bites the R1 receipt-format bug"
chk "$(awk '/<!-- GATE:START -->/{f=1} f{print} /<!-- GATE:END -->/{f=0}' "$PLUGIN_ROOT/shared/gate.md" | grep -c 'compass.sh cockpit')" "1" "v0.24 INV-PUSH-STAGE: the canonical gate block invokes compass.sh cockpit"
# INV-MULTI-CONTRACT — both contracts render, and a status flip flips the glyph (teeth)
chk "$([ "$(printf '%s' "$COUT" | grep -c 'p2-a')" -ge 1 ] && [ "$(printf '%s' "$COUT" | grep -c 'p2-b')" -ge 1 ] && echo 1 || echo 0)" "1" "v0.24 INV-MULTI-CONTRACT: both contracts in phase 2 render"
sed -i.bak 's/p2-a · status=shipped/p2-a · status=planned/' "$V24/.claude/builds/PROGRAM.md"
chk "$("$SH" cockpit "$V24/.claude/builds/b" 2>/dev/null | grep 'p2-a' | grep -c '○')" "1" "v0.24 INV-MULTI-CONTRACT teeth: contract shipped→planned flips its glyph ✓→○"
# INV-PROGRAM-COCKPIT — suppressed when there is no ledger
rm -f "$V24/.claude/builds/PROGRAM.md"
chk "$("$SH" cockpit "$V24/.claude/builds/b" 2>/dev/null | grep -c 'PROGRAM ·')" "0" "v0.24 INV-PROGRAM-COCKPIT: program strip suppressed with no ledger"
# INV-ASCII-CHEAP / INV-PERF-ASCII — cmd_cockpit body pays no renderer or git-heavy ledger cost
chk "$(awk '/^cmd_cockpit\(\) \{/{f=1} f{print} f&&/^}$/{exit}' "$CURSH" | grep -cE 'render\.sh|gen\.mjs|chrome|headless')" "0" "v0.24 INV-ASCII-CHEAP: cmd_cockpit invokes no renderer"
chk "$(awk '/^cmd_cockpit\(\) \{/{f=1} f{print} f&&/^}$/{exit}' "$CURSH" | grep -cE 'cmd_program_ledger|_tag_is_real_and_bound')" "0" "v0.24 INV-PERF-ASCII: cmd_cockpit avoids the git-heavy ledger path"
# INV-SURFACE-3 — 3 primary (go/status/resume) · 9 advanced · 12 present · WELCOME lists no advanced invocation
chk "$(grep -l '^tier: primary' "$PLUGIN_ROOT"/commands/*.md | wc -l | tr -d ' ')" "3" "v0.24 INV-SURFACE-3: exactly 3 primary commands"
chk "$(grep -q '^tier: primary' "$PLUGIN_ROOT/commands/go.md" && grep -q '^tier: primary' "$PLUGIN_ROOT/commands/status.md" && grep -q '^tier: primary' "$PLUGIN_ROOT/commands/resume.md" && echo 1 || echo 0)" "1" "v0.24 INV-SURFACE-3: the 3 primary are go/status/resume"
chk "$(grep -l '^tier: advanced' "$PLUGIN_ROOT"/commands/*.md 2>/dev/null | wc -l | tr -d ' ')" "0" "v0.25 INV-SURFACE-3: 0 advanced command files remain (the 9 were removed)"
chk "$(ls "$PLUGIN_ROOT"/commands/*.md | wc -l | tr -d ' ')" "3" "v0.25 INV-SURFACE-3: exactly 3 command files present (go/status/resume)"
WB="$(awk '/<!-- WELCOME:START -->/{f=1} f{print} /<!-- WELCOME:END -->/{f=0}' "$PLUGIN_ROOT/commands/go.md")"
chk "$([ -n "$WB" ] && echo 1 || echo 0)" "1" "v0.24 INV-SURFACE-3: WELCOME block present in go.md"
chk "$(printf '%s' "$WB" | grep -cE '/compass:(start|contract|plan|build|ship|explain|review-)')" "0" "v0.24 INV-SURFACE-3: WELCOME block lists no advanced command invocation"
# INV-ONE-DOOR — go.md branches to both resume and new-build
chk "$([ "$(grep -c 'esume' "$PLUGIN_ROOT/commands/go.md")" -ge 1 ] && [ "$(grep -c 'ew build' "$PLUGIN_ROOT/commands/go.md")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.24 INV-ONE-DOOR: go.md branches to resume AND new-build"
# INV-PUSH-RESUME — go.md + resume.md push the cockpit on re-entry
chk "$([ "$(grep -c 'compass.sh cockpit' "$PLUGIN_ROOT/commands/go.md")" -ge 1 ] && [ "$(grep -c 'compass.sh cockpit' "$PLUGIN_ROOT/commands/resume.md")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.24 INV-PUSH-RESUME: go.md + resume.md push the cockpit"
# INV-MODE-AT-LOCK — the pre-contract mode prompt is gone (kill test = the deletion)
chk "$(grep -c 'BEFORE writing the contract' "$PLUGIN_ROOT/skills/start/SKILL.md")" "0" "v0.24 INV-MODE-AT-LOCK: start skill has no pre-contract mode prompt"
# INV-ARTIFACT-MILESTONES — the 3 views exist + milestone-gate bites (negative fails, positive passes)
chk "$([ "$(grep -c "'plan-map'" "$PLUGIN_ROOT/skills/compass-visual/gen.mjs")" -ge 1 ] && [ "$(grep -c "'review'" "$PLUGIN_ROOT/skills/compass-visual/gen.mjs")" -ge 1 ] && [ "$(grep -c "'release-card'" "$PLUGIN_ROOT/skills/compass-visual/gen.mjs")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.30 INV-ARTIFACT-MILESTONES: gen.mjs adds plan-map/review/release-card"
if ( "$SH" milestone-gate "$V24/.claude/builds/b" release-card ) >/dev/null 2>&1; then mn=0; else mn=1; fi
chk "$mn" "1" "v0.24 INV-ARTIFACT-MILESTONES: milestone-gate FAILS when the artifact is absent (biting)"
printf 'x' > "$V24/.claude/builds/b/release-card.html"
printf -- '- [x] MILESTONE: release-card render=release-card.html bytes=1\n' >> "$V24/.claude/builds/b/receipts.md"
if ( "$SH" milestone-gate "$V24/.claude/builds/b" release-card ) >/dev/null 2>&1; then mp=0; else mp=1; fi
chk "$mp" "0" "v0.24 INV-ARTIFACT-MILESTONES: milestone-gate PASSES when the HTML artifact exists"
# INV-NO-LIFECYCLE-CHANGE — frozen units byte-identical to v0.23.0 (name-anchored extract)
_ex(){ awk -v fn="$1" '$0 ~ "^"fn"\\(\\) \\{"{f=1} f{print} f&&/^}$/{exit}'; }
V23="$(git -C "$PLUGIN_ROOT" show v0.23.0:plugins/compass/scripts/compass.sh 2>/dev/null || true)"
frz=1
if [ -n "$V23" ]; then
  # v0.29.2 — the freeze is NARROWED, deliberately and with user sign-off (G2).
  # v0.24 froze cmd_gate byte-for-byte. But the codebase itself contradicts the
  # strict reading: schema-pin, perf-budget, expand-contract, backfill-recon and
  # green-ci are ALL additive guard-first arms added to these very seams. The
  # invariant's intent is "gate SEMANTICS must not drift", not "cmd_gate may
  # never gain another no-op-on-legacy check". So cmd_gate is now pinned on two
  # narrower, stronger properties instead (asserted just below):
  #   1. its CORE decision logic is byte-identical to v0.23.0, and
  #   2. every seam call it makes is guard-first (`if type ... >/dev/null`),
  #      so a legacy build passes exactly as before.
  for fn in cmd_restore_point cmd_config_parity cmd_migration_gate cmd_check_db_isolation; do
    a="$(printf '%s' "$V23" | _ex "$fn")"; b="$(_ex "$fn" < "$CURSH")"
    { [ -n "$a" ] && [ "$a" = "$b" ]; } || frz=0
  done
  la="$(printf '%s' "$V23" | grep '^LIFECYCLE=')"; lb="$(grep '^LIFECYCLE=' "$CURSH")"
  { [ -n "$la" ] && [ "$la" = "$lb" ]; } || frz=0
else frz=1; fi   # tag unreachable (shallow/CI clone) → do not false-FAIL
chk "$frz" "1" "v0.28 INV-NO-LIFECYCLE-CHANGE: LIFECYCLE + prod-safety fns byte-identical to v0.23.0"
# cmd_gate core: everything from the function head down to the first seam block.
# This is the part that decides PASS / SUPERSEDED / unchecked-box — the actual
# gate semantics. It must never drift.
_core() { awk '/^cmd_gate\(\) \{/{f=1} f&&/v0\.13\.0 seams/{exit} f{print}'; }
_ca="$(printf '%s' "$V23" | _core)"; _cb="$(_core < "$CURSH")"
chk "$([ -n "$_ca" ] && [ "$_ca" = "$_cb" ] && echo 1 || echo 0)" "1" "v0.28 INV-NO-LIFECYCLE-CHANGE: cmd_gate CORE decision logic byte-identical to v0.23.0 (PASS/SUPERSEDED/unchecked-box semantics frozen)"
# Every seam function cmd_gate invokes must be `type`-guarded, so a build whose
# Compass predates that gate passes byte-identically. cmd_intake_gate is the one
# grandfathered exception: it was already unguarded before the v0.24 freeze.
_gbody="$(_ex cmd_gate < "$CURSH")"
_unguarded=0
for _fn in $(printf '%s' "$_gbody" | grep -oE 'cmd_[a-z_]+_gate' | sort -u); do
  [ "$_fn" = "cmd_intake_gate" ] && continue
  printf '%s' "$_gbody" | grep -q "type $_fn >/dev/null 2>&1" || _unguarded=1
done
chk "$_unguarded" "0" "v0.28 INV-NO-LIFECYCLE-CHANGE: every cmd_gate seam call is type-guarded (a legacy build passes byte-identically)"
chk "$(printf '%s' "$_gbody" | grep -c 'type cmd_mode_gate >/dev/null 2>&1')" "1" "v0.28 INV-MODE-ASKED: mode-gate rides the contract seam, guard-first"
rm -rf "$V24"
# ═══════════════════════════════════════════════════════════════════════════════════════════════

# ── v0.25.0: trim the / menu to 3 (user-invocable:false mechanism + dead-ref scrub) ──
DEADPAT='/compass:(start|contract|plan|build|ship|explain|review-[a-z-]+|rk-house-style|cinematic-hero|compass-visual)'
# INV-MENU-3: the / menu = exactly 3 command files {go,status,resume} AND every skill hidden (user-invocable:false)
_m3c=$(ls "$PLUGIN_ROOT"/commands/*.md | wc -l | tr -d ' ')
_m3set=$(for c in "$PLUGIN_ROOT"/commands/*.md; do basename "$c" .md; done | sort | xargs)
_m3false=$(grep -l '^user-invocable: false' "$PLUGIN_ROOT"/skills/*/SKILL.md | wc -l | tr -d ' ')
_m3true=$(grep -l '^user-invocable: true' "$PLUGIN_ROOT"/skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
_m3total=$(ls -d "$PLUGIN_ROOT"/skills/*/SKILL.md | wc -l | tr -d ' ')
chk "$([ "$_m3c" = "3" ] && [ "$_m3set" = "go resume status" ] && echo 1 || echo 0)" "1" "v0.25 INV-MENU-3: exactly 3 command files, the set == {go,resume,status}"
chk "$([ "$_m3false" = "$_m3total" ] && [ "$_m3true" = "0" ] && echo 1 || echo 0)" "1" "v0.25 INV-MENU-3: every skill hidden (user-invocable:false, none :true) — nothing extra shows in /"
# INV-START-SKILL: start.md migrated to skills/start (orchestrator intact, hidden, 0 dead slashes)
_ss="$PLUGIN_ROOT/skills/start/SKILL.md"; _ssok=1
{ [ -f "$_ss" ] && grep -q '^user-invocable: false' "$_ss" && grep -qE '^description: .+' "$_ss"; } || _ssok=0
for g in 'Autonomous mode' 'Gated or Autonomous' 'auto-start' 'pipeline'; do grep -qF "$g" "$_ss" || _ssok=0; done
[ "$(grep -roE "$DEADPAT" "$_ss" | wc -l | tr -d ' ')" = "0" ] || _ssok=0
chk "$_ssok" "1" "v0.25 INV-START-SKILL: skills/start migrated (orchestrator intact, hidden, no dead slashes)"
# INV-EXPLAIN-SKILL: explain.md migrated to skills/explain (feynman, hidden, 0 dead slashes)
_es="$PLUGIN_ROOT/skills/explain/SKILL.md"; _esok=1
{ [ -f "$_es" ] && grep -q '^user-invocable: false' "$_es" && grep -qE '^description: .+' "$_es" && grep -q 'feynman-walkthrough' "$_es"; } || _esok=0
[ "$(grep -roE "$DEADPAT" "$_es" | wc -l | tr -d ' ')" = "0" ] || _esok=0
chk "$_esok" "1" "v0.25 INV-EXPLAIN-SKILL: skills/explain migrated (feynman-walkthrough, hidden, no dead slashes)"
# INV-GATE-FOOTER-GO: the canonical gate block points at /compass:go, not the old per-stage command
_gblk="$(xblk "$GATE")"
chk "$(printf '%s' "$_gblk" | grep -c '/compass:go')" "1" "v0.25 INV-GATE-FOOTER-GO: gate footer runs /compass:go"
chk "$(printf '%s' "$_gblk" | grep -c '/compass:<next stage>')" "0" "v0.25 INV-GATE-FOOTER-GO: old /compass:<next stage> footer literal is gone"
chk "$(printf '%s' "$_gblk" | grep -cE '/compass:(start|contract|plan|build|ship|review-[a-z-]+)')" "0" "v0.25 INV-GATE-FOOTER-GO: gate block names no dead /compass:<stage> command"
# INV-GO-ROUTES: go.md has no dead slash + still names the compass:start/compass:contract skill routes
chk "$(grep -roE "$DEADPAT" "$PLUGIN_ROOT/commands/go.md" | wc -l | tr -d ' ')" "0" "v0.25 INV-GO-ROUTES: go.md has no dead /compass:<removed> slash"
chk "$([ "$(grep -c 'compass:start' "$PLUGIN_ROOT/commands/go.md")" -ge 1 ] && [ "$(grep -c 'compass:contract' "$PLUGIN_ROOT/commands/go.md")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.25 INV-GO-ROUTES: go.md still routes into the compass:start/compass:contract skills"
# INV-NO-DEAD-REF: no shippable surface points at a removed /compass:<x> (CHANGELOG exempt)
_ndr=0
for f in "$REPO/README.md" "$REPO/ROADMAP.md" "$PLUGIN_ROOT/scripts/compass.sh" "$PLUGIN_ROOT/shared/gate.md" "$PLUGIN_ROOT/commands/go.md"; do
  _ndr=$((_ndr + $(grep -roE "$DEADPAT" "$f" | wc -l | tr -d ' ')))
done
_ndr=$((_ndr + $(grep -roE "$DEADPAT" "$PLUGIN_ROOT"/skills/*/SKILL.md | wc -l | tr -d ' ')))
chk "$_ndr" "0" "v0.25 INV-NO-DEAD-REF: no dead /compass:<removed> ref across README/ROADMAP/compass.sh/gate.md/go.md/skills"
chk "$(grep -c 'commands/start.md' "$PLUGIN_ROOT/shared/gate.md")" "0" "v0.25 INV-NO-DEAD-REF: gate.md header has no commands/start.md file-path ref"
chk "$(grep -c 'start.md' "$PLUGIN_ROOT/commands/resume.md")" "0" "v0.25 INV-NO-DEAD-REF: resume.md has no dangling start.md ref"

# ── v0.29.2: visual Brief redesign + delivery enforcement ──
FXB="$PLUGIN_ROOT/scripts/fixtures/brief-contract"
GENJS="$PLUGIN_ROOT/skills/compass-visual/gen.mjs"
V26T="$(mktemp -d)"
node "$GENJS" "$FXB" brief-body --out "$V26T/body.html" >/dev/null 2>&1
# INV-GEN-PARSE — hero shows the Goal not the Non-goals sentinel (region-scoped); every card populated
_hero="$(awk '/class="ba"/{exit} {print}' "$V26T/body.html")"
# v0.30: the goal moved out of the lede into the Build-what fact card (it used to render in
# both, one directly under the other). Same property, new home — rewritten, not deleted.
_lede="$(grep -o 'Build what</div><div class="v">[^<]*' "$V26T/body.html" | head -1)"
chk "$([ "$(printf '%s' "$_lede" | grep -c 'revenue')" -ge 1 ] && [ "$(printf '%s' "$_hero" | grep -c 'NONGOAL-SENTINEL')" -eq 0 ] && echo 1 || echo 0)" "1" "v0.26 INV-GEN-PARSE: the lede shows the real Goal (an empty goal reddens it) + hero carries no Non-goals sentinel"
# exercise sec('Goal') ITSELF (a contract with NO **Goal:** header falls through to sec) — this is what bites the anchored-sec fix
node "$GENJS" "$PLUGIN_ROOT/scripts/fixtures/brief-contract-nohdr" brief-body --out "$V26T/nohdr.html" >/dev/null 2>&1
_hn="$(awk '/class="ba"/{exit} {print}' "$V26T/nohdr.html")"
chk "$([ "$(printf '%s' "$_hn" | grep -c 'GOALSEC-REAL-PP')" -ge 1 ] && [ "$(printf '%s' "$_hn" | grep -c 'GOALSEC-DECOY-QQ')" -eq 0 ] && echo 1 || echo 0)" "1" "v0.26 INV-GEN-PARSE: with no **Goal:** header, sec('Goal') resolves to the Goal section not Non-goals (the anchored-sec fix BITES — a substring sec() renders the DECOY here)"
chk "$([ "$(grep -c '1234567' "$V26T/body.html")" -ge 1 ] && [ "$(grep -c 'INV-RECON-TIE' "$V26T/body.html")" -ge 1 ] && [ "$(grep -c 'INV-IDEMPOTENT' "$V26T/body.html")" -ge 1 ] && [ "$(grep -c 'INV-FRESH-BY-6AM' "$V26T/body.html")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.26 INV-GEN-PARSE: reconciliation literal + all 3 fixture INV names present (every card populated, not blanked by an exact-equality over-fix)"
# INV-BRIEF-IA — the 6 regions + flow/guardrails POPULATED + deterministic
# v0.29.2 REWRITTEN (not retired) — the v0.26 regions (before→after · done · flow · guardrails
# · fold) encoded the OLD layout, and the v0.29 contract explicitly removes Before/After as
# empty scaffolding. The INTENT — "the mental-model regions are all present" — is preserved
# verbatim against the NEW four-band skeleton, which is the same assertion about a different
# structure. Retiring it would have meant the redesign was never checked.
_r=0; for cls in 'class="b-decide"' 'class="b-facts"' 'class="b-flow"' 'class="b-sec"' '<svg'; do grep -q "$cls" "$V26T/body.html" && _r=$((_r+1)); done
chk "$_r" "5" "v0.29 INV-BRIEF-IA: the four bands + the logic block are all present (decision · facts · flow · detail · diagram)"
# The "not empty shells" half is BEHAVIOURAL and is preserved exactly: the facts row and the
# scope list must carry real content, not styled emptiness.
chk "$([ "$(grep -o 'class="b-fact"' "$V26T/body.html" | wc -l | tr -d ' ')" -ge 4 ] && [ "$(awk '/class="pl"/{f=1} f&&/<li>/{n++} /<\/ul>/{if(f)exit} END{print n+0}' "$V26T/body.html")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.29 INV-BRIEF-IA: facts row + scope list POPULATED (real content, not empty shells)"
node "$GENJS" "$FXB" brief-body --out "$V26T/body2.html" >/dev/null 2>&1
chk "$(diff -q "$V26T/body.html" "$V26T/body2.html" >/dev/null 2>&1 && echo 1 || echo 0)" "1" "v0.26 INV-BRIEF-IA: deterministic (two runs byte-identical)"
# INV-RENDER-REAL — the no-browser fail leg is mandatory + reasoned; the browser leg is probe-guarded/skipped
COMPASS_NO_BROWSER=1 "$SH" render "$V26T/body.html" "$V26T/nb.png" >"$V26T/rerr" 2>&1; _nbrc=$?
chk "$([ "$_nbrc" -ne 0 ] && grep -q 'N/A' "$V26T/rerr" && [ ! -s "$V26T/nb.png" ] && echo 1 || echo 0)" "1" "v0.26 INV-RENDER-REAL: COMPASS_NO_BROWSER render exits non-zero WITH a reason and no 0-byte PNG (a fake png=N/A can't be honest)"
if [ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ] || command -v google-chrome >/dev/null 2>&1 || command -v chromium >/dev/null 2>&1; then
  "$SH" render "$V26T/body.html" "$V26T/br.png" >/dev/null 2>&1; _brc=$?
  chk "$([ "$_brc" -eq 0 ] && [ -s "$V26T/br.png" ] && echo 1 || echo 0)" "1" "v0.26 INV-RENDER-REAL: with a browser present, render produces a non-empty PNG (exit 0)"
fi   # else: Chrome not guaranteed in CI — the real PNG is proven at build + ship time (matches the render-stays-build-time precedent)
# INV-MILESTONE-DELIVERY — guard-first + fail-closed grammar (negatives FAIL, positives incl. legacy PASS)
printf 'x' > "$V26T/a.html"; printf 'x' > "$V26T/a.png"
_mg() { printf -- "- [x] MILESTONE: m render=%s\n" "$2" > "$V26T/receipts.md"; ( "$SH" milestone-gate "$V26T" m ) >/dev/null 2>&1; local rc=$?; if [ "$1" = pass ]; then chk "$rc" "0" "$3"; else chk "$([ "$rc" -ne 0 ] && echo 1 || echo 0)" "1" "$3"; fi; }
_mg pass 'a.html png=a.png artifact=https://claude.ai/code/artifact/xyz' "v0.26 INV-MILESTONE-DELIVERY: full delivery (render+png+url) PASSES"
_mg pass 'a.html png=N/A — no browser artifact=N/A — headless (no Artifact tool)' "v0.26 INV-MILESTONE-DELIVERY: honest degrade (reasoned N/A both) PASSES"
_mg pass 'a.html png=N/A — no renderer' "v0.26 INV-MILESTONE-DELIVERY: legacy line (no artifact= token, png=N/A) PASSES — png= does NOT trigger strict (the C2 non-break)"
_mg fail 'a.html png=a.png artifact=N/A' "v0.26 INV-MILESTONE-DELIVERY: bare artifact=N/A (no reason) FAILS closed"
_mg fail 'a.html png=N/A artifact=https://claude.ai/x' "v0.26 INV-MILESTONE-DELIVERY: bare png=N/A (no reason) FAILS closed"
_mg fail 'a.html png=a.png artifact=notaurl' "v0.26 INV-MILESTONE-DELIVERY: non-url non-N/A artifact FAILS"
_mg fail 'nope.html png=a.png artifact=https://claude.ai/x' "v0.26 INV-MILESTONE-DELIVERY: render= path absent FAILS"
chk "$([ "$(grep -c 'milestone-gate' "$PLUGIN_ROOT/skills/contract/SKILL.md")" -ge 1 ] && [ "$(grep -c 'milestone-gate' "$PLUGIN_ROOT/skills/plan/SKILL.md")" -ge 1 ] && [ "$(grep -c 'milestone-gate' "$PLUGIN_ROOT/skills/ship/SKILL.md")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.26 INV-MILESTONE-DELIVERY: contract/plan/ship skills invoke milestone-gate (reaches the Brief, not just ship)"
chk "$([ "$(grep -c 'artifact=' "$PLUGIN_ROOT/skills/contract/SKILL.md")" -ge 1 ] && [ "$(grep -c 'artifact=' "$PLUGIN_ROOT/skills/plan/SKILL.md")" -ge 1 ] && [ "$(grep -c 'artifact=' "$PLUGIN_ROOT/skills/ship/SKILL.md")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.26 INV-MILESTONE-DELIVERY: milestone templates carry an artifact= token (can't be dodged by omission)"
# INV-BRIEF-SHAREABLE — declared numeric gold → exit 3 + absent; fold uses firstPara not bodyHtml
node "$GENJS" "$FXB" brief-body --shareable --out "$V26T/sh.html" >/dev/null 2>&1; _shrc=$?
chk "$([ "$_shrc" -eq 3 ] && [ "$(grep -c '1234567' "$V26T/sh.html" 2>/dev/null)" -eq 0 ] && echo 1 || echo 0)" "1" "v0.26 INV-BRIEF-SHAREABLE: declared numeric gold in a rendered region → exit 3 AND literal absent"
chk "$(grep -c 'FOLD-LEAK-SENTINEL' "$V26T/sh.html" 2>/dev/null)" "0" "v0.26 INV-BRIEF-SHAREABLE: the fold uses firstPara not raw bodyHtml (undeclared para-2 sentinel absent on shareable — the leak gate can't catch it, so this bites)"
chk "$(grep -c 'FOLD-LEAK-SENTINEL' "$V26T/body.html")" "1" "v0.26 INV-BRIEF-SHAREABLE: the LOCAL brief keeps the full body (sentinel present locally — proves the distinction)"
chk "$([ "$(grep -c 'S&P_score' "$V26T/sh.html" 2>/dev/null)" -eq 0 ] && [ "$(grep -c 'S&amp;P_score' "$V26T/sh.html" 2>/dev/null)" -eq 0 ] && echo 1 || echo 0)" "1" "v0.26 INV-BRIEF-SHAREABLE: a declared never-show value with an HTML metachar (S&P_score) is scrubbed in BOTH raw + escaped form (RB-v0.26 leak fix — esc()'d prose no longer slips a raw-only regex)"
rm -rf "$V26T"

# ── v0.29.2: milestone-view mental-model redesign (plan-map/release-card/program-cockpit) ──
FXV="$PLUGIN_ROOT/scripts/fixtures/view-fixture"
GENV="$PLUGIN_ROOT/skills/compass-visual/gen.mjs"
THEMEV="$PLUGIN_ROOT/skills/compass-visual/themes/compass-artefact.json"  # v0.30: artefact views score against the pinned artefact theme
ADV="$PLUGIN_ROOT/skills/rk-house-style/gates/anti-drift-grep.mjs"
COV="$PLUGIN_ROOT/skills/rk-house-style/gates/compose-check.mjs"
V27T="$(mktemp -d)"
node "$GENV" "$FXV/b" plan-map --out "$V27T/pm.html" >/dev/null 2>&1
node "$GENV" "$FXV/b" release-card --out "$V27T/rc.html" >/dev/null 2>&1
node "$GENV" "$FXV/b" program-cockpit --out "$V27T/pc.html" >/dev/null 2>&1
# INV-VIEW-IA — the new region classes (absent from the pre-v0.27 bodies) + populated content
# v0.29.2 REWRITTEN (not retired). The old assert required `vp-hero`, `vp-prog` and **≥1 wave**
# — but the v0.29 contract explicitly REMOVES the wave chip (a plan that uses no waves must not
# render "0 waves"). Asserting ≥1 wave would have forced the exact defect this release fixes.
# The intent — "the plan map carries its mental-model IA, populated" — is preserved against the
# new bands, and strengthened: every step must now also carry its VERIFY block.
chk "$([ "$(grep -c 'class="b-decide"' "$V27T/pm.html")" -ge 1 ] && [ "$(grep -c 'class="b-facts"' "$V27T/pm.html")" -ge 1 ] && [ "$(grep -o 'class="b-step"' "$V27T/pm.html" | wc -l | tr -d ' ')" -ge 1 ] && [ "$(grep -o 'class="verify"' "$V27T/pm.html" | wc -l | tr -d ' ')" -ge 1 ] && echo 1 || echo 0)" "1" "v0.29 INV-VIEW-IA: plan-map has the decision + facts bands, ≥1 step, and every step carries its VERIFY"
chk "$([ "$(grep -c 'card vr-hero' "$V27T/rc.html")" -ge 1 ] && [ "$(grep -c 'v9.9.9' "$V27T/rc.html")" -ge 1 ] && [ "$(grep -c '<li>' "$V27T/rc.html")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.27 INV-VIEW-IA: release-card has the vr-hero + version (not ?) + ≥1 changed item"
chk "$([ "$(grep -c 'LATER-SENTINEL' "$V27T/rc.html")" -eq 0 ] && [ "$(grep -c 'NEVER-SENTINEL' "$V27T/rc.html")" -eq 0 ] && echo 1 || echo 0)" "1" "v0.27 INV-VIEW-IA: release-card shows NOW items ONLY — LATER/NEVER absent (the v0.24 R2 guard, now biting)"
node "$GENV" "$FXV/b" review --out "$V27T/rv.html" >/dev/null 2>&1
chk "$([ "$(grep -c 'b-step' "$V27T/rv.html")" -ge 1 ] && [ "$(grep -c 'Compass · Review' "$V27T/rv.html")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.30 INV-VIEW-IA: the review artefact renders its finding rows (replaces the deleted program-cockpit assertion)"
mkdir -p "$V27T/eb/b"; cp "$FXV/b"/*.md "$V27T/eb/b/" 2>/dev/null; node "$GENV" "$V27T/eb/b" program-cockpit --out "$V27T/pce.html" >/dev/null 2>&1
node "$GENV" "$V27T/eb/b" review --out "$V27T/rve.html" >/dev/null 2>&1
# The PROPERTY, not the wording: a build with no ledger must say so and must NEVER print the
# all-clear. Three shipped builds rendered "Every finding was fixed and re-checked. Nothing is
# waiting on you." over a directory containing no review-ledger.md at all.
chk "$([ "$(grep -ci 'no review-ledger\|No review has been recorded\|no ledger rows yet' "$V27T/rve.html")" -ge 1 ] && [ "$(grep -c 'Nothing is waiting on you' "$V27T/rve.html")" -eq 0 ] && echo 1 || echo 0)" "1" "v0.30 INV-VIEW-IA: no ledger says so and never prints the all-clear"
# INV-VIEW-DETERMINISTIC — each view byte-identical across two runs
_det=1; for v in plan-map release-card review; do node "$GENV" "$FXV/b" $v --out "$V27T/x-$v.html" >/dev/null 2>&1; node "$GENV" "$FXV/b" $v --out "$V27T/y-$v.html" >/dev/null 2>&1; diff -q "$V27T/x-$v.html" "$V27T/y-$v.html" >/dev/null 2>&1 || _det=0; done
chk "$_det" "1" "v0.30 INV-VIEW-DETERMINISTIC: plan-map/release-card/review each byte-identical across two runs"
# INV-VIEW-GATES — each redesigned view body (+ brief-body) passes anti-drift + compose
node "$GENV" "$FXV/b" brief-body --out "$V27T/bb.html" >/dev/null 2>&1
# v0.30: `pc` was the program-cockpit file, which the generator no longer writes. Re-pointed
# at the review artefact that replaced it, so the gate coverage stays at four views.
node "$GENV" "$FXV/b" review --out "$V27T/rv.html" >/dev/null 2>&1
_g=1; for f in pm rc rv bb; do node "$ADV" "$V27T/$f.html" "$THEMEV" 2>&1 | grep -q '0 off-theme' || _g=0; node "$COV" "$V27T/$f.html" 2>&1 | grep -q 'composed' || _g=0; done
chk "$_g" "1" "v0.30 INV-VIEW-GATES: each view body + brief-body passes anti-drift (0 off-theme) + compose-check"
rm -rf "$V27T"


# ══ v0.29.2 "always clarity" — BEHAVIOUR asserts. Every one of these fails when
# the behaviour breaks, not merely when bytes go missing from a file. That
# distinction is the entire point of this release (see the deleted INV-WELCOME
# asserts above). ══
V28="$PLUGIN_ROOT/scripts/fixtures"; HOOK="$PLUGIN_ROOT/hooks/orient-hook.sh"

# INV-ORIENT-NOREPEAT — the MID block never carries the NEW-BUILD intro
chk "$(bash "$SH" orient --where "$V28/orient/state/inflight" | grep -c 'Build true to a spec you lock first')" "0" "v0.28 INV-ORIENT-NOREPEAT: MID block does not repeat the intro"
chk "$(bash "$SH" orient --where "$V28/orient/state/inflight" | diff -q - "$V28/orient/state/inflight/expected.txt" >/dev/null 2>&1 && echo 1 || echo 0)" "1" "v0.28 INV-ORIENT: MID block byte-identical to its pinned fixture"

# INV-LOCALE-SAFE — determinism across locale AND timezone. This is the assert
# that caught last_block's multibyte bracket-expression bug, under which EVERY
# receipt lookup returned empty and EVERY gate reported "no receipt" in a C locale.
_a="$(TZ=UTC LC_ALL=C bash "$SH" orient --where "$V28/orient/state/inflight")"
_b="$(TZ=Asia/Kolkata LC_ALL=en_US.UTF-8 bash "$SH" orient --where "$V28/orient/state/inflight" 2>/dev/null)"
chk "$([ "$_a" = "$_b" ] && echo 1 || echo 0)" "1" "v0.28 INV-LOCALE-SAFE: orient identical across TZ+locale (guards the last_block multibyte-range bug)"
chk "$(LC_ALL=C bash -c 'source "'"$SH"'" 2>/dev/null; stage_pass "'"$V28"'/orient/state/inflight" contract && echo 1 || echo 0')" "1" "v0.28 INV-LOCALE-SAFE: stage_pass works under LC_ALL=C (receipt parser is locale-independent)"

# INV-TERMINAL-STATUS — a shipped build must not be reported as in-flight forever
chk "$(bash -c 'source "'"$SH"'" 2>/dev/null; is_terminal shipped && echo 1 || echo 0')" "1" "v0.28 INV-TERMINAL-STATUS: lowercase 'shipped' is terminal (ship writes lowercase; the check was uppercase-only)"
chk "$(bash -c 'source "'"$SH"'" 2>/dev/null; is_terminal CLOSED && echo 1 || echo 0')" "1" "v0.28 INV-TERMINAL-STATUS: uppercase CLOSED still terminal (no regression)"
chk "$(bash -c 'source "'"$SH"'" 2>/dev/null; is_terminal draft && echo 0 || echo 1')" "1" "v0.28 INV-TERMINAL-STATUS: a draft build is NOT terminal"

# INV-CARD / INV-CARD-HONEST / INV-CARD-CAP
chk "$(bash "$SH" progress-card "$V28/progress-card/nine" | grep -cE '^  [✓▶!·] [0-9]+ ')" "9" "v0.28 INV-CARD: one rendered line per plan step"
chk "$(bash "$SH" progress-card "$V28/progress-card/liar" | grep -c 'box-only')" "1" "v0.28 INV-CARD-HONEST: a ticked box with no receipt renders box-only"
chk "$(bash "$SH" progress-card "$V28/progress-card/liar" | grep -cE '^  ✓ 2 ')" "0" "v0.28 INV-CARD-HONEST: that step is NEVER rendered as verified"
chk "$([ "$(bash "$SH" progress-card "$V28/progress-card/long" | wc -l | tr -d ' ')" -le 18 ] && echo 1 || echo 0)" "1" "v0.28 INV-CARD-CAP: a 30-step plan renders <= 18 lines"
chk "$(bash "$SH" progress-card "$V28/progress-card/hostile" | od -c | grep -c '033')" "0" "v0.28 INV-CARD: terminal escape sequences in a step title are stripped (STRIDE tampering)"

# INV-CARD-GATE / INV-CARD-RECEIPT — all four directions incl. the empty-fence trap
( bash "$SH" progress-gate "$V28/progress-card/receipt-ok" >/dev/null 2>&1 ); chk "$?" "0" "v0.28 INV-CARD-GATE: a receipt carrying a card PASSES"
( bash "$SH" progress-gate "$V28/progress-card/receipt-missing" >/dev/null 2>&1 ); chk "$?" "1" "v0.28 INV-CARD-GATE: a receipt with no card BLOCKS"
( bash "$SH" progress-gate "$V28/progress-card/receipt-empty-fence" >/dev/null 2>&1 ); chk "$?" "1" "v0.28 INV-CARD-RECEIPT: an EMPTY fence blocks (marker present, card absent = byte-inert in miniature)"
( bash "$SH" progress-gate "$V28/progress-card/receipt-quiet" >/dev/null 2>&1 ); chk "$?" "0" "v0.28 INV-CARD-GATE: quiet-mode still records, so COMPASS_QUIET cannot deadlock the build loop"
( bash "$SH" progress-gate "$V28/progress-card/receipt-later-block" >/dev/null 2>&1 ); chk "$?" "1" "v0.28 INV-CARD-GATE: a card in a LATER receipt block does NOT satisfy the step's own gate (review-3 bypass, now fixed)"

# INV-ORIENT zero-builds path (post-ship regression, v0.29.2): cmd_active_builds
# prints a human "0 active builds." status line when nothing is in flight. A naive
# ^[a-zA-Z0-9] match counted THAT line as a build, so with nothing in flight the
# renderer emitted NOTHING — breaking the single most important case, a new user
# with no builds yet. Assert the row filter ignores the status line.
chk "$(bash -c 'source "'"$SH"'" 2>/dev/null; cmd_active_builds() { echo "COMPASS-GATE: PASS — 0 active builds."; }; _orient_active_rows /tmp | grep -c . || true')" "0" "v0.28 INV-ORIENT: the active-builds row filter ignores the '0 active builds' status line (zero-build path renders the NEW block)"
chk "$(bash -c 'source "'"$SH"'" 2>/dev/null; cmd_active_builds() { echo "my-build (build)"; echo "COMPASS-GATE: PASS — 1 active build."; }; _orient_active_rows /tmp | grep -c . || true')" "1" "v0.28 INV-ORIENT: the row filter keeps real build rows and drops the trailing status line"

# INV-STATUSLINE
chk "$(bash "$SH" statusline "$V28/orient/state/inflight" | wc -l | tr -d ' ')" "1" "v0.28 INV-STATUSLINE: exactly one line for an in-flight build"
chk "$(bash "$SH" statusline "$SMOKE_TMP/definitely-not-a-build" 2>/dev/null | wc -c | tr -d ' ')" "0" "v0.28 INV-STATUSLINE: zero bytes when there is no build"

# INV-MODE-VISIBLE
chk "$(bash "$SH" orient --where "$V28/orient/state/auto" | grep -c 'mode: Autonomous')" "1" "v0.28 INV-MODE-VISIBLE: the MID block shows Autonomous"
chk "$(bash "$SH" orient --where "$V28/orient/state/inflight" | grep -c 'mode: Human-gated')" "1" "v0.28 INV-MODE-VISIBLE: the MID block shows Human-gated"
chk "$(bash "$SH" statusline "$V28/orient/state/auto" | grep -c 'Autonomous')" "1" "v0.28 INV-MODE-VISIBLE: the status line carries the run-mode"

# INV-ORIENT-DELIVERED — the shipped hook, fed a real payload, on the ONE
# documented user-visible channel. A renderer that works while the hook never
# fires MUST fail here; that combination is what passed for twelve versions.
chk "$(bash "$HOOK" < "$V28/orient/hook-payload/go.json" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); print(1 if "Compass" in d.get("systemMessage","") else 0)
except Exception: print(0)')" "1" "v0.28 INV-ORIENT-DELIVERED: the hook emits the block on systemMessage (the user-visible channel), not plain stdout"
chk "$(bash "$HOOK" < "$V28/orient/hook-payload/unrelated.json" | wc -c | tr -d ' ')" "0" "v0.28 INV-ORIENT-DELIVERED: an unrelated prompt produces zero output"
( bash "$HOOK" < "$V28/orient/hook-payload/unrelated.json" >/dev/null 2>&1 ); chk "$?" "0" "v0.28 INV-ORIENT-DELIVERED: the hook NEVER exits 2 (exit 2 erases the user's prompt)"
chk "$(bash "$HOOK" < "$V28/orient/hook-payload/nostate.json" | wc -c | tr -d ' ')" "0" "v0.28 INV-ORIENT-INERT: no .claude/builds anywhere above cwd -> zero bytes"
chk "$(printf 'not json' | bash "$HOOK" 2>/dev/null | wc -c | tr -d ' ')" "0" "v0.28 INV-ORIENT-INERT: malformed stdin is fail-open and silent"

# INV-ONE-RENDERER — three doors, one source, and no second copy of the block
_or=1; for _f in go status resume; do
  [ "$(grep -c 'compass.sh orient' "$PLUGIN_ROOT/commands/$_f.md")" -ge 1 ] || _or=0
  [ "$(grep -c 'Build true to a spec you lock first' "$PLUGIN_ROOT/commands/$_f.md")" = "0" ] || _or=0
done
chk "$_or" "1" "v0.28 INV-ONE-RENDERER: go/status/resume all call the renderer and none carries a duplicate of the block"
chk "$(grep -c 'Welcome — how Compass works' "$PLUGIN_ROOT/commands/go.md")" "0" "v0.28 INV-ONE-RENDERER: the old hand-written welcome prose is GONE from go.md"

# The build loop is wired, and the byte-locked gate footer was not touched
chk "$(grep -c 'compass.sh progress-card' "$PLUGIN_ROOT/skills/build/SKILL.md")" "1" "v0.28 INV-CARD: the build skill renders the card every step"
chk "$(grep -c 'compass.sh progress-gate' "$PLUGIN_ROOT/skills/build/SKILL.md")" "1" "v0.28 INV-CARD-GATE: the build skill gates the next step on it"
chk "$(grep -c 'progress-card' "$PLUGIN_ROOT/shared/gate.md")" "0" "v0.28 INV-NO-LIFECYCLE-CHANGE: the byte-locked gate footer is untouched"


# ══ v0.29.2 "visual artefacts" — the four views, rebuilt. Every assert below fails when
# the BEHAVIOUR breaks, and each one traces to a defect measured in the shipped output. ══
V29FX="$PLUGIN_ROOT/scripts/fixtures/artefacts"; V29G="$PLUGIN_ROOT/skills/compass-visual/gen.mjs"
V29AG="$PLUGIN_ROOT/scripts/artefact-gate.mjs"; V29TH="$PLUGIN_ROOT/skills/compass-visual/themes/compass-artefact.json"  # v0.30: ditto
V29T="$(mktemp -d)"

# INV-FENCE-BLIND — a drawing is not data. The shipped brief printed `<goal from INDEX>`
# four times because the parser read an ASCII mockup inside a ``` fence as a contract field.
node "$V29G" "$V29FX/fenced" brief --out "$V29T/f.html" >/dev/null 2>&1
chk "$(grep -c 'goal from INDEX' "$V29T/f.html")" "0" "v0.29 INV-FENCE-BLIND: a Goal: inside a code fence is NOT read as the contract's goal"
# v0.30: was `-ge 2`, which only held because the goal rendered in BOTH the lede and the
# Build-what card. It renders once now. REWRITTEN to the property the check is actually for, and
# strengthened: the real goal must appear AND the fenced decoy must NOT. Counting occurrences
# never tested fence-blindness; this does.
chk "$([ "$(grep -c 'lives in a proper section' "$V29T/f.html")" -ge 1 ] && [ "$(grep -c 'goal from INDEX' "$V29T/f.html")" -eq 0 ] && echo 1 || echo 0)" "1" "v0.30 INV-FENCE-BLIND: the REAL section goal is used and the FENCED decoy is not"
node "$V29G" "$V29FX/fenced" plan-map --out "$V29T/fp.html" >/dev/null 2>&1
chk "$(grep -o 'class="b-step"' "$V29T/fp.html" | wc -l | tr -d ' ')" "1" "v0.29 INV-FENCE-BLIND: checkboxes inside a fenced receipt template are NOT plan steps"

# INV-NO-TOKEN — refuse rather than ship a blank where the headline should be.
( node "$V29G" "$V29FX/no-goal" brief --out "$V29T/ng.html" >/dev/null 2>&1 ); chk "$?" "4" "v0.29 INV-NO-TOKEN: an unresolved REQUIRED field refuses (exit 4)"
chk "$([ -f "$V29T/ng.html" ] && echo 1 || echo 0)" "0" "v0.29 INV-NO-TOKEN: and writes NOTHING (a wrong page is worse than no page)"
( node "$V29G" "$V29FX/fenced" brief --out "$V29T/ok.html" >/dev/null 2>&1 ); chk "$?" "0" "v0.29 INV-NO-TOKEN: no false positive on a contract that merely QUOTES a token"

# INV-HOUSE — every body's palette comes from the theme file.
_h=1; for _v in brief-body plan-map release-card review; do
  node "$V29G" "$V29FX/five-verify" "$_v" --out "$V29T/h-$_v.html" >/dev/null 2>&1
  node "$PLUGIN_ROOT/skills/rk-house-style/gates/anti-drift-grep.mjs" "$V29T/h-$_v.html" "$V29TH" 2>&1 | grep -q '0 off-theme' || _h=0
done
chk "$_h" "1" "v0.29 INV-HOUSE: all four view bodies score 0 off-theme against the theme"

# INV-LOGIC-BLOCK — a diagram, not an icon. Counted structurally so "decorative" is a number.
_l=1; for _v in brief-body plan-map release-card review; do
  _r=$(grep -o '<rect' "$V29T/h-$_v.html" | wc -l | tr -d ' '); _p=$(grep -o '<path' "$V29T/h-$_v.html" | wc -l | tr -d ' '); _x=$(grep -o '<text' "$V29T/h-$_v.html" | wc -l | tr -d ' ')
  { [ "$_r" -ge 3 ] && [ "$_p" -ge 2 ] && [ "$_x" -ge 3 ]; } || _l=0
done
chk "$_l" "1" "v0.29 INV-LOGIC-BLOCK: every view carries >=3 rect, >=2 path, >=3 text (an icon cannot pass)"
chk "$(grep -c '<script' "$V29T/h-plan-map.html")" "0" "v0.29 INV-LOGIC-BLOCK: no script tag — the page runs nothing"

# v0.29.2 — the Release Card read NOW items only from a `### NOW` section of NUMBERED items,
# but the canonical ladder the contract skill writes is `## Scope ladder` with `- NOW:` bullets.
# Every standard contract therefore rendered "0 changes": a release card advertising that
# nothing shipped. Found by generating a sample and LOOKING at it.
node "$V29G" "$V29FX/five-verify" release-card --out "$V29T/rc.html" >/dev/null 2>&1
chk "$([ "$(grep -c '0 changes' "$V29T/rc.html")" -eq 0 ] && echo 1 || echo 0)" "1" "v0.29 release-card: never renders '0 changes' when the contract has a NOW ladder"

# INV-VERIFY-SHOWN — the proof that closes a step was absent from every shipped Plan Map.
node "$V29G" "$V29FX/five-verify" plan-map --out "$V29T/fv.html" >/dev/null 2>&1
chk "$(grep -o 'class="verify"' "$V29T/fv.html" | wc -l | tr -d ' ')" "5" "v0.29 INV-VERIFY-SHOWN: every step renders its VERIFY command"

# INV-COUNTS-MATCH — the shipped Plan Map said 0/18 for a 20-step plan.
node "$V29G" "$V29FX/twenty-steps" plan-map --out "$V29T/ts.html" >/dev/null 2>&1
chk "$(psays "$V29T/ts.html" '20 steps · 7 done' && echo 1 || echo 0)" "1" "v0.29 INV-COUNTS-MATCH: the header count equals the source"
chk "$(grep -o 'class="b-step"' "$V29T/ts.html" | wc -l | tr -d ' ')" "20" "v0.29 INV-COUNTS-MATCH: the body renders exactly that many steps"
chk "$(psays "$V29T/ts.html" '7 done' && echo 1 || echo 0)" "1" "v0.29 INV-COUNTS-MATCH: done/remaining reflect the real checkbox state"
node "$V29G" "$V29FX/no-waves" plan-map --out "$V29T/nw.html" >/dev/null 2>&1
chk "$(grep -ciE '[0-9]+ waves?' "$V29T/nw.html")" "0" "v0.29 INV-COUNTS-MATCH: no chip for a concept the plan never used (the '0 waves' defect)"

# INV-NO-TRUNCATION — the shipped Plan Map cut step text mid-word at .slice(0,110).
node "$V29G" "$V29FX/long-titles" plan-map --out "$V29T/lt.html" >/dev/null 2>&1
chk "$(python3 - "$V29FX/long-titles/plan.md" "$V29T/lt.html" <<'PYEOF'
import re,html,sys
t=' '.join(re.search(r'\*\*1 · (.+?)\*\*', open(sys.argv[1]).read(), re.S).group(1).split())
out=' '.join(html.unescape(re.sub(r'<[^>]+>',' ',open(sys.argv[2]).read())).split())
print(1 if t in out else 0)
PYEOF
)" "1" "v0.29 INV-NO-TRUNCATION: a 363-character step title survives WHOLE (no character slice anywhere)"

# INV-COMPLETE-PLAN — a section a reader cannot see is indistinguishable from one never required.
node "$V29G" "$V29FX/minimal-plan" plan-map --out "$V29T/mp.html" >/dev/null 2>&1
chk "$([ "$(grep -o 'class="b-na"' "$V29T/mp.html" | wc -l | tr -d ' ')" -ge 5 ] && echo 1 || echo 0)" "1" "v0.29 INV-COMPLETE-PLAN: every missing plan section renders an explicit N/A card"

# INV-STRUCTURE — the whole gate runs with no browser, and BITES on each seeded defect.
( node "$V29AG" "$V29T/ts.html" --bands --steps 20 >/dev/null 2>&1 ); chk "$?" "0" "v0.29 INV-STRUCTURE: the gate PASSES good output"
( node "$V29AG" "$V29T/ts.html" --bands --steps 99 >/dev/null 2>&1 ); chk "$?" "1" "v0.29 INV-STRUCTURE: BITES on a count that disagrees with the source"
python3 -c "import re,sys;s=open(sys.argv[1]).read();open(sys.argv[2],'w').write(re.sub(r'<svg[\s\S]*?</svg>','',s))" "$V29T/ts.html" "$V29T/nosvg.html"
( node "$V29AG" "$V29T/nosvg.html" >/dev/null 2>&1 ); chk "$?" "1" "v0.29 INV-STRUCTURE: BITES when the logic block is missing"
# v0.30: re-anchored from '</body>' — which the fragment no longer contains, making the seed a
# NO-OP and the mutation test silently vacuous (it would have "passed" by comparing a clean file
# to itself). Anchored on a token the fragment does carry, exactly as the band seed below does.
python3 -c "import sys;s=open(sys.argv[1]).read();open(sys.argv[2],'w').write(s.replace('<div class=\"b-sec\"','<script>x</script><div class=\"b-sec\"',1))" "$V29T/ts.html" "$V29T/scr.html"
( node "$V29AG" "$V29T/scr.html" >/dev/null 2>&1 ); chk "$?" "1" "v0.29 INV-STRUCTURE: BITES when a script tag appears"
python3 -c "import sys;s=open(sys.argv[1]).read();open(sys.argv[2],'w').write(s.replace('<div class=\"b-decide\"','<div class=\"b-x\"',1))" "$V29T/ts.html" "$V29T/nob.html"
( node "$V29AG" "$V29T/nob.html" --bands >/dev/null 2>&1 ); chk "$?" "1" "v0.29 INV-STRUCTURE: BITES when the decision band is gone"

# INV-FRESH — an artefact older than its source is a wrong number waiting to be read.
sleep 1; touch "$V29FX/twenty-steps/plan.md"
( node "$V29AG" "$V29T/ts.html" --source "$V29FX/twenty-steps/plan.md" >/dev/null 2>&1 ); chk "$?" "1" "v0.29 INV-FRESH: an artefact older than its source FAILS the gate"

# INV-BANDS — the order is the product decision, asserted positionally.
chk "$(node "$V29AG" "$V29T/h-brief-body.html" --bands >/dev/null 2>&1 && echo 1 || echo 0)" "1" "v0.29 INV-BANDS: the Brief emits decision -> facts -> flow -> detail, in that order"
chk "$(node "$V29AG" "$V29T/h-release-card.html" --bands >/dev/null 2>&1 && echo 0 || echo 1)" "1" "v0.29 INV-BANDS: --bands still BITES on a view without a facts row (the flag cannot wave a check away)"

# INV-DELIVERED — the wiring exists at the seams, and the kill-switch is honoured.
chk "$([ "$(grep -c 'artefact-gate' "$PLUGIN_ROOT/skills/contract/SKILL.md")" -ge 1 ] && [ "$(grep -c 'artefact-gate' "$PLUGIN_ROOT/skills/plan/SKILL.md")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.29 INV-DELIVERED: contract + plan skills gate the artefact before showing it"
# v0.30: the seams publish to ONE stored URL instead of copying to a personal folder. REWRITTEN.
chk "$([ "$(grep -c 'artefact-publish' "$PLUGIN_ROOT/skills/contract/SKILL.md")" -ge 1 ] && echo 1 || echo 0)" "1" "v0.30 INV-DELIVERED: the contract seam publishes via artefact-publish"
# v0.30: was a byte-presence grep for the kill-switch string — which would survive as theatre once
# the block it gated was deleted. REPLACED with a BEHAVIOUR assert on the real failure path:
# publishing with no URL and none stored must exit non-zero, name the local file, and write no
# stored URL. "Delivered" used to be unfalsifiable — the only thing that could fail was a copy.
_apdir="$(mktemp -d)"; printf '<title>x</title>' > "$_apdir/brief.html"
bash "$SH" artefact-publish "$_apdir/brief.html" --dir "$_apdir" >/dev/null 2>&1
_aprc=$?
chk "$([ "$_aprc" -ne 0 ] && [ ! -f "$_apdir/artifact-urls" ] && echo 1 || echo 0)" "1" "v0.30 INV-DELIVERED: publish with no URL exits non-zero and stores nothing"
bash "$SH" artefact-publish "$_apdir/brief.html" --dir "$_apdir" --url https://example.test/a >/dev/null 2>&1
chk "$([ "$(grep -c '^brief=https://example.test/a$' "$_apdir/artifact-urls" 2>/dev/null)" -eq 1 ] && echo 1 || echo 0)" "1" "v0.30 INV-7: a published URL is stored once for reuse"
bash "$SH" artefact-publish "$_apdir/brief.html" --dir "$_apdir" 2>/dev/null | grep -q 'https://example.test/a'
chk "$?" "0" "v0.30 INV-7: republish hands back the SAME URL (never a second artefact)"
rm -rf "$_apdir"

# determinism — the same source renders byte-identically (no clock, no locale leakage).
node "$V29G" "$V29FX/twenty-steps" plan-map --out "$V29T/d1.html" >/dev/null 2>&1
TZ=Asia/Kolkata LC_ALL=en_US.UTF-8 node "$V29G" "$V29FX/twenty-steps" plan-map --out "$V29T/d2.html" >/dev/null 2>&1
chk "$(diff -q "$V29T/d1.html" "$V29T/d2.html" >/dev/null 2>&1 && echo 1 || echo 0)" "1" "v0.29 views are deterministic across TZ and locale"
rm -rf "$V29T"
# ── v0.30 R3 stream B: every gate below was DEFEATED by an adversarial pass. Each assertion here
# is the exact attack that worked, so a regression re-opens the same door loudly. ────────────────
_b3d="$(mktemp -d)"
# B1 — a zero-byte .compass-format passed as "created by new-build"
mkdir -p "$_b3d/b1"; printf -- '---\ncompass-format: v0.30\n---\n# c\n' > "$_b3d/b1/contract.md"; : > "$_b3d/b1/.compass-format"
bash "$PLUGIN_ROOT/scripts/compass.sh" contract-gate "$_b3d/b1" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-B1: a zero-byte compass-format stamp is not proof of new-build"
# B6 — evidence prose that records the OPPOSITE of a pre-change RED
mkdir -p "$_b3d/b6"; printf '# c\n- **INV-A:** x\n' > "$_b3d/b6/contract.md"
printf 'INV-A ran and was GREEN from the start. It never went RED.\n' > "$_b3d/b6/red-first-evidence.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" redfirst-check "$_b3d/b6" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-B6: 'never went RED' is anti-evidence, not evidence"
printf -- '- **INV-A** — DEFERRED to a later build.\n' > "$_b3d/b6/red-first-evidence.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" redfirst-check "$_b3d/b6" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-B6: a deferral with no reason does not discharge an INVARIANT"
printf 'INV-A    value=0    target=0    RED\n' > "$_b3d/b6/red-first-evidence.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" redfirst-check "$_b3d/b6" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-B6: a machine row whose value equals its target is not a RED"
mkdir -p "$_b3d/b6t"; printf '# c\n| id | rule |\n|---|---|\n| **INV-Q** | a thing |\n' > "$_b3d/b6t/contract.md"
printf 'nothing here\n' > "$_b3d/b6t/red-first-evidence.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" redfirst-check "$_b3d/b6t" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-B6: invariants declared in a TABLE are not 'no invariants'"
# B3 — the gold gate, three ways
_g3(){ mkdir -p "$_b3d/$1"; printf -- '---\ncompass-format: v0.30\n---\n# c\n\n## Reconciliation\n' > "$_b3d/$1/contract.md"; printf '%s\n' "$2" >> "$_b3d/$1/contract.md"; printf 'compass-format: v0.30\n' > "$_b3d/$1/.compass-format"; }
_g3 g1 'The gold is self-computed by the reproducing query.
png: N/A — headless, no browser.
provenance: the v0.29.2 tree.'
bash "$PLUGIN_ROOT/scripts/compass.sh" gold-gate "$_b3d/g1" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-B3: an unrelated 'N/A — ' line no longer switches the gold gate off"
_g3 g2 'The gold is self-computed by the reproducing query, rather than typed in by hand.
provenance: the v0.29.2 tree.'
bash "$PLUGIN_ROOT/scripts/compass.sh" gold-gate "$_b3d/g2" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-B3: a negation of something ELSE no longer clears a self-referential gold"
_g3 g3 'The gold: we run the OLD query and the NEW query over the same snapshot and diff them.'
bash "$PLUGIN_ROOT/scripts/compass.sh" gold-gate "$_b3d/g3" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-B3: a NEW build must name external provenance (paraphrase defeats a blocklist)"
_g3 g4 'gold = 3 of 24 builds report a false 0 — an independent pre-build baseline, not self-computed by the new code.
provenance: on-disk build state predating this build.'
bash "$PLUGIN_ROOT/scripts/compass.sh" gold-gate "$_b3d/g4" >/dev/null 2>&1
chk "$?" "0" "v0.30 R3-B3: a genuine disclaimer still passes (the filter did not get too broad)"
# B4/B9 — one extractor, shared by gen.mjs and copy-gate
_j="$(grep -m1 -vE '^#|^$' "$PLUGIN_ROOT/scripts/fixtures/copy/positive-control.txt")"
printf 'x\n```compass-reader-copy \nlead: %s\n```\n' "$_j" > "$_b3d/tsp.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" copy-gate "$_b3d/tsp.md" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-B4: a trailing space on the fence no longer hides the block from the gate"
printf -- '- s\n  ```compass-reader-copy\n  lead: %s\n  ```\n' "$_j" > "$_b3d/ind.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" copy-gate "$_b3d/ind.md" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-B9: an indented fence inside a list item is still policed"
printf '````compass-reader-copy\na: clean\n```\nlead: %s\n````\n' "$_j" > "$_b3d/nest.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" copy-gate "$_b3d/nest.md" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-B9: an inner fence no longer closes a 4-backtick block early"
printf '```compass-reader-copy\n\n```\n' > "$_b3d/empty.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" copy-gate "$_b3d/empty.md" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-B9: an EMPTY block is a defect, not 'no block present'"
printf '# just a doc\n' > "$_b3d/none.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" copy-gate "$_b3d/none.md" >/dev/null 2>&1
chk "$?" "0" "v0.30 R3-B4: a file with genuinely no block still N/A-passes (set -e does not abort it)"
# B7/B8 — the copy checks
printf '<html><body><div class="v">The build rebuilds the artefact layer so a stranger can read it</div><div class="v">The build rebuilds the artefact layer so a stranger can read it</div></body></html>' > "$_b3d/dup.html"
_dupout="$(node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_b3d/dup.html" --copy 2>&1 || true)"
case "$_dupout" in *no-duplicated-sentence*) _dr=0 ;; *) _dr=1 ;; esac
chk "$_dr" "0" "v0.30 R3-B7: a repeated line with NO terminal punctuation is caught"
rm -rf "$_b3d"

# ── v0.30 R3 round 2: nineteen more defeats, four of them CRITICAL. Same shape as round 1 — each
# mechanism was built correctly and then aimed at a narrower input than the property it asserts. ──
_r2d="$(mktemp -d)"
_g3(){ mkdir -p "$_r2d/$1"; printf '# c\n\n%s\n' "$2" > "$_r2d/$1/contract.md"; printf 'compass-format: v0.30\n' > "$_r2d/$1/.compass-format"; }
# R2-6 — three one-line escapes past gold-gate, each with the fixture's own control text present
_g3 n1 '## 7. Reconciliation
The gold is self-computed by the reproducing query.'
bash "$PLUGIN_ROOT/scripts/compass.sh" gold-gate "$_r2d/n1" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-R2-6: a NUMBERED Reconciliation heading is still scanned"
_g3 n2 '## Reconciliation
Independent figure: 4,182 loans.
The gold is self-computed by the reproducing query.'
bash "$PLUGIN_ROOT/scripts/compass.sh" gold-gate "$_r2d/n2" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-R2-6: the blocklist runs even when no line contains the word gold"
_g3 n3 '## Reconciliation
gold: 4,182 loans (units N/A). The gold is self-computed by the reproducing query.'
bash "$PLUGIN_ROOT/scripts/compass.sh" gold-gate "$_r2d/n3" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-R2-6: N/A must be the gold declaration, not any substring in the section"
# R2-7 — provenance that points back at the build
_g3 n4 '## Reconciliation
gold: 4,182 loans.
We run the OLD query and the NEW query over the same snapshot and diff the two answers.
provenance: the query itself.'
bash "$PLUGIN_ROOT/scripts/compass.sh" gold-gate "$_r2d/n4" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-R2-7: a provenance naming the build itself is not provenance"
# R2-8 — typographic hyphen + non-breaking space
_g3 n5 '## Reconciliation
The gate is cross‑path parity — both paths produce the same figure.
provenance: measured by the build itself.'
bash "$PLUGIN_ROOT/scripts/compass.sh" gold-gate "$_r2d/n5" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-R2-8: unicode dashes/spaces are normalised before matching"
# regression: the doctrine stated CORRECTLY must still pass (2 shipped contracts write it)
_g3 n6 '## Reconciliation
gold = 3 of 24 builds report a false 0 — an independent pre-build baseline, not self-computed by the new code.
A gate agreeing with itself proves nothing, so each INVARIANT pins the real failure shape.
provenance: on-disk build state predating this build.'
bash "$PLUGIN_ROOT/scripts/compass.sh" gold-gate "$_r2d/n6" >/dev/null 2>&1
chk "$?" "0" "v0.30 R3-R2-6: a contract stating the doctrine CORRECTLY is not flagged"
# R2-9 — one typed line naming five invariants reported as five machine rows
mkdir -p "$_r2d/rf"; printf '# c\n- **INV-1:** a\n- **INV-2:** b\n' > "$_r2d/rf/contract.md"
printf 'ASSERT-INVARIANTS-RUN root=/x tree=5f0b53f8e9f889fc15bb54e123c8aba59acd91e6\nINV-1 INV-2  value=9  target=0  RED\n' > "$_r2d/rf/red-first-evidence.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" redfirst-check "$_r2d/rf" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-R2-9: a row naming several invariants at once is not runner-shaped evidence"
printf 'INV-1 value=8 target=0 RED\nINV-2 value=8 target=0 RED\n' > "$_r2d/rf/red-first-evidence.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" redfirst-check "$_r2d/rf" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-R2-9: evidence with no assert-invariants provenance header is refused"
# R2-14 — the count claim, three ways past a case-sensitive digits-only regex
# v0.32.0 M-1b, from an independent review. This asserted an EXIT CODE, and the stub page fails
# four unrelated structural rules (band-detail-last, logic-block-present, logic-block-real,
# no-mid-field-cut) — so a page carrying NO count claim at all exits 1 identically. Three assertions
# measuring nothing about counts. The `--source` file was gitignored too, so it did not exist on a
# clean clone. Now: a TRACKED source, and the gate must NAME the count rule for the guilty page and
# must NOT name it for an innocent one that is otherwise byte-for-byte the same shape.
_r2src="$PLUGIN_ROOT/scripts/fixtures/corpus/long-ledger/contract.md"
printf '<html><body><p>covers the invariants here</p></body></html>' > "$_r2d/innocent.html"
_r2neg="$(node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_r2d/innocent.html" --copy --source "$_r2src" 2>&1 | grep -c 'claimed-count-matches' || true)"
chk "$_r2neg" "0" "v0.32 M-1b: a page making NO count claim is not accused of a false count — the control that shows the three assertions below are about counts"
for _v in "11 INVARIANTs" "eleven invariants" "11 invariant checks"; do
  printf '<html><body><p>covers %s here</p></body></html>' "$_v" > "$_r2d/c.html"
  chk "$(node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_r2d/c.html" --copy --source "$_r2src" 2>&1 | grep -c 'claimed-count-matches' || true)" "1" "v0.30 R3-R2-14: a false count written as '$_v' is caught BY NAME"
done
# R2-16 — INV-5 must search the WHOLE plugin, not a hand-listed subset
_inv="$_r2d/inv"; mkdir -p "$_inv/plugins"; cp -R "$PLUGIN_ROOT" "$_inv/plugins/compass" 2>/dev/null
# The seed lives in the excluded fixtures dir; writing it inline planted a real INV-5 violation
# in the shipped tree, so the plugin could not reach its own pass target as committed.
printf '\n%s\n' "$(cat "$PLUGIN_ROOT/scripts/fixtures/portable/seed-violation.txt")" >> "$_inv/plugins/compass/shared/gate.md"
_v5="$(bash "$PLUGIN_ROOT/scripts/assert-invariants.sh" "$_inv" 2>/dev/null | awk '/^INV-5/{print $2}')"
chk "$([ "$_v5" = "value=0" ] && echo 0 || echo 1)" "1" "v0.30 R3-R2-16: a violation in shared/ is found (INV-5 searches the whole plugin)"
rm -rf "$_r2d"

# ── v0.30 R3 round 3: 29 more defeats. Shape: "called on the right thing, but only on ONE of the
# N places the property lives — and the fix that proved it works was never wired to its siblings." ─
_r3d="$(mktemp -d)"
# R3-21 — INV-6 could not go red: it tested line 1, and every generated page opens with <title>
printf '<title>x</title>\n<style>a{}</style>\n<!doctype html><html><head></head><body>\n<p>hi</p>\n' > "$_r3d/doc.html"
_r3n="$(sed -e 's/<code>[^<]*<\/code>/ /g' "$_r3d/doc.html" | tr -d '\r' | grep -ciE '<!doctype|<html[ >]|<head[ >]|</head>|<body[ >]' || echo 0)"
chk "$([ "${_r3n:-0}" -ge 1 ] && echo 1 || echo 0)" "1" "v0.30 R3-21: a document wrapper below line 1 is still a document"
# R3-06/R3-08 — redfirst-check must reject ERR rows and PASS verdicts
mkdir -p "$_r3d/rf"; printf '# c\n- **INV-1:** a\n' > "$_r3d/rf/contract.md"
_r3sha="$(git -C "$PLUGIN_ROOT" rev-parse HEAD 2>/dev/null || echo 0000000)"
printf 'ASSERT-INVARIANTS-RUN root=/x tree=%s\nINV-1 value=ERR-no-pattern-file target=0 RED\n' "$_r3sha" > "$_r3d/rf/red-first-evidence.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" redfirst-check "$_r3d/rf" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-06: an ERR row measured nothing — it is not a recorded RED"
printf 'ASSERT-INVARIANTS-RUN root=/x tree=%s\nINV-1 value=1 target=0 PASS\n' "$_r3sha" > "$_r3d/rf/red-first-evidence.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" redfirst-check "$_r3d/rf" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-08: a row whose verdict is PASS is not a recorded RED"
# R3-01/R3-03 — gold-gate section extraction
_gg(){ mkdir -p "$_r3d/$1"; printf '# c\n\n%s\n' "$2" > "$_r3d/$1/contract.md"; printf 'compass-format: v0.30\n' > "$_r3d/$1/.compass-format"; }
_gg s1 '## Reconciliation

### Gold figure
The gold is self-computed by the reproducing query.
provenance: the query itself.'
bash "$PLUGIN_ROOT/scripts/compass.sh" gold-gate "$_r3d/s1" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-01: a sub-heading no longer truncates the Reconciliation section"
_gg s2 '**Reconciliation**
The gate is cross-path parity.
provenance: the query itself.'
bash "$PLUGIN_ROOT/scripts/compass.sh" gold-gate "$_r3d/s2" >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-03: a bold pseudo-heading opens the section too"
_gg s3 '## Reconciliation
Cross-path parity is explicitly rejected as a gold for this build.
gold = 4,182 loans.
provenance: the audited MIS pack dated 2026-03-31.'
bash "$PLUGIN_ROOT/scripts/compass.sh" gold-gate "$_r3d/s3" >/dev/null 2>&1
chk "$?" "0" "v0.30 R3-29: a contract that REJECTS a self-referential gold is not refused for saying so"
# R3-13/R3-14 — the copy checks must not depend on a class allow-list
printf '<div class="v">asking a person to read one page and <b>decide</b> from it, without hedging, so they can dec</div>' > "$_r3d/cut.html"
node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_r3d/cut.html" --copy >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-13: a cut field containing an inline tag is still seen"
printf '<p>x</p><span class="chip">This build rebuilds the artefact layer so a stranger can read it and decide</span><span class="chip">This build rebuilds the artefact layer so a stranger can read it and decide</span>' > "$_r3d/dup2.html"
node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_r3d/dup2.html" --copy >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-14: a duplicate outside the old tag list is caught"
printf '<p class="lede">This release ships the rebuilt artefact layer so you can read one page and dec</p>' > "$_r3d/lede.html"
node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_r3d/lede.html" --copy >/dev/null 2>&1
chk "$?" "1" "v0.30 R3-14: a hard slice in a paragraph is caught (the Release Card has no v fields)"
# R3-09/R3-10 covered above with the insight-gate block; R3-22/23 — load-bearing files tracked
for _f in scripts/reader-copy.mjs scripts/fixtures/portable/variants.txt scripts/fixtures/lockphrase.txt \
          scripts/fixtures/svg-labels/long-boxes/contract.md \
          scripts/fixtures/status-buckets/list-edges/review-ledger.md; do
  git -C "$PLUGIN_ROOT" ls-files --error-unmatch "$_f" >/dev/null 2>&1
  chk "$?" "0" "v0.30 R3-22/23: $_f is tracked (an untracked gate vanishes on a fresh clone)"
done
rm -rf "$_r3d"

# ── v0.30 R3 round 4 + the ledger-parser rewrite. Round 4's shape: the check looks in the right
# place at the right thing, and the shell plumbing underneath silently answers "no". ─────────────
_r4d="$(mktemp -d)"
# R4-1 — `set -o pipefail` above `grep -q` returns 141 on an EARLY match, so the check read
# "no match" precisely when there was one. This asserts the pipeline shape is gone.
# Match a PIPE FEEDING grep -q, not any pipe on the line — the pattern itself contains `|`
# alternations, which is what made the first version of this assertion test nothing.
_r4p="$(grep -cE '\|[[:space:]]*(LC_ALL=C[[:space:]]+)?grep[[:space:]]+-q' "$PLUGIN_ROOT/scripts/assert-invariants.sh" || true)"
chk "${_r4p:-0}" "0" "v0.30 R4-1: assert-invariants pipes nothing into grep -q (pipefail returns 141 on an early match)"
# and the behaviour itself: a document wrapper below line 1, in a file big enough to fill the pipe
{ printf '<title>x</title>\n'; head -c 40000 /dev/zero | tr '\0' 'a'; printf '\n<!doctype html>\n<html>\n'; } > "$_r4d/big.html"
_r4o="$(sed -e 's/<code>[^<]*<\/code>/ /g' "$_r4d/big.html" | tr -d '\r')"
grep -qiE '<!doctype|<html[ >]' <<<"$_r4o"
chk "$?" "0" "v0.30 R4-1: the here-string form still fires on a 40 KB page with an early match"
# RF-3 — the deferral-distinctness rule could not fire: `tr` collapsed the newline
mkdir -p "$_r4d/rf"; printf '# c\n- **INV-1:** a\n- **INV-2:** b\n- **INV-3:** c\n' > "$_r4d/rf/contract.md"
_r4sha="$(git -C "$PLUGIN_ROOT" rev-parse HEAD 2>/dev/null || echo 0000000)"
printf 'ASSERT-INVARIANTS-RUN root=/x tree=%s\nINV-1 value=9 target=0 RED\n- **INV-2** DEFERRED — we will do it later\n- **INV-3** DEFERRED — we will do it later\n' "$_r4sha" > "$_r4d/rf/red-first-evidence.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" redfirst-check "$_r4d/rf" >/dev/null 2>&1
chk "$?" "1" "v0.30 RF-3: two deferrals with the SAME reason are refused (the rule could not fire at all)"
# FP-1 — the id regex omitted `-`, so the count check refused 13 of 28 CORRECT builds
printf -- '- **INV-MILESTONE-DELIVERY:** a\n- **INV-ONE-DOOR:** b\n' > "$_r4d/src.md"
printf '<p>this page covers 2 invariants</p>' > "$_r4d/ok.html"
# Assert THIS check, not the whole page — a one-line fixture legitimately fails the band and
# logic-block checks, which says nothing about the count regex.
node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_r4d/ok.html" --copy --source "$_r4d/src.md" 2>&1 | grep -c 'claimed-count' > "$_r4d/n" || true
chk "$(cat "$_r4d/n")" "0" "v0.30 FP-1: a multi-hyphen invariant id counts as ONE id (the gate must not refuse correct work)"
printf '<p>this page covers 9 invariants</p>' > "$_r4d/lie.html"
node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_r4d/lie.html" --copy --source "$_r4d/src.md" 2>&1 | grep -c 'claimed-count' > "$_r4d/n2" || true
chk "$(cat "$_r4d/n2")" "1" "v0.30 FP-1: a false count is still refused"
# C1 — the jargon gates matched case-SENSITIVELY, and reader copy is sentences
printf '# c\n\n```compass-reader-copy\nlead: Self-computed numbers are what we avoid here.\n```\n' > "$_r4d/cap.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" copy-gate "$_r4d/cap.md" >/dev/null 2>&1
chk "$?" "1" "v0.30 C1: sentence-initial jargon (Self-computed) is caught, not just the lowercase form"
# R4-2/3 — count_re never received the fixes count_matches got
_r4t="$_r4d/tree"; mkdir -p "$_r4t/plugins"; cp -R "$PLUGIN_ROOT" "$_r4t/plugins/compass" 2>/dev/null
mkdir -p "$_r4t/plugins/compass/skills/compass-visual/fixtures"
cp "$PLUGIN_ROOT/scripts/fixtures/lockphrase.txt" "$_r4t/plugins/compass/skills/compass-visual/fixtures/PLANTED.md" 2>/dev/null
_r4v="$(bash "$PLUGIN_ROOT/scripts/assert-invariants.sh" "$_r4t" 2>/dev/null | awk '/^INV-2/{print $2}')"
chk "$([ "$_r4v" = "value=0" ] && echo 0 || echo 1)" "1" "v0.30 R4-2: INV-2 sees a violation in a skills fixtures dir (its twin INV-5 already did)"
# The ledger parser: a bullet ledger must never render "0 findings"
mkdir -p "$_r4d/led"; printf '# c\n' > "$_r4d/led/contract.md"
printf '# ledger\n\n- R1-C1 CRITICAL — a real finding written as a bullet, not a table row.\n- R1-C2 CRITICAL — another one.\n' > "$_r4d/led/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r4d/led" review --out "$_r4d/led.html" >/dev/null 2>&1
_r4c="$(LC_ALL=C sed -e 's/<[^>]*>//g' "$_r4d/led.html" | tr '\n' ' ' | grep -o '[0-9][0-9]* findings' | head -1 | cut -d' ' -f1)"
chk "$([ "${_r4c:-0}" -ge 2 ] && echo 1 || echo 0)" "1" "v0.30 R-1: a BULLET ledger is parsed (four shipped builds rendered '0 findings' over real ones)"
# a ledger the parser cannot read must SAY so, never report zero
printf '# ledger\n\n%s\n' "$(head -c 900 /dev/zero | tr '\0' 'x')" > "$_r4d/led/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r4d/led" review --out "$_r4d/led2.html" >/dev/null 2>&1
grep -q 'could not be read' "$_r4d/led2.html"
chk "$?" "0" "v0.30 R-1: an unparseable ledger says so — it never prints '0 findings, nothing waiting'"
# R-5 — a bare pipe inside an inline code span must not split the row
printf '# ledger\n\n| Issue ID | Area | Severity | Status |\n|---|---|---|---|\n| P1 | `a \| b` | CRITICAL | OPEN |\n' > "$_r4d/led/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r4d/led" review --out "$_r4d/led3.html" >/dev/null 2>&1
psays "$_r4d/led3.html" '1 findings — 1 critical'
chk "$?" "0" "v0.30 R-5: a pipe inside a code span does not split the row (severity read as CRITICAL)"
# R-4 — severity is the cell's LEADING verdict, not a keyword anywhere in it
printf '# ledger\n\n| Issue ID | Area | Severity | Status |\n|---|---|---|---|\n| P1 | x | MAJOR — not Critical, it cannot ship a wrong number | OPEN |\n' > "$_r4d/led/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r4d/led" review --out "$_r4d/led4.html" >/dev/null 2>&1
psays "$_r4d/led4.html" '0 critical'
chk "$?" "0" "v0.30 R-4: severity is the cell's leading verdict, not any keyword inside it"
rm -rf "$_r4d"

# ── v0.30 review-3 on contract v11 (narrowed scope). Round 1's shape: the ledger REWRITE fixed the
# row-splitting heuristics and introduced new ways to lose rows, plus an all-clear over no evidence. ─
_v11="$(mktemp -d)"
mkdir -p "$_v11/b"; printf '# c\n\n## Goal\nA thing.\n' > "$_v11/b/contract.md"
# C2 — a build with NO ledger must never print the all-clear
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_v11/b" review --out "$_v11/none.html" >/dev/null 2>&1
grep -q 'Nothing is waiting on you' "$_v11/none.html"
chk "$?" "1" "v0.30 v11-C2: no review-ledger.md NEVER prints 'nothing is waiting on you'"
grep -qi 'no review-ledger\|No review has been recorded' "$_v11/none.html"
chk "$?" "0" "v0.30 v11-C2: a missing ledger says so — missing evidence is not an all-clear"
# a SHORT ledger that plainly says do-not-ship must not read as clean either
printf 'Round 1 found three CRITICAL defects. Do not ship.\n' > "$_v11/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_v11/b" review --out "$_v11/short.html" >/dev/null 2>&1
grep -q 'Nothing is waiting on you' "$_v11/short.html"
chk "$?" "1" "v0.30 v11-C2: a short unparseable ledger does not read as clean (no 400-char floor)"
# C1 — the FIRST row of a separator-less table must not be lost
printf 'Columns: Issue ID | Severity | Status\n\n| A-1 | CRITICAL | OPEN |\n| A-2 | MAJOR | FIXED |\n| A-3 | MINOR | FIXED |\n' > "$_v11/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_v11/b" review --out "$_v11/c1.html" >/dev/null 2>&1
psays "$_v11/c1.html" '3 findings'
chk "$?" "0" "v0.30 v11-C1: a separator-less table keeps its FIRST row (it was silently dropped)"
# C1b — a lone row with no header and no separator must still be counted
printf '> a note\n| Z-9 | CRITICAL | OPEN |\n\nmore prose\n\n| Y-8 | MAJOR | FIXED |\n' > "$_v11/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_v11/b" review --out "$_v11/c1b.html" >/dev/null 2>&1
psays "$_v11/c1b.html" '2 findings'
chk "$?" "0" "v0.30 v11-C1: a single-row table is flushed, not discarded when the table ends"
# C3/C4 — a summary line is not a finding
printf '# ledger\n\n- Findings: 0 Critical / 0 Major. Converged.\n\n| Issue | Sev | Status |\n|---|---|---|\n| MIN-1: the grep matched the island body | MINOR | FIXED |\n' > "$_v11/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_v11/b" review --out "$_v11/c3.html" >/dev/null 2>&1
psays "$_v11/c3.html" '1 findings'
chk "$?" "0" "v0.30 v11-C3: a summary bullet is not counted as a finding, and 'MIN-1: text' is"
# M5 — the description column is found by NAME, not hard-coded to cells[1]
printf '| Issue ID | Review | Severity | Failure mode | Status |\n|---|---|---|---|---|\n| Q-1 | R2 | MAJOR | the gate accepted a forged record | FIXED |\n' > "$_v11/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_v11/b" review --out "$_v11/m5.html" >/dev/null 2>&1
grep -q 'the gate accepted a forged record' "$_v11/m5.html"
chk "$?" "0" "v0.30 v11-M5: the row description comes from Failure mode, not the Review column"
# C5 — a status of 'VERIFIED FIXED' is closed, not OPEN
printf '| Issue ID | Severity | Status |\n|---|---|---|\n| W-1 | MAJOR | VERIFIED FIXED |\n' > "$_v11/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_v11/b" review --out "$_v11/c5.html" >/dev/null 2>&1
psays "$_v11/c5.html" '0 still open'
chk "$?" "0" "v0.30 v11-C5: 'VERIFIED FIXED' is closed (it rendered as OPEN, contradicting band 2)"
# the VERIFY regression: the ordinary word 'verify' in prose must not truncate a step
mkdir -p "$_v11/p"; printf '# c\n\n## Goal\nA thing.\n' > "$_v11/p/contract.md"
printf -- '- [x] **1 · A step.** There is nothing to verify (the common case) and the rest of this sentence must survive. **VERIFY:** `cmd 1`\n' > "$_v11/p/plan.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_v11/p" plan-map --out "$_v11/pv.html" >/dev/null 2>&1
# Strip tags first: the step's text is legitimately split across its title and detail divs, so a
# grep for the joined phrase tests the layout, not the property.
sed -e 's/<[^>]*>/ /g' "$_v11/pv.html" | tr -s ' ' | grep -q 'the rest of this sentence must survive'
chk "$?" "0" "v0.30 v11: the word 'verify' in prose does not truncate a step (only a literal VERIFY: marker does)"
psays "$_v11/pv.html" 'cmd 1'
chk "$?" "0" "v0.30 v11: the real VERIFY command is still extracted from the step line"
rm -rf "$_v11"

# ── v0.30 review-3 on contract v11, round 2. Shape: round 1's ID FILTER — added to stop a
# fabricated finding — became the mechanism by which real findings disappeared. ─────────────────
_r2v="$(mktemp -d)"
mkdir -p "$_r2v/b"; printf '# c\n\n## Goal\nA thing.\n' > "$_r2v/b/contract.md"
# R2-C1 — range / compound / numeric ids were dropped, and the page then printed the all-clear
printf '| Issue ID | Severity | Status |\n|---|---|---|\n| R-1..R-11 | CRITICAL | OPEN |\n| G3/G4 | CRITICAL | OPEN |\n| 1 | CRITICAL | OPEN |\n| A-2 | MINOR | FIXED |\n' > "$_r2v/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r2v/b" review --out "$_r2v/id.html" >/dev/null 2>&1
psays "$_r2v/id.html" '4 findings'
chk "$?" "0" "v0.30 v11-R2-C1: range, compound and numeric ids are findings (they vanished)"
grep -q 'Nothing is waiting on you' "$_r2v/id.html"
chk "$?" "1" "v0.30 v11-R2-C1: three OPEN CRITICALs never render as 'nothing is waiting on you'"
# R2-M4 — the parser must be fence-blind like every other reader here
printf '# how to write a ledger\n\n```\n| Issue ID | Severity | Status |\n|---|---|---|\n| EX-1 | CRITICAL | OPEN |\n| EX-2 | CRITICAL | OPEN |\n```\n\n| Issue ID | Severity | Status |\n|---|---|---|\n| A-1 | MINOR | FIXED |\n' > "$_r2v/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r2v/b" review --out "$_r2v/fence.html" >/dev/null 2>&1
psays "$_r2v/fence.html" '1 findings'
chk "$?" "0" "v0.30 v11-R2-M4: an EXAMPLE table inside a code fence is not counted as findings"
# R2-M5 — a prose bullet that merely mentions a severity is not a finding
printf '# ledger\n\n- R1-C1 CRITICAL — a real finding.\n\nre-attacked, no new material:\n- R2-M1/M2 (rollback-rehearsed, no CRITICAL left)\n' > "$_r2v/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r2v/b" review --out "$_r2v/bul.html" >/dev/null 2>&1
psays "$_r2v/bul.html" '1 findings'
chk "$?" "0" "v0.30 v11-R2-M5: a severity word in a prose bullet does not invent a finding"
# R2-C3 — band 2 and band 4 must agree, including on an unrecognised status
printf '| Issue ID | Severity | Status |\n|---|---|---|\n| A-1 | MAJOR | G2 — user decision |\n| A-2 | MAJOR | VERIFIED FIXED |\n' > "$_r2v/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r2v/b" review --out "$_r2v/st.html" >/dev/null 2>&1
psays "$_r2v/st.html" '0 still open'
chk "$?" "0" "v0.30 v11-R2-C3: 'VERIFIED FIXED' is closed and an unknown status is not counted open"
_r2o="$(grep -o 'class="verify"><b>OPEN</b>' "$_r2v/st.html" | wc -l | tr -d ' ')"
chk "${_r2o:-0}" "0" "v0.30 v11-R2-C3: band 4 prints no OPEN label when band 2 says none are open"
# R2-C2 — an empty file is not a missing file
printf '   \n\t\n' > "$_r2v/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r2v/b" review --out "$_r2v/mt.html" >/dev/null 2>&1
grep -q 'is empty' "$_r2v/mt.html"
chk "$?" "0" "v0.30 v11-R2-m3: an EMPTY ledger says it is empty, not that no file exists"
# R2-M1 — a plan writing `*Verify:*` after a sentence is not "none recorded"
mkdir -p "$_r2v/p"; printf '# c\n\n## Goal\nA.\n' > "$_r2v/p/contract.md"
printf -- '- [x] **S1 — a step** in compass.sh: do the thing. *Verify:* `bash compass.sh status` exit 0\n' > "$_r2v/p/plan.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r2v/p" plan-map --out "$_r2v/pv.html" >/dev/null 2>&1
grep -q 'none recorded' "$_r2v/pv.html"
chk "$?" "1" "v0.30 v11-R2-M1: '*Verify:*' after a sentence IS the marker (92 false 'none recorded' claims)"
# R2-M3 — a label ending in a colon must not swallow its content
mkdir -p "$_r2v/g"; printf '# c\n\n## Goal\nA thing.\n\n## Reconciliation\nGold figures (pinned literals):\n\n- version = 0.13.0\n- selftest_passed = 349\n' > "$_r2v/g/contract.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r2v/g" brief --out "$_r2v/gb.html" >/dev/null 2>&1
psays "$_r2v/gb.html" 'selftest_passed = 349' 
chk "$?" "0" "v0.30 v11-R2-M3: a colon-terminated label keeps its content (the gold figures were dropped)"
# R2-C4 — the Release Card must never advertise "0 changes"
_zc=0
# v0.32.0 M-1b, from an independent review. This loop read `.claude/builds/*/`, which is
# GITIGNORED — so on a clean clone the glob matched nothing, the body never ran, and `_zc` was 0 by
# construction. The assertion has been comparing 0 to 0 since it was written, in a check whose own
# premise is "11 Release Cards did this". It now reads the TRACKED fixture corpus, and counts what
# it rendered so an empty population is a failure rather than a pass.
_r2n=0
for _d in "$PLUGIN_ROOT/scripts/fixtures/corpus"/*/; do
  [ -f "$_d/contract.md" ] || continue
  node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_d" release-card --out "$_r2v/rc.html" >/dev/null 2>&1 || continue
  _r2n=$((_r2n+1))
  psays "$_r2v/rc.html" '0 changes' && _zc=$((_zc+1))
done
chk "$([ "$_r2n" -ge 5 ] && echo ok || echo "EMPTY($_r2n)")" "ok" "v0.32 M-1b: ...and it rendered a Release Card to look at — this loop read a gitignored directory and scored 0 out of 0 on every clean clone"
chk "$_zc" "0" "v0.30 v11-R2-C4: no Release Card says '0 changes' (11 did, one under a lede saying 'Five changes')"
rm -rf "$_r2v"

# ── v0.30 review-3 on contract v11, round 3. Shape unchanged: round 2's WIDENINGS let non-findings
# in, its NARROWINGS still dropped real ones — and the suites were green through all of it. ──────
_r3v="$(mktemp -d)"; mkdir -p "$_r3v/b" "$_r3v/p"
printf '# c\n\n## Goal\nA thing.\n' > "$_r3v/b/contract.md"; cp "$_r3v/b/contract.md" "$_r3v/p/contract.md"
# R3-2 — ledgers head the column `Sev` and write `Crit` / `Maj`
printf '| Issue ID | Sev | Status |\n|---|---|---|\n| A-1 | Crit | OPEN |\n| A-2 | **Crit** | OPEN |\n| A-3 | Maj | OPEN |\n' > "$_r3v/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r3v/b" review --out "$_r3v/sev.html" >/dev/null 2>&1
psays "$_r3v/sev.html" '3 findings — 2 critical, 1 major'
chk "$?" "0" "v0.30 v11-R3-2: abbreviated severities (Crit/Maj) grade correctly"
# R3-1 — six real bullet formats, not one
printf '# ledger\n\n- **A1-C1 CRITICAL** — one.\n- **A2-C2 CRITICAL** (reason) — two.\n- **A3-C3 (CRITICAL)** — three.\n- **A4-C4 [CRITICAL]** — four.\n' > "$_r3v/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r3v/b" review --out "$_r3v/bul.html" >/dev/null 2>&1
psays "$_r3v/bul.html" '4 findings — 4 critical'
chk "$?" "0" "v0.30 v11-R3-1: a bullet's severity is read from anywhere in its leading segment"
# R3-1b — a sub-finding inherits its parent's severity
printf '# ledger\n\n- **C1 (CRITICAL)** — the parent.\n- **C1a (a detail)** → the first half.\n- **C1b (another)** → the second half.\n' > "$_r3v/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r3v/b" review --out "$_r3v/sub.html" >/dev/null 2>&1
psays "$_r3v/sub.html" '3 findings — 3 critical'
chk "$?" "0" "v0.30 v11-R3-1: C1a/C1b inherit C1's severity (two CRITICALs were hidden)"
# R3-3 — the same-shape rescue must not invent findings
printf '| Issue ID | Sev | Status |\n|---|---|---|\n| A-1 | CRITICAL | OPEN |\n| — | — | NONE |\n| Total | — | — |\n| 2026-08-18 | — | — |\n' > "$_r3v/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r3v/b" review --out "$_r3v/resc.html" >/dev/null 2>&1
psays "$_r3v/resc.html" '1 findings'
chk "$?" "0" "v0.30 v11-R3-3: a no-findings row, a totals row and a date are not findings"
# R3-4 — "NOT FIXED" with a space is OPEN, not closed
printf '| Issue ID | Sev | Status |\n|---|---|---|\n| A-1 | CRITICAL | NOT FIXED |\n' > "$_r3v/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r3v/b" review --out "$_r3v/nf.html" >/dev/null 2>&1
psays "$_r3v/nf.html" '1 still open'
chk "$?" "0" "v0.30 v11-R3-4: 'NOT FIXED' (with a space) is OPEN"
# R3-5 — a bracketed qualifier between VERIFY and its colon
printf -- '- [x] **S1 — a step.** Do the thing. **Verify (INV-8):** `bash smoke.sh`\n- [x] **S2 — another.** Do it. **SINGLE VERIFY (merged):** `bash recon.sh`\n' > "$_r3v/p/plan.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r3v/p" plan-map --out "$_r3v/pv.html" >/dev/null 2>&1
grep -q 'none recorded' "$_r3v/pv.html"
chk "$?" "1" "v0.30 v11-R3-5: 'Verify (INV-8):' and 'SINGLE VERIFY (merged):' are markers"
# R3-7 — sub-step labels must not collide with real step numbers
printf -- '- [x] **1 · one.** x **VERIFY:** `a`\n- [x] **4a · sub.** y **VERIFY:** `b`\n- [x] **4b · sub.** z **VERIFY:** `c`\n- [x] **5 · five.** w **VERIFY:** `d`\n' > "$_r3v/p/plan.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r3v/p" plan-map --out "$_r3v/pn.html" >/dev/null 2>&1
_r3n="$(grep -o 'class="b-num">[0-9a-z]*</div>' "$_r3v/pn.html" | sed 's/.*>\(.*\)<.*/\1/' | sort | uniq -d | wc -l | tr -d ' ')"
chk "${_r3n:-0}" "0" "v0.30 v11-R3-7: sub-step labels (4a/4b) keep their own number — no duplicates"
# R3-6 — a labelled field must never render empty
printf -- '- [x] **1 · one.** x **VERIFY:** `a`\n' > "$_r3v/p/plan.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r3v/p" plan-map --out "$_r3v/pe.html" >/dev/null 2>&1
grep -q 'class="v"></div>' "$_r3v/pe.html"
chk "$?" "1" "v0.30 v11-R3-6: no labelled field renders empty on the plan-approval page"
node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_r3v/pe.html" --copy >/dev/null 2>&1
printf '<div class="k">What changes</div><div class="v"></div>' > "$_r3v/empty.html"
# Capture first — `node … | grep -q` under `set -o pipefail` reports NODE's exit (1 on a FAIL page),
# not grep's. That is the R4-1 class, in an assertion written during the round that found it.
_r3e="$(node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_r3v/empty.html" --copy 2>&1 || true)"
case "$_r3e" in *no-empty-field*) _r3ef=0 ;; *) _r3ef=1 ;; esac
chk "$_r3ef" "0" "v0.30 v11-R3-6: the gate can SEE an empty labelled field (nothing looked for it)"
# R3-8 — a colon-terminated label in lineMatching keeps its content
printf '# c\n\n## Goal\nA thing.\n\n## Reconciliation\nGold figures (pinned):\n- lead = 4\n- lag = 0\n' > "$_r3v/g_contract.md"
mkdir -p "$_r3v/g"; cp "$_r3v/g_contract.md" "$_r3v/g/contract.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r3v/g" brief --out "$_r3v/gb.html" >/dev/null 2>&1
psays "$_r3v/gb.html" 'lead = 4'
chk "$?" "0" "v0.30 v11-R3-8: the Proof card keeps the gold figures under a colon label"
rm -rf "$_r3v"

# ── v0.30 review-3 on contract v11, round 4. The SIBLING pattern, sixth occurrence: a fix applied
# to one of two functions holding the same rule. These assertions pin the rules that are now SHARED.
_r4w="$(mktemp -d)"; mkdir -p "$_r4w/b" "$_r4w/p"
printf '# c\n\n## Goal\nA thing.\n' > "$_r4w/b/contract.md"; cp "$_r4w/b/contract.md" "$_r4w/p/contract.md"
# R4-C1 — a severity must be a WHOLE WORD. "CRITIQUE-TARGET" is not CRITICAL.
printf '| Issue ID | Status |\n|---|---|\n| R1-M1 | OPEN |\n' > "$_r4w/b/review-ledger.md"
printf '| Issue ID | Area | Status |\n|---|---|---|\n| R1-M1 | the CRITIQUE-TARGET list and cold-critic wiring | OPEN |\n' > "$_r4w/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r4w/b" review --out "$_r4w/sv.html" >/dev/null 2>&1
psays "$_r4w/sv.html" '0 critical'
chk "$?" "0" "v0.30 v11-R4-C1: 'CRITIQUE-TARGET' does not grade a row CRITICAL (13 rows on 4 builds did)"
# R4-C3 — the rescue's blocklist must BITE, not be gated behind a severity check
printf '| Issue ID | Sev | Status |\n|---|---|---|\n| A-1 | CRITICAL | OPEN |\n| N/A | MAJOR | OPEN |\n| TOTAL | CRITICAL | OPEN |\n| — | MINOR | folded above |\n' > "$_r4w/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r4w/b" review --out "$_r4w/rs.html" >/dev/null 2>&1
psays "$_r4w/rs.html" '1 findings'
chk "$?" "0" "v0.30 v11-R4-C3: N/A, TOTAL and a roll-up dash row are not findings"
# R4-C2 — a bare count leading a summary bullet is not an id
printf '# ledger\n\n- **A-1 CRITICAL** — real.\n- **3 MINOR hardenings applied (round 2 fixes):** (a) one (b) two\n' > "$_r4w/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r4w/b" review --out "$_r4w/bc.html" >/dev/null 2>&1
psays "$_r4w/bc.html" '1 findings'
chk "$?" "0" "v0.30 v11-R4-C2: a leading COUNT ('3 MINOR hardenings') is not a finding id"
# R4-M6 — inheritance must not make R10 a child of R1
printf '# ledger\n\n- **R1 (CRITICAL)** — the parent.\n- **R10 — a later note that is not a finding**\n' > "$_r4w/b/review-ledger.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r4w/b" review --out "$_r4w/inh.html" >/dev/null 2>&1
psays "$_r4w/inh.html" '1 findings'
chk "$?" "0" "v0.30 v11-R4-M6: R10 does not inherit R1's severity (fires as soon as a ledger passes 9)"
# R4-M5 — ONE fence rule: stripFences must handle a 3-tick sample nested in a 4-tick fence
# The Goal is placed AFTER the nested fence: with the old naive toggle the 4-backtick opener and
# the 3-backtick inner opener cancelled, so everything past the mockup was swallowed and the Brief
# rendered a Goal taken from the INDEX instead of the contract.
# What the naive toggle actually does: the 4-backtick opener and the 3-backtick inner opener
# cancel, so the SAMPLE'S OWN CONTENT falls outside the fence and reaches the reader's page.
# The goal line below is the bait — it must render; the mockup text must not.
# The naive toggle's exact symptom: the 4-tick opener and the 3-tick INNER opener cancel, so the
# text BETWEEN the inner fences falls outside the block and reaches the reader. `MOCKUPLEAKSENTINEL`
# is the bait — it sits between the inner ``` pair, which is precisely what leaks.
printf '# c\n\n## Goal\n````\nouter sample line.\n```\nMOCKUPLEAKSENTINEL should never reach a page.\n```\n````\nThe real goal sentence.\n' > "$_r4w/b/contract.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r4w/b" brief --out "$_r4w/fn.html" >/dev/null 2>&1
grep -q 'MOCKUPLEAKSENTINEL' "$_r4w/fn.html"
chk "$?" "1" "v0.30 v11-R4-M5: a 3-backtick sample nested in a 4-backtick fence does not leak onto the page"
# R4-M2 — step numbers: BOTH separators
printf '# c\n\n## Goal\nA.\n' > "$_r4w/p/contract.md"
printf -- '- [x] **1. one.** x **VERIFY:** `a`\n- [x] **1b. sub.** y **VERIFY:** `b`\n- [x] **2. two.** z **VERIFY:** `c`\n' > "$_r4w/p/plan.md"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_r4w/p" plan-map --out "$_r4w/sn.html" >/dev/null 2>&1
_r4b="$(node -e "
const h=require('fs').readFileSync(process.argv[1],'utf8');
const rows=[...h.matchAll(/class=\"b-num\">([0-9a-z]+)<\/div>[\s\S]{0,80}?class=\"b-ttl\">([^<]{0,14})/g)];
console.log(rows.filter(r=>{const m=r[2].match(/^(\d+[a-z]?)\s*[.·)]/);return m&&m[1]!==r[1];}).length);" "$_r4w/sn.html")"
chk "${_r4b:-9}" "0" "v0.30 v11-R4-M2: a '1b. ' step keeps its own number (16 of 17 rows contradicted their title)"
# R4-M3 — the empty-field check must see a value that only LOOKS empty
for _v in '&nbsp;' '—'; do
  printf '<div class="k">Build what</div><div class="v">%s</div>' "$_v" > "$_r4w/ef.html"
  _r4e="$(node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_r4w/ef.html" --copy 2>&1 || true)"
  case "$_r4e" in *no-empty-field*) _r4ef=0 ;; *) _r4ef=1 ;; esac
  chk "$_r4ef" "0" "v0.30 v11-R4-M3: a field containing only '$_v' counts as empty"
done
rm -rf "$_r4w"

# ── v0.30 INV-WAIVER: a review that did NOT converge is a real state, and Compass could not say it.
# Before this, the options were PASS or blocked — so shipping a knowingly-un-converged build meant
# ticking a box that was false, which is the falsification this whole build exists to prevent.
# It lives in its OWN subcommand, never inside cmd_gate: v0.28's INV-NO-LIFECYCLE-CHANGE freezes
# that function byte-for-byte and caught the first attempt to put it there.
_wv="$(mktemp -d)"; mkdir -p "$_wv/b"
printf '# c\n' > "$_wv/b/contract.md"
_mk_rb() { printf '## RECEIPT — review-build · b · %s\n- [x] gate: build receipt OK\n- [ ] converged in two consecutive clean rounds — NO.\n%s\n' "$1" "$2" > "$_wv/b/receipts.md"; }
_mk_rb 'ACCEPTED WITH OPEN FINDINGS' ''
bash "$PLUGIN_ROOT/scripts/compass.sh" converge-waiver "$_wv/b" >/dev/null 2>&1
chk "$?" "1" "v0.30 INV-WAIVER: 'ACCEPTED WITH OPEN FINDINGS' alone does NOT let a build ship"
_mk_rb 'ACCEPTED WITH OPEN FINDINGS' '- [x] converge-waiver: user-signed · Rishi accepted the open parsing risk'
bash "$PLUGIN_ROOT/scripts/compass.sh" converge-waiver "$_wv/b" >/dev/null 2>&1
chk "$?" "0" "v0.30 INV-WAIVER: a USER-SIGNED waiver lets it ship, un-converged and recorded"
# the waiver may never be a model-authored header — the cold-critic lesson, applied again
_mk_rb 'ACCEPTED WITH OPEN FINDINGS' '- [x] converge-waiver: auto'
bash "$PLUGIN_ROOT/scripts/compass.sh" converge-waiver "$_wv/b" >/dev/null 2>&1
chk "$?" "1" "v0.30 INV-WAIVER: 'converge-waiver: auto' is not a signature"
# the normal gate is UNCHANGED — an un-converged receipt still cannot walk through it
_mk_rb 'ACCEPTED WITH OPEN FINDINGS' '- [x] converge-waiver: user-signed · signed'
bash "$PLUGIN_ROOT/scripts/compass.sh" gate "$_wv/b" review-build >/dev/null 2>&1
chk "$?" "1" "v0.30 INV-WAIVER: cmd_gate stays frozen — the waiver widens nothing there"
# and the waiver refuses to bless an ordinary PASS receipt, so it cannot become a general bypass
printf '## RECEIPT — review-build · b · PASS\n- [x] gate ok\n- [x] converge-waiver: user-signed · x\n' > "$_wv/b/receipts.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" converge-waiver "$_wv/b" >/dev/null 2>&1
chk "$?" "1" "v0.30 INV-WAIVER: the waiver applies ONLY to an un-converged receipt, never as a general bypass"
rm -rf "$_wv"

# ── v0.30 POST-SHIP, found by dogfooding v0.31's first stage against shipped v0.30.0 ───────────
_ps="$(mktemp -d)"; mkdir -p "$_ps/b"
printf 'compass-format: v0.30\n' > "$_ps/b/.compass-format"
printf -- '---\ncompass-format: v0.30\n---\n# c\n\n## Goal\nA thing.\n\n## INVARIANTs\n- **INV-1:** a thing that must hold.\n' > "$_ps/b/contract.md"
printf '## RECEIPT — contract · b · PASS\n- [x] done\n- [x] mode choice: asked=yes · answer=Autonomous · source=question\n' > "$_ps/b/receipts.md"
# INV-0's evidence records a PRE-CHANGE failure. It cannot exist while the contract is being
# locked, because the work has not started — so arming redfirst-check at the CONTRACT seam made it
# impossible for any new build to lock its own contract. It belongs where INV-0's own words put it:
# "before its step is ticked".
bash "$PLUGIN_ROOT/scripts/compass.sh" gate "$_ps/b" contract >/dev/null 2>&1
chk "$?" "0" "v0.30 post-ship: a NEW build can lock its contract (redfirst-check is not on the contract seam)"
printf '## RECEIPT — build · b · PASS\n- [x] done\n' >> "$_ps/b/receipts.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" gate "$_ps/b" build >/dev/null 2>&1
chk "$?" "1" "v0.30 post-ship: redfirst-check STILL bites at the build seam (no evidence = refused)"
printf 'ASSERT-INVARIANTS-RUN root=/x tree=%s\nINV-1 value=9 target=0 RED\n' "$(git -C "$PLUGIN_ROOT" rev-parse HEAD 2>/dev/null || echo 0)" > "$_ps/b/red-first-evidence.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" gate "$_ps/b" build >/dev/null 2>&1
chk "$?" "0" "v0.30 post-ship: with real evidence the build seam passes"
# The rail printed a frame with NOTHING inside it whenever no link was passed — against its own
# comment that an empty frame is worse than silence.
printf '# Progress\n\n**Stage:** ① contract\n' > "$_ps/b/progress.md"
_r1="$(bash "$PLUGIN_ROOT/scripts/compass.sh" rail "$_ps/b" --artefact brief 2>&1)"
chk "${#_r1}" "0" "v0.30 post-ship: the rail prints NOTHING when it has nothing to point at"
printf '<title>x</title><p>hi</p>' > "$_ps/b/brief.html"
_r2="$(bash "$PLUGIN_ROOT/scripts/compass.sh" rail "$_ps/b" --artefact brief 2>&1)"
case "$_r2" in *brief.html*) _rr=0 ;; *) _rr=1 ;; esac
chk "$_rr" "0" "v0.30 post-ship: the rail finds the view's own file without being handed a path"
rm -rf "$_ps"

# ── v0.30 INV-A11Y: the new theme's contrast claim is EXECUTED, not asserted ─────────────────
# contrast-check.mjs existed and NO suite ran it, so a theme added this build carried an
# accessibility claim that nothing verified — the founding defect of this build, in a new place.
node "$PLUGIN_ROOT/scripts/contrast-check.mjs" "$PLUGIN_ROOT/skills/compass-visual/themes/compass-artefact.json" >/dev/null 2>&1
chk "$?" "0" "v0.30 INV-A11Y: every token pair meets its contrast target in BOTH themes"
# The --html mode: contrast-check's own header says a token file "cannot show a bad pairing that
# gen.mjs composes", and until now every caller passed the token file alone — the gate ran in the
# weaker of its two modes, which is the mode its author documented as insufficient.
# v0.32.0 M-1b: this rendered from `.claude/builds/`, which is gitignored. On a clean clone gen.mjs
# exited 2 with "no contract.md", no page was written, and `--html` on a missing file fell back to
# exactly the token-only mode the comment above calls insufficient. Render from a TRACKED fixture
# and refuse to run the check at all unless a page actually exists.
_ccd="$(mktemp -d)"
node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$PLUGIN_ROOT/scripts/fixtures/corpus/long-ledger" brief-body --out "$_ccd/p.html" >/dev/null 2>&1
chk "$([ -s "$_ccd/p.html" ] && echo ok || echo MISSING)" "ok" "v0.32 M-1b: ...and there IS a generated page to check the contrast against"
node "$PLUGIN_ROOT/scripts/contrast-check.mjs" "$PLUGIN_ROOT/skills/compass-visual/themes/compass-artefact.json" --html "$_ccd/p.html" >/dev/null 2>&1
chk "$?" "0" "v0.30 INV-A11Y: contrast checked against the GENERATED page, not the token file alone"
rm -rf "$_ccd"
node "$PLUGIN_ROOT/scripts/contrast-check.mjs" --self-test >/dev/null 2>&1
chk "$?" "0" "v0.30 INV-A11Y: contrast-check --self-test — including that a MISSING token fails rather than passes"
_ctd="$(mktemp -d)"
python3 -c "import json,sys;t=json.load(open(sys.argv[1]));t['mut']='#f2f4f4';json.dump(t,open(sys.argv[2],'w'))" "$PLUGIN_ROOT/skills/compass-visual/themes/compass-artefact.json" "$_ctd/bad.json" 2>/dev/null
node "$PLUGIN_ROOT/scripts/contrast-check.mjs" "$_ctd/bad.json" >/dev/null 2>&1
chk "$?" "1" "v0.30 INV-A11Y: an illegible pair FAILS (the check can go red)"
rm -rf "$_ctd"

# ── v0.30 INV-1: the cold-read gate's contract ───────────────────────────────────────────────
# The intent check WAS lexical — it counted how many of the pinned intent's words appeared in the
# reader's answer. That is a proxy for comprehension and the wrong one: it failed the rebuilt Brief
# because the page had just been rewritten to STOP using the project's vocabulary, so a reader who
# understood it perfectly matched 2 of 12 terms. A metric that punishes the thing it measures.
# Replaced by a second grader that judges meaning, and by a refusal to guess when none is supplied.
bash -c 'node "$0" --self-test' "$PLUGIN_ROOT/scripts/insight-gate.mjs" >/dev/null 2>&1
chk "$?" "0" "v0.30 INV-1: insight-gate --self-test — every guard fires"
_ig="$PLUGIN_ROOT/scripts/insight-gate.mjs"; _igd="$(mktemp -d)"
printf 'MESSAGE: lock a contract for rebuilding the pages.\nIMPLICATION: it commits the build to named checks.\n' > "$_igd/intent.txt"
printf '<title>t</title><p>Lock this contract? This page asks you to lock a rebuild of the pages.</p>' > "$_igd/p.html"
# The probe is MANDATORY (R3-09): a verdict without one is a read that only quoted the headline.
printf '{"message":{"answer":"It asks you to lock a contract for rebuilding the pages.","confident":true,"quote":"Lock this contract? This page asks you"},"implication":{"answer":"It commits the build to named checks.","confident":true,"quote":"asks you to lock a rebuild of the pages"},"probe":{"question":"What does this page ask you to lock?","answer":"a rebuild of the pages","evidence":"asks you to lock a rebuild of the pages"}}' > "$_igd/v.json"
# and one WITHOUT a probe, which must not pass
printf '{"message":{"answer":"It asks you to lock a contract for rebuilding the pages.","confident":true,"quote":"Lock this contract? This page asks you"},"implication":{"answer":"It commits the build to named checks.","confident":true,"quote":"asks you to lock a rebuild of the pages"}}' > "$_igd/v-noprobe.json"
_ish="$(node -e "const c=require('crypto'),f=require('fs');console.log(c.createHash('sha256').update(f.readFileSync(process.argv[1],'utf8').trim()).digest('hex').slice(0,16))" "$_igd/intent.txt")"
printf '{"message_matches":true,"implication_matches":true,"intent_sha":"%s","reason":"t"}' "$_ish" > "$_igd/g.json"
# The control read the gate now requires: the reader correctly refused the known-bad page.
printf '{"message":{"answer":"cannot tell what this page asks","confident":false},"implication":{"answer":"cannot tell","confident":false}}' > "$_igd/ctl.json"
node "$_ig" --artefact "$_igd/p.html" --intent "$_igd/intent.txt" < "$_igd/v.json" >/dev/null 2>&1
# 2 (usage), not 3: no read was GRADED, so no read COMPLETED, and this file's exit contract reserves
# 3 for a completed read with a negative verdict. Either way it is not a pass — which is the point.
chk "$?" "2" "v0.30 INV-1: --grader is mandatory — an ungraded read cannot pass"
# ── The self-grading defeat: a reader that appends its own `grader` block to its own stdout. It
# scored GO. The reader's own claim about its own correctness is now discarded before scoring.
printf '{"message":{"answer":"It asks you to lock a contract for rebuilding the pages.","confident":true,"quote":"Lock this contract? This page asks you"},"implication":{"answer":"It commits the build to named checks.","confident":true,"quote":"asks you to lock a rebuild of the pages"},"grader":{"message_matches":true,"implication_matches":true,"reason":"self-graded by the reader itself"}}' > "$_igd/self.json"
node "$_ig" --artefact "$_igd/p.html" --intent "$_igd/intent.txt" < "$_igd/self.json" >/dev/null 2>&1
chk "$?" "2" "v0.30 INV-1: the reader may NOT grade itself (a grader on stdin is discarded)"
# ── The control round: documented in insight-gate's header since round 2, called from nowhere.
printf '{"message":{"answer":"it locks the rebuild","confident":true},"implication":{"answer":"a stranger grades it","confident":true}}' > "$_igd/ctl-go.json"
node "$_ig" --artefact "$_igd/p.html" --intent "$_igd/intent.txt" --grader "$_igd/g.json" --control "$_igd/ctl-go.json" < "$_igd/v.json" >/dev/null 2>&1
chk "$?" "3" "v0.30 INV-1: a GO on the known-bad control VOIDS the round (the reader passes anything)"
printf '{"message":{"answer":"unclear what this page wants","confident":false},"implication":{"answer":"not sure","confident":false}}' > "$_igd/ctl-no.json"
printf '{}' > "$_igd/ctl-empty.json"
node "$_ig" --artefact "$_igd/p.html" --intent "$_igd/intent.txt" --grader "$_igd/g.json" --control "$_igd/ctl-empty.json" < "$_igd/v.json" >/dev/null 2>&1
chk "$?" "3" "v0.30 R3-R2-3: an EMPTY control verdict is an unrun control, not a careful reader"
node "$_ig" --artefact "$_igd/p.html" --intent "$_igd/intent.txt" --grader "$_igd/g.json" --control "$_igd/ctl-no.json" < "$_igd/v.json" >/dev/null 2>&1
chk "$?" "0" "v0.30 INV-1: a control the reader correctly refused leaves the round standing"
node "$_ig" --artefact "$_igd/p.html" --intent "$_igd/intent.txt" --grader "$_igd/g.json" --control "$_igd/ctl.json" < "$_igd/v.json" >/dev/null 2>&1
chk "$?" "0" "v0.30 INV-1: a graded, unhedged, quoted read is a GO"
node "$_ig" --artefact "$_igd/p.html" --intent "$_igd/intent.txt" --grader "$_igd/g.json" --control "$_igd/ctl.json" < "$_igd/v-noprobe.json" >/dev/null 2>&1
chk "$?" "3" "v0.30 R3-09: the probe is MANDATORY — a reader cannot opt out of being tested"
printf '{"message_matches":true,"implication_matches":true,"intent_sha":"deadbeefdeadbeef","reason":"t"}' > "$_igd/gwrong.json"
node "$_ig" --artefact "$_igd/p.html" --intent "$_igd/intent.txt" --grader "$_igd/gwrong.json" --control "$_igd/ctl.json" < "$_igd/v.json" >/dev/null 2>&1
chk "$?" "3" "v0.30 R3-10: the grader must have graded against THIS pinned intent"
node "$_ig" --artefact "$_igd/p.html" --intent "$_igd/intent.txt" --grader "$_igd/g.json" < "$_igd/v.json" >/dev/null 2>&1
chk "$?" "2" "v0.30 R3-R2-2: --control is mandatory — the anti-rubber-stamp guard cannot be omitted"
printf '{"message_matches":true,"implication_matches":false,"intent_sha":"%s","reason":"t"}' "$_ish" > "$_igd/gbad.json"
node "$_ig" --artefact "$_igd/p.html" --intent "$_igd/intent.txt" --grader "$_igd/gbad.json" --control "$_igd/ctl.json" < "$_igd/v.json" >/dev/null 2>&1
chk "$?" "3" "v0.30 INV-1: the grader rejecting either half is a NO-GO"
node "$_ig" --artefact "$_igd/nope.html" --intent "$_igd/intent.txt" --grader "$_igd/g.json" < "$_igd/v.json" >/dev/null 2>&1
chk "$?" "4" "v0.30 INV-1: a missing artefact is ERROR(4), never NO-GO(3) — a broken harness is not evidence"
rm -rf "$_igd"

# ── v0.30 INV-RUNNER: the assertion runner is itself covered ─────────────────────────────────
# Nothing tested `assert-invariants.sh`. It changed six times during this build and INV-5 read
# 8 -> 6 -> 7 on one unmodified tree, so "the invariants pass" meant nothing without this.
bash "$PLUGIN_ROOT/scripts/assert-invariants.sh" "$PLUGIN_ROOT/../.." --self-test >/dev/null 2>&1
chk "$?" "0" "v0.30 INV-RUNNER: assert-invariants --self-test — every guard fires"
_gc="$(bash "$PLUGIN_ROOT/scripts/assert-invariants.sh" "$PLUGIN_ROOT/../.." --self-test 2>/dev/null | grep -c '  ok ')"
chk "$([ "$_gc" -ge 13 ] && echo 1 || echo 0)" "1" "v0.30 INV-RUNNER: at least 13 guards run (each earned by an attack that previously reached a false PASS)"
# the anti-gaming control page must not be silently regenerated — if it becomes the page under
# test, "a GO on the control voids the round" has nothing to score.
chk "$(shasum -a 256 "$PLUGIN_ROOT/scripts/fixtures/insight/control-brief.png" 2>/dev/null | cut -c1-16)" "16737533e56d08c7" "v0.30 INV-RUNNER: the cold-read control page is unchanged (sha pinned)"

# ── v0.30 INV-RAIL: the terminal surface ─────────────────────────────────────────────────────
_rd="$(mktemp -d)"; mkdir -p "$_rd/b"; printf '# c\n' > "$_rd/b/contract.md"
printf '**Stage:** build\n' > "$_rd/b/progress.md"
_r1="$(bash "$SH" rail "$_rd/b" --artefact brief --url https://x.test/a 2>/dev/null)"
chk "$(printf '%s' "$_r1" | grep -c 'https://x.test/a')" "1" "v0.30 INV-RAIL: the URL variant carries the link"
chk "$(printf '%s' "$_r1" | grep -c 'step ')" "0" "v0.30 INV-RAIL: no plan.md means NO step segment (never a false 0/0)"
_r2="$(bash "$SH" rail "$_rd/b" --artefact brief --local /tmp/x.html 2>/dev/null)"
chk "$(printf '%s' "$_r2" | grep -c 'No link this time')" "1" "v0.30 INV-RAIL: the fallback states there is no link, and why"
chk "$(bash "$SH" rail "$_rd/empty" 2>/dev/null | wc -c | tr -d ' ')" "0" "v0.30 INV-RAIL: an empty/absent dir prints NOTHING, not an empty frame"
# widths must differ — a uniform width would mean a right border, which cannot hold a 68-char URL
chk "$([ "$(printf '%s' "$_r1" | awk '{print length($0)}' | sort -u | wc -l | tr -d ' ')" -gt 1 ] && echo 1 || echo 0)" "1" "v0.30 INV-RAIL: no right border (line widths are ragged by design)"
# INV-LOCALE-SAFE: this repo has a documented class where byte-ranges under LC_ALL=C returned empty
chk "$([ "$(LC_ALL=C bash "$SH" rail "$_rd/b" --artefact brief --url https://x.test/a | md5 -q)" = "$(LC_ALL=en_US.UTF-8 bash "$SH" rail "$_rd/b" --artefact brief --url https://x.test/a | md5 -q)" ] && echo 1 || echo 0)" "1" "v0.30 INV-RAIL: byte-identical under LC_ALL=C and UTF-8"
rm -rf "$_rd"

# ── v0.30 INV-COPY-GATE: the artefact gate stops being purely structural ─────────────────────
# The structural gate passed a page that printed its goal three times, cut fields mid-word,
# mashed two headings into one word, and claimed 11 invariants while showing 2 — all invisible
# to "are the four bands present". A defective fixture proves each copy check can go red; the
# real Brief proves none of them fires on correct work.
_cgf="$PLUGIN_ROOT/scripts/fixtures/copygate/defective.html"
_cgo="$(node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_cgf" --copy 2>&1 || true)"
for _c in no-duplicated-sentence no-mashed-headings no-mid-field-cut claimed-count-matches; do
  chk "$(printf '%s' "$_cgo" | grep -c -- "$_c")" "1" "v0.30 INV-COPY-GATE: --copy catches $_c"
done
node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_cgf" >/dev/null 2>&1
chk "$?" "0" "v0.30 INV-COPY-GATE: the same fixture PASSES structurally — proving the copy checks are what caught it"


# ── v0.32 S1b: the destroyed-text instrument, and the corpus split that makes it testable ────
# The live corpus (.claude/builds) is GITIGNORED, so a clean clone has zero pages. A check pointed
# there returns a confident 0, which is indistinguishable from "the defect is fixed". Two ideas were
# tangled and are now separate: the GOLD is measured over live folders on a working machine; the
# CHECK is regression-tested against the tracked fixtures below. Hence an explicit --corpus.
#
# Asserting PER PATH, not on the total, is the whole point. A fixture set chosen by ledger shape
# alone would leave most destroying paths unexercised while the total still looked healthy — the
# same class of blind spot that produced three wrong headline figures from rendered-page greps.
_v32li="$PLUGIN_ROOT/scripts/lossy-instrument.mjs"
_v32corpus="$PLUGIN_ROOT/scripts/fixtures/corpus"
if [ -f "$_v32li" ] && command -v node >/dev/null 2>&1; then
  _v32out="$(node "$_v32li" "$RR22" --corpus "$_v32corpus" --json 2>/dev/null || true)"
  # v0.32 S1c — QUANTITIES, not just "it fires". An independent reviewer showed that asserting
  # `events > 0` leaves every number free: four mutations moved the published headline (chars
  # 375,761 -> 376,062; units 2,259 -> 2,039; events 1,111 -> 1,429) and the suite stayed 738/0.
  # One of those mutations was this build's OWN headline correction — the cap6 char fix — which had
  # no test behind it at all. Each path now pins events AND units over the TRACKED corpus, so any
  # change to what the instrument counts has to be a deliberate edit to these numbers.
  # Format: <path> <events> <units>
  while read -r _p _we _wu; do
    [ -n "$_p" ] || continue
    _got="$(printf '%s' "$_v32out" | node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
        try{ const j=JSON.parse(s); const k=process.argv[1]; const v=j.paths&&j.paths[k];
             process.stdout.write(v?`${v.events} ${v.unitsDropped}`:"0 0"); }
        catch{ process.stdout.write("0 0"); }
      });' "$_p" 2>/dev/null)"
    chk "$_got" "$_we $_wu" "v0.32 S1c: '$_p' drops exactly $_we events / $_wu units on the tracked corpus"
  done <<'PATHS'
fieldText:and-N-more 10 59
fieldText:continues-sentence 2 2
fieldText:continues-hardcut 22 22
closedRows.slice 1 10
bullets.slice8 1 4
nowItems.slice6 1 3
firstPara 12 38
firstBullet 3 10
lineMatching.cap6 1 2
invariants.assertTail 16 16
invariants.deferredReplaced 2 2
doneMeans.goalSentence2 1 2
waiverReason.firstOnly 1 2
PATHS
  # chars are pinned only where the two independent censuses AGREED. `lineMatching.cap6` is the one
  # path whose char figure this build corrected (it counted the label line and the six KEPT lines as
  # dropped), so it is pinned here specifically: reverting that correction must go red.
  chk "$(printf '%s' "$_v32out" | node -e '
    let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
      try{ const j=JSON.parse(s); const v=j.paths&&j.paths["lineMatching.cap6"];
           process.stdout.write(v?String(v.charsDropped):"none"); }
      catch{ process.stdout.write("none"); }
    });' 2>/dev/null)" "107" "v0.32 S1c: lineMatching.cap6 drops exactly 107 chars — the figure this build corrected, now pinned"
  chk "$(printf '%s' "$_v32out" | node -e '
    let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
      try{ const j=JSON.parse(s); let e=0,u=0; for (const k of Object.keys(j.paths||{})) { e+=j.paths[k].events||0; u+=j.paths[k].unitsDropped||0; }
           process.stdout.write(`${e} ${u} ${Object.keys(j.paths||{}).length}`); }
      catch{ process.stdout.write("err"); }
    });' 2>/dev/null)" "73 172 13" "v0.32 S1c: the tracked corpus totals 73 events / 172 units across exactly 13 paths (a 14th path appearing is a deliberate edit, never a surprise)"
  chk "$(printf '%s' "$_v32out" | node -e '
    let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
      try{ const j=JSON.parse(s); process.stdout.write(j.pagesFailed===0&&j.pagesRendered>0?"1":"0"); }
      catch{ process.stdout.write("0"); }
    });' 2>/dev/null)" "1" "v0.32 S1b: every fixture page renders (a failed page is UNMEASURED, never 0)"
  # An absent corpus must ERR, never PASS. Without this the clean-clone case silently reports zero
  # destroyed text and the whole measurement reads as a success.
  node "$_v32li" "$RR22" --corpus "$SMOKE_BASE/no-such-corpus" >/dev/null 2>&1
  chk "$?" "3" "v0.32 S1b: an absent corpus ERRs (exit 3) instead of reporting a confident zero"
else
  chk "1" "1" "v0.32 S1b: N/A — no node or no lossy-instrument.mjs on this tree"
fi

# ── v0.32 S24 (§17-11, Rishi's reported bug): ONE **Status:** parser, and it trims ───────────
# Before this step there were FIVE copies of the parser regex and they disagreed: three folded
# case and two did not, one read the FIRST status line and four the LAST, and NOT ONE trimmed.
_SP="$PLUGIN_ROOT/scripts/fixtures/statusparse"
_sl(){ bash -c 'source "'"$SH"'" 2>/dev/null; status_line "$@"' _ "$@"; }
_it(){ bash -c 'source "'"$SH"'" 2>/dev/null; is_terminal "$1" && echo 1 || echo 0' _ "$1"; }
chk "$(grep -cE "sed -nE .*Status:" "$SH")" "1" "v0.32 S24: the **Status:** parser regex appears EXACTLY ONCE in compass.sh (was 5)"
chk "$(bash -c 'source "'"$SH"'" 2>/dev/null; declare -F status_line >/dev/null && echo 1 || echo 0')" "1" "v0.32 S24: that one source is status_line()"
if [ -d "$_SP" ]; then
  chk "$(_sl "$_SP/terminal-trailing-space/progress.md" --token)" "shipped" "v0.32 S24 corpus 'terminal-trailing-space': trailing space trimmed"
  chk "$(_it "$(_sl "$_SP/terminal-trailing-space/progress.md" --raw --token)")" "1" "v0.32 S24 corpus 'terminal-trailing-space': classified TERMINAL (is_terminal compares exactly — it never trimmed)"
  chk "$(_sl "$_SP/terminal-leading-space/progress.md" --token)" "shipped" "v0.32 S24 corpus 'terminal-leading-space': an indented status line is FOUND (all five parsers were blind to it)"
  chk "$(_it "$(_sl "$_SP/terminal-leading-space/progress.md" --raw --token)")" "1" "v0.32 S24 corpus 'terminal-leading-space': classified TERMINAL"
  chk "$(_sl "$_SP/terminal-mixed-case/progress.md" --token)" "shipped" "v0.32 S24 corpus 'terminal-mixed-case': folds to lowercase"
  chk "$(_it "$(_sl "$_SP/terminal-mixed-case/progress.md" --raw --token)")" "1" "v0.32 S24 corpus 'terminal-mixed-case': classified TERMINAL"
  chk "$(_it "$(_sl "$_SP/terminal-crlf/progress.md")")" "1" "v0.32 S24 corpus 'terminal-crlf': a CR-terminated status is still TERMINAL"
  chk "$(_sl "$_SP/status-malformed/progress.md")" "" "v0.32 S24: a progress.md with no status line yields empty, never an error"
  bash "$SH" status "$_SP/status-malformed" >/dev/null 2>&1
  chk "$?" "0" "v0.32 S24: a malformed progress.md does not make the Stop-hook path exit non-zero"
  # the five sites must now return ONE value for one file
  _f="$_SP/terminal-trailing-space/progress.md"
  chk "$(printf '%s\n%s\n%s\n' "$(_sl "$_f" --token)" "$(_sl "$_f")" "$(_sl "$_f" --raw --token | tr 'A-Z' 'a-z')" | sort -u | grep -c .)" "1" "v0.32 S24: every fold-case mode returns ONE value for one file"
else
  chk "1" "1" "v0.32 S24: N/A — statusparse fixtures absent"
fi
# ── v0.32 S24b: the three findings the INDEPENDENT reviewer of S24 raised about its TESTS ────
# It reverted each half of the fix and watched the suite stay green. Three assertions below exist
# because of that, and each was mutation-proven to go RED when its own half is reverted.
#
# MAJOR-5 first: the checks above lean on a TRACKED fixture, but the multi-status case leaned on a
# GITIGNORED build folder, so on a clean clone (`git ls-files .claude/builds` -> 0) it silently
# N/A-passed. `multi-status` and `bold-status` are tracked, so a clean clone tests them for real.
if [ -d "$_SP/multi-status" ]; then
  # MAJOR-3: this runs cmd_status END TO END. The earlier form called status_line directly, so
  # reverting the CALL SITE back to --first cost nothing and the suite stayed at 713/0.
  chk "$(bash "$SH" status "$_SP/multi-status" 2>/dev/null | sed -n 's/^Status:  //p' | head -1)" "SHIPPED — v0.7.0 live (commit dd59a24)" "v0.32 S24b: cmd_status on a 5-status-line build reports its LAST status (MAJOR-3: the call site is now tested, not just the helper)"
  chk "$(grep -cE '^[[:space:]]*\*\*Status:\*\*' "$_SP/multi-status/progress.md")" "5" "v0.32 S24b: ...and the fixture really stacks five of them, so that check has something to catch"
fi
if [ -d "$_SP/bold-status" ]; then
  # MAJOR-1: a REAL regression S24 shipped. `**Status:** **SHIPPED (...)**` — the token mode could
  # not see past the leading `**`, returned empty, the stale-INDEX fallback fired, and a SHIPPED
  # build was advertised as a ship contender. Emphasis is decoration and is now stripped.
  chk "$(_sl "$_SP/bold-status/progress.md" --token | cut -c1-7)" "shipped" "v0.32 S24b (MAJOR-1): a status written in **bold** still reads as shipped, not as empty"
  chk "$(_it "$(_sl "$_SP/bold-status/progress.md" --raw --token | sed -E 's/ .*//')")" "1" "v0.32 S24b (MAJOR-1): ...and it classifies TERMINAL, so it is not offered as a ship contender"
fi
# MAJOR-2: is_terminal's OWN trim, exercised with dirty input that status_line never cleaned.
# Every earlier assertion fed it a value status_line had already trimmed, so reverting is_terminal
# to its shipped form left the suite byte-identical at 712/1 — a fix with no test behind it.
chk "$(_it 'SHIPPED ')" "1" "v0.32 S24b (MAJOR-2): is_terminal trims a TRAILING space itself (fed raw, not via status_line)"
chk "$(_it ' SHIPPED')" "1" "v0.32 S24b (MAJOR-2): is_terminal trims a LEADING space itself"
chk "$(_it "$(printf 'SHIPPED\r')")" "1" "v0.32 S24b (MAJOR-2): is_terminal strips a CR itself"
chk "$(_it "$(printf '\tCLOSED\t')")" "1" "v0.32 S24b (MAJOR-2): is_terminal trims TABS itself"
chk "$(_it 'draft ')" "0" "v0.32 S24b (MAJOR-2): ...and still says NO to a non-terminal status (the trim did not make it permissive)"

# ── v0.32 S21 (§17-3 + §17-4): the sketch-gate can now refuse something ──────────────────────
# It passed 30 of 30 build folders and had never refused anything. Two reasons, one edit:
# (a) a mockup was checked only when the contract carried a `mockup:` header, and on the web arm
#     a bare `design-standard:` line satisfied the gate — so deleting the mock changed nothing;
# (b) the Logic Map check lived in the non-web arm of a `case`, and the arm is chosen by a
#     SUBSTRING match over the free-prose Facets line, so builds saying "no web surface" took the
#     web arm and skipped it.
# The fixture is BUILT AT RUNTIME, not committed: a tracked file carrying the line-1
# COMPASS-MOCK marker would trip the gate's own leak tracer on every run.
_SG="$(mktemp -d)"
mkdir -p "$_SG/base/sketch"
cat > "$_SG/base/contract.md" <<'SGC'
# fixture contract — S21

Facets: library + web
sketch: in-scope — one alternative rendered.
design-standard: compass-artefact
intake: co-construct-v1

## Logic Map

```mermaid
graph TD
  A[source] --> B[gate]
```

## End
SGC
printf 'v1 · 2026-08-21 · decision=x · alternatives=a,b · picked=a · render=file-only · file=sketch/mock-v1.html\n' > "$_SG/base/sketch/LEDGER"
printf '<!-- COMPASS-MOCK slug=fixture -->\n<h1>THROWAWAY WIREFRAME</h1>\n' > "$_SG/base/sketch/mock-v1.html"
_sg(){ bash "$SH" sketch-gate "$_SG/$1" >/dev/null 2>&1; [ "$?" -ne 0 ] && echo 1 || echo 0; }   # 1 = REFUSED
bash "$SH" sketch-gate "$_SG/base" >/dev/null 2>&1
chk "$?" "0" "v0.32 S21: the unmutated sketch fixture still PASSES (the gate did not become a wall)"
# Every mutant below breaks EXACTLY ONE thing. The first version of these fixtures broke two at
# once, so three assertions were killed by the WRONG check and stayed green when their own check
# was deleted — found by the independent reviewer, and the reason each fixture is now isolated.
cp -R "$_SG/base" "$_SG/nomock"; rm -f "$_SG/nomock/sketch/mock-v1.html"
chk "$(_sg nomock)" "1" "v0.32 S21 (§17-3): deleting the artefact the LEDGER NAMES is REFUSED (shipped gate: exit 0)"
cp -R "$_SG/base" "$_SG/nomarker"; printf '<h1>THROWAWAY WIREFRAME</h1>\n' > "$_SG/nomarker/sketch/mock-v1.html"
chk "$(_sg nomarker)" "1" "v0.32 S21 (§17-3): marker absent, BANNER PRESENT — isolated, so only the marker check can kill it"
cp -R "$_SG/base" "$_SG/nobanner"; printf '<!-- COMPASS-MOCK slug=fixture -->\n<h1>quiet</h1>\n' > "$_SG/nobanner/sketch/mock-v1.html"
chk "$(_sg nobanner)" "1" "v0.32 S21 (§17-3): banner absent, MARKER PRESENT — isolated"
cp -R "$_SG/base" "$_SG/nolm"; sed -e 's/^  A\[source\] --> B\[gate\]$/  (no edges)/' "$_SG/base/contract.md" > "$_SG/nolm/contract.md"
chk "$(_sg nolm)" "1" "v0.32 S21 (§17-4): a WEB build with no Logic Map edge is REFUSED (the check used to sit in the non-web arm)"
# the doc#anchor shape: 9 of 14 render lines in the live corpus are `contract.md#logic-map`.
cp -R "$_SG/base" "$_SG/anchor"
printf 'v1 · 2026-08-21 · decision=x · render=file-only · file=contract.md#logic-map\n' > "$_SG/anchor/sketch/LEDGER"
rm -f "$_SG/anchor/sketch/mock-v1.html"
bash "$SH" sketch-gate "$_SG/anchor" >/dev/null 2>&1
chk "$?" "0" "v0.32 S21: a 'contract.md#logic-map' render line resolves to the heading and PASSES (canary: 9 historical builds use this shape)"
# ISOLATED: the Logic Map heading stays intact, only the ANCHOR is bogus. The earlier fixture also
# removed the heading, so it died on `refuse: logicmap` and the anchor branch was never exercised.
cp -R "$_SG/anchor" "$_SG/anchorbad"
printf 'v1 · 2026-08-21 · decision=x · render=file-only · file=contract.md#no-such-heading\n' > "$_SG/anchorbad/sketch/LEDGER"
chk "$(_sg anchorbad)" "1" "v0.32 S21c: an anchor resolving to NOTHING is REFUSED (heading left intact, so only the anchor check can kill it)"
cp -R "$_SG/anchor" "$_SG/anchorpfx"
printf 'v1 · 2026-08-21 · decision=x · render=file-only · file=contract.md#l\n' > "$_SG/anchorpfx/sketch/LEDGER"
chk "$(_sg anchorpfx)" "1" "v0.32 S21c: a PREFIX anchor ('#l' for '## Logic Map') is REFUSED — it used to resolve"
# A heading that exists ONLY inside a code fence is an EXAMPLE, not a heading. It used to satisfy
# the anchor. The Logic Map the §17-4 check needs is kept under a different name so this fixture
# tests the fence rule and nothing else.
cp -R "$_SG/anchor" "$_SG/anchorfence"
sed -e 's/^## Logic Map$/## Diagram/' "$_SG/anchor/contract.md" > "$_SG/anchorfence/contract.md"
printf '\n```\n## Logic Map\n```\n' >> "$_SG/anchorfence/contract.md"
printf 'v1 · x · file=contract.md#logic-map\n' > "$_SG/anchorfence/sketch/LEDGER"
chk "$(_sg anchorfence)" "1" "v0.32 S21c: a heading that exists ONLY inside a code fence does NOT satisfy an anchor"
# ── the seven defeats an independent reviewer found in the FIRST version of this check ──
cp -R "$_SG/base" "$_SG/nofile"
printf 'v1 · 2026-08-21 · decision=x · alternatives=a,b · picked=a · render=local\n' > "$_SG/nofile/sketch/LEDGER"
chk "$(_sg nofile)" "1" "v0.32 S21c: a render line naming NO artefact is REFUSED — it used to skip the whole check, so 'unwaivable' was false"
cp -R "$_SG/base" "$_SG/notrail"
printf 'v1 · x · file=sketch/mock-v1.html\nv2 · x · file=sketch/GONE.html' > "$_SG/notrail/sketch/LEDGER"
chk "$(_sg notrail)" "1" "v0.32 S21c: a LEDGER with NO TRAILING NEWLINE still reads its last render line"
cp -R "$_SG/base" "$_SG/upper"
printf 'v1 · x · file=sketch/mock-v1.HTML\n' > "$_SG/upper/sketch/LEDGER"
printf 'no marker and no banner\n' > "$_SG/upper/sketch/mock-v1.HTML"
chk "$(_sg upper)" "1" "v0.32 S21c: an UPPERCASE .HTML gets the marker+banner checks (the extension match was case-sensitive)"
cp -R "$_SG/base" "$_SG/escape"; mkdir -p "$_SG/shared"
printf '<!-- COMPASS-MOCK slug=x -->\n<h1>THROWAWAY WIREFRAME</h1>\n' > "$_SG/shared/any.html"
printf 'v1 · x · file=../shared/any.html\n' > "$_SG/escape/sketch/LEDGER"
chk "$(_sg escape)" "1" "v0.32 S21c: a '../' path is REFUSED — one mock anywhere used to satisfy every build"
cp -R "$_SG/base" "$_SG/twofile"
printf 'v1 · x · file=sketch/GONE.html · note file=contract.md#logic-map\n' > "$_SG/twofile/sketch/LEDGER"
chk "$(_sg twofile)" "1" "v0.32 S21c: EVERY file= on a line is checked — a greedy match used to read only the last, laundering a missing mock"
# ISOLATED for the plain-existence check: a NON-.html artefact, so the marker/banner branch cannot
# be what kills it. 3 of the 14 live render lines name a non-.html artefact.
cp -R "$_SG/base" "$_SG/missingtxt"
printf 'v1 · x · file=sketch/notes.txt\n' > "$_SG/missingtxt/sketch/LEDGER"
chk "$(_sg missingtxt)" "1" "v0.32 S21c: a MISSING non-.html artefact is REFUSED (isolates the existence check from the marker check)"
cp -R "$_SG/missingtxt" "$_SG/emptytxt"; : > "$_SG/emptytxt/sketch/notes.txt"
chk "$(_sg emptytxt)" "1" "v0.32 S21c: a ZERO-BYTE non-.html artefact is REFUSED — a recorded sketch that was never made"
cp -R "$_SG/missingtxt" "$_SG/goodtxt"; printf 'a real note\n' > "$_SG/goodtxt/sketch/notes.txt"
bash "$SH" sketch-gate "$_SG/goodtxt" >/dev/null 2>&1
chk "$?" "0" "v0.32 S21c: ...and a non-empty non-.html artefact PASSES, so that branch is not a wall"
rm -rf "$_SG"

# ── v0.32 S19 + S31: the three fabricated numbers on the pages, each with a check that FAILS ─
# Written after mutation testing showed that reverting every one of these four fixes left the
# suite at 731/0. A fix with no failing test behind it is the defect this build is named for.
_GEN="$PLUGIN_ROOT/skills/compass-visual/gen.mjs"
if [ -f "$_GEN" ] && command -v node >/dev/null 2>&1; then
  _FB="$(mktemp -d)"; mkdir -p "$_FB/b"
  cat > "$_FB/b/contract.md" <<'FBC'
# Contract — fabnum

facets: library
schema-touching: no

## Goal & scope
**Goal:** prove the three fabricated numbers are gone. This fixture has no version suffix in its title, so the version chip has nothing to read.

### NOW
1. One scope item.

## Acceptance & INVARIANTs
| Invariant | What it asserts | Evidence |
| --- | --- | --- |
| **INV-TABLE-A** | invariants written as a TABLE are counted | the brief lists this row |
| **INV-TABLE-B** | and so is the second one | the brief lists this row too |
FBC
  cat > "$_FB/b/plan.md" <<'FBP'
# Plan — fabnum
- [ ] **S1** nothing started — VERIFY: the page must not claim a step is running.
- [ ] **S2** also not started — VERIFY: same.
- [ ] **S3** also not started — VERIFY: same.
FBP
  printf '# fabnum\n\n**Status:** draft\n' > "$_FB/b/progress.md"
  # S19 §17-6 — a TABLE of invariants must be read, not reported as none
  node "$_GEN" "$_FB/b" brief --out "$_FB/brief.html" >/dev/null 2>&1
  # NB: `grep -c ... || echo 0` prints "0\n0" on a no-match — grep -c already emits 0 AND exits 1.
  # That is a check whose failure text is unreadable, so `|| true` throughout below.
  chk "$(grep -c 'INV-TABLE-A' "$_FB/brief.html" 2>/dev/null || true)" "1" "v0.32 S19 (§17-6): invariants written as a TABLE are read (the panel said 'pins no INVARIANTs' while the header said 12)"
  chk "$(grep -c 'pins no INVARIANTs' "$_FB/brief.html" 2>/dev/null || true)" "0" "v0.32 S19 (§17-6): ...so the page does not also claim the contract pins none"
  # S19 §17-12 — a title with no version must not be reported as v1
  _txt(){ sed -e 's/<[^>]*>//g' -e 's/&nbsp;/ /g' "$1" 2>/dev/null; }
  # A NEGATIVE form of this check ("does not say v1") stayed green when the fix was reverted,
  # because the version is the LAST chip and the pattern demanded a trailing separator. Asserting
  # the value POSITIVELY is what makes it fail.
  # flatten to ONE line first: sed is line-oriented, so without this every other line of the page
  # also survives the strip and the comparison is against the whole file.
  _vchip="$(tr '\n' ' ' < "$_FB/brief.html" | sed -e 's/.*<div class="b-id">//' -e 's|</div>.*||' -e 's/<[^>]*>//g' -e 's/&nbsp;/ /g' | awk -F'·' '{gsub(/^[ \t]+|[ \t]+$/,"",$NF); print $NF}')"
  chk "$_vchip" "contract version not stated" "v0.32 S19 (§17-12): a contract whose title carries no version SAYS SO — it is not reported as v1"
  # S31 — an all-unstarted plan must not claim a step is running
  node "$_GEN" "$_FB/b" plan-map --out "$_FB/pm.html" >/dev/null 2>&1
  chk "$(_txt "$_FB/pm.html" | grep -cE '[0-9]+ running' || true)" "0" "v0.32 S31: a plan with nothing started claims NO step is running (was hardcoded to 1)"
  # S31 — a REAL in-progress marker must be counted, and the count must match it
  cp -R "$_FB/b" "$_FB/c"
  printf '# Plan — fabnum\n- [x] **S1** done — VERIFY: ran.\n- [~] **S2** in flight — VERIFY: pending.\n- [~] **S3** in flight — VERIFY: pending.\n- [ ] **S4** not started — VERIFY: pending.\n' > "$_FB/c/plan.md"
  node "$_GEN" "$_FB/c" plan-map --out "$_FB/pm2.html" >/dev/null 2>&1
  chk "$(_txt "$_FB/pm2.html" | grep -oE '[0-9]+ running' | head -1)" "2 running" "v0.32 S31: ...and two steps marked in flight are reported as two, not as one"
  # S19 §17-6 — a DECLARED number that contradicts the computed one is REFUSED, not printed
  cp -R "$_FB/b" "$_FB/d"
  printf '# fabnum\n\n**Status:** draft\n\n```compass-artefact-data\n{ "invariants.total": 99 }\n```\n' > "$_FB/d/progress.md"
  node "$_GEN" "$_FB/d" brief --out "$_FB/bad.html" >/dev/null 2>&1
  chk "$([ "$?" -ne 0 ] && echo 1 || echo 0)" "1" "v0.32 S19 (§17-6): a declared number contradicting the computed one is REFUSED (it used to win silently)"
  # ...and an AGREEING declared number still renders, so the refusal is not a wall
  cp -R "$_FB/b" "$_FB/e"
  printf '# fabnum\n\n**Status:** draft\n\n```compass-artefact-data\n{ "invariants.total": 2 }\n```\n' > "$_FB/e/progress.md"
  node "$_GEN" "$_FB/e" brief --out "$_FB/ok.html" >/dev/null 2>&1
  chk "$?" "0" "v0.32 S19 (§17-6): ...and a declared number that AGREES still renders (the refusal is not a wall)"
  rm -rf "$_FB"
else
  chk "1" "1" "v0.32 S19 + S31: N/A — no node or no gen.mjs on this tree"
fi

# ── v0.32 S31b: every LIVE counter that reads plan checkboxes must give ONE answer ───────────
# S31 taught the plan-map parser a new marker, `- [~]`, and left `compass.sh` (9 sites) on `[ x]`.
# Same plan.md, two different totals — the self-contradiction §17-6 is about, introduced by the fix
# for a different fabricated number. Found by an independent reviewer.
# It named a THIRD counter, gen.mjs's `cockpit()`. That one is UNREACHABLE: `VIEWS` does not list
# `cockpit`, and gen.mjs validates against VIEWS before dispatching, so the `else` branch holding it
# can never run. Widened anyway (dead code that disagrees is still a trap for the next reader) and
# recorded as a §17 candidate rather than asserted here — a check on unreachable code proves nothing.
if [ -f "$_GEN" ] && command -v node >/dev/null 2>&1; then
  _TL="$(mktemp -d)"
  printf '# Plan\n- [x] **S1** done — VERIFY: ran.\n- [~] **S2** in flight — VERIFY: pending.\n- [ ] **S3** not started — VERIFY: pending.\n' > "$_TL/plan.md"
  printf '# t\n\n**Status:** build\n**Stage:** build\n**Next:** S2\n' > "$_TL/progress.md"
  printf '# Contract — t\n\nfacets: library\n\n## Goal & scope\n**Goal:** x.\n\n### NOW\n1. one\n' > "$_TL/contract.md"
  _c1="$(bash "$SH" status "$_TL" 2>/dev/null | sed -n 's/^Steps:  *//p' | sed -E 's#^([0-9]+)/([0-9]+).*#\1 \2#')"
  node "$_GEN" "$_TL" plan-map --out "$_TL/pm.html" >/dev/null 2>&1
  _c2="$(sed -e 's/<[^>]*>//g' -e 's/&nbsp;/ /g' "$_TL/pm.html" 2>/dev/null | grep -oE '[0-9]+ steps +· +[0-9]+ done' | head -1 | sed -E 's#^([0-9]+) steps +· +([0-9]+) done#\2 \1#')"
  chk "$_c1" "1 3" "v0.32 S31b: compass.sh counts a '[~]' step in the TOTAL (1 done of 3)"
  chk "$_c2" "1 3" "v0.32 S31b: ...and gen.mjs's plan-map gives the SAME answer for the same plan.md"
  chk "$(printf '%s\n%s\n' "$_c1" "$_c2" | sort -u | grep -c .)" "1" "v0.32 S31b: two independent readers of one plan.md return ONE answer"
  # and the marker must not be counted as DONE — a step in flight is not a finished step
  chk "$(sed -e 's/<[^>]*>//g' -e 's/&nbsp;/ /g' "$_TL/pm.html" 2>/dev/null | grep -oE '[0-9]+ running' | head -1)" "1 running" "v0.32 S31b: a '[~]' step counts as RUNNING, never as done"
  rm -rf "$_TL"
fi

# ── v0.32 S4: the gold's own check — can a reader still REACH what was destroyed? ────────────
# Counting units says how much is cut. It cannot say whether a reader can get to it, and that is
# what the gold grades. Each destroying return hands over the TEXT it dropped; the check looks for
# that text in the page's REACHABLE text — never for a marker, which is how three published figures
# went wrong. Runs against the TRACKED corpus so a clean clone tests it for real.
_RAC="$PLUGIN_ROOT/scripts/reachable-argument-check.sh"
_RCORP="$PLUGIN_ROOT/scripts/fixtures/corpus"
if [ -f "$_RAC" ] && command -v node >/dev/null 2>&1; then
  _rout="$(bash "$_RAC" "$RR22" --corpus "$_RCORP" 2>&1)"
  chk "$(printf '%s' "$_rout" | sed -nE 's/^[[:space:]]*dropped units[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)" "172" "v0.32 S4: the check sees every dropped unit the instrument counts (172 on the tracked corpus)"
  # v0.32 S4b (M-4). ONLY `dropped units` was pinned, so `probed`, `UNREACHABLE` and
  # `SOURCE UNREACHABLE` were pinned to no value at all: an independent reviewer removed one call
  # site's dropped text (probes 2,215 -> 1,335, unreachable 2,181 -> 1,323), shortened the probe cap
  # and raised SRC_MIN, and the suite stayed green through all three. Every figure is pinned now.
  chk "$(printf '%s' "$_rout" | sed -nE 's/^[[:space:]]*\.\.\.probed[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)" "152" "v0.32 S4b: exactly 152 of those units are probed (a call site quietly dropping its text moves this)"
  # v0.32.0, from an independent review: the three buckets must ADD UP to the population. They did
  # not — the not-rendered units were subtracted from `probed` and then described a SECOND time as
  # "NOT PROBED: shorter than 12 characters", so the printed columns summed to 190 out of 172.
  # Pinning each bucket AND the total is what stops a unit being quietly moved between them.
  chk "$(printf '%s' "$_rout" | sed -nE 's/^[[:space:]]*\.\.\.NOT PROBED[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)" "2" "v0.32 S4b: exactly 2 units are genuinely too short to probe"
  chk "$(printf '%s' "$_rout" | sed -nE 's/^[[:space:]]*\.\.\.NOT RENDERED[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)" "18" "v0.32 S4b: exactly 18 units belong to a row the page never showed"
  chk "$(( $(printf '%s' "$_rout" | sed -nE 's/^[[:space:]]*\.\.\.probed[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1) + 2 + 18 ))" "$(printf '%s' "$_rout" | sed -nE 's/^[[:space:]]*dropped units[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)" "v0.32 S4b: probed + too-short + not-rendered EQUALS the dropped-unit population — a bucket cannot absorb a unit without this going red"
  chk "$(printf '%s' "$_rout" | sed -nE 's/^[[:space:]]*UNREACHABLE[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)" "0" "v0.32 S4b: exactly 0 are unreachable on the tracked corpus"
  chk "$(printf '%s' "$_rout" | sed -nE 's/^[[:space:]]*SOURCE LINES[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)" "108" "v0.32 S4b: the SOURCE denominator is exactly 108 lines (raising SRC_MIN to hide lines moves this)"
  chk "$(printf '%s' "$_rout" | sed -nE 's/^[[:space:]]*SOURCE UNREACHABLE[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)" "64" "v0.32 S4b: exactly 64 source lines cannot be found on any page — this ROSE from 51 when cross-document transfers stopped, and the rise is the honest reading: those lines were only ever \"findable\" because they had been dumped into an unrelated row\'s disclosure. Rendering them under a row that continues them is follow-up work, not a reason to put the dump back"
  _runr="$(printf '%s' "$_rout" | sed -nE 's/^[[:space:]]*UNREACHABLE[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)"
  # the verdict must be readable from the PRINTED figure, never from an exit code alone (SELF-4)
  # It says FAIL again, and that is the honest state. The PASS this asserted was bought by two
  # cancelling bugs an independent reviewer found — glued block elements hiding a whole event in an
  # exclusion bucket, and a generator-supplied `discarded` flag the check believed. Both are gone.
  # The figure was 8 for as long as `firstNonEmpty` moved a discarded candidate's TEXT to the row
  # that renders it but left the destroying EVENT naming the candidate. It is now 0, so the honest
  # tree says PASS, and the FAIL wording is exercised where the failing trees are — the twelve
  # cheated trees in `behaviour-corpus-check.sh`, each of which parses this same verdict line.
  chk "$(printf '%s' "$_rout" | grep -c 'COMPASS-GATE: PASS')" "1" "v0.32 S7f: ...and it says PASS in words once no dropped unit is unreachable"
  # ERR, never a confident zero, when there is nothing to measure
  bash "$_RAC" "$RR22" --corpus "$RR22/no-such-corpus-xyz" >/dev/null 2>&1
  chk "$?" "3" "v0.32 S4: an ABSENT corpus ERRs (exit 3) — a corpus with no pages is not a clean result"
  chk "$(bash "$_RAC" "$RR22" --corpus "$RR22/no-such-corpus-xyz" 2>&1 | grep -c 'COMPASS-GATE: ERR')" "1" "v0.32 S4: ...and says ERR in words"
  # contract section 12: the kill switch may silence a REPORTING gate, never the MEASUREMENT
  _roff="$(COMPASS_V32_STRICT=0 bash "$_RAC" "$RR22" --corpus "$_RCORP" 2>&1 | sed -nE 's/^[[:space:]]*UNREACHABLE[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' | head -1)"
  chk "$_roff" "$_runr" "v0.32 S4: COMPASS_V32_STRICT=0 does not change the figure — the flag cannot silence the measurement"
  # and the flag is not read at all, so it CANNOT
  chk "$(grep -c 'process.env.COMPASS_V32_STRICT' "$PLUGIN_ROOT/scripts/reachable-argument.mjs" || true)" "0" "v0.32 S4: ...because the measurement never reads that variable"
  # weak evidence is reported apart from strong: text merely present elsewhere is NOT disclosure
  chk "$(printf '%s' "$_rout" | grep -c 'each in a control holding THAT row.s remainder')" "1" "v0.32 S4b: only a control holding THAT row's remainder counts as reachable — text merely present elsewhere does not"
  chk "$(printf '%s' "$_rout" | grep -c 'UNBINDABLE PATHS')" "1" "v0.32 S6b: the unbindable count is ALWAYS printed, at zero as well — an absent line is not evidence"
  chk "$(printf '%s' "$_rout" | sed -nE 's/^ *UNREACHABLE \(bindable\) *: *([0-9]+).*/\1/p' | head -1)" "0" "v0.32 S7f: exactly 0 remainders remain unreachable on the tracked corpus — an EARLIER zero was bought by two cancelling bugs, so this one is pinned beside the probed population (162) that makes it mean something"
  # v0.32 S7b (C-3), from the independent review of S6. `UNREACHABLE (bindable)` filters by SITE, so
  # ONE blank shown half poisons a whole path OUT of the figure — and with all three poisoned the
  # POSITIVE CONTROL still printed "an honest fix reaches ZERO" on a tree with no disclosure at all.
  # A conjunction whose SET the thing under test chooses proves nothing. So the CREDIT side is
  # pinned too, and so is how many paths are in scope.
  chk "$(printf '%s' "$_rout" | sed -nE 's/^ *REACHABLE *: *([0-9]+).*/\1/p' | head -1)" "152" "v0.32 S7b: exactly 152 remainders are CREDITED as reachable — poisoning a path out of scope moves this"
  chk "$(printf '%s' "$_rout" | sed -nE 's/^ *UNBINDABLE PATHS *: *([0-9]+) of ([0-9]+).*/\1 \2/p' | head -1)" "0 13" "v0.32 S7b: ZERO of 13 paths are unbindable — every destroying path now carries its shown half"
  # units too short to probe are reported as UNMEASURED, never folded into either column
  chk "$(printf '%s' "$_rout" | grep -c 'NOT PROBED')" "1" "v0.32 S4: units too short to probe are reported as UNMEASURED, not silently dropped"
else
  chk "1" "1" "v0.32 S4: N/A — no node or no reachable-argument-check.sh on this tree"
fi

# ── v0.32 S5: the behaviour corpus — five ways to look clean without fixing anything ─────────
# Each entry is APPLIED to a throwaway copy and the named check re-run against it. The previous
# corpus in this repo pinned a COUNT, so swapping real entries for trivial ones scored the same;
# this one pins each entry's IDENTITY and, more importantly, RUNS it.
# Three of the five defeated my own check the first time it was run. That is what the corpus is for.
# v0.32 S5b — PERF. With eight entries the full run costs 11s, and re-rendering the corpus once per
# cheat is inherent to what it proves. Together with everything else this build added, the suite hit
# 53.4s against a 25.2s baseline and a 50.2s ceiling — a BREACH of this build's own budget. So the
# full run joins defeat-corpus-check, declared-check, proven-numbers and redfirst-count as a
# standalone RELEASE gate, and what runs here is the part that is cheap: the corpus's shape, and
# whether its identity pinning has teeth. Set COMPASS_BEHAVIOUR_FULL=1 to run it here anyway.
_BCC="$PLUGIN_ROOT/scripts/behaviour-corpus-check.sh"
if [ -f "$_BCC" ] && command -v node >/dev/null 2>&1 && [ -n "${COMPASS_BEHAVIOUR_FULL:-}" ]; then
  _bout="$(bash "$_BCC" "$RR22" 2>&1)"
  # The corpus is ADD-ONLY, so this floor RISES and never falls. It went 5 -> 8: two cheats an
  # independent reviewer found and wrote (a <template> stash, and exhausting the old stripper's
  # 5,000-iteration budget with decoys), plus the POSITIVE control that asks the question v0.31
  # forgot — can an honest fix actually reach the target?
  chk "$([ "$(printf '%s' "$_bout" | sed -nE 's/^behaviour-corpus: ([0-9]+) entries.*/\1/p' | head -1)" -ge 8 ] && echo 1 || echo 0)" "1" "v0.32 S5: the behaviour corpus holds at least 8 entries — five from contract section 9, two found by review, and the honest-fix control"
  chk "$(printf '%s' "$_bout" | sed -nE 's/^behaviour-corpus: [0-9]+ entries, ([0-9]+) failing.*/\1/p' | head -1)" "0" "v0.32 S5: every cheat is DEFEATED — none lowers the figure without a row being fixed"
  # The KNOWN-OPEN count is PINNED, not floored. `open=` exists so one measured, argued, named
  # defect can ship (C-1, on Rishi's call 2026-08-21) — and pinning it at exactly one is what stops
  # it becoming the way every future cheat gets retired. A second one is a red diff, deliberately.
  chk "$(printf '%s' "$_bout" | sed -nE 's/^behaviour-corpus: [0-9]+ entries, [0-9]+ failing, ([0-9]+) known-open.*/\1/p' | head -1)" "1" "v0.32 S5: EXACTLY ONE known-open defect (C-1) — a second would be a new decision, not a habit"
  chk "$(printf '%s' "$_bout" | grep -c 'OPEN shared-shown-half')" "1" "v0.32 S5: ...and it is named in the run's own output, not only in a commit message"
  for _c in rename-marker hide-rows empty-control one-control-per-page css-clip template-stash clip-guard-exhaustion; do
    chk "$(printf '%s' "$_bout" | grep -c "ok   $_c - defeated")" "1" "v0.32 S5: cheat '$_c' is applied and defeated (not merely stored)"
    chk "$([ -s "$PLUGIN_ROOT/scripts/fixtures/defeat-behaviour/$_c/REPRODUCTION.md" ] && echo 1 || echo 0)" "1" "v0.32 S5: ...and carries the reproduction that earned its place"
  done
  # identity, never a count: the previous corpus's own recorded defeat
  chk "$([ -s "$PLUGIN_ROOT/scripts/behaviour-corpus-manifest.txt" ] && echo 1 || echo 0)" "1" "v0.32 S5: the corpus is pinned by a per-entry checksum, so hollowing one out is a visible diff"
  # a zero baseline would make every 'must not fall' rule pass for free — both baselines are guarded
  chk "$(printf '%s' "$_bout" | grep -c 'baseline unreachable = ')" "1" "v0.32 S5: the run states the baseline it judged against, so a vacuous pass is visible"
  # THE POSITIVE CONTROL. Every other entry asks "can this be cheated?". This asks the question
  # v0.31 shipped without asking: can an HONEST implementation reach the target at all? When an
  # independent reviewer first measured it the answer was NO — baseline 159, honest fix 141, and a
  # <template> cheat 124, so the cheat beat the fix and exit 0 was unreachable by any honest route.
  chk "$(printf '%s' "$_bout" | grep -c 'an honest fix reaches ZERO')" "1" "v0.32 S5b: an HONEST fix reaches ZERO, so the gold is satisfiable and not a wall (the v0.31 lesson, asserted on every run)"
elif [ -f "$_BCC" ]; then
  # the cheap half, and it is not decorative: it is the two properties an independent reviewer
  # broke — entries could be DELETED with the run still green, and the manifest could be removed to
  # disable identity pinning altogether.
  _BD="$PLUGIN_ROOT/scripts/fixtures/defeat-behaviour"
  _BM="$PLUGIN_ROOT/scripts/behaviour-corpus-manifest.txt"
  chk "$([ "$(find "$_BD" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" -ge 19 ] && echo 1 || echo 0)" "1" "v0.32 S5: the behaviour corpus holds at least 19 entries (ADD-ONLY, so this floor rises and never falls)"
  _bmiss=0
  for _e in "$_BD"/*/; do
    # a CHEAT ships apply.sh (it patches the generator); a BEHAVIOUR entry ships case.sh (it builds
    # a fixture and runs a gate). Both ship their reproduction and both are pinned.
    _r=apply.sh; grep -q '^kind=behaviour' "$_e/EXPECTED" 2>/dev/null && _r=case.sh
    for _f in "$_r" EXPECTED REPRODUCTION.md; do [ -s "$_e/$_f" ] || _bmiss=$((_bmiss+1)); done
    grep -q "^$(basename "$_e")  " "$_BM" 2>/dev/null || _bmiss=$((_bmiss+1))
  done
  chk "$_bmiss" "0" "v0.32 S5: every entry carries its reproduction AND is pinned in the manifest"
  # deleting an entry must FAIL, and removing the manifest must ERR — both were possible.
  _bt="$(mktemp -d)"; mkdir -p "$_bt/plugins/compass/scripts"
  cp -R "$PLUGIN_ROOT/scripts/." "$_bt/plugins/compass/scripts/" 2>/dev/null
  rm -rf "$_bt/plugins/compass/scripts/fixtures/defeat-behaviour/css-clip"
  bash "$_bt/plugins/compass/scripts/behaviour-corpus-check.sh" "$_bt" >/dev/null 2>&1
  chk "$([ "$?" -ne 0 ] && echo 1 || echo 0)" "1" "v0.32 S5b: DELETING an entry fails the corpus — 'a removed slug fails' used to be simply untrue"
  rm -f "$_bt/plugins/compass/scripts/behaviour-corpus-manifest.txt"
  bash "$_bt/plugins/compass/scripts/behaviour-corpus-check.sh" "$_bt" >/dev/null 2>&1
  chk "$([ "$?" -ne 0 ] && echo 1 || echo 0)" "1" "v0.32 S5b: removing the MANIFEST ERRs — it used to silently disable all identity pinning"
  rm -rf "$_bt"
  # EVERY entry must assert that its patch actually landed. rename-marker was the one that did not,
  # so against a tree whose markers had moved it printed "renamed 0 marker occurrences", exited 0,
  # and the runner reported "defeated" — an entry proving nothing while looking green.
  _bna=0
  for _e in "$_BD"/*/; do
    # `kind=control` patches NOTHING by design (honest-fix-reaches-zero), and `kind=behaviour`
    # patches nothing either — it builds a fixture and runs a gate, and asserts BOTH directions
    # inside its own case.sh. Only a CHEAT has a patch that could silently fail to land.
    grep -qE '^kind=(control|behaviour)' "$_e/EXPECTED" 2>/dev/null && continue
    grep -qE '^assert |assert s\.count|assert n > 0' "$_e/apply.sh" 2>/dev/null || _bna=$((_bna+1))
  done
  chk "$_bna" "0" "v0.32 S5b: every cheat ASSERTS that its patch landed, so none can silently no-op and still report 'defeated'"
else
  chk "1" "1" "v0.32 S5: N/A — no node or no behaviour-corpus-check.sh on this tree"
fi

# ── v0.32 S20: every recorded RED is RE-RUN, not counted ─────────────────────────────────────
# `redfirst-check` asks whether a record was machine-produced. It cannot ask whether the record is
# still TRUE — a fix can be reverted and the row sits there reading like evidence. So each
# reproduction is a tracked file with a MUTATION that puts the defect back and an ASSERT that must
# pass on a healthy tree and FAIL on the mutated one.
#
# The full re-run costs ~16s and lives OUTSIDE this suite, beside defeat-corpus-check,
# declared-check and proven-numbers, which are standalone for the same reason. Adding it here would
# take the suite to ~56s against a baseline of 25.2s and a bound of +25s — it would BREACH this
# build's own perf budget, and quietly blowing your own budget to look thorough is the sin this
# build is named for. What IS asserted here is the registry's SHAPE, which is cheap.
_RFC="$PLUGIN_ROOT/scripts/redfirst-count.sh"
_RFR="$PLUGIN_ROOT/scripts/fixtures/redfirst/repro"
if [ -f "$_RFC" ] && [ -d "$_RFR" ]; then
  _nrep="$(find "$_RFR" -name '*.sh' -type f | wc -l | tr -d ' ')"
  chk "$([ "$_nrep" -ge 4 ] && echo 1 || echo 0)" "1" "v0.32 S20: the red-first registry is TRACKED and non-empty ($_nrep reproductions), so a clean clone can re-run them"
  _rbad=0
  for _rf in "$_RFR"/*.sh; do
    grep -q '^repro_mutate()' "$_rf" || _rbad=$((_rbad+1))
    grep -q '^repro_assert()' "$_rf" || _rbad=$((_rbad+1))
    grep -q '^REPRO_WHAT=' "$_rf" || _rbad=$((_rbad+1))
  done
  chk "$_rbad" "0" "v0.32 S20: every reproduction defines a mutation, an assert and what it records"
  # a registry that cannot fail is the defect this step exists to remove: prove the runner refuses
  # a reproduction whose assert passes even with the defect put back.
  _rt="$(mktemp -d)"; mkdir -p "$_rt/plugins/compass/scripts/fixtures/redfirst/repro"
  cp "$_RFC" "$_rt/plugins/compass/scripts/"
  printf 'REPRO_ID="FAKE"\nREPRO_WHAT="a reproduction that cannot fail"\nrepro_mutate() { : ; }\nrepro_assert() { return 0; }\n' > "$_rt/plugins/compass/scripts/fixtures/redfirst/repro/fake.sh"
  bash "$_rt/plugins/compass/scripts/redfirst-count.sh" "$_rt" >/dev/null 2>&1
  chk "$([ "$?" -ne 0 ] && echo 1 || echo 0)" "1" "v0.32 S20: a reproduction that stays GREEN with the defect put back is REFUSED — a record that cannot fail is not evidence"
  rm -rf "$_rt"
else
  chk "1" "1" "v0.32 S20: N/A — no redfirst-count.sh on this tree"
fi

# ── v0.32 S32: contract §4's evidence-file shape, which no step covered at all ────────────────
# A schema nothing validates is a paragraph. §4's own rule is the load-bearing one: a file missing
# `nonce` or `target-sha` is treated as ABSENT, never as a pass — so the round fails for a missing
# stream instead of a malformed file counting as a review that happened.
_ESC="$PLUGIN_ROOT/scripts/evidence-shape-check.sh"
_EFX="$PLUGIN_ROOT/scripts/fixtures/evidence"
if [ -f "$_ESC" ] && [ -d "$_EFX" ]; then
  bash "$_ESC" "$_EFX/good" --expect-streams security,perf >/dev/null 2>&1
  chk "$?" "0" "v0.32 S32: a well-formed evidence set passes and every declared stream resolves"
  bash "$_ESC" "$_EFX/no-target-sha" --expect-streams security,perf >/dev/null 2>&1
  chk "$([ "$?" -ne 0 ] && echo 1 || echo 0)" "1" "v0.32 S32: a file missing 'target-sha' makes the ROUND FAIL for that stream (§4: absent, not a pass)"
  chk "$(bash "$_ESC" "$_EFX/no-target-sha" 2>&1 | grep -c 'treated as ABSENT, not as a pass')" "1" "v0.32 S32: ...and it says ABSENT in words, not merely in an exit code"
  bash "$_ESC" "$_EFX/malformed" --expect-streams security >/dev/null 2>&1
  chk "$([ "$?" -ne 0 ] && echo 1 || echo 0)" "1" "v0.32 S32: a verdict outside CLEAN|FINDINGS|COULD-NOT-VERIFY is malformed, not accepted"
  # a short nonce is malformed: §4 requires 16+ characters
  _et="$(mktemp -d)"; sed -e 's/^- nonce: .*/- nonce: short/' "$_EFX/good/review-build-r1-perf.md" > "$_et/x.md"
  bash "$_ESC" "$_et" >/dev/null 2>&1
  chk "$([ "$?" -ne 0 ] && echo 1 || echo 0)" "1" "v0.32 S32: a nonce shorter than the 16 characters §4 requires is malformed"
  rm -rf "$_et"
  # and an EMPTY agents dir is not a pass either — zero files means zero streams reviewed
  _ee="$(mktemp -d)"; bash "$_ESC" "$_ee" --expect-streams security >/dev/null 2>&1
  chk "$([ "$?" -ne 0 ] && echo 1 || echo 0)" "1" "v0.32 S32: an EMPTY agents directory fails for every expected stream"
  rm -rf "$_ee"
else
  chk "1" "1" "v0.32 S32: N/A — no evidence-shape-check.sh on this tree"
fi

# ── v0.32 S4b (M-3): each of the check's DEFENCES, tested on its own ─────────────────────────
# An independent reviewer gutted four of them one at a time — CLIP_PROPS down to line-clamp only,
# the hidden/aria-hidden branch deleted, dropSubtree's unclosed branch made to fail open, nesting
# depth ignored — and the suite stayed green through every one. Only `-webkit-line-clamp` was
# tested anywhere. These exercise the reachability function directly, one hiding technique each.
_RAM="$PLUGIN_ROOT/scripts/reachable-argument.mjs"
if [ -f "$_RAM" ] && command -v node >/dev/null 2>&1; then
  _hid(){ node --input-type=module -e '
    const m = await import(process.argv[1]);
  ' >/dev/null 2>&1; }
  # the module runs its own main on import, so the defences are exercised through a tiny harness
  # that re-implements nothing: it renders a page-shaped string and asks the real check to score it.
  _probe="thisisaverydistinctiveremaindersentence"
  _try(){ # $1 = html body holding the probe · echoes 1 if the text is REACHABLE
    COMPASS_RA_SELFTEST="$1" COMPASS_RA_PROBE="$_probe" node -e '
      const fs=require("fs");
      const src=fs.readFileSync(process.env.RAM,"utf8");
      const body=src.slice(src.indexOf("const CLIP_PROPS ="), src.indexOf("// Which disclosure control"));
      const fn=new Function(body+"; return { reachableText, clippedClasses };")();
      const t=fn.reachableText(process.env.COMPASS_RA_SELFTEST);
      process.stdout.write(t.includes(process.env.COMPASS_RA_PROBE)?"1":"0");
    ' 2>/dev/null
  }
  RAM="$_RAM" export RAM
  chk "$(RAM="$_RAM" _try "<div><p>$_probe</p></div>")" "1" "v0.32 S4b (M-3): plain visible text IS reachable (the control case — without it every check below passes for free)"
  chk "$(RAM="$_RAM" _try "<div style=\"display:none\"><p>$_probe</p></div>")" "0" "v0.32 S4b (M-3): display:none is not reachable"
  chk "$(RAM="$_RAM" _try "<div style=\"visibility:hidden\"><p>$_probe</p></div>")" "0" "v0.32 S4b (M-3): visibility:hidden is not reachable"
  chk "$(RAM="$_RAM" _try "<div style=\"font-size:0\"><p>$_probe</p></div>")" "0" "v0.32 S4b (M-3): font-size:0 is not reachable"
  chk "$(RAM="$_RAM" _try "<div style=\"color:transparent\"><p>$_probe</p></div>")" "0" "v0.32 S4b (M-3): color:transparent is not reachable"
  chk "$(RAM="$_RAM" _try "<div style=\"position:absolute;left:-9999px\"><p>$_probe</p></div>")" "0" "v0.32 S4b (M-3): parked off-screen at left:-9999px is not reachable"
  chk "$(RAM="$_RAM" _try "<div hidden><p>$_probe</p></div>")" "0" "v0.32 S4b (M-3): the bare 'hidden' attribute is not reachable"
  chk "$(RAM="$_RAM" _try "<div aria-hidden=\"true\"><p>$_probe</p></div>")" "0" "v0.32 S4b (M-3): aria-hidden=true is not reachable"
  chk "$(RAM="$_RAM" _try "<template><p>$_probe</p></template>")" "0" "v0.32 S4b (M-3): a <template> is inert in every browser and is not reachable"
  chk "$(RAM="$_RAM" _try "<style>.k{display:none}</style><div class=\"k\"><p>$_probe</p></div>")" "0" "v0.32 S4b (M-3): clipping set by a CLASS, not inline, is not reachable"
  chk "$(RAM="$_RAM" _try "<style>@media all{.k{display:none}}</style><div class=\"k\"><p>$_probe</p></div>")" "0" "v0.32 S4b (M-3): ...including a class clipped inside an @media block"
  chk "$(RAM="$_RAM" _try "<style>[data-x] .k{display:none}</style><div class=\"k\"><p>$_probe</p></div>")" "0" "v0.32 S4b (M-3): ...and one reached by an attribute selector"
  chk "$(RAM="$_RAM" _try "<div style=\"display:none\"><div><div><p>$_probe</p></div></div></div>")" "0" "v0.32 S4b (M-3): nesting is counted, so a clipped ancestor is not escaped by depth"
  chk "$(RAM="$_RAM" _try "<div style=\"display:none\"><p>$_probe</p>")" "0" "v0.32 S4b (M-3): an UNCLOSED clipped element fails CLOSED — text after it is not credited"
  chk "$(RAM="$_RAM" _try "<div style=\"display:none\"><img hidden><p>$_probe</p></div>")" "0" "v0.32 S4b (M-3): a void element inside a clipped subtree does not end it"
  # printf, not a concat loop: building this string by appending cost 5.3 SECONDS of the suite's
  # own budget. Same 142,800 characters, 0.01s. A test that blows the perf budget it is meant to
  # protect is a defect in its own right.
  _decoys="$(printf '<i style="display:none"></i>%.0s' $(seq 1 5100))"
  chk "$(RAM="$_RAM" _try "$_decoys<div style=\"display:none\"><p>$_probe</p></div>")" "0" "v0.32 S4b (C-1): 5,100 clipped decoys do NOT exhaust the stripper — it has no budget to exhaust"
else
  chk "1" "1" "v0.32 S4b: N/A — no node or no reachable-argument.mjs"
fi

# ── v0.32 S7c: the disclosure control must not land in the PILL column ───────────────────────
# A LAYOUT regression an independent reviewer measured in a real browser on 30 of 120 pages.
# `ul.pl li` is a two-column grid (pill then text) and S6 made the control its THIRD child, so it
# auto-placed into row 2 COLUMN 1 — 127px wide inside a 921px text column — turning a sentence into
# a seven-line ribbon beside an ~890px empty pill bar, and adding 158px of horizontal page scroll
# once the controls were opened.
# This suite is deliberately Chrome-free (see the "durable gold, no Chrome" checks above), so what
# is asserted here is the STRUCTURE that produced it: the grid has exactly two columns, so a third
# child wraps, and the control is explicitly placed in column 2. The browser numbers are in the
# receipt: column 2, width 1012px (was 127px), horizontal overflow with every control open 0px
# (was 158px).
_GEN2="$PLUGIN_ROOT/skills/compass-visual/gen.mjs"
if [ -f "$_GEN2" ]; then
  chk "$(grep -c 'ul\.pl li{[^}]*grid-template-columns:auto 1fr' "$_GEN2" || true)" "1" "v0.32 S7c: the pill list is still a TWO-column grid, so a third child would wrap into the pill column"
  chk "$(grep -c 'ul\.pl li > \.rest{grid-column:2}' "$_GEN2" || true)" "1" "v0.32 S7c: ...so the control is explicitly placed in column 2, under the text it discloses"
  chk "$(grep -c 'rest-body{overflow-wrap:anywhere' "$_GEN2" || true)" "1" "v0.32 S7c: a long unbroken token in a remainder wraps instead of widening the page by 158px"
  # and the control must NOT be clipped to achieve that — this build's own check would call it unreachable
  chk "$(grep -cE '\.rest[^{]*\{[^}]*(max-height:0|overflow:hidden|-webkit-line-clamp|text-overflow:ellipsis)' "$_GEN2" || true)" "0" "v0.32 S7c: ...and the fix uses NO clipping property, which would make the text unreachable by this build's own measure"
fi

# ── v0.32 S7c: the SVG box label, which was the one call site with no generic answer ─────────
# An independent reviewer measured the claim "shorten to what fits" and it was FALSE: 255px inside a
# 210px box, clipped by the viewBox — the css-clip cheat by another route. `fieldParts` appends
# " (continues)" AFTER its cap, so a 34-character budget produced a 46-character string. And the
# whole diagram emitted ONE control for ALL its boxes, which is the aggregation §9 cheat 4 names.
# Measured across all 120 live pages: longest sub-label 68 -> 34, labels over the cap 27 -> 0.
# v0.32.0 M-1 — all three of these assertions were VACUOUS. They ran over the tracked corpus, whose
# six contracts carry only short mermaid node labels, so the diagram emitted ZERO sub-labels: the
# first scored 0 over 0, and the other two compared 0 against 0. They would have passed against a
# generator with the sub-label code deleted. `fixtures/svg-labels/long-boxes` exists to give them
# something to measure — five sub-labels, four of them shortened — and it is deliberately NOT in
# the tracked corpus, because adding a seventh build there would move every pinned reachability
# figure. The VACUITY GUARD below is the part that matters: it fails if the population is ever
# empty again, so this class of defect cannot come back quietly.
if [ -f "$_GEN2" ] && command -v node >/dev/null 2>&1; then
  _sv="$(mktemp -d)"
  for _d in "$PLUGIN_ROOT/scripts/fixtures/corpus"/*/ "$PLUGIN_ROOT/scripts/fixtures/svg-labels"/*/; do
    [ -f "$_d/contract.md" ] || continue
    node "$_GEN2" "$_d" brief --out "$_sv/$(basename "$_d").html" >/dev/null 2>&1 || true
  done
  # VACUITY GUARD, before any of the three. An assertion over an empty set is not a passing
  # assertion, it is an absent one.
  chk "$(node -e '
    const fs=require("fs"), path=require("path");
    let subs=0, rows=0;
    for (const f of fs.readdirSync(process.argv[1])) {
      const s=fs.readFileSync(path.join(process.argv[1],f),"utf8");
      subs += (s.match(/<text[^>]*font-size="11"[^>]*>/g)||[]).length;
      rows += (s.match(/class="svg-label-row"/g)||[]).length;
    }
    process.stdout.write(subs >= 4 && rows >= 4 ? "ok" : `EMPTY(subs=${subs},rows=${rows})`);
  ' "$_sv" 2>/dev/null)" "ok" "v0.32 M-1: the three SVG sub-label assertions below have a NON-EMPTY population to measure — they scored 0 over 0 on the tracked corpus alone and would have passed with the code deleted"
  chk "$(node -e '
    const fs=require("fs"), path=require("path");
    let over=0, n=0;
    for (const f of fs.readdirSync(process.argv[1])) {
      const s=fs.readFileSync(path.join(process.argv[1],f),"utf8");
      for (const m of s.matchAll(/<text[^>]*font-size="11"[^>]*>([\s\S]*?)<\/text>/g)) {
        const t=m[1].replace(/<[^>]+>/g,"").replace(/&[a-z]+;|&#\d+;/g," ");
        n++; if (t.length > 34) over++;
      }
    }
    process.stdout.write(String(over));
  ' "$_sv" 2>/dev/null)" "0" "v0.32 S7c: no SVG box sub-label exceeds the width it is budgeted for (68 chars -> 34, and it is CLIPPED BY THE VIEWBOX above that)"
  # One control per box, counted on the RENDERED page: each row carries exactly one control with
  # its own summary, so the two counts must be equal. They were 1 and N before — one box's worth of
  # summary over every box's text.
  chk "$(node -e '
    const fs=require("fs"), path=require("path");
    let bad=0;
    for (const f of fs.readdirSync(process.argv[1])) {
      const s=fs.readFileSync(path.join(process.argv[1],f),"utf8");
      const rows=(s.match(/class="svg-label-row"/g)||[]).length;   // the CLASS ATTRIBUTE, not the CSS rule
      const ctrls=(s.match(/Show this box in full/g)||[]).length;
      if (rows !== ctrls) bad++;
    }
    process.stdout.write(String(bad));
  ' "$_sv" 2>/dev/null)" "0" "v0.32 S7c: the diagram emits ONE control PER BOX — it emitted one for ALL boxes, which is §9 cheat 4"
  chk "$(node -e '
    const fs=require("fs"), path=require("path");
    let bad=0;
    for (const f of fs.readdirSync(process.argv[1])) {
      const s=fs.readFileSync(path.join(process.argv[1],f),"utf8");
      for (const m of s.matchAll(/<svg[\s\S]*?<\/svg>/g)) if (/<details/.test(m[0])) bad++;
    }
    process.stdout.write(String(bad));
  ' "$_sv" 2>/dev/null)" "0" "v0.32 S7c: and NO control sits inside an <svg>, where it would be illegal"
  rm -rf "$_sv"
fi

# ── v0.32 S10: THE STREAM LIST IS THE DENOMINATOR ────────────────────────────────────────────
# Measured before this gate existed: 31 build folders, 20 receipts with a checked "all streams run"
# line, ONE folder with an agents/ directory. The denominator was the receipt's claim about itself.
_CS="$PLUGIN_ROOT/scripts/compass.sh"
for _rv in review-contract review-plan review-build; do
  _sn="$(bash "$_CS" review-streams "$_rv" 2>/dev/null | grep -c .)"
  chk "$([ "${_sn:-0}" -ge 3 ] && echo ok || echo "ONLY:${_sn:-0}")" "ok" "v0.32 S10: $_rv declares a machine-readable stream list with at least 3 ids — a denominator of 0 makes '0 of 0 streams' a pass"
done
# The counts are PINNED, not floored. A shrinking list silently lowers what the gate demands, which
# is the same defect as a receipt naming its own denominator, one level up.
chk "$(bash "$_CS" review-streams review-contract 2>/dev/null | grep -c .)" "8" "v0.32 S10: review-contract declares exactly 8 streams"
chk "$(bash "$_CS" review-streams review-plan 2>/dev/null | grep -c .)" "6" "v0.32 S10: review-plan declares exactly 6 streams"
chk "$(bash "$_CS" review-streams review-build 2>/dev/null | grep -c .)" "6" "v0.32 S10: review-build declares exactly 6 streams"
# ...and the ids are real ids, not the [A]..[F] letters contract §4 forbids as a denominator.
# An independent reviewer showed the first version of this scored 0 over 0: deleting review-build's
# list entirely made `review-streams` fail, print nothing, and the grep still counted 0 = PASS. It
# also only ever checked review-build. Now: all three skills, and the count of ids is asserted
# NON-ZERO in the same breath as the count of letters is asserted zero.
for _rv in review-contract review-plan review-build; do
  _ids="$(bash "$_CS" review-streams "$_rv" 2>/dev/null || true)"
  _tot="$(printf '%s' "$_ids" | grep -c . || true)"
  _ltr="$(printf '%s' "$_ids" | grep -cE '^[A-F]$' || true)"
  chk "$([ "${_tot:-0}" -ge 3 ] && [ "${_ltr:-0}" -eq 0 ] && echo ok || echo "tot=${_tot:-0} letters=${_ltr:-0}")" "ok" "v0.32 S10: $_rv's ids are derived NAMES over a non-empty list, never the [A]..[F] letter range contract §4 forbids"
done
# An empty list is an ERR, never an empty denominator.
_s10d="$(mktemp -d)"; mkdir -p "$_s10d/plugins/compass/scripts" "$_s10d/plugins/compass/skills/review-plan"
cp "$_CS" "$_s10d/plugins/compass/scripts/" 2>/dev/null
printf '# stub

## Streams

<!-- COMPASS-STREAMS:START -->
<!-- COMPASS-STREAMS:END -->
' > "$_s10d/plugins/compass/skills/review-plan/SKILL.md"
bash "$_s10d/plugins/compass/scripts/compass.sh" review-streams review-plan >/dev/null 2>&1
chk "$?" "1" "v0.32 S10: a review skill declaring NO streams is an ERR — 0 of 0 is never a pass"
rm -rf "$_s10d"
# GUARD-FIRST: a legacy build (no agents/ dir, no streams: receipt line) N/A-passes AND SAYS SO.
_s10l="$(mktemp -d)"; printf '# r
' > "$_s10l/receipts.md"
_s10o="$(bash "$_CS" review-evidence-gate "$_s10l" review-plan 1 2>&1)"
chk "$(printf '%s' "$_s10o" | grep -c 'COMPASS-GATE: PASS')" "1" "v0.32 S10: a build predating per-stream evidence N/A-PASSES (30 of this repo's 31 build folders do)"
chk "$(printf '%s' "$_s10o" | grep -c 'predates per-stream evidence')" "1" "v0.32 S10: ...and SAYS SO in words — a silent pass would read as 'independently verified'"
chk "$(printf '%s' "$_s10o" | grep -c 'NOT a statement that the review was independently verified')" "1" "v0.32 S10: ...and says explicitly what it is NOT claiming"
# And the claim-without-files case is refused.
mkdir -p "$_s10l/agents"
printf '# r

## RECEIPT — review-plan · t · PASS
- [x] all streams run; ledger updated
' > "$_s10l/receipts.md"
bash "$_CS" review-evidence-gate "$_s10l" review-plan 1 >/dev/null 2>&1
chk "$?" "1" "v0.32 S10: an agents/ directory with zero evidence files is REFUSED, whatever the receipt says"
rm -rf "$_s10l"

# ── v0.32 S11: INV-DISCLOSE-UNVERIFIED — the page AND the receipt ────────────────────────────
# Contract §4 deleted the claim that independence can be proven in this environment, so §8's
# "independence positively established" branch is unreachable by design and the disclosure is
# unconditional. What is checked is that nothing stays SILENT about it.
for _rv in review-contract review-plan review-build; do
  chk "$(grep -cF 'this review was NOT independently verified' "$PLUGIN_ROOT/skills/$_rv/SKILL.md" || true)" "1" "v0.32 S11: $_rv's receipt template carries the disclosure — a new review inherits it from the template, not from remembering"
done
if command -v node >/dev/null 2>&1; then
  _s11="$(mktemp -d)"; mkdir -p "$_s11/b"
  printf '# Contract — d · v1\n\nfacets: library\n\n## Goal & scope\n**Goal:** a fixture.\n\n## Acceptance & INVARIANTs\n- **INV-X:** a thing. → *assert:* it holds.\n' > "$_s11/b/contract.md"
  printf '| Issue ID | Sev | Status |\n|---|---|---|\n| A-1 | Maj | OPEN |\n' > "$_s11/b/review-ledger.md"
  node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_s11/b" review --out "$_s11/r.html" >/dev/null 2>&1
  # VACUITY GUARD first: an assertion about a page that was never written is an assertion about nothing.
  chk "$([ -s "$_s11/r.html" ] && echo ok || echo MISSING)" "ok" "v0.32 S11: ...and there IS a rendered review page to check the disclosure on"
  chk "$(grep -ci 'this review was NOT independently verified' "$_s11/r.html" || true)" "1" "v0.32 S11: the rendered review page carries the disclosure sentence"
  # It must be styled as something a reader does not skip — two cold readers walked past the muted
  # version, and moving it changed nothing, because a reader skips by style before position matters.
  chk "$(grep -c 'class="unver"' "$_s11/r.html" || true)" "1" "v0.32 S11: ...in the banner class, not as muted small print at the foot"
  _s11j="$(node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_s11/r.html" --json 2>/dev/null || true)"
  chk "$(printf '%s' "$_s11j" | grep -c '"review-disclosure"' || true)" "1" "v0.32 S11: artefact-gate RECORDS the disclosure rule passing on a review page"
  sed 's/This review was NOT independently verified\.//' "$_s11/r.html" > "$_s11/silent.html"
  _s11k="$(node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_s11/silent.html" --json 2>/dev/null || true)"
  chk "$(printf '%s' "$_s11k" | grep -c 'review-disclosure — ' || true)" "1" "v0.32 S11: ...and REFUSES a review page with the sentence stripped out"
  node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_s11/b" plan-map --out "$_s11/p.html" >/dev/null 2>&1
  _s11m="$(node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_s11/p.html" --json 2>/dev/null || true)"
  chk "$(printf '%s' "$_s11m" | grep -c '"review-disclosure-na"' || true)" "1" "v0.32 S11: a NON-review page RECORDS the rule as N/A — a silent skip is indistinguishable from a pass"
  rm -rf "$_s11"
fi
# GUARD-FIRST, re-measured after an independent reviewer showed the first figure was wrong: 30 of
# this repo's 31 build folders carry a review receipt (the earlier note said 20, which was the count
# of files containing the looser string "all streams run"). SCOPE is now the v0.30 `.compass-format`
# stamp, NOT a line in the receipt — the reviewer showed five of seven natural ways to write the
# `streams:` line took the rule out of scope, including backticks, which the skill's own template
# uses on that very line. Scope decided by the thing being judged is the defect S10 exists to fix.
_s11l="$(mktemp -d)"; printf '# r\n\n## RECEIPT — review-plan · t · PASS\n- [x] all streams run; ledger updated\n' > "$_s11l/receipts.md"
_s11o="$(bash "$PLUGIN_ROOT/scripts/compass.sh" review-disclose-gate "$_s11l" 2>&1)"
chk "$(printf '%s' "$_s11o" | grep -c 'COMPASS-GATE: PASS')" "1" "v0.32 S11: an UNSTAMPED build N/A-PASSES"
chk "$(printf '%s' "$_s11o" | grep -c 'predates the rule')" "1" "v0.32 S11: ...and SAYS SO, because a silent pass there reads as a clean bill"
# STAMPED and silent -> refused, however the streams line is written (or whether it is written).
: > "$_s11l/.compass-format"
for _w in '- [x] streams: review-plan r1 -> 6 of 6' '- [x] streams: `review-plan` r1 -> 6 of 6' '- **streams:** review-plan r1 -> 6 of 6' '- [x] all streams run; ledger updated'; do
  printf '# r\n\n## RECEIPT — review-plan · t · PASS\n%s\n' "$_w" > "$_s11l/receipts.md"
  bash "$PLUGIN_ROOT/scripts/compass.sh" review-disclose-gate "$_s11l" >/dev/null 2>&1
  chk "$?" "1" "v0.32 S11: a stamped review round that says nothing about independence is REFUSED — however its streams line is written"
done
# EACH ROUND DISCLOSES FOR ITSELF: round 1 saying it twice does not cover round 2.
printf '# r\n\n## RECEIPT — review-plan · t · PASS\n- [x] this review was NOT independently verified\n- [x] this review was NOT independently verified\n\n## RECEIPT — review-build · t · PASS\n- [x] all streams run\n' > "$_s11l/receipts.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" review-disclose-gate "$_s11l" >/dev/null 2>&1
chk "$?" "1" "v0.32 S11: one round saying it TWICE does not cover a second round that says nothing — two global counts passed this"
# ...and the honest version passes, or every refusal above is free.
printf '# r\n\n## RECEIPT — review-plan · t · PASS\n- [x] this review was NOT independently verified\n\n## RECEIPT — review-build · t · PASS\n- [x] this review was NOT independently verified\n' > "$_s11l/receipts.md"
bash "$PLUGIN_ROOT/scripts/compass.sh" review-disclose-gate "$_s11l" >/dev/null 2>&1
chk "$?" "0" "v0.32 S11: two rounds that each disclose in their OWN block PASS (the control)"
rm -rf "$_s11l"

# ── v0.32 S16: THE WAKEUP COUNTER — the only part of v0.32 whose blast radius leaves the repo ──
# It lives in the UserPromptSubmit hook, registered "matcher": "*", so once v0.32 is published it
# runs on every prompt in every project where Compass is installed. Its own test file drives the
# REAL hook with real payloads from real directories; this wires that file into the suite so it
# cannot rot unnoticed, and pins the case count so a silently-shrinking test is a visible diff.
_WCT="$PLUGIN_ROOT/scripts/wakeup-counter-test.sh"
if [ -f "$_WCT" ]; then
  _wct_out="$(bash "$_WCT" "$PLUGIN_ROOT/../.." 2>&1 || true)"
  chk "$(printf '%s' "$_wct_out" | sed -nE 's/^wakeup-counter: [0-9]+ cases, ([0-9]+) failing.*/\1/p' | head -1)" "0" "v0.32 S16: the wakeup counter passes every case in its own test file"
  chk "$(printf '%s' "$_wct_out" | sed -nE 's/^wakeup-counter: ([0-9]+) cases.*/\1/p' | head -1)" "75" "v0.32 S16: ...and there are exactly 75 of them — a shrinking test is how coverage leaves quietly. It went 16 -> 34 -> 64 -> 75 across THREE independent reviews that found 14, 11 and 13 defects the earlier cases could not see — the third being that the counter never fired in this repo at all, because every fixture path came from mktemp and had no spaces in it"
else
  chk "MISSING" "present" "v0.32 S16: wakeup-counter-test.sh is present"
fi
# The counter must sit ABOVE the matcher's fast path. Below it, a `/long-build continue` wakeup —
# which names no /compass front door — never reaches the counter, the cap never trips, and the loop
# is unbounded. That is worse than having no counter, so the ORDER is pinned, not just the presence.
_HK="$PLUGIN_ROOT/hooks/orient-hook.sh"
chk "$([ "$(grep -n 'S16 — THE WAKEUP COUNTER' "$_HK" | head -1 | cut -d: -f1)" -lt "$(grep -n 'FAST PATH: the only work done' "$_HK" | head -1 | cut -d: -f1)" ] && echo above || echo BELOW)" "above" "v0.32 S16: the counter sits ABOVE the matcher's fast path — below it, a /long-build wakeup never reaches it and the cap never trips"
# INV-ORIENT-INERT still holds: the hook must never exit non-zero, on any path.
# The "hook never exits 2" rule is NOT re-asserted here. v0.28's INV-ORIENT-DELIVERED already does
# it and catches the same planted mutation (verified in this turn: planting a real `exit 2` reddens
# both). A second assertion for the same property is noise that looks like coverage.

# ── v0.32 S17: ARM THE ENGINE, AND SAY SO WHEN YOU CANNOT ────────────────────────────────────
# Compass's own --auto stalls; the long-build skill is the engine that replaces that continuation
# and S16's counter is what BOUNDS it. Arming it is a build decision, so it lives in progress.md
# AND on the receipt. GUARD-FIRST, measured before the gate was written: 31 build folders, 4 with
# the v0.30 stamp, 0 with an engine line — and after wiring, 31 pass / 0 refused.
_ENG="$PLUGIN_ROOT/scripts/compass.sh"
_eg="$(mktemp -d)"
_mkeng() { # <dir> <progress-extra> <receipt-extra>
  mkdir -p "$1"; : > "$1/.compass-format"
  printf '# p\n\n**Status:** BUILDING\n%s\n' "$2" > "$1/progress.md"
  printf '# r\n\n## RECEIPT — build · t · PASS\n%s\n' "$3" > "$1/receipts.md"
}
_ARMED='engine: long-build · armed=yes · cap=40 · counter=.compass-wakeups'
_STAMP='- [x] engine: long-build armed, cap 40'
# CONTROL FIRST — the gate must be able to PASS, or every refusal below proves nothing.
_mkeng "$_eg/ok" "$_ARMED" "$_STAMP"
bash "$_ENG" engine-gate "$_eg/ok" >/dev/null 2>&1
chk "$?" "0" "v0.32 S17: a build that arms the engine with a cap, in progress.md AND on the receipt, PASSES (the control — without it every refusal below is free)"
# ...and the SAME fixture in auto mode passes identically: the rule is 'by default in auto AND
# human-gated modes', so the two must not diverge.
cp -R "$_eg/ok" "$_eg/okauto"; : > "$_eg/okauto/.auto-mode"
bash "$_ENG" engine-gate "$_eg/okauto" >/dev/null 2>&1
chk "$?" "0" "v0.32 S17: ...and identically in AUTO mode — the engine is armed by default in both, not only where a human is watching"
# no engine line at all
_mkeng "$_eg/none" "" "$_STAMP"
bash "$_ENG" engine-gate "$_eg/none" >/dev/null 2>&1
chk "$?" "1" "v0.32 S17: an active stamped build that records NO engine line is REFUSED"
# armed but unbounded — the 2026-04-28 runaway shape
_mkeng "$_eg/nocap" 'engine: long-build · armed=yes' "$_STAMP"
bash "$_ENG" engine-gate "$_eg/nocap" >/dev/null 2>&1
chk "$?" "1" "v0.32 S17: 'armed' with no cap=N is REFUSED — an armed loop with no bound is the failure this exists to prevent"
# in progress.md but never on the receipt
_mkeng "$_eg/norec" "$_ARMED" '- [x] something else'
bash "$_ENG" engine-gate "$_eg/norec" >/dev/null 2>&1
chk "$?" "1" "v0.32 S17: recorded in progress.md but never stamped on a receipt is REFUSED — progress.md is rewritten, the receipt is what survives"
# the loop ran past its own bound
_mkeng "$_eg/over" 'engine: long-build · armed=yes · cap=3' "$_STAMP"
printf '1 t 0 x\n2 t 0 x\n7 t 0 x\n' > "$_eg/over/.compass-wakeups"
bash "$_ENG" engine-gate "$_eg/over" >/dev/null 2>&1
chk "$?" "1" "v0.32 S17: a counter past the stated cap is REFUSED — the bound has to bite, not just be written down"
# N/A branches, each of which must SAY which case it is: a bare PASS reads as 'armed'.
_eo="$(bash "$_ENG" engine-gate "$_eg/none" 2>&1 || true)"
_mkeng "$_eg/skillless" "" "$_STAMP"
_eo2="$(COMPASS_ENGINE_SKILL_DIR=/nonexistent-xyz HOME=/nonexistent-xyz CLAUDE_PROJECT_DIR=/nonexistent-xyz bash "$_ENG" engine-gate "$_eg/skillless" 2>&1 || true)"
chk "$(printf '%s' "$_eo2" | grep -c 'COMPASS-GATE: PASS')" "1" "v0.32 S17: with NO long-build skill installed the gate N/A-PASSES — it cannot demand a build arm an engine that is not there"
chk "$(printf '%s' "$_eo2" | grep -c 'not installed here, and Compass does not ship it')" "1" "v0.32 S17: ...and SAYS the skill is absent"
chk "$(printf '%s' "$_eo2" | grep -c 'NOT a statement that this build is bounded')" "1" "v0.32 S17: ...and says explicitly what it is NOT claiming"
mkdir -p "$_eg/legacy"; printf '# p\n\n**Status:** BUILDING\n' > "$_eg/legacy/progress.md"
_eo3="$(bash "$_ENG" engine-gate "$_eg/legacy" 2>&1 || true)"
chk "$(printf '%s' "$_eo3" | grep -c 'predates the engine rule')" "1" "v0.32 S17: a build with no v0.30 stamp N/A-PASSES and says it predates the rule"
_mkeng "$_eg/shipped" "" "$_STAMP"; printf '# p\n\n**Status:** SHIPPED v0.30.0\n' > "$_eg/shipped/progress.md"
_eo4="$(bash "$_ENG" engine-gate "$_eg/shipped" 2>&1 || true)"
chk "$(printf '%s' "$_eo4" | grep -c 'STATUS line says it is finished')" "1" "v0.32 S17: a SHIPPED build N/A-PASSES — demanding an engine line retroactively would be a gate rewriting history"
# ...and the word SHIPPED in unrelated PROSE does NOT take an active build out of scope. A status of
# "BUILDING — S17 and S18 shipped" was reading as finished, on this repo's own build.
_mkeng "$_eg/prose" "$_ARMED" "$_STAMP"
printf '# p\n\n**Status:** BUILDING — S17 and S18 shipped; F-3 was CLOSED in S12\nCaps: wakeups_used: 12/40\n%s\n' "$_ARMED" > "$_eg/prose/progress.md"
_eo5="$(bash "$_ENG" engine-gate "$_eg/prose" 2>&1 || true)"
chk "$(printf '%s' "$_eo5" | grep -c 'STATUS line says it is finished')" "0" "v0.32 S17: ...and SHIPPED/CLOSED in unrelated PROSE does NOT take an actively-building build out of scope"
chk "$(printf '%s' "$_eo5" | grep -c 'engine armed and BOUNDED')" "1" "v0.32 S17: ...it is judged on its merits instead"
rm -rf "$_eg"
# And this repo's own live builds: the gate must refuse none of them.
_egn=0; _egf=0
for _d in "$PLUGIN_ROOT/../../.claude/builds"/*/; do
  [ -d "$_d" ] || continue
  _egn=$((_egn+1)); bash "$_ENG" engine-gate "$_d" >/dev/null 2>&1 || _egf=$((_egf+1))
done
# `.claude/builds/` is GITIGNORED, so a clean clone has none. This used to assert a non-empty
# population unconditionally and went RED on every clean clone — the assertion's own message said it
# could be empty there and it failed anyway. An explicit N/A is the rule this build applies
# everywhere else; a check that fails for a user who did nothing wrong is a check that gets deleted.
if [ "$_egn" -eq 0 ]; then
  chk "1" "1" "v0.32 S17: N/A — no build folders on this tree (.claude/builds is gitignored, so a clean clone has none). NOT a statement that no build is refused."
else
  chk "$([ "$_egn" -ge 5 ] && echo ok || echo "ONLY:$_egn")" "ok" "v0.32 S17: ...over a NON-EMPTY population of real build folders"
  chk "$_egf" "0" "v0.32 S17: ...and refuses none of them"
fi
# THE WIRING, which the commit that added this gate did not assert — the very lesson it was written
# to apply. An independent reviewer neutered only the CALL (keeping the `if type …` guard intact)
# and NOTHING went red. This goes through compass.sh gate and matches engine-gate's own words.
_egw="$(mktemp -d)"; mkdir -p "$_egw/b"; : > "$_egw/b/.compass-format"
printf '# p\n\n**Status:** BUILDING\nCaps: wakeups_used: 3/40\n' > "$_egw/b/progress.md"
printf '## RECEIPT — plan · x · PASS\n- [x] ok\n' > "$_egw/b/receipts.md"
_egwo="$(bash "$_ENG" gate "$_egw/b" plan 2>&1 || true)"
chk "$(printf '%s' "$_egwo" | grep -c "records no 'engine:' line")" "1" "v0.32 S17: engine-gate is REACHED THROUGH compass.sh gate — the refusal is its own words, which only the wired call can produce"
# ...and the honest control: with the line and the stamp, the same seam passes.
printf '# p\n\n**Status:** BUILDING\n%s\n' "$_ARMED" > "$_egw/b/progress.md"
printf '## RECEIPT — plan · x · PASS\n- [x] ok\n%s\n' "$_STAMP" > "$_egw/b/receipts.md"
_egwp="$(bash "$_ENG" gate "$_egw/b" plan 2>&1 || true)"
chk "$(printf '%s' "$_egwp" | grep -c "records no 'engine:' line")" "0" "v0.32 S17: ...and a build that DOES arm it passes that same seam (the control)"
rm -rf "$_egw"
# The build skill must TELL someone to write the line the gate hard-stops on.
chk "$(grep -c 'engine: long-build armed' "$PLUGIN_ROOT/skills/build/SKILL.md" || true)" "1" "v0.32 S17: the build skill's receipt template carries the engine line — a gate that hard-stops on a line nothing instructs is a trap"

# ── v0.32 S11b: two holes an independent reviewer opened in the disclosure ────────────────────
if command -v node >/dev/null 2>&1; then
  _s11b="$(mktemp -d)"; mkdir -p "$_s11b/b/agents"
  printf '# Contract — d · v1\n\nfacets: library\n\n## Goal & scope\n**Goal:** a fixture.\n\n## Acceptance & INVARIANTs\n- **INV-X:** a thing. → *assert:* it holds.\n' > "$_s11b/b/contract.md"
  printf '| Issue ID | Sev | Status |\n|---|---|---|\n| A-1 | Maj | OPEN |\n' > "$_s11b/b/review-ledger.md"
  # (1) THE NUMBER WAS INFLATABLE WITH `touch`. Three files each holding the letter "x" made the
  # banner say "3 evidence files are on record" about three files evidence-shape-check calls ABSENT.
  for _f in s1 s2 s3; do printf 'x\n' > "$_s11b/b/agents/review-plan-r1-$_f.md"; done
  node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_s11b/b" review --out "$_s11b/junk.html" >/dev/null 2>&1
  chk "$([ -s "$_s11b/junk.html" ] && echo ok || echo MISSING)" "ok" "v0.32 S11b: ...and a page was rendered to check it on"
  chk "$(grep -c 'No per-stream reviewer evidence files are on record' "$_s11b/junk.html" || true)" "1" "v0.32 S11b: three malformed evidence files count as ZERO on the banner — contract §4 calls a file with no nonce/target-sha ABSENT, and the banner now agrees with the checker"
  # ...and well-formed ones DO count, or the rule above is just 'always say none'.
  for _f in s1 s2 s3; do printf 'nonce: n7f3a91c4e2b8d605x\nstream: %s\nreview: review-plan\nround: 1\ntarget-sha: 8e1fc84\nverdict: CLEAN\n' "$_f" > "$_s11b/b/agents/review-plan-r1-$_f.md"; done
  node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_s11b/b" review --out "$_s11b/good.html" >/dev/null 2>&1
  chk "$(grep -c 'per-stream reviewer evidence files are on record' "$_s11b/good.html" || true)" "1" "v0.32 S11b: ...and three WELL-FORMED files do count (the control — without it 'always report none' would pass)"
  # (2) THE PAGE DECIDED WHETHER THE RULE APPLIED TO IT. Renaming the kicker in the same edit that
  # strips the sentence made artefact-gate record a PASS for a review page that says nothing.
  sed -e 's/This review was NOT independently verified\.//' -e 's/Compass · Review/Compass · Findings/' "$_s11b/good.html" > "$_s11b/dodge.html"
  _s11bj="$(node "$PLUGIN_ROOT/scripts/artefact-gate.mjs" "$_s11b/dodge.html" --json 2>/dev/null || true)"
  chk "$(printf '%s' "$_s11bj" | grep -c '"review-disclosure-na"' || true)" "0" "v0.32 S11b: renaming the kicker does NOT take a review page out of the rule — the view is stamped in a machine field the page cannot edit away"
  chk "$(printf '%s' "$_s11bj" | grep -c 'review-disclosure — ' || true)" "1" "v0.32 S11b: ...it is refused by name instead"
  chk "$(grep -c 'name="compass-view" content="review"' "$_s11b/good.html" || true)" "1" "v0.32 S11b: ...and that machine field is actually emitted"
  rm -rf "$_s11b"
fi

# ── v0.32 S10/S11c: A GATE NOBODY RUNS IS NOT A GATE ─────────────────────────────────────────
# An independent reviewer's first and worst finding: neither review gate was invoked by any skill,
# by cmd_gate, or by any hook — the only callers on the whole tree were the corpus fixtures and this
# suite. Two steps built to replace the honour system left it exactly where it was. This repo has
# made the same mistake before; the note beside gold-numbers-gate reads "the gold checks existed and
# NOTHING CALLED THEM". So the WIRING is asserted, through `compass.sh gate` and nothing else.
_wg="$(mktemp -d)"; mkdir -p "$_wg/b/agents"; : > "$_wg/b/.compass-format"
printf '# p\n\n**Status:** BUILDING\nengine: long-build · armed=yes · cap=40\n' > "$_wg/b/progress.md"
_wgrec() { printf '## RECEIPT — plan · x · PASS\n- [x] ok\n- [x] engine: long-build armed, cap 40\n\n## RECEIPT — review-plan · x · PASS\n%s\n' "$1" > "$_wg/b/receipts.md"; }
# the honest control FIRST — the seam must be able to pass, or every refusal below is free
for _s in $(bash "$PLUGIN_ROOT/scripts/compass.sh" review-streams review-plan 2>/dev/null); do
  printf 'nonce: n7f3a91c4e2b8d605x\nstream: %s\nreview: review-plan\nround: 1\ntarget-sha: 8e1fc84\nverdict: CLEAN\n' "$_s" > "$_wg/b/agents/review-plan-r1-$_s.md"
done
_wgn="$(bash "$PLUGIN_ROOT/scripts/compass.sh" review-streams review-plan 2>/dev/null | grep -c .)"
_wgrec "- [x] streams: review-plan r1 -> $_wgn of $_wgn
- [x] this review was NOT independently verified"
bash "$PLUGIN_ROOT/scripts/compass.sh" gate "$_wg/b" review-plan >/dev/null 2>&1
chk "$?" "0" "v0.32 S10/S11c: an honest review round PASSES through compass.sh gate (the control)"
# ...now break the evidence. Only the WIRED evidence gate can catch this at the gate seam.
rm -f "$_wg/b/agents"/review-plan-r1-*.md
bash "$PLUGIN_ROOT/scripts/compass.sh" gate "$_wg/b" review-plan >/dev/null 2>&1
chk "$?" "1" "v0.32 S10/S11c: a round CLAIMED with zero evidence files is refused BY compass.sh gate — not merely by a subcommand nothing calls"
# ...and restore the evidence, then remove the disclosure.
for _s in $(bash "$PLUGIN_ROOT/scripts/compass.sh" review-streams review-plan 2>/dev/null); do
  printf 'nonce: n7f3a91c4e2b8d605x\nstream: %s\nreview: review-plan\nround: 1\ntarget-sha: 8e1fc84\nverdict: CLEAN\n' "$_s" > "$_wg/b/agents/review-plan-r1-$_s.md"
done
_wgrec "- [x] streams: review-plan r1 -> $_wgn of $_wgn"
bash "$PLUGIN_ROOT/scripts/compass.sh" gate "$_wg/b" review-plan >/dev/null 2>&1
chk "$?" "1" "v0.32 S10/S11c: a review round that says nothing about independence is refused BY compass.sh gate"
rm -rf "$_wg"

# ── v0.32 S18: --self-consistency, which the plan named as if it existed ─────────────────────
# It did not. `grep -c self-consistency page-audit.mjs` returned 0 and passing the flag exited 0 in
# silence, so plan v1's assertion against it was a no-op that always passed. Building the mode was
# step one; these are its teeth.
_PA="$PLUGIN_ROOT/scripts/page-audit.mjs"
if [ -f "$_PA" ] && command -v node >/dev/null 2>&1; then
  chk "$([ "$(grep -c 'self-consistency' "$_PA" || true)" -gt 0 ] && echo ok || echo ABSENT)" "ok" "v0.32 S18: the --self-consistency mode EXISTS (it did not; the flag exited 0 in silence)"
  _sc="$(mktemp -d)"; mkdir -p "$_sc/b"
  printf '# Contract — d · v1\n\nfacets: library\n\n## Goal & scope\n**Goal:** a fixture with a ledger.\n\n## Acceptance & INVARIANTs\n- **INV-X:** a thing. → *assert:* it holds.\n' > "$_sc/b/contract.md"
  { printf '| Issue ID | Sev | Status |\n|---|---|---|\n'
    i=0; while [ "$i" -lt 9 ]; do i=$((i+1)); printf '| A-%s | Maj | CLOSED |\n' "$i"; done
    printf '| B-1 | Crit | OPEN |\n| B-2 | Maj | WEIRDSTATUS |\n'; } > "$_sc/b/review-ledger.md"
  node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_sc/b" review --out "$_sc/r.html" >/dev/null 2>&1
  # VACUITY GUARD: the assertions below are about a page, so there had better be one.
  chk "$([ -s "$_sc/r.html" ] && echo ok || echo MISSING)" "ok" "v0.32 S18: ...and there IS a rendered page to audit"
  # grep -c counts LINES and this page is nearly all one line — the first version of this assertion
  # read "1" for a page carrying eight counted claims. Occurrences, not lines.
  _scn="$(grep -o 'data-prov="counted"' "$_sc/r.html" | wc -l | tr -d ' ')"
  chk "$([ "${_scn:-0}" -ge 4 ] && echo ok || echo "ONLY:${_scn:-0}")" "ok" "v0.32 S18: ...carrying a NON-EMPTY population of counted claims to reconcile"
  node "$_PA" --self-consistency "$_sc/r.html" >/dev/null 2>&1
  chk "$?" "0" "v0.32 S18: a CONSISTENT page passes (the control — without it every refusal below is free)"
  # A HEADER TOTAL THAT DISAGREES WITH THE BODY. Rewriting only the FIRST occurrence is the point:
  # the same figure is stated twice on the page and the two must agree.
  node -e '
    const fs=require("fs"); const s=fs.readFileSync(process.argv[1],"utf8");
    const m=s.match(/<span data-prov="counted">(\d+)<\/span> findings/);
    if(!m){process.exit(3);}
    fs.writeFileSync(process.argv[2], s.replace(m[0], m[0].replace(m[1], String(Number(m[1])+1))));
  ' "$_sc/r.html" "$_sc/bad.html"
  chk "$([ -s "$_sc/bad.html" ] && echo ok || echo MISSING)" "ok" "v0.32 S18: ...and the disagreeing variant was actually produced"
  node "$_PA" --self-consistency "$_sc/bad.html" >/dev/null 2>&1
  chk "$?" "1" "v0.32 S18: a header total that disagrees with the body total is REFUSED"
  # a page with nothing counted is UNMEASURED, never 'consistent'
  printf '<html><body><p>nothing counted here at all</p></body></html>' > "$_sc/none.html"
  node "$_PA" --self-consistency "$_sc/none.html" >/dev/null 2>&1
  chk "$?" "2" "v0.32 S18: a page with NO counted claim is UNMEASURED (exit 2), never a silent pass over an empty set"
  # THE TRAP THIS CHECK EXISTS TO AVOID. A review ledger QUOTES historical numbers inside finding
  # text — real rows on the live corpus read "207 findings, 64 critical + 100 major = 164". Those
  # are quotations of past defects, not claims this page makes, and a checker reading the prose
  # flags every one. Provenance markup is what separates them, so it is tested, not asserted.
  printf '| Issue ID | Sev | Status | Failure mode |\n|---|---|---|---|\n| A-1 | Maj | CLOSED | Header said 162 findings / 69 critical / 74 major, and 999 closed, 0 still open |\n| A-2 | Crit | OPEN | a second row |\n| A-3 | Maj | CLOSED | a third row |\n' > "$_sc/b/review-ledger.md"
  node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_sc/b" review --out "$_sc/quoted.html" >/dev/null 2>&1
  chk "$([ -s "$_sc/quoted.html" ] && echo ok || echo MISSING)" "ok" "v0.32 S18: ...and the quoting page rendered"
  # The literal "162 findings" is NOT contiguous on the page — the number is wrapped as
  # `<span data-prov="quoted">162</span> findings`, which is the very mechanism under test. Grepping
  # the plain literal returned 0 and made the PASS below vacuous, which is how a control quietly
  # stops controlling anything.
  chk "$(grep -o 'data-prov="quoted">162<' "$_sc/quoted.html" | wc -l | tr -d ' ')" "1" "v0.32 S18: ...and it really does carry the contradictory total, marked QUOTED — without this the pass below would be over a page that never had the numbers"
  chk "$(grep -o 'data-prov="quoted">999<' "$_sc/quoted.html" | wc -l | tr -d ' ')" "1" "v0.32 S18: ...including a '999 closed' that would break the partition rule if it were read as a claim"
  node "$_PA" --self-consistency "$_sc/quoted.html" >/dev/null 2>&1
  chk "$?" "0" "v0.32 S18: a page whose LEDGER QUOTES contradictory totals still PASSES — quoting a past defect is not claiming it, and only data-prov markup can tell them apart"
  rm -rf "$_sc"
fi

# ── v0.32 S22: a LITERAL is not a MEASUREMENT ────────────────────────────────────────────────
# §17-7: perf-budget-gate proved a NUMBER WAS WRITTEN and could not tell a measured 200ms from an
# invented one. Three earlier perf claims in this repo were carried over from a previous build's
# contract and never run — this build's own contract says so in its perf line.
# DELIBERATELY NOT A GREP FOR "MEASURED": requiring a word would pass any contract that types six
# letters, which is the sin this build is named after. It checks ARITHMETIC instead — a real
# baseline leaves a RUN SERIES, and the derived figure must reconcile with it.
# GUARD-FIRST, measured before the rule: 31 folders · 12 declare a perf-budget · 9 are explicit N/A
# · 3 carry a real budget · 0 refused after wiring.
_pbd="$(mktemp -d)"
_mkpb() { mkdir -p "$_pbd/$1"; : > "$_pbd/$1/.compass-format"; printf '# c\n\nperf-budget: %s\n' "$2" > "$_pbd/$1/contract.md"; }
_PBBASE='p95 latency 200 ms; peak-mem 256 MB; cost $0.00 per request; SLO healthy range 25-50s.'
_mkpb good "25.4 / 25.2 / 25.2s → median 25.2s; $_PBBASE"
bash "$PLUGIN_ROOT/scripts/compass.sh" perf-budget-gate "$_pbd/good" >/dev/null 2>&1
chk "$?" "0" "v0.32 S22: a budget whose derived figure reconciles with its run series PASSES (the control)"
_mkpb noser "$_PBBASE"
bash "$PLUGIN_ROOT/scripts/compass.sh" perf-budget-gate "$_pbd/noser" >/dev/null 2>&1
chk "$?" "1" "v0.32 S22: literals with NO run series behind them are REFUSED — a number nobody ran is a number somebody typed"
_mkpb word "MEASURED MEASURED MEASURED. $_PBBASE"
bash "$PLUGIN_ROOT/scripts/compass.sh" perf-budget-gate "$_pbd/word" >/dev/null 2>&1
chk "$?" "1" "v0.32 S22: writing the word MEASURED three times does NOT satisfy it — this build's own named sin, refused inside its own fix"
# HONEST BUDGETS MUST STILL PASS. A gate that refuses correct work is the one that gets switched
# off, and an independent reviewer showed this rule hard-stopping four ordinary ones: a slash-form
# DATE parsed as a run series, a quoted EXAMPLE series (the one the gate error text tells you to
# write) blocked the build, and "Suite: 951 / 0 / 38.6s" was read as three runs of the same thing.
# A run series is three measurements of ONE thing, so its values cluster and carry a unit.
_mkpb hd1 "25.4 / 25.2 / 25.2s -> median 25.2s; Measured 2026/08/21. $_PBBASE"
bash "$PLUGIN_ROOT/scripts/compass.sh" perf-budget-gate "$_pbd/hd1" >/dev/null 2>&1
chk "$?" "0" "v0.32 S22: a slash-form DATE in the budget is not a run series — writing the measurement date the ordinary way must not block a build"
_mkpb hd2 "25.4 / 25.2 / 25.2s -> median 25.2s; Suite: 951 / 0 / 38.6s. $_PBBASE"
bash "$PLUGIN_ROOT/scripts/compass.sh" perf-budget-gate "$_pbd/hd2" >/dev/null 2>&1
chk "$?" "0" "v0.32 S22: ...and three unrelated numbers that do not cluster are not a run series either"
_mkpb hd3 "25.4 / 25.2 / 25.2s -> median 25.2s; versions 1.2 / 3.4 / 5.6. $_PBBASE"
bash "$PLUGIN_ROOT/scripts/compass.sh" perf-budget-gate "$_pbd/hd3" >/dev/null 2>&1
chk "$?" "0" "v0.32 S22: ...and a unit-less triple is not one — a measurement carries its unit"
_mkpb recon "25.4 / 25.2 / 25.2s measured; $_PBBASE median 99.9s"
bash "$PLUGIN_ROOT/scripts/compass.sh" perf-budget-gate "$_pbd/recon" >/dev/null 2>&1
chk "$?" "1" "v0.32 S22: a series that reconciles with NOTHING stated is REFUSED — a first version searched the whole line and the median of an odd series IS one of its own members, so the rule matched itself"
# EVERY series must reconcile, not just the longest. Checking one let a budget carry a real
# measurement beside an INVENTED one and pass on the strength of the real one — the exact shape this
# rule exists to refuse, one level up. Found by the rule catching this build's OWN contract when a
# third series was recorded without its derived figure.
_mkpb twoser "25.4 / 25.2 / 25.2s -> median 25.2s; and 90.1 / 90.2 / 90.3s -> median 12.0s; $_PBBASE"
bash "$PLUGIN_ROOT/scripts/compass.sh" perf-budget-gate "$_pbd/twoser" >/dev/null 2>&1
chk "$?" "1" "v0.32 S22: a budget with a REAL series beside an invented one is REFUSED — every series must reconcile, or one true measurement launders a false one"
_mkpb twook "25.4 / 25.2 / 25.2s -> median 25.2s; and 90.1 / 90.2 / 90.3s -> median 90.2s; $_PBBASE"
bash "$PLUGIN_ROOT/scripts/compass.sh" perf-budget-gate "$_pbd/twook" >/dev/null 2>&1
chk "$?" "0" "v0.32 S22: ...and two series that BOTH reconcile pass (the control — without it 'refuse anything with two series' would satisfy the case above)"
# The unit is required. Without it, "25" inside the SLO range "25-50s" satisfied the rule.
_mkpb unitless "25.4 / 25.2 / 25.2s runs; p95 latency 200 ms; peak-mem 256 MB; cost $0.00 per request; SLO healthy range 25-50s."
bash "$PLUGIN_ROOT/scripts/compass.sh" perf-budget-gate "$_pbd/unitless" >/dev/null 2>&1
chk "$?" "1" "v0.32 S22: ...and a bare integer inside an unrelated range does not count as the derived figure — the unit must be adjacent"
# GUARD-FIRST: unstamped builds N/A-pass the new rule AND say what is not being checked.
mkdir -p "$_pbd/legacy"; printf '# c\n\nperf-budget: %s\n' "$_PBBASE" > "$_pbd/legacy/contract.md"
_pbo="$(bash "$PLUGIN_ROOT/scripts/compass.sh" perf-budget-gate "$_pbd/legacy" 2>&1)"
chk "$(printf '%s' "$_pbo" | grep -c 'COMPASS-GATE: PASS')" "1" "v0.32 S22: an UNSTAMPED build still passes on literals alone"
chk "$(printf '%s' "$_pbo" | grep -c 'is NOT checked here')" "1" "v0.32 S22: ...and SAYS the measurement behind those literals was not checked"
rm -rf "$_pbd"
# THE WIRING. perf-budget-gate rides the contract seam in cmd_gate; a gate nobody calls is not a gate.
_pbw="$(mktemp -d)"; mkdir -p "$_pbw/b"; : > "$_pbw/b/.compass-format"
printf -- '---\ncompass-format: v0.30\n---\n# c\n\nperf-budget: %s\n\n## Goal\nA thing.\n\n## INVARIANTs\n- **INV-1:** a thing.\n' "$_PBBASE" > "$_pbw/b/contract.md"
printf '## RECEIPT — contract · b · PASS\n- [x] done\n- [x] mode choice: asked=yes · answer=Autonomous · source=question\n' > "$_pbw/b/receipts.md"
# THE MESSAGE, NOT THE EXIT CODE. A first version asserted `gate ... contract` exits 1, and it did —
# but so did the unwired mutant, because other contract-seam gates refuse this stub fixture anyway.
# That is the ninth instance of the vacuity class in this build, committed inside the assertion
# meant to prove a wiring. The gate must NAME perf-budget in its refusal, which only the wired rule
# can produce.
_pbwo="$(bash "$PLUGIN_ROOT/scripts/compass.sh" gate "$_pbw/b" contract 2>&1 || true)"
# The INNER die fires and exits before cmd_gate's wrapper message is ever printed, so the string to
# look for is the rule's own words, not "perf-budget-gate FAILED".
chk "$(printf '%s' "$_pbwo" | grep -c 'no RUN SERIES behind them')" "1" "v0.32 S22: ...and the rule is REACHED THROUGH compass.sh gate — the refusal is the run-series rule's own words, which only the wired rule can produce"
rm -rf "$_pbw"

# ── v0.32 S26: ONE RECONCILED STREAM VOCABULARY ──────────────────────────────────────────────
# §17-10. Three skills declare stream lists and S10's denominator reads all three, so the ids have
# to be one vocabulary rather than three private ones. What is checked is shape and agreement, not
# taste: every id kebab-case, unique within its skill, and a concern that appears in more than one
# skill spelled IDENTICALLY — `secret-leak` is in review-plan and review-build and must match.
_s26all=""
for _rv in review-contract review-plan review-build; do
  _s26="$(bash "$_CS" review-streams "$_rv" 2>/dev/null || true)"
  _s26n="$(printf '%s' "$_s26" | grep -c . || true)"
  chk "$([ "${_s26n:-0}" -ge 3 ] && echo ok || echo "EMPTY:${_s26n:-0}")" "ok" "v0.32 S26: $_rv's list parses into a non-empty vocabulary"
  chk "$(printf '%s' "$_s26" | grep -cvE '^[a-z][a-z0-9]*(-[a-z0-9]+)*$' || true)" "0" "v0.32 S26: ...and every id in it is kebab-case — one vocabulary, not three private ones"
  chk "$(printf '%s' "$_s26" | sort | uniq -d | grep -c . || true)" "0" "v0.32 S26: ...with no id repeated inside it (a duplicate would inflate the denominator for free)"
  _s26all="$_s26all
$_rv $_s26"
done
# A shared concern must be spelled the same way in every skill that has it. `secret-leak` is the
# live case; if it is ever spelled two ways, S10's denominator counts one concern as two streams.
chk "$(bash "$_CS" review-streams review-plan 2>/dev/null | grep -cx 'secret-leak' || true)" "1" "v0.32 S26: review-plan names the shared concern exactly 'secret-leak'"
chk "$(bash "$_CS" review-streams review-build 2>/dev/null | grep -cx 'secret-leak' || true)" "1" "v0.32 S26: ...and review-build spells it identically — a concern in two skills under two names is two streams in the denominator and one in reality"

# ── v0.32 S25: the claim and the evidence must agree ─────────────────────────────────────────
# §17-9. `review-contract`'s anti-fabrication stream cited `session-chain.log` as establishing that
# a contract was authored by an --auto session. It does not: `check-session-chain` validates that
# log's SHAPE — seven fields, a known event, a known stage, numeric counters — and never reads who
# wrote anything. The log is also written by the same party it would police, which is the limit §4
# states about independence. The citation is removed and the stream now says what it actually does.
_S25F="$PLUGIN_ROOT/skills/review-contract/SKILL.md"
chk "$(grep -c 'session-chain.log / receipts show it' "$_S25F" || true)" "0" "v0.32 S25: the false citation is GONE — check-session-chain never established authorship"
chk "$(grep -c "validates that log's SHAPE" "$_S25F" || true)" "1" "v0.32 S25: ...and the stream states what the command actually checks instead"
chk "$(grep -c 'Do not cite the chain log as proof of it' "$_S25F" || true)" "1" "v0.32 S25: ...and says plainly not to cite it as proof"
# The claim has to match the CODE, so this reads the code too: check-session-chain must not read
# the contract or claim authorship.
chk "$(sed -n "/^cmd_check_session_chain()/,/^}/p" "$PLUGIN_ROOT/scripts/compass.sh" | grep -c 'contract.md' || true)" "0" "v0.32 S25: ...and check-session-chain genuinely never reads contract.md, which is what makes the correction true rather than merely softer"

# ── v0.32 S27: the kill switch, §12 ──────────────────────────────────────────────────────────
# §12 documents COMPASS_V32_STRICT and then constrains it: "the flag may disable reporting gates,
# but never the measurement the build is graded on, and closure is REFUSED while the flag is off."
# Before this step the flag was read by NOTHING — zero references across all nine v0.32 checks,
# except two comments saying it is deliberately not read. Both halves of §12 were unbacked.
_v32d="$(mktemp -d)"; mkdir -p "$_v32d/b"; printf '# c\n' > "$_v32d/b/contract.md"
_v32off="$(COMPASS_V32_STRICT=0 bash "$PLUGIN_ROOT/scripts/compass.sh" close "$_v32d/b" smoke-v32 2>&1 || true)"
_v32on="$(bash "$PLUGIN_ROOT/scripts/compass.sh" close "$_v32d/b" smoke-v32 2>&1 || true)"
chk "$(printf '%s' "$_v32off" | grep -c 'COMPASS_V32_STRICT is off')" "1" "v0.32 S27: closure is REFUSED while the kill switch is off, for the flag's OWN reason"
chk "$(printf '%s' "$_v32off" | grep -c '§12')" "1" "v0.32 S27: ...and the refusal names §12, so a reader can tell it from any other refusal"
chk "$(printf '%s' "$_v32off" | grep -c 'v32-strict=off')" "1" "v0.32 S27: ...and names the receipt stamp §12 requires"
chk "$(printf '%s' "$_v32on" | grep -c 'COMPASS_V32_STRICT is off')" "0" "v0.32 S27: ...and with the flag ON that refusal does NOT appear — the guard is a switch, not a wall (the control)"
_v32ab="$(COMPASS_V32_STRICT=0 bash "$PLUGIN_ROOT/scripts/compass.sh" close "$_v32d/b" smoke-v32 --abandon 2>&1 || true)"
chk "$(printf '%s' "$_v32ab" | grep -c 'ABANDONED')" "1" "v0.32 S27: --abandon is still allowed with the flag off — cancelling claims nothing about a build, and blocking it would only strand it"
rm -rf "$_v32d"
# THE HALF §12 WAS WRITTEN FOR: the flag must never reach a measurement. Asserted about the CODE,
# which is what makes it a fact rather than an intention. Round 2 of the contract review found a
# design where the flag returned every new gate to an N/A-pass, including the one measuring the gold.
_v32n=0
for _f in reachable-argument.mjs reachable-argument-check.sh page-audit.mjs behaviour-corpus-check.sh evidence-shape-check.sh declared-check.sh defeat-corpus-check.sh redfirst-count.sh; do
  [ -f "$PLUGIN_ROOT/scripts/$_f" ] || continue
  _v32n=$((_v32n+1))
  chk "$(grep -vE '^[[:space:]]*(#|//)' "$PLUGIN_ROOT/scripts/$_f" | grep -c 'COMPASS_V32_STRICT' || true)" "0" "v0.32 S27: $_f does not READ the kill switch in code, so it cannot be silenced by it"
done
chk "$([ "$_v32n" -ge 6 ] && echo ok || echo "ONLY:$_v32n")" "ok" "v0.32 S27: ...over a NON-EMPTY set of measurements (a loop over files that are not there would assert nothing)"

# ── v0.32 S35: §12's CANARY — no historical build newly refused ──────────────────────────────
# Compass has shipped this mistake before: v0.28's mode-gate armed on a MISSING header and refused
# 25 of 26 existing builds. §12 makes any historical build a new gate would newly refuse a RELEASE
# BLOCKER, not a fixture to delete. `canary-gates.sh` runs every gate v0.32 ADDS or CHANGES over
# every build folder and every lifecycle stage, and it found one: cockpit-gate refused the parked
# `gate-soundness-v0-32`, which is a no-touch zone — so the GATE was what had to change.
_CG="$PLUGIN_ROOT/scripts/canary-gates.sh"
chk "$([ -f "$_CG" ] && echo ok || echo MISSING)" "ok" "v0.32 S35: canary-gates.sh exists — §12's canary needs a run, and a run needs a script"
if [ -f "$_CG" ]; then
  # It reads the GITIGNORED .claude/builds/, so on a clean clone there is nothing to canary. That
  # must ERR, never pass: an empty canary reporting "0 newly refused" is the vacuity class this
  # build has now found eleven times.
  _cgt="$(mktemp -d)"; mkdir -p "$_cgt/plugins/compass/scripts"
  cp "$PLUGIN_ROOT/scripts/compass.sh" "$_cgt/plugins/compass/scripts/" 2>/dev/null
  bash "$_CG" "$_cgt" >/dev/null 2>&1
  chk "$?" "2" "v0.32 S35: ...and a tree with NO build folders ERRs (exit 2) rather than reporting zero refusals over zero builds"
  rm -rf "$_cgt"
  # A SAMPLE here, the FULL run at release. The complete canary is 374 gate calls and 41.7s — it
  # took this suite from 39s to 59.1s, past the 50.2s ceiling the contract states. Coverage is MOVED,
  # not deleted: the sample runs every time, the release runs all of it (S28-S31), and the sample
  # says in its own output that it is one.
  # `.claude/builds/` is GITIGNORED, so a clean clone has none and there is nothing to canary. That
  # must be an explicit N/A here, not a failure and not a silent pass — the same rule this build
  # applies to every other gate. The canary script itself ERRs on an empty tree, which is what stops
  # "0 refusals over 0 builds" from ever reading as a clean bill.
  _cgo="$(bash "$_CG" "$PLUGIN_ROOT/../.." --sample 6 2>&1 || true)"
  if printf '%s' "$_cgo" | grep -q 'no .claude/builds at\|zero build folders'; then
    chk "1" "1" "v0.32 S35: N/A — this tree has no build folders to canary (.claude/builds is gitignored, so a clean clone has none). NOT a statement that nothing is newly refused; the release runs the full canary on a tree that has them."
  else
  _cgb="$(printf '%s' "$_cgo" | sed -nE 's/^canary-gates: [0-9]+ gate calls over (a SAMPLE of )?([0-9]+).*/\2/p' | head -1)"
  _cgr="$(printf '%s' "$_cgo" | sed -nE 's/^canary-gates: .* · ([0-9]+) newly refused.*/\1/p' | head -1)"
  chk "$([ "${_cgb:-0}" -ge 5 ] && echo ok || echo "ONLY:${_cgb:-0}")" "ok" "v0.32 S35: ...over a NON-EMPTY population of real historical builds"
  # THE POSITIVE CONTROL. An independent reviewer deleted all three `refused` increments and this
  # suite stayed green: "0 newly refused" was asserted over a population where nothing refuses.
  _cgs="$(bash "$_CG" "$PLUGIN_ROOT/../.." --self-check 2>&1 || true)"
  chk "$(printf '%s' "$_cgs" | grep -c 'self-check PASSED')" "1" "v0.32 S35: ...and the canary CATCHES a planted refusing build, so its zero is a measurement and not a shape"
  # ...and the sample must include every stamped build: alphabetical order put BOTH .compass-format
  # folders outside it, and those are the only ones the new rules grade. The refusal this canary
  # found on its first run was in one of them.
  chk "$(printf '%s' "$_cgo" | grep -c 'every .compass-format build first')" "1" "v0.32 S35: ...and the sample takes every stamped build first, not the same six alphabetically"
  chk "$(printf '%s' "$_cgo" | grep -c 'this is NOT the full canary')" "1" "v0.32 S35: ...and a SAMPLE says it is one — the release runs it without --sample, and a sample passed off as the whole thing is the false all-clear this build is about"
  chk "${_cgr:-none}" "0" "v0.32 S35: ...and NO historical build is newly refused by any gate this build adds"
  chk "$(printf '%s' "$_cgo" | grep -c 'excluded   :')" "1" "v0.32 S35: ...and what it does NOT run is stated, not quietly dropped — a canary that cannot tell a NEW refusal from a pre-existing one reported 41 problems and hid the one that mattered"
  fi
fi

# ── v0.32 S34: §7's FALSE-CERTAINTY RULE ─────────────────────────────────────────────────────
# §7 enumerates all three buckets and says PREFIX match, and gen.mjs had grown its own lists that
# disagreed in BOTH directions: DONE / NOTED / WAIVED / OK counted as settled (§7 lists none of
# them, so they are UNREADABLE), and WONTFIX counted as OPEN while §7 lists it as SETTLED.
# The pinned corpus cannot exercise any of this — 39 rows over 2 builds, zero unreadable, and the
# two lists agree on all 39. That is the fixture-shape problem this build keeps meeting, so the
# cases get their own fixtures and the pinned reachability figures are left alone.
_SB="$PLUGIN_ROOT/scripts/fixtures/status-buckets"
if [ -d "$_SB" ] && command -v node >/dev/null 2>&1; then
  _sbt="$(mktemp -d)"; _sbn=0
  for _f in all-settled one-open one-unreadable list-edges; do
    [ -d "$_SB/$_f" ] || continue
    node "$PLUGIN_ROOT/skills/compass-visual/gen.mjs" "$_SB/$_f" review --out "$_sbt/$_f.html" >/dev/null 2>&1
    [ -s "$_sbt/$_f.html" ] && _sbn=$((_sbn+1))
  done
  chk "$_sbn" "4" "v0.32 S34: all four status-bucket fixtures render — the assertions below are about pages, so there had better be four"
  _sbtxt() { sed -e 's/<[^>]*>/ /g' "$1" | tr -s ' \n' ' '; }
  # 1. The all-clear is printed ONLY when every row is settled. Without this control, "never print
  #    the all-clear" would be satisfied by never printing it at all.
  chk "$(_sbtxt "$_sbt/all-settled.html" | grep -c 'Every finding was fixed and re-checked')" "1" "v0.32 S34: a ledger whose rows are ALL settled DOES print the all-clear (the control)"
  chk "$(_sbtxt "$_sbt/one-open.html" | grep -c 'Every finding was fixed and re-checked')" "0" "v0.32 S34: one OPEN row and the all-clear is not printed"
  chk "$(_sbtxt "$_sbt/one-unreadable.html" | grep -c 'Every finding was fixed and re-checked')" "0" "v0.32 S34: one UNREADABLE row and the all-clear is not printed either — unreadable is never folded into settled"
  # 2. The RANGE, which §7 requires whenever any row is unreadable.
  chk "$(_sbtxt "$_sbt/one-unreadable.html" | grep -c 'the honest range is')" "1" "v0.32 S34: ...and the page states the honest RANGE, because a single settled figure claims a certainty it does not have"
  chk "$(_sbtxt "$_sbt/one-open.html" | grep -c 'the honest range is')" "0" "v0.32 S34: ...and does NOT state a range when every row is classifiable (the control — a range printed always is not a range)"
  # 3. §7's LISTS, both directions, on one page: WONTFIX/REFUTED/DUPLICATE settled · CARRIED/PARTIAL/
  #    IN PROGRESS/OUTSTANDING open · DONE/NOTED unreadable.
  chk "$(_sbtxt "$_sbt/list-edges.html" | grep -oE '[0-9]+ closed, [0-9]+ still open, [0-9]+ whose status' | head -1)" "3 closed, 4 still open, 2 whose status" "v0.32 S34: the buckets are contract §7's enumerated lists — WONTFIX/REFUTED/DUPLICATE settled, CARRIED/PARTIAL/IN PROGRESS/OUTSTANDING open, DONE/NOTED unreadable"
  rm -rf "$_sbt"
fi

# ── v0.32 S8: the COLD-READ harness ──────────────────────────────────────────────────────────
# The harness picks the rows, not the readers. A cold reader told "see if you can finish a few rows"
# picks rows that read easily — and a row the page did not shorten renders no control at all, so it
# is trivially finishable. Two lazy readers choosing freely would pass a page on which NOTHING is
# reachable. The candidates therefore come from the rows the page ACTUALLY SHORTENED.
# The READERS run out of band, in minutes, on §9's split budget. Nothing here claims to have read.
_CR="$PLUGIN_ROOT/scripts/cold-read.sh"
chk "$([ -f "$_CR" ] && echo ok || echo MISSING)" "ok" "v0.32 S8: cold-read.sh exists"
if [ -f "$_CR" ] && command -v node >/dev/null 2>&1; then
  _cro="$(bash "$_CR" --self-check "$PLUGIN_ROOT/../.." 2>&1 || true)"
  chk "$(printf '%s' "$_cro" | grep -c 'self-check PASSED')" "1" "v0.32 S8: its control pair passes — a readable page offers candidate rows and a KNOWN-UNREADABLE one offers none"
  # The population is stated, so "0 candidates on both" can never read as a pass.
  chk "$(printf '%s' "$_cro" | grep -cE 'readable control offers [0-9]+ candidate rows' || true)" "1" "v0.32 S8: ...and it STATES how many candidates the readable control offered — a harness that finds none passes every page ever written"
  chk "$(printf '%s' "$_cro" | grep -c 'does NOT prove')" "1" "v0.32 S8: ...and it says what it does NOT prove: nobody read anything, because the readers run out of band"
  # THE NEGATIVE CONTROL. Asserting "self-check PASSED" cannot detect a self-check that always
  # passes — two mutations proved exactly that, and neither reddened this suite. So the self-check
  # is run against a tree whose GENERATOR emits no disclosure controls at all: every row is still
  # shortened, nothing is reachable, and the harness must refuse it.
  _crn="$(mktemp -d)"
  mkdir -p "$_crn/plugins/compass/skills" "$_crn/plugins/compass/scripts"
  cp -R "$PLUGIN_ROOT/skills/compass-visual" "$_crn/plugins/compass/skills/" 2>/dev/null
  cp -R "$PLUGIN_ROOT/scripts/." "$_crn/plugins/compass/scripts/" 2>/dev/null
  python3 - "$_crn/plugins/compass/skills/compass-visual/gen.mjs" <<'PYEOF' >/dev/null 2>&1
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o="""function disclose(rest, label = 'Show the rest') {
  if (!rest) return '';"""
assert s.count(o)==1
io.open(p,'w',encoding='utf-8').write(s.replace(o, o + "\n  return '';"))
PYEOF
  _cron="$(bash "$_crn/plugins/compass/scripts/cold-read.sh" --self-check "$_crn" 2>&1 || true)"
  chk "$(printf '%s' "$_cron" | grep -c 'self-check PASSED')" "0" "v0.32 S8: ...and the self-check REFUSES a tree whose generator emits no controls at all — without this, a self-check that always passes would satisfy every assertion above"
  chk "$(printf '%s' "$_cron" | grep -cE 'self-check FAILED|UNMEASURED')" "1" "v0.32 S8: ...and says which way it refused"
  rm -rf "$_crn"
  # And it emits real packets for a real build: two independent readers plus a grader.
  _crd="$(mktemp -d)"
  bash "$_CR" "$PLUGIN_ROOT/../../.claude/builds/artefacts-from-data-v0-31" --emit "$_crd" >/dev/null 2>&1 || true
  if [ -d "$PLUGIN_ROOT/../../.claude/builds/artefacts-from-data-v0-31" ]; then
    chk "$(ls "$_crd" 2>/dev/null | wc -l | tr -d ' ')" "4" "v0.32 S8: ...and it emits page.html plus TWO reader packets and a grader — two readings, independent, and a grader who never sees the contract"
    chk "$(grep -c 'may not substitute other rows' "$_crd/reader-1.md" 2>/dev/null || true)" "1" "v0.32 S8: ...and the packet forbids substituting rows, which is the whole point of the harness choosing them"
  else
    chk "1" "1" "v0.32 S8: N/A — the emit fixture build is not on this tree (.claude/builds is gitignored)"
  fi
  rm -rf "$_crd"
fi

# ── v0.32 S14: an ABSENT reader-copy block was an N/A-PASS ───────────────────────────────────
# So on 27 of 30 contracts this gate printed a pass for a file it had not read one word of. "No
# block" is not "the copy is fine". GUARD-FIRST (the v0.28 lesson): a contract that PREDATES the
# format N/A-passes and SAYS SO. Measured before the change: the three contracts carrying a
# `compass-format:` line are EXACTLY the three carrying a block, so this refuses none of them.
_S14="$(mktemp -d)"
printf '# Contract — t\n\ncompass-format: v0.30\n\n## Goal\nA thing.\n' > "$_S14/new.md"
printf '# Contract — t\n\n## Goal\nA thing.\n' > "$_S14/old.md"
bash "$SH" copy-gate "$_S14/new.md" >/dev/null 2>&1
chk "$([ "$?" -ne 0 ] && echo 1 || echo 0)" "1" "v0.32 S14: a contract declaring a compass-format but carrying NO reader-copy block is REFUSED (it used to N/A-pass)"
bash "$SH" copy-gate "$_S14/old.md" >/dev/null 2>&1
chk "$?" "0" "v0.32 S14: a contract that predates the format N/A-passes (guard-first — it would otherwise refuse 27 of 30 builds)"
chk "$(bash "$SH" copy-gate "$_S14/old.md" 2>&1 | grep -c 'predates the reader-copy format')" "1" "v0.32 S14: ...and it SAYS why in words — an unstated N/A is a rule quietly retired"
rm -rf "$_S14"

# ── v0.32 S15 (INV-PLAIN-TERMINAL): the stage-end block carries all FOUR elements ─────────────
# The invariant named four and NOTHING asserted them; the fourth — the options — was missing on
# every build in every mode, so the surface that exists to tell a person what they can do never did.
_S15="$(mktemp -d)/b"; mkdir -p "$_S15"
printf '# t — progress\n\n**Status:** build\n**Stage:** build\n**Next:** S1 do the thing\n' > "$_S15/progress.md"
printf '# Contract — t\n\nfacets: library\n' > "$_S15/contract.md"
printf '# Plan\n- [x] **S1** a — VERIFY: ran.\n- [ ] **S2** b — VERIFY: pending.\n' > "$_S15/plan.md"
_ck="$(bash "$SH" cockpit "$_S15" 2>&1)"
chk "$(printf '%s' "$_ck" | grep -c '^BUILD · ')" "1" "v0.32 S15: element 1 of 4 — what happened (the stage strip)"
chk "$(printf '%s' "$_ck" | grep -c '▲ ')" "1" "v0.32 S15: element 2 of 4 — where you are"
chk "$([ "$(printf '%s' "$_ck" | grep -cE 'next:|all stages ✓')" -ge 1 ] && echo 1 || echo 0)" "1" "v0.32 S15: element 3 of 4 — what is next"
chk "$(printf '%s' "$_ck" | grep -c '▸ you can:')" "1" "v0.32 S15: element 4 of 4 — THE OPTIONS, which were absent on every build in every mode"
chk "$(printf '%s' "$_ck" | grep -c '/compass:go')" "1" "v0.32 S15: ...and the options name a real COMMAND, not a category"
bash "$SH" cockpit-gate "$_S15" >/dev/null 2>&1
chk "$?" "0" "v0.32 S15: cockpit-gate passes a block that carries all four"
# it must REFUSE one that does not — proven by removing the element, not by assuming
_S15M="$(mktemp -d)"; mkdir -p "$_S15M/scripts"
sed -e "s|printf '  ▸ you can:  '|printf ''|" "$SH" > "$_S15M/scripts/compass.sh"
cp -R "$(dirname "$SH")/fixtures" "$_S15M/scripts/" 2>/dev/null
bash "$_S15M/scripts/compass.sh" cockpit-gate "$_S15" >/dev/null 2>&1
chk "$([ "$?" -ne 0 ] && echo 1 || echo 0)" "1" "v0.32 S15: ...and REFUSES one with the options removed — the check can fail"
rm -rf "$_S15M"
# the plain-words half N/A-passes when the walkthrough skill is absent, AND says that it did
chk "$(CLAUDE_CONFIG_DIR=/nonexistent-xyz bash "$SH" cockpit-gate "$_S15" 2>&1 | grep -c 'Plain-words half N/A')" "1" "v0.32 S15: with /feynman-walkthrough absent the plain-words half N/A-passes AND says so"
rm -rf "$(dirname "$_S15")"

# ── v0.32 S12 + S13: the stage-end contract, checked instead of hoped for ────────────────────
# Contract §7 says two things about the end of every stage — the cockpit prints in EVERY mode, and
# the next step is ASKED unless the mode is auto, in which case the receipt says `asked=no ·
# reason=auto-mode` so an un-asked stage stays visible forever. Neither had a check. Measured
# before: 5 of 30 receipt files carry any `asked=` at all, and all five are the mode choice at LOCK
# time, not a stage end. This build committed the defect against itself (plan step S13).
_SE="$(mktemp -d)"
mkdir -p "$_SE/ok" "$_SE/nocock" "$_SE/noask" "$_SE/unstamped" "$_SE/legacy"
printf '# r\n\n## RECEIPT — build · t · PASS\n- [x] stage-end: cockpit=printed · asked=yes · answer=continue\n' > "$_SE/ok/receipts.md"
printf '# r\n\n## RECEIPT — build · t · PASS\n- [x] stage-end: asked=yes · answer=continue\n' > "$_SE/nocock/receipts.md"
printf '# r\n\n## RECEIPT — build · t · PASS\n- [x] stage-end: cockpit=printed\n' > "$_SE/noask/receipts.md"
printf '# r\n\n## RECEIPT — build · t · PASS\n- [x] stage-end: cockpit=printed · asked=no\n' > "$_SE/unstamped/receipts.md"
printf '# r\n\n## RECEIPT — build · t · PASS\n- [x] a legacy line with no stamp at all\n' > "$_SE/legacy/receipts.md"
printf '# r\n\n## RECEIPT — build · t · PASS\n- [x] stage-end: cockpit=printed · asked=no · reason=auto-mode\n' > "$_SE/ok/auto.md"
bash "$SH" stage-end-gate "$_SE/ok" >/dev/null 2>&1
chk "$?" "0" "v0.32 S12/S13: a well-formed stage-end stamp PASSES (without this the checks below pass for free)"
bash "$SH" stage-end-gate "$_SE/nocock" >/dev/null 2>&1
chk "$([ "$?" -ne 0 ] && echo 1 || echo 0)" "1" "v0.32 S12: a stage end that does not say cockpit=printed is REFUSED — §7 requires it in every mode, no exception"
bash "$SH" stage-end-gate "$_SE/noask" >/dev/null 2>&1
chk "$([ "$?" -ne 0 ] && echo 1 || echo 0)" "1" "v0.32 S13: a stage end recording no ask at all is REFUSED"
bash "$SH" stage-end-gate "$_SE/unstamped" >/dev/null 2>&1
chk "$([ "$?" -ne 0 ] && echo 1 || echo 0)" "1" "v0.32 S13: asked=no with no reason=auto-mode is REFUSED — an un-asked stage that does not say why is just an un-asked stage"
bash "$SH" stage-end-gate "$_SE/legacy" >/dev/null 2>&1
chk "$?" "0" "v0.32 S12/S13: a receipt predating the stamp N/A-passes (guard-first — receipts are written by the SKILLS, so none could carry a stamp that did not exist)"
chk "$(bash "$SH" stage-end-gate "$_SE/legacy" 2>&1 | grep -c 'predate the stamp and are NOT checked')" "1" "v0.32 S12/S13: ...and it SAYS how many are unchecked — an unstated N/A is a rule quietly retired"
rm -rf "$_SE"

# ── v0.32 §17-8 teeth: did THIS suite run dirty a tracked fixture? ───────────────────────────
# Runs last, after every fixture-touching assertion above. Compares against the snapshot taken
# before the first one. `__nogit__` on both sides = no git = N/A-pass, stated rather than skipped.
_V32_FX_AFTER="$(_v32_fxstate)"
if [ "$_V32_FX_BEFORE" = "__nogit__" ]; then
  chk "1" "1" "v0.32 §17-8: N/A — not a git work tree, so tracked-fixture drift is unmeasurable here"
else
  _v32drift="$(comm -13 <(printf '%s\n' "$_V32_FX_BEFORE") <(printf '%s\n' "$_V32_FX_AFTER") | grep -c . || true)"
  [ -n "$_v32drift" ] || _v32drift=0
  chk "$_v32drift" "0" "v0.32 §17-8: a full suite run modifies 0 tracked fixture files (was 6)"
  [ "$_v32drift" = 0 ] || comm -13 <(printf '%s\n' "$_V32_FX_BEFORE") <(printf '%s\n' "$_V32_FX_AFTER") | sed 's/^/    DIRTIED: /'
fi

echo "──────── $pass passed, $fail failed ────────"
cd /; rm -rf "$SMOKE_TMP" 2>/dev/null
[ "$fail" = 0 ]

