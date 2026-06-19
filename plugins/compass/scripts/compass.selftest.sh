#!/usr/bin/env bash
# compass.selftest.sh — reproduction tests for the v0.7.0 hardening (INV-1..INV-7).
# Each case reproduces a REAL failure shape (migration bypass / ship soft-pass / skipped
# stage) authored in-repo (no private data), and asserts the new gates catch it via EXACT
# exit codes. Stub migrate commands → no real DB needed. Run: bash compass.selftest.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SH="$HERE/compass.sh"
PASS=0; FAIL=0
chk() { # <actual> <expected> <msg>
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$3"
  else FAIL=$((FAIL+1)); printf '  FAIL %s   (got exit %s, want %s)\n' "$3" "$1" "$2"; fi
}
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT

# ---- receipt-chain helpers (author a clean PASS chain through a given last stage) -------
full_chain() { # <build-dir> <last-stage> [--signoff]
  local dir="$1" last="$2" signoff="${3:-}"; mkdir -p "$dir"; : > "$dir/receipts.md"
  for s in contract review-contract plan review-plan build review-build ship; do
    printf '\n## RECEIPT — %s · fix · PASS\n- [x] %s done\n' "$s" "$s" >> "$dir/receipts.md"
    if [ "$s" = review-build ] && [ "$signoff" = --signoff ]; then printf -- '- [x] human sign-off recorded\n' >> "$dir/receipts.md"; fi
    [ "$s" = "$last" ] && break
  done
}

echo "── migration-gate (INV-1, INV-2) ─────────────────────────────"
# 1a clean: declared stub recipe, a real migration file, fresh+diff succeed → PASS (exit 0)
C="$SB/clean"; mkdir -p "$C/canon"; : > "$C/canon/0001_init.sql"
cat > "$C/contract.md" <<EOF
schema-touching: yes
canonical_migrations_dir: $C/canon
migrate_deploy_fresh_cmd: sh -c 'exit 0'
migrate_diff_cmd: sh -c 'exit 0'
EOF
bash "$SH" migration-gate "$C" >/dev/null 2>&1; chk "$?" "0" "INV-1 clean: migration present + fresh-apply + diff-empty → PASS"

# 1b db-execute bypass (the pg-method-rates root cause) → FAIL
B="$SB/bypass"; mkdir -p "$B/canon"; : > "$B/canon/0001_init.sql"
cp "$C/contract.md" "$B/contract.md"; sed -i.bak "s#$C/canon#$B/canon#" "$B/contract.md"; rm -f "$B/contract.md.bak"
printf '## RECEIPT — build · fix · PASS\n- [x] S3 migration: hand-authored SQL applied to dev DB via prisma db execute\n' > "$B/receipts.md"
bash "$SH" migration-gate "$B" >/dev/null 2>&1; chk "$?" "1" "INV-1 bypass: 'db execute' delivery → FAIL (G-M3)"

# 1c stray migration dir (prisma/schema present AND prisma/migrations present) → FAIL
T="$SB/stray"; mkdir -p "$T/prisma/schema/migrations" "$T/prisma/migrations"; : > "$T/prisma/schema/migrations/0001.sql"
mkdir -p "$SB/strayb"; printf 'schema-touching: yes\n' > "$SB/strayb/contract.md"
COMPASS_REPO_ROOT="$T" bash "$SH" migration-gate "$SB/strayb" >/dev/null 2>&1; chk "$?" "1" "INV-1 stray: prisma/migrations beside prisma/schema/ → FAIL (G-M3, the incident class)"

# 1d schema-touching but NO migration file in canonical dir → FAIL
N="$SB/nomig"; mkdir -p "$N/prisma/schema/migrations"   # empty
mkdir -p "$SB/nomigb"; printf 'schema-touching: yes\n' > "$SB/nomigb/contract.md"
COMPASS_REPO_ROOT="$N" bash "$SH" migration-gate "$SB/nomigb" >/dev/null 2>&1; chk "$?" "1" "INV-1 no-file: schema-touching yes, empty canonical dir → FAIL (G-M1)"

# INV-2 strict: history won't replay (fresh-apply stub fails) → FAIL (no waiver)
R="$SB/replay"; mkdir -p "$R/canon"; : > "$R/canon/0001.sql"
cat > "$R/contract.md" <<EOF
schema-touching: yes
canonical_migrations_dir: $R/canon
migrate_deploy_fresh_cmd: sh -c 'exit 1'
migrate_diff_cmd: sh -c 'exit 0'
EOF
bash "$SH" migration-gate "$R" >/dev/null 2>&1; chk "$?" "1" "INV-2 strict: fresh-DB replay failure → FAIL (G-M4, no waiver)"

echo "── lifecycle-audit (INV-3, INV-4, INV-5) ─────────────────────"
# INV-3 ship soft-pass: SHIPPED but ship receipt prod-verify UNCHECKED → FAIL
SP="$SB/softpass"; full_chain "$SP" review-build --signoff
printf '\n## RECEIPT — ship · fix · PASS\n- [x] deployed via repo path\n- [ ] prod reconcile: UNVERIFIED — prod unreachable, deferred\n' >> "$SP/receipts.md"
: > "$SP/contract.md"
bash "$SH" lifecycle-audit "$SP" SHIPPED >/dev/null 2>&1; chk "$?" "1" "INV-3 soft-pass: SHIPPED + unchecked prod-verify → FAIL (G-L2)"
# clean ship → PASS (ship block carries a CHECKED prod-verify line)
SPok="$SB/shipok"; full_chain "$SPok" ship --signoff; : > "$SPok/contract.md"
printf -- '- [x] prod reconcile: compass.sh reconcile 1 1 0 → PASS\n' >> "$SPok/receipts.md"
bash "$SH" lifecycle-audit "$SPok" SHIPPED >/dev/null 2>&1; chk "$?" "0" "INV-3 clean: SHIPPED + checked prod-verify → PASS"
# RB-01 omission: ship block with NO prod-verify line at all → FAIL (no omission loophole)
SPo="$SB/shipomit"; full_chain "$SPo" ship --signoff; : > "$SPo/contract.md"
bash "$SH" lifecycle-audit "$SPo" SHIPPED >/dev/null 2>&1; chk "$?" "1" "INV-3 omit: SHIPPED + prod-verify line ABSENT → FAIL (RB-01, G-L2)"

# INV-4 skipped stage: receipts missing review-plan → FAIL
SK="$SB/skipped"; mkdir -p "$SK"; : > "$SK/contract.md"; : > "$SK/receipts.md"
for s in contract review-contract plan build review-build; do printf '\n## RECEIPT — %s · fix · PASS\n- [x] %s\n' "$s" "$s" >> "$SK/receipts.md"; done
printf -- '- [x] human sign-off recorded\n' >> "$SK/receipts.md"
bash "$SH" lifecycle-audit "$SK" >/dev/null 2>&1; chk "$?" "1" "INV-4 skipped: review-plan missing → FAIL (G-L1)"

# INV-5 ship skipped: chain to review-build, no ship, contract has NO deploy waiver → FAIL; with waiver → PASS
SS="$SB/shipskip"; full_chain "$SS" review-build --signoff; : > "$SS/contract.md"
bash "$SH" lifecycle-audit "$SS" >/dev/null 2>&1; chk "$?" "1" "INV-5 ship-skipped: no waiver, no ship → FAIL (G-L3)"
printf 'deploy: out-of-scope — internal tooling, no deploy\n' > "$SS/contract.md"
bash "$SH" lifecycle-audit "$SS" >/dev/null 2>&1; chk "$?" "0" "INV-5 waiver: deploy out-of-scope (field line) → PASS"
# v0.7.1: the phrase appearing ONLY in prose must NOT count as a waiver (anchored field match)
printf 'This build does NOT record a `deploy: out-of-scope` waiver — it is mentioned only in prose.\n' > "$SS/contract.md"
bash "$SH" lifecycle-audit "$SS" >/dev/null 2>&1; chk "$?" "1" "INV-5 prose: 'deploy: out-of-scope' only in prose → NOT waived → FAIL (v0.7.1 anchor fix)"

echo "── route-coverage (INV-R0..R4, v0.8.0 blast-radius) ─────────"
RC="$SB/rc"; mkdir -p "$RC"
# INV-R4 no-op: no routes declared + no changed route files → N/A PASS
printf '## 7. Steps\n- [ ] **S1**\n' > "$RC/plan.md"
COMPASS_CHANGED_FILES="" bash "$SH" route-coverage "$RC" >/dev/null 2>&1; chk "$?" "0" "INV-R4 no routes + no route files → N/A PASS"
# INV-R0 anti-gaming: a page.tsx changed but empty ## Affected routes → FAIL (declaration mandatory)
COMPASS_CHANGED_FILES="src/app/accounts/page.tsx" bash "$SH" route-coverage "$RC" >/dev/null 2>&1; chk "$?" "1" "INV-R0 page file changed + no declared routes → FAIL (G-R0, can't game by omission)"
# Declare routes (pg-method-rates shape): two [param] routes + a prefix pair /accounts & /accounts/new
cat > "$RC/plan.md" <<'EOF'
## Affected routes
- /accounts/[branchId] — prospect page
- /active/[groupId] — active account
- /accounts/new — create prospect
- /accounts — list
## 7. Steps
- [ ] **S1**
EOF
# INV-R1 RED: routes declared, no canonical proof → FAIL
: > "$RC/receipts.md"
COMPASS_CHANGED_FILES="" bash "$SH" route-coverage "$RC" >/dev/null 2>&1; chk "$?" "1" "INV-R1 declared routes, no canonical proof line → FAIL"
# INV-R1 RED: R2-01 [param] char-class imposter + R2-02 prefix-steal + scattered tokens → still FAIL
cat > "$RC/receipts.md" <<'EOF'
- [x] route /accounts/new: curl -s localhost/accounts/new → 200 form
- [x] route /accounts/b: curl → 200 imposter-not-the-param-route
a stray 200 here and a curl over there on unrelated lines
EOF
COMPASS_CHANGED_FILES="" bash "$SH" route-coverage "$RC" >/dev/null 2>&1; chk "$?" "1" "INV-R1 R2-01 [param] imposter + R2-02 prefix-steal + scattered → still FAIL"
# INV-R1 GREEN: a canonical literal+colon-anchored proof per route → PASS
cat > "$RC/receipts.md" <<'EOF'
- [x] route /accounts/[branchId]: curl -s 'localhost/accounts/1' → 200 prospect
- [x] route /active/[groupId]: curl -s 'localhost/active/1' → 200 active
- [x] route /accounts/new: curl -s localhost/accounts/new → 200 form
- [x] route /accounts: curl -s localhost/accounts → 200 list
EOF
COMPASS_CHANGED_FILES="" bash "$SH" route-coverage "$RC" >/dev/null 2>&1; chk "$?" "0" "INV-R1 canonical proof per route (grep -F literal + colon anchor) → PASS"
# INV-R1 RB3-01: a markdown-wrapped declared route (backtick / bold) must NOT be silently dropped
RCW="$SB/rcw"; mkdir -p "$RCW"
printf '## Affected routes\n- `/accounts/secret` — backtick-wrapped\n- **/active/bold** — bold-wrapped\n- /accounts/plain — plain\n## 7. Steps\n- [ ] S1\n' > "$RCW/plan.md"
printf -- '- [x] route /accounts/plain: curl → 200 ok\n' > "$RCW/receipts.md"   # only the plain route proved
COMPASS_CHANGED_FILES="" bash "$SH" route-coverage "$RCW" >/dev/null 2>&1; chk "$?" "1" "INV-R1 RB3-01: backtick/bold-wrapped declared routes unproved → still FAIL (not silently dropped)"
# same, all three proved (incl the wrapped ones, parser extracts the bare path) → PASS
printf -- '- [x] route /accounts/secret: curl → 200 a\n- [x] route /active/bold: curl → 200 b\n- [x] route /accounts/plain: curl → 200 c\n' > "$RCW/receipts.md"
COMPASS_CHANGED_FILES="" bash "$SH" route-coverage "$RCW" >/dev/null 2>&1; chk "$?" "0" "INV-R1 RB3-01: wrapped routes proved by their bare path → PASS (parser robust)"
# INV-R2 typecheck-only: page step tsc-only + no proof → FAIL (G-R1) AND a G-R2 advisory printed
RC2="$SB/rc2"; mkdir -p "$RC2"
cat > "$RC2/plan.md" <<'EOF'
## Affected routes
- /accounts/new — create prospect
## 7. Steps
- [ ] S7 accounts/new/page.tsx · VERIFY: npx tsc --noEmit
EOF
: > "$RC2/receipts.md"
ADV="$(COMPASS_CHANGED_FILES="" bash "$SH" route-coverage "$RC2" 2>&1 >/dev/null || true)"
COMPASS_CHANGED_FILES="" bash "$SH" route-coverage "$RC2" >/dev/null 2>&1; chk "$?" "1" "INV-R2 typecheck-only page step + no proof → FAIL (G-R1 carries the teeth)"
printf '%s' "$ADV" | grep -q 'G-R2 advisory'; chk "$?" "0" "INV-R2 G-R2 advisory printed (surfaced, not a die)"
printf -- '- [x] route /accounts/new: curl → 200 form\n' > "$RC2/receipts.md"
COMPASS_CHANGED_FILES="" bash "$SH" route-coverage "$RC2" >/dev/null 2>&1; chk "$?" "0" "INV-R2 same typecheck-only step WITH a load proof → PASS (no false-positive)"

echo "── ship route-smoke (INV-R3, v0.8.0) ────────────────────────"
R3="$SB/r3"; full_chain "$R3" ship --signoff
printf 'schema-touching: no\n' > "$R3/contract.md"
printf '## Affected routes\n- /accounts/new — create prospect\n## 7. Steps\n- [ ] S1\n' > "$R3/plan.md"
# ship block carries a CHECKED prod-verify (passes RB-01) but NO prod route-smoke line yet
printf -- '- [x] prod reconcile: compass.sh reconcile 5 5 0 → PASS\n' >> "$R3/receipts.md"
bash "$SH" lifecycle-audit "$R3" SHIPPED >/dev/null 2>&1; chk "$?" "1" "INV-R3 SHIPPED + route declared + ship receipt missing prod route-smoke → FAIL"
printf -- '- [x] route /accounts/new: curl prod → 200 form (prod)\n' >> "$R3/receipts.md"
bash "$SH" lifecycle-audit "$R3" SHIPPED >/dev/null 2>&1; chk "$?" "0" "INV-R3 with a CHECKED prod route-smoke per declared route → PASS"

echo "── stop-guard (INV-6 retained + INV-R5 §3d gate-quiet) ───────"
# isolated throwaway git repo so state_root/INDEX are sandboxed
G="$SB/repo"; mkdir -p "$G"; ( cd "$G" && git init -q && git commit -q --allow-empty -m x 2>/dev/null )
mkdir -p "$G/.claude/builds/midbuild"
printf 'midbuild · goal · status=plan-LOCKED · facets=library\n' > "$G/.claude/builds/INDEX"
printf '## RECEIPT — contract · midbuild · PASS\n- [x] x\n' > "$G/.claude/builds/midbuild/receipts.md"
printf '**Status:** plan-LOCKED\n**Stage:** plan\n**Next:** build\n' > "$G/.claude/builds/midbuild/progress.md"
printf '## 7. Steps\n- [ ] **S1**\n- [ ] **S2**\n' > "$G/.claude/builds/midbuild/plan.md"
OUT="$(cd "$G" && echo '{"stop_hook_active":false}' | bash "$SH" stop-guard)"
printf '%s' "$OUT" | grep -q '"decision":"block"'; chk "$?" "1" "INV-R5 gate (plan-LOCKED, 0 boxes) → NO block (v0.8.0 §3d — inverts old INV-6 'mid-lifecycle→block'; quiet at gates)"
OUT="$(cd "$G" && echo '{"stop_hook_active":true}' | bash "$SH" stop-guard)"
printf '%s' "$OUT" | grep -q '"decision":"block"'; chk "$?" "1" "INV-6 loop-guard: stop_hook_active=true → NO block (anti-deadlock)"
# terminal status → no block
printf 'midbuild · goal · status=SHIPPED · facets=library\n' > "$G/.claude/builds/INDEX"
printf '**Status:** SHIPPED\n' > "$G/.claude/builds/midbuild/progress.md"
OUT="$(cd "$G" && echo '{"stop_hook_active":false}' | bash "$SH" stop-guard)"
printf '%s' "$OUT" | grep -q '"decision":"block"'; chk "$?" "1" "INV-6 terminal (SHIPPED) → NO block"
# RB-02 fail-open: outside a git repo the hook must not crash (set -e would otherwise propagate state_root's exit)
NG="$(mktemp -d)"; ( cd "$NG" && echo '{"stop_hook_active":false}' | bash "$SH" stop-guard >/dev/null 2>&1 ); chk "$?" "0" "INV-6 fail-open: stop-guard outside a git repo → exit 0 (RB-02, never crash)"

# INV-R5 (§3d): block ONLY on true mid-build; quiet at every clean checkpoint/gate.
printf 'midbuild · goal · status=building · facets=library\n' > "$G/.claude/builds/INDEX"
# (block) mid-build: last build receipt is IN-PROGRESS · step k/n
printf '## RECEIPT — contract · midbuild · PASS\n- [x] x\n## RECEIPT — build · midbuild · IN-PROGRESS · step 4/11\n- [x] y\n' > "$G/.claude/builds/midbuild/receipts.md"
printf '**Status:** building\n**Stage:** build · IN-PROGRESS · step 4/11\n**Next:** step 5\n' > "$G/.claude/builds/midbuild/progress.md"
printf '## 7. Steps\n- [x] **S1**\n- [ ] **S2**\n' > "$G/.claude/builds/midbuild/plan.md"
OUT="$(cd "$G" && echo '{"stop_hook_active":false}' | bash "$SH" stop-guard)"
printf '%s' "$OUT" | grep -q '"decision":"block"'; chk "$?" "0" "INV-R5 mid-build (build receipt IN-PROGRESS · step 4/11) → block"
# (block) plan.md half-checked, NO IN-PROGRESS build receipt → still mid-build via (b)
printf '## RECEIPT — contract · midbuild · PASS\n- [x] x\n' > "$G/.claude/builds/midbuild/receipts.md"
OUT="$(cd "$G" && echo '{"stop_hook_active":false}' | bash "$SH" stop-guard)"
printf '%s' "$OUT" | grep -q '"decision":"block"'; chk "$?" "0" "INV-R5 plan.md half-checked (≥1 [x] AND ≥1 [ ]) → block"
# (quiet) ambiguity guard: a review-plan IN PROGRESS receipt (spaced prose, no k/n) is NOT a build mid-step
printf '## RECEIPT — contract · midbuild · PASS\n- [x] x\n## RECEIPT — review-plan · midbuild · IN PROGRESS\n- [ ] round 1 paused\n' > "$G/.claude/builds/midbuild/receipts.md"
printf '## 7. Steps\n- [ ] **S1**\n' > "$G/.claude/builds/midbuild/plan.md"
OUT="$(cd "$G" && echo '{"stop_hook_active":false}' | bash "$SH" stop-guard)"
printf '%s' "$OUT" | grep -q '"decision":"block"'; chk "$?" "1" "INV-R5 ambiguity guard: 'review-plan IN PROGRESS' (no build k/n) → NO block (quiet)"
# (quiet) CLOSED-awaiting-ship is a user gate (relaxes old closed-not-waived block)
printf 'midbuild · goal · status=closed · facets=library\n' > "$G/.claude/builds/INDEX"
printf '**Status:** CLOSED\n**Stage:** review-build\n**Next:** ship\n' > "$G/.claude/builds/midbuild/progress.md"
printf 'schema-touching: no\n' > "$G/.claude/builds/midbuild/contract.md"
OUT="$(cd "$G" && echo '{"stop_hook_active":false}' | bash "$SH" stop-guard)"
printf '%s' "$OUT" | grep -q '"decision":"block"'; chk "$?" "1" "INV-R5 CLOSED-awaiting-ship (all boxes done) → NO block (§3d relaxes the old ship-nudge)"
# (quiet, RP2-02) a build with NO plan.md must not crash the hook under set -euo pipefail
rm -f "$G/.claude/builds/midbuild/plan.md"
printf 'midbuild · goal · status=building · facets=library\n' > "$G/.claude/builds/INDEX"
printf '**Status:** building\n**Stage:** build\n**Next:** step 1\n' > "$G/.claude/builds/midbuild/progress.md"
printf '## RECEIPT — contract · midbuild · PASS\n- [x] x\n' > "$G/.claude/builds/midbuild/receipts.md"
( cd "$G" && echo '{"stop_hook_active":false}' | bash "$SH" stop-guard >/dev/null 2>&1 ); chk "$?" "0" "INV-R5 RP2-02: build with NO plan.md → is_mid_build quiet, exit 0 (no crash under set -euo pipefail)"

echo "── no-regression + old-misses baseline (INV-7) ───────────────"
# migration-gate no-op for schema-touching:no
NS="$SB/noschema"; mkdir -p "$NS"; printf 'schema-touching: no\n' > "$NS/contract.md"
bash "$SH" migration-gate "$NS" >/dev/null 2>&1; chk "$?" "0" "INV-7 no-op: schema-touching:no → N/A PASS"
# lifecycle-audit clean complete build (deploy waived) → PASS  (reset $SS contract — prior cases mutated it)
printf 'deploy: out-of-scope — internal tooling, no deploy\n' > "$SS/contract.md"
bash "$SH" lifecycle-audit "$SS" >/dev/null 2>&1; chk "$?" "0" "INV-7 no-op: complete+waived build → PASS"
# OLD MISSES: the soft-pass ship receipt's LAST block is a clean PASS → existing scan-receipt does NOT catch it
bash "$SH" scan-receipt "$SPok" ship >/dev/null 2>&1
echo "  note  OLD MISSES — existing 'scan-receipt ship' on a clean-looking ship receipt exits $? (passes); only lifecycle-audit ties SHIPPED status to a CHECKED prod-verify."

echo
echo "selftest: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
