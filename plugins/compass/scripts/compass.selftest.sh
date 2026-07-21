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

echo "── stop-guard §3d behaviors (now OWNER-aware — v0.9.0) ───────"
# isolated throwaway git repo so state_root/INDEX are sandboxed. v0.9.0: every mid-build
# fixture now writes an OWNER (sessX) and pipes session_id=sessX, so the §3d quiet cases stay
# quiet for the RIGHT reason (is_mid_build/status), not merely a missing owner (R2-12).
G="$SB/repo"; mkdir -p "$G"; ( cd "$G" && git init -q && git commit -q --allow-empty -m x 2>/dev/null )
mkdir -p "$G/.claude/builds/midbuild" "$G/.claude/builds/.locks"
printf 'session=sessX\n' > "$G/.claude/builds/.locks/midbuild.owner"   # owner present for ALL cases below
JX='{"session_id":"sessX","stop_hook_active":false}'   # the OWNING session stops
sg() { cd "$G" && printf '%s' "${1:-$JX}" | bash "$SH" stop-guard; }   # run guard in $G
printf 'midbuild · goal · status=plan-LOCKED · facets=library\n' > "$G/.claude/builds/INDEX"
printf '## RECEIPT — contract · midbuild · PASS\n- [x] x\n' > "$G/.claude/builds/midbuild/receipts.md"
printf '**Status:** plan-LOCKED\n**Stage:** plan\n**Next:** build\n' > "$G/.claude/builds/midbuild/progress.md"
printf '## 7. Steps\n- [ ] **S1**\n- [ ] **S2**\n' > "$G/.claude/builds/midbuild/plan.md"
printf '%s' "$(sg)" | grep -q '"decision":"block"'; chk "$?" "1" "§3d gate (plan-LOCKED, 0 boxes) + owner present → NO block (quiet from is_mid_build, not missing owner)"
printf '%s' "$(sg '{"session_id":"sessX","stop_hook_active":true}')" | grep -q '"decision":"block"'; chk "$?" "1" "loop-guard: stop_hook_active=true → NO block (anti-deadlock)"
# terminal status → no block
printf 'midbuild · goal · status=SHIPPED · facets=library\n' > "$G/.claude/builds/INDEX"
printf '**Status:** SHIPPED\n' > "$G/.claude/builds/midbuild/progress.md"
printf '%s' "$(sg)" | grep -q '"decision":"block"'; chk "$?" "1" "terminal (SHIPPED) + owner present → NO block"
# RB-02 fail-open: outside a git repo the hook must not crash
NG="$(mktemp -d)"; ( cd "$NG" && printf '%s' "$JX" | bash "$SH" stop-guard >/dev/null 2>&1 ); chk "$?" "0" "fail-open: stop-guard outside a git repo → exit 0 (RB-02, never crash)"

# §3d: block ONLY on true mid-build (owner matches); quiet at every clean checkpoint/gate.
printf 'midbuild · goal · status=building · facets=library\n' > "$G/.claude/builds/INDEX"
printf '## RECEIPT — contract · midbuild · PASS\n- [x] x\n## RECEIPT — build · midbuild · IN-PROGRESS · step 4/11\n- [x] y\n' > "$G/.claude/builds/midbuild/receipts.md"
printf '**Status:** building\n**Stage:** build · IN-PROGRESS · step 4/11\n**Next:** step 5\n' > "$G/.claude/builds/midbuild/progress.md"
printf '## 7. Steps\n- [x] **S1**\n- [ ] **S2**\n' > "$G/.claude/builds/midbuild/plan.md"
printf '%s' "$(sg)" | grep -q '"decision":"block"'; chk "$?" "0" "mid-build (IN-PROGRESS · step 4/11) + owning session → block"
# plan.md half-checked, NO IN-PROGRESS build receipt → still mid-build via (b)
printf '## RECEIPT — contract · midbuild · PASS\n- [x] x\n' > "$G/.claude/builds/midbuild/receipts.md"
printf '%s' "$(sg)" | grep -q '"decision":"block"'; chk "$?" "0" "plan.md half-checked (≥1 [x] AND ≥1 [ ]) + owning session → block"
# (quiet) ambiguity guard: review-plan IN PROGRESS (no build k/n) is NOT a build mid-step
printf '## RECEIPT — contract · midbuild · PASS\n- [x] x\n## RECEIPT — review-plan · midbuild · IN PROGRESS\n- [ ] round 1 paused\n' > "$G/.claude/builds/midbuild/receipts.md"
printf '## 7. Steps\n- [ ] **S1**\n' > "$G/.claude/builds/midbuild/plan.md"
printf '%s' "$(sg)" | grep -q '"decision":"block"'; chk "$?" "1" "ambiguity guard ('review-plan IN PROGRESS', no build k/n) + owner present → NO block (quiet from is_mid_build)"
# POSITIVE CONTROL (R2-12): same fixture flipped to a REAL mid-step build + owner → MUST block (proves owner path didn't disable everything)
printf '## RECEIPT — contract · midbuild · PASS\n- [x] x\n## RECEIPT — build · midbuild · IN-PROGRESS · step 2/7\n- [x] y\n' > "$G/.claude/builds/midbuild/receipts.md"
printf '%s' "$(sg)" | grep -q '"decision":"block"'; chk "$?" "0" "POSITIVE CONTROL: same slug flipped to real mid-step + owner → block (owner path is live, not a kill-switch)"
# (quiet) CLOSED-awaiting-ship
printf 'midbuild · goal · status=closed · facets=library\n' > "$G/.claude/builds/INDEX"
printf '**Status:** CLOSED\n**Stage:** review-build\n**Next:** ship\n' > "$G/.claude/builds/midbuild/progress.md"
printf 'schema-touching: no\n' > "$G/.claude/builds/midbuild/contract.md"
printf '## RECEIPT — contract · midbuild · PASS\n- [x] x\n' > "$G/.claude/builds/midbuild/receipts.md"
printf '## 7. Steps\n- [x] **S1**\n' > "$G/.claude/builds/midbuild/plan.md"
printf '%s' "$(sg)" | grep -q '"decision":"block"'; chk "$?" "1" "CLOSED-awaiting-ship (no unchecked box) + owner → NO block"
# (quiet, RP2-02) no plan.md must not crash under set -euo pipefail
rm -f "$G/.claude/builds/midbuild/plan.md"
printf 'midbuild · goal · status=building · facets=library\n' > "$G/.claude/builds/INDEX"
printf '**Status:** building\n**Stage:** build\n**Next:** step 1\n' > "$G/.claude/builds/midbuild/progress.md"
printf '## RECEIPT — contract · midbuild · PASS\n- [x] x\n' > "$G/.claude/builds/midbuild/receipts.md"
( sg >/dev/null 2>&1 ); chk "$?" "0" "RP2-02: no plan.md + owner → is_mid_build quiet, exit 0 (no crash)"

echo "── session isolation S1–S17 (v0.9.0 — owner=session id) ──────"
# fresh sandbox; a single mid-build 'A' owned by sessX (IN-PROGRESS step 3/9)
I="$SB/iso"; mkdir -p "$I/.claude/builds/A" "$I/.claude/builds/.locks"; ( cd "$I" && git init -q && git commit -q --allow-empty -m x 2>/dev/null )
setA() { printf 'A · goal · status=building · facets=library\n' > "$I/.claude/builds/INDEX"
  printf '## RECEIPT — contract · A · PASS\n- [x] x\n## RECEIPT — build · A · IN-PROGRESS · step 3/9\n- [x] y\n' > "$I/.claude/builds/A/receipts.md"
  printf '**Status:** building\n**Stage:** build step 3/9\n**Next:** step 4\n' > "$I/.claude/builds/A/progress.md"
  printf '## 7. Steps\n- [x] **S1**\n- [x] **S2**\n- [x] **S3**\n- [ ] **S4**\n' > "$I/.claude/builds/A/plan.md"
  printf 'session=%s\n' "${1:-sessX}" > "$I/.claude/builds/.locks/A.owner"; rm -f "$I/.claude/builds/.locks/A.blocked"; }
ig() { cd "$I" && printf '%s' "$1" | bash "$SH" stop-guard; }
setA sessX
O="$(ig '{"session_id":"sessX","stop_hook_active":false}')"
printf '%s' "$O" | grep -q '"decision":"block"' && printf '%s' "$O" | grep -q '\bA\b'; chk "$?" "0" "S1 owning session sessX + mid-build → block (reason names A)"
printf '%s' "$(ig '{"session_id":"sessY","stop_hook_active":false}')" | grep -q '"decision":"block"'; chk "$?" "1" "S2 foreign session sessY → quiet {}"
printf '%s' "$(ig '{"stop_hook_active":false}')" | grep -q '"decision":"block"'; chk "$?" "1" "S3 no session id (env unset) → quiet {}"
rm -f "$I/.claude/builds/.locks/A.owner"
printf '%s' "$(ig '{"session_id":"sessX","stop_hook_active":false}')" | grep -q '"decision":"block"'; chk "$?" "1" "S4 orphan (no owner file) → quiet {} for everyone"
setA sessX
printf '%s' "$(ig '{"session_id":"sessX","stop_hook_active":false}')" >/dev/null   # arm block once
# S5 paused
printf '**Status:** PAUSED — parked\n' > "$I/.claude/builds/A/progress.md"
printf '%s' "$(ig '{"session_id":"sessX","stop_hook_active":false}')" | grep -q '"decision":"block"'; chk "$?" "1" "S5 status PAUSED + owner sessX → quiet {}"
# S6 CLOSED + deploy waived
printf 'A · goal · status=closed · facets=library\n' > "$I/.claude/builds/INDEX"
printf '**Status:** CLOSED\n' > "$I/.claude/builds/A/progress.md"; printf 'deploy: out-of-scope — internal\n' > "$I/.claude/builds/A/contract.md"
printf '%s' "$(ig '{"session_id":"sessX","stop_hook_active":false}')" | grep -q '"decision":"block"'; chk "$?" "1" "S6 CLOSED+deploy-waived + owner → quiet {}"
# S7/S8 two builds, two owners
mkdir -p "$I/.claude/builds/B"; setA sessX
printf 'A · goal · status=building · facets=library\nB · goal · status=building · facets=library\n' > "$I/.claude/builds/INDEX"
printf '## RECEIPT — contract · B · PASS\n- [x] x\n## RECEIPT — build · B · IN-PROGRESS · step 1/4\n- [x] y\n' > "$I/.claude/builds/B/receipts.md"
printf '**Status:** building\n**Stage:** build step 1/4\n**Next:** step 2\n' > "$I/.claude/builds/B/progress.md"
printf '## 7. Steps\n- [x] **S1**\n- [ ] **S2**\n' > "$I/.claude/builds/B/plan.md"
printf 'session=sessY\n' > "$I/.claude/builds/.locks/B.owner"
O="$(ig '{"session_id":"sessX","stop_hook_active":false}')"; printf '%s' "$O" | grep -q '\bA\b' && ! printf '%s' "$O" | grep -q '\bB\b'; chk "$?" "0" "S7 A(sessX)+B(sessY) mid: sessX stops → block names A NOT B"
O="$(ig '{"session_id":"sessY","stop_hook_active":false}')"; printf '%s' "$O" | grep -q '\bB\b' && ! printf '%s' "$O" | grep -q '\bA\b'; chk "$?" "0" "S8 same: sessY stops → block names B NOT A"
rm -f "$I/.claude/builds/B.owner" "$I/.claude/builds/.locks/B.owner" "$I/.claude/builds/.locks/B.blocked"; rm -rf "$I/.claude/builds/B"
# S9 non-git already covered (fail-open). S10 malformed progress + mid-build + owner → still block, exit 0
setA sessX; printf 'GARBAGE no status line here\x01\n' > "$I/.claude/builds/A/progress.md"
S10E=0; O="$(ig '{"session_id":"sessX","stop_hook_active":false}')" || S10E=$?   # ONE call (a 2nd would dedupe)
chk "$S10E" "0" "S10 malformed progress.md + mid-build + owner → exit 0 (no crash)"
printf '%s' "$O" | grep -q '"decision":"block"'; chk "$?" "0" "S10b malformed progress.md → still valid block JSON (stage/next '?')"
# S11 substring non-collision
setA sessX
printf '%s' "$(ig '{"session_id":"sessXY","stop_hook_active":false}')" | grep -q '"decision":"block"'; chk "$?" "1" "S11 owner sessX vs stop sessXY → quiet (exact compare, no substring match)"
# S12 fingerprint dedup + re-arm
setA sessX
printf '%s' "$(ig '{"session_id":"sessX","stop_hook_active":false}')" | grep -q '"decision":"block"'; chk "$?" "0" "S12a first stop, step 3/9 → block"
printf '%s' "$(ig '{"session_id":"sessX","stop_hook_active":false}')" | grep -q '"decision":"block"'; chk "$?" "1" "S12b identical step (zero mutation) → quiet {} (fingerprint dedup)"
printf '## RECEIPT — contract · A · PASS\n- [x] x\n## RECEIPT — build · A · IN-PROGRESS · step 4/9\n- [x] y\n' > "$I/.claude/builds/A/receipts.md"   # advance step → re-arm
printf '%s' "$(ig '{"session_id":"sessX","stop_hook_active":false}')" | grep -q '"decision":"block"'; chk "$?" "0" "S12c step advanced 3→4 → block again (re-armed)"
# S13 own refuses empty
( cd "$I" && bash "$SH" own A --session "" >/dev/null 2>&1 ); chk "$?" "1" "S13 own --session '' → non-zero (refuse empty)"
# S15 transcript_path different uuid + spaced/pretty JSON
setA sessX
O="$(ig '{ "transcript_path" : "/x/9999dead-0000-0000-0000-000000000000/t.jsonl" , "session_id" : "sessX" , "stop_hook_active" : false }')"
printf '%s' "$O" | grep -q '"decision":"block"'; chk "$?" "0" "S15 different uuid in transcript_path + spaced JSON → block (parse keyed to session_id field)"
# S16 env fallback
setA sessX
( cd "$I" && printf '%s' '{"stop_hook_active":false}' | CLAUDE_CODE_SESSION_ID=sessX bash "$SH" stop-guard | grep -q '"decision":"block"' ); chk "$?" "0" "S16 no stdin session_id + env CLAUDE_CODE_SESSION_ID=sessX → block (env fallback)"
setA sessX
( cd "$I" && printf '%s' '{"stop_hook_active":false}' | CLAUDE_CODE_SESSION_ID= bash "$SH" stop-guard | grep -q '"decision":"block"' ); chk "$?" "1" "S16b no stdin + empty env → quiet {}"
# S17 trailing-newline / whitespace owner still matches
setA sessX; printf 'session=sessX  \n\n' > "$I/.claude/builds/.locks/A.owner"; rm -f "$I/.claude/builds/.locks/A.blocked"
printf '%s' "$(ig '{"session_id":"sessX","stop_hook_active":false}')" | grep -q '"decision":"block"'; chk "$?" "0" "S17 owner with trailing whitespace/newline → still block (strict extract + trim)"

echo "── S14 cross-project isolation (two real repos) ──────────────"
RA="$SB/repoA"; RB="$SB/repoB"
for R in "$RA" "$RB"; do mkdir -p "$R/.claude/builds/.locks"; ( cd "$R" && git init -q && git commit -q --allow-empty -m x 2>/dev/null ); done
mkdir -p "$RA/.claude/builds/X"
printf 'X · goal · status=building · facets=library\n' > "$RA/.claude/builds/INDEX"
printf '## RECEIPT — contract · X · PASS\n- [x] x\n## RECEIPT — build · X · IN-PROGRESS · step 2/5\n- [x] y\n' > "$RA/.claude/builds/X/receipts.md"
printf '**Status:** building\n**Stage:** build step 2/5\n**Next:** step 3\n' > "$RA/.claude/builds/X/progress.md"
printf '## 7. Steps\n- [x] **S1**\n- [ ] **S2**\n' > "$RA/.claude/builds/X/plan.md"
printf 'session=sessX\n' > "$RA/.claude/builds/.locks/X.owner"
printf '%s' "$(cd "$RB" && printf '%s' '{"session_id":"sessX","stop_hook_active":false}' | bash "$SH" stop-guard)" | grep -q '"decision":"block"'; chk "$?" "1" "S14 same session sessX stopping in repoB → quiet (cross-project isolation)"
printf '%s' "$(cd "$RA" && printf '%s' '{"session_id":"sessX","stop_hook_active":false}' | bash "$SH" stop-guard)" | grep -q '"decision":"block"'; chk "$?" "0" "S14b converse: sessX in repoA still blocks (proves quiet is isolation, not global invisibility)"

echo "── ship coordination P1–P7 (v0.9.0) ─────────────────────────"
SP="$SB/ship"; mkdir -p "$SP/.claude/builds/A" "$SP/.claude/builds/B" "$SP/.claude/builds/C" "$SP/.claude/builds/.locks"; ( cd "$SP" && git init -q && git commit -q --allow-empty -m x 2>/dev/null )
printf 'A · goal · status=building · facets=library\nB · goal · status=plan-LOCKED · facets=library\nC · goal · status=closed · facets=library\n' > "$SP/.claude/builds/INDEX"
printf '**Status:** CLOSED\n' > "$SP/.claude/builds/A/progress.md"; printf 'schema-touching: no\n' > "$SP/.claude/builds/A/contract.md"
printf '**Status:** plan-LOCKED\n' > "$SP/.claude/builds/B/progress.md"; printf 'x\n' > "$SP/.claude/builds/B/contract.md"
printf '**Status:** CLOSED\n' > "$SP/.claude/builds/C/progress.md"; printf 'deploy: out-of-scope — internal\n' > "$SP/.claude/builds/C/contract.md"
spc() { cd "$SP" && bash "$SH" ship-contenders "$1" 2>/dev/null; }
[ "$(spc B)" = "A" ]; chk "$?" "0" "P3 ship-contenders B → lists A (progress=CLOSED beats stale INDEX), excludes C(waived)+self"
[ -z "$(spc A)" ]; chk "$?" "0" "P4 ship-contenders A → empty (no other ship-ready)"
( cd "$SP" && bash "$SH" ship-claim A >/dev/null 2>&1 && bash "$SH" ship-claim B >/dev/null 2>&1 ); chk "$?" "1" "P1/P7 A holds lock, B claims (A live) → non-zero (single-flight)"
( cd "$SP" && bash "$SH" ship-claim A >/dev/null 2>&1 ); chk "$?" "0" "P2 A re-claims its own lock → idempotent 0"
# no-steal-on-CLOSED: A is CLOSED (terminal var) but mid-ship → B must NOT steal
( cd "$SP" && bash "$SH" ship-claim B >/dev/null 2>&1 ); chk "$?" "1" "P7b holder A status=CLOSED (live mid-ship) → B refused (no steal on CLOSED)"
# P6 steal when holder SHIPPED
printf 'A · goal · status=SHIPPED · facets=library\nB · goal · status=plan-LOCKED · facets=library\nC · goal · status=closed · facets=library\n' > "$SP/.claude/builds/INDEX"; printf '**Status:** SHIPPED\n' > "$SP/.claude/builds/A/progress.md"
( cd "$SP" && bash "$SH" ship-claim B >/dev/null 2>&1 ); chk "$?" "0" "P6 holder A SHIPPED → B steals stale lock (self-healing, no deadlock)"
( cd "$SP" && bash "$SH" ship-release B >/dev/null 2>&1 ); chk "$?" "0" "ship-release B (holder) → 0"
# P8 (review-build M1): a corrupt lock (empty holder / garbage ts) is stealable — never an un-healable deadlock
mkdir -p "$SP/.claude/builds/.locks/.ship.lock"; printf 'holder=\nts=garbage\n' > "$SP/.claude/builds/.locks/.ship.lock/info"
( cd "$SP" && bash "$SH" ship-claim B >/dev/null 2>&1 ); chk "$?" "0" "P8 corrupt ship lock (empty holder / non-numeric ts) → stealable (no un-healable deadlock)"
( cd "$SP" && bash "$SH" ship-release B >/dev/null 2>&1 )
# P5 loser re-check: post-merge-check non-zero when base advanced AND touches claimed files
RP="$SB/p5"; mkdir -p "$RP"; ( cd "$RP" && git init -q
  git config user.email t@t; git config user.name t
  echo base > f.txt; git add -A; git commit -q -m base
  git clone -q --bare . origin.git
  git remote add origin "$RP/origin.git"; git push -q origin HEAD:main 2>/dev/null )
( cd "$RP" && mkdir -p .claude/builds/.locks
  printf 'L · goal · status=closed · facets=library\n' > .claude/builds/INDEX
  printf 'f.txt\n' > .claude/builds/.locks/L.files
  printf 'base_branch=main\nbase_sha=%s\n' "$(cd "$RP" && git rev-parse HEAD)" > .claude/builds/.locks/L.base
  # advance origin/main touching the claimed file
  git clone -q "$RP/origin.git" wc 2>/dev/null && cd wc && git config user.email t@t && git config user.name t && echo changed >> f.txt && git add -A && git commit -q -m advance && git push -q origin HEAD:main 2>/dev/null )
( cd "$RP" && bash "$SH" post-merge-check L >/dev/null 2>&1 ); chk "$?" "1" "P5 base advanced + touches claimed file → post-merge-check NON-ZERO (loser must integrate+re-verify before ship)"

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

echo "── v0.10.0 --auto autonomous loop (INV-2..INV-8) ─────────────"
LOCKS="$(bash "$SH" state-root 2>/dev/null)/.locks"
# Idempotency: clear any stale v10* lock artifacts (incl. with_lock mutex dirs) from a prior
# interrupted run, so a leftover mutex can't make fire-g2 time out without creating the gate-lock.
rm -rf "$LOCKS"/v10* "$LOCKS"/.gate-v10*.lock "$LOCKS"/.budget-v10*.lock 2>/dev/null || true
mk_auto() { local d="$1"; shift; mkdir -p "$d"; printf '**Status:** Plan LOCKED\n' > "$d/progress.md"; bash "$SH" budget-init "$d" "$@" >/dev/null 2>&1; }

# INV-8 flag exclusivity
bash "$SH" auto-precheck --auto --unattended >/dev/null 2>&1; chk "$?" "1" "INV-8: --auto + --unattended → exit 1 (mutually exclusive)"
bash "$SH" auto-precheck --auto >/dev/null 2>&1;             chk "$?" "0" "INV-8: --auto alone → exit 0 (mode=auto)"
bash "$SH" auto-precheck >/dev/null 2>&1;                    chk "$?" "0" "INV-8: neither flag → exit 0 (gated default)"

# INV-3 budget required
I3="$SB/v10i3"; mkdir -p "$I3"; printf '**Status:** Plan LOCKED\n' > "$I3/progress.md"
bash "$SH" auto-init "$I3" >/dev/null 2>&1;    chk "$?" "1" "INV-3: auto-init with no budget → exit 1 (budget required)"
bash "$SH" budget-check "$I3" >/dev/null 2>&1; chk "$?" "1" "INV-3: budget-check with no budget → exit 1"

# INV-4 ceiling binds (sessions), wall accumulation, lock-safe concurrent bump
I4s="$SB/v10i4s"; mk_auto "$I4s" --sessions 1
bash "$SH" budget-check "$I4s" >/dev/null 2>&1; chk "$?" "1" "INV-4: spent_sessions==ceiling → budget-check exit 1 (ceiling binds)"
I4w="$SB/v10i4w"; mk_auto "$I4w" --wall 5 --sessions 99 --stages 99
NOWP=$(( $(date +%s) - 30 )); sed -i.bak "s/^session_start_ts=.*/session_start_ts=$NOWP/" "$I4w/budget.env"; rm -f "$I4w/budget.env.bak"
bash "$SH" budget-check "$I4w" >/dev/null 2>&1; chk "$?" "1" "INV-4: elapsed 30s > wall ceiling 5s → exit 1 (wall cumulative, not reset — RP-07)"
I4c="$SB/v10i4c"; mk_auto "$I4c" --stages 999
for _ in 1 2 3 4 5; do ( bash "$SH" budget-check "$I4c" --bump-stage >/dev/null 2>&1 ) & done; wait
gotstg="$(sed -nE 's/^spent_stages=//p' "$I4c/budget.env" | tail -1)"
chk "$gotstg" "5" "INV-4: 5 concurrent --bump-stage under with_lock → spent_stages=5 (no lost update — RP-08)"

# INV-2 / INV-2b gate preservation + auto-closed marker
I2="$SB/v10i2"; mk_auto "$I2"; bash "$SH" auto-init "$I2" >/dev/null 2>&1
bash "$SH" can-advance "$I2" >/dev/null 2>&1; chk "$?" "0" "INV-2: clean build → can-advance exit 0"
bash "$SH" fire-g2 "$I2" "invariant failed" >/dev/null 2>&1; chk "$?" "1" "INV-2: fire-g2 → exit 1 (G2 stop)"
bash "$SH" can-advance "$I2" >/dev/null 2>&1; chk "$?" "1" "INV-2: after G2 (gate-lock) → can-advance exit 1 (no advance past gate)"
A1="$SB/v10ac"; full_chain "$A1" review-build; printf -- '- [x] auto-closed: two clean adversarial rounds + all INVARIANTs green\n' >> "$A1/receipts.md"; printf 'deploy: out-of-scope — test\n' > "$A1/contract.md"
bash "$SH" lifecycle-audit "$A1" CLOSED >/dev/null 2>&1; chk "$?" "0" "INV-2b: 'auto-closed:' marker → lifecycle-audit CLOSED exit 0"
A2="$SB/v10so"; full_chain "$A2" review-build --signoff; printf 'deploy: out-of-scope — test\n' > "$A2/contract.md"
bash "$SH" lifecycle-audit "$A2" CLOSED >/dev/null 2>&1; chk "$?" "0" "INV-1: human 'sign-off' marker → lifecycle-audit CLOSED exit 0 (gated path intact)"
A3="$SB/v10no"; full_chain "$A3" review-build; printf 'deploy: out-of-scope — test\n' > "$A3/contract.md"
bash "$SH" lifecycle-audit "$A3" CLOSED >/dev/null 2>&1; chk "$?" "1" "INV-1: review-build with NEITHER marker → lifecycle-audit exit 1 (inverse — RP-06)"

# INV-5/6/7 spawn guards (COMPASS_SPAWN_CMD stub writes a sentinel; never launches claude)
I6="$SB/v10i6"; mk_auto "$I6"; bash "$SH" auto-init "$I6" >/dev/null 2>&1; SENT6="$I6/sentinel"
mkdir -p "$LOCKS/$(basename "$I6").gate-lock"
COMPASS_SPAWN_CMD="sh -c 'echo ok > \"$SENT6\"'" bash "$SH" auto-spawn "$I6" >/dev/null 2>&1; chk "$?" "1" "INV-6: spawn with gate-lock held → refused (exit 1)"
sleep 0.3; { [ -f "$SENT6" ] && r=present || r=absent; }; chk "$r" "absent" "INV-6: gate held → stub NOT invoked (no spawn past a gate)"
rmdir "$LOCKS/$(basename "$I6").gate-lock" 2>/dev/null || true
I5="$SB/v10i5"; mk_auto "$I5"; bash "$SH" auto-init "$I5" >/dev/null 2>&1; SENT5="$I5/sentinel"
bash "$SH" own "$(basename "$I5")" --session "other-session" >/dev/null 2>&1
COMPASS_SPAWN_CMD="sh -c 'echo ok > \"$SENT5\"'" CLAUDE_CODE_SESSION_ID="me" bash "$SH" auto-spawn "$I5" >/dev/null 2>&1; chk "$?" "1" "INV-5: live FOREIGN owner → spawn refused (single-flight)"
rm -f "$LOCKS/$(basename "$I5").owner" 2>/dev/null || true
I7="$SB/v10i7"; mk_auto "$I7" --sessions 1; bash "$SH" auto-init "$I7" >/dev/null 2>&1
COMPASS_SPAWN_CMD="sh -c 'exit 0'" bash "$SH" auto-spawn "$I7" >/dev/null 2>&1; chk "$?" "1" "INV-7: session cap reached (1/1) → spawn refused"
I7b="$SB/v10i7b"; mk_auto "$I7b" --sessions 6; bash "$SH" auto-init "$I7b" >/dev/null 2>&1
COMPASS_SPAWN_CMD="sh -c 'exit 1'" bash "$SH" auto-spawn "$I7b" >/dev/null 2>&1
gotss="$(sed -nE 's/^spent_sessions=//p' "$I7b/budget.env" | tail -1)"
chk "$gotss" "2" "INV-7: spent_sessions incremented (1→2) BEFORE spawn → crash can't hide a session (RP-02)"

# spawn fires when clear + idempotency (RP-12)
I8="$SB/v10i8"; mk_auto "$I8" --sessions 6; bash "$SH" auto-init "$I8" >/dev/null 2>&1; SENT8="$I8/sentinel"
COMPASS_SPAWN_CMD="sh -c 'echo ok > \"$SENT8\"'" bash "$SH" auto-spawn "$I8" >/dev/null 2>&1; chk "$?" "0" "F6: clear build → spawn fires (exit 0)"
COMPASS_SPAWN_CMD="sh -c 'echo ok > \"$I8/sentinel2\"'" bash "$SH" auto-spawn "$I8" >/dev/null 2>&1; chk "$?" "1" "RP-12: recent spawn already recorded → second spawn skipped (idempotent)"

# S3 session-chain validator
I9="$SB/v10i9"; mkdir -p "$I9"; printf '%s|s|build|spawn|0|1|0\n' "$(date +%s)" > "$I9/session-chain.log"
bash "$SH" check-session-chain "$I9" >/dev/null 2>&1; chk "$?" "0" "S3: well-formed chain → valid (exit 0)"
printf 'bad|line|only-3\n' >> "$I9/session-chain.log"
bash "$SH" check-session-chain "$I9" >/dev/null 2>&1; chk "$?" "1" "S3: malformed line (wrong field count) → exit 1"

# ── review-build hardening (RB-01..RB-06) ──
# RB-01: spawn path enforces the WALL ceiling itself (not only the session cap)
RBw="$SB/v10rbw"; mk_auto "$RBw" --wall 5 --sessions 99 --stages 99; bash "$SH" auto-init "$RBw" >/dev/null 2>&1
sed -i.bak "s/^session_start_ts=.*/session_start_ts=$(( $(date +%s) - 30 ))/" "$RBw/budget.env"; rm -f "$RBw/budget.env.bak"
COMPASS_SPAWN_CMD="sh -c 'echo ok > \"$RBw/sentinel\"'" bash "$SH" auto-spawn "$RBw" >/dev/null 2>&1; chk "$?" "1" "RB-01: spawn refused on WALL ceiling (under session cap) — defense-in-depth runaway guard"
sleep 0.2; { [ -f "$RBw/sentinel" ] && r=present || r=absent; }; chk "$r" "absent" "RB-01: wall-exceeded → stub NOT invoked"
# RB-02: corrupt (non-numeric) spent → fail CLOSED, not open
RBc="$SB/v10rbc"; mk_auto "$RBc" --sessions 6; bash "$SH" auto-init "$RBc" >/dev/null 2>&1
sed -i.bak 's/^spent_sessions=.*/spent_sessions=garbage/' "$RBc/budget.env"; rm -f "$RBc/budget.env.bak"
bash "$SH" budget-check "$RBc" >/dev/null 2>&1; chk "$?" "1" "RB-02: corrupt spent_sessions → budget-check fails CLOSED (exit 1)"
COMPASS_SPAWN_CMD="sh -c 'echo ok > \"$RBc/sentinel\"'" bash "$SH" auto-spawn "$RBc" >/dev/null 2>&1; chk "$?" "1" "RB-02: corrupt budget → spawn refused (no fail-open runaway)"
# RB-03: fire-g2 appends a Status banner when progress.md has none
RBg="$SB/v10rbg"; mkdir -p "$RBg"; printf '# progress\n' > "$RBg/progress.md"   # NO **Status:** line
bash "$SH" fire-g2 "$RBg" "test" >/dev/null 2>&1
grep -q '^\*\*Status:\*\* gate-wait-G2' "$RBg/progress.md" && r=1 || r=0; chk "$r" "1" "RB-03: fire-g2 APPENDS the gate-wait-G2 banner when no Status line exists (never silently dropped)"
# RB-04: budget-init twice preserves cumulative spend
RBi="$SB/v10rbi"; mk_auto "$RBi" --sessions 6; bash "$SH" budget-check "$RBi" --bump-stage >/dev/null 2>&1; bash "$SH" budget-check "$RBi" --bump-stage >/dev/null 2>&1
bash "$SH" budget-init "$RBi" --sessions 6 >/dev/null 2>&1
got="$(sed -nE 's/^spent_stages=//p' "$RBi/budget.env" | tail -1)"; chk "$got" "2" "RB-04: budget-init re-call PRESERVES spent_stages (no ceiling-bypass reset)"
# RB-05: can-advance fails closed with no progress.md
RBa="$SB/v10rba"; mkdir -p "$RBa"; bash "$SH" can-advance "$RBa" >/dev/null 2>&1; chk "$?" "1" "RB-05: can-advance with absent progress.md → exit 1 (fail closed)"
# RB-06: INV-6 via the REAL gate path — fire-g2 creates the gate-lock, then spawn is refused
RB6="$SB/v10rb6"; mk_auto "$RB6" --sessions 6; bash "$SH" auto-init "$RB6" >/dev/null 2>&1
bash "$SH" fire-g2 "$RB6" "real-gate" >/dev/null 2>&1
COMPASS_SPAWN_CMD="sh -c 'echo ok > \"$RB6/sentinel\"'" bash "$SH" auto-spawn "$RB6" >/dev/null 2>&1; chk "$?" "1" "RB-06: fire-g2 (real gate path) → subsequent auto-spawn refused (INV-6, integration)"
sleep 0.2; { [ -f "$RB6/sentinel" ] && r=present || r=absent; }; chk "$r" "absent" "RB-06: real gate held → stub NOT invoked"

# RB-07: clock-skew — a FUTURE session_start_ts must NOT under-count wall and bypass the ceiling
RB7="$SB/v10rb7"; mk_auto "$RB7" --wall 8 --sessions 99 --stages 99
sed -i.bak "s/^spent_wall=.*/spent_wall=10/; s/^session_start_ts=.*/session_start_ts=$(( $(date +%s) + 100 ))/" "$RB7/budget.env"; rm -f "$RB7/budget.env.bak"
bash "$SH" budget-check "$RB7" >/dev/null 2>&1; chk "$?" "1" "RB-07: future session_start_ts (clock skew) → elapsed clamped ≥0 → prior 10s>8s ceiling still detected (exit 1)"

rm -rf "$LOCKS"/v10*.gate-lock "$LOCKS"/v10*.owner "$LOCKS"/v10*.blocked 2>/dev/null || true

echo "── v0.11.0 autonomous self-spawn (INV-BC/STAGE/CONTINUABLE/HALT/GATE/TRIGGER/DEGRADE) ──"
# Run ENTIRELY inside a sandbox git repo so all locks/state are isolated from the real ~/.claude
# (the real-process chain test spawns detached children — must never touch the live lock dir).
V="$SB/v11repo"; mkdir -p "$V/.claude/builds"; ( cd "$V" && git init -q && git commit -q --allow-empty -m x 2>/dev/null )
B11="$V/.claude/builds"
mka() { local n="$1"; shift; local d="$B11/$n"; mkdir -p "$d"; printf '**Status:** Plan LOCKED\n' > "$d/progress.md"; ( cd "$V" && bash "$SH" auto-start "$d" "$@" >/dev/null 2>&1 ); }
v11() { ( cd "$V" && bash "$SH" "$@" ); }   # run a compass.sh subcommand with state-root = sandbox

# INV-TRIGGER: auto-start one-command + reject --unattended
mka v11trig --wall 3600 --sessions 6 --stages 40; chk "$([ -f "$B11/v11trig/.auto-mode" ] && echo 1 || echo 0)" "1" "INV-TRIGGER: auto-start wrote .auto-mode marker"
v11 budget-check "$B11/v11trig" >/dev/null 2>&1; chk "$?" "0" "INV-TRIGGER: budget present after auto-start"
v11 auto-start "$B11/v11trig" --unattended >/dev/null 2>&1; chk "$?" "1" "INV-TRIGGER: auto-start --unattended → exit 1 (mutually exclusive)"

# INV-CONTINUABLE: terminal/idle/gate → not continuable; locked-with-PASS+no-ship → continuable
mka v11cont --sessions 6; C="$B11/v11cont"
printf '## RECEIPT — contract · v11cont · PASS\n- [x] x\n' > "$C/receipts.md"
v11 stage-continuable "$C" >/dev/null 2>&1; chk "$?" "0" "INV-CONTINUABLE: contract PASS + no ship → continuable (exit 0)"
printf '**Status:** SHIPPED\n' > "$C/progress.md"
v11 stage-continuable "$C" >/dev/null 2>&1; chk "$?" "1" "INV-CONTINUABLE: SHIPPED → not continuable (exit 1)"
printf '**Status:** Plan LOCKED\n' > "$C/progress.md"; : > "$C/receipts.md"   # no PASS receipt = stuck/never-started
v11 stage-continuable "$C" >/dev/null 2>&1; chk "$?" "1" "INV-CONTINUABLE: no clean PASS receipt → not continuable (exit 1)"
printf '## RECEIPT — contract · v11cont · PASS\n- [x] x\n' > "$C/receipts.md"; v11 fire-g1 "$C" >/dev/null 2>&1
v11 stage-continuable "$C" >/dev/null 2>&1; chk "$?" "1" "INV-CONTINUABLE: gate-lock held → not continuable (exit 1)"
v11 gate-clear "$C" >/dev/null 2>&1

# INV-GATE: G1 lock → spawn refused; gate-clear → G2 takes same lock (no collision); foreign owner → refused
mka v11gate --sessions 6; GA="$B11/v11gate"
v11 fire-g1 "$GA" >/dev/null 2>&1
COMPASS_SPAWN_CMD="sh -c 'echo x > \"$GA/sent\"'" v11 auto-spawn "$GA" >/dev/null 2>&1; chk "$?" "1" "INV-GATE: G1 lock held → auto-spawn refused"
sleep 0.2; chk "$([ -f "$GA/sent" ] && echo present || echo absent)" "absent" "INV-GATE: G1 held → spawn stub NOT invoked"
v11 gate-clear "$GA" >/dev/null 2>&1
v11 fire-g2 "$GA" "x" >/dev/null 2>&1; chk "$?" "1" "INV-GATE: after gate-clear, fire-g2 takes the SAME lock with no collision (fires, exit 1)"
v11 gate-clear "$GA" >/dev/null 2>&1
mka v11foreign --sessions 6; GF="$B11/v11foreign"; v11 own v11foreign --session "other" >/dev/null 2>&1
COMPASS_SPAWN_CMD="sh -c 'echo x'" CLAUDE_CODE_SESSION_ID="me" v11 auto-spawn "$GF" >/dev/null 2>&1; chk "$?" "1" "INV-GATE: live foreign owner → auto-spawn refused (single-flight)"
rm -f "$B11/.locks/v11foreign.owner" 2>/dev/null || true

# INV-DEGRADE: failing spawn command → spawn-failed event + non-zero, no hang
mka v11deg --sessions 6; DG="$B11/v11deg"
COMPASS_SPAWN_CMD="sh -c 'exit 1'" v11 auto-spawn "$DG" >/dev/null 2>&1; chk "$?" "1" "INV-DEGRADE: failing spawn cmd → auto-spawn non-zero"
chk "$(grep -c '|spawn-failed|' "$DG/session-chain.log" 2>/dev/null | tr -d ' ')" "1" "INV-DEGRADE: spawn-failed event recorded (honest, not silent)"

# ★ INV-HALT (the safety centerpiece) — REAL separate OS processes through the lock, no real claude.
# A recursive helper SCRIPT re-invokes `compass.sh auto-spawn` (a genuine separate process re-entering
# the budget lock); the chain self-propagates until the cap REFUSES. Proven across real processes.
mka v11halt --wall 99999 --sessions 4 --stages 999; H="$B11/v11halt"
SEQHELP="$SB/seqhelp.sh"
cat > "$SEQHELP" <<EOF
#!/usr/bin/env bash
# a "session" that (like a real --auto session) tries to spawn the next, carrying the same helper.
cd "$V" && COMPASS_SPAWN_CMD="$SEQHELP" "$SH" auto-spawn "$H" >/dev/null 2>&1 || true
EOF
chmod +x "$SEQHELP"
COMPASS_SPAWN_CMD="$SEQHELP" v11 auto-spawn "$H" >/dev/null 2>&1   # kick off the real-process chain
sleep 1.5   # let the chain self-propagate across real processes
halt_ss="$(sed -nE 's/^spent_sessions=//p' "$H/budget.env" | tail -1)"
chk "$([ "${halt_ss:-0}" -le 4 ] && echo ok || echo "OVER:$halt_ss")" "ok" "★ INV-HALT: real-process self-spawn chain NEVER exceeds session cap (spent_sessions=${halt_ss} ≤ 4)"
COMPASS_SPAWN_CMD="$SEQHELP" v11 auto-spawn "$H" >/dev/null 2>&1; chk "$?" "1" "★ INV-HALT: at the cap, the next real spawn is REFUSED (exit 1)"

# INV-HALT concurrent pressure: N real background processes, 1 slot → exactly 1 wins, no deadlock, fast
mka v11conc --wall 99999 --sessions 2 --stages 999; HC="$B11/v11conc"   # spent=1, cap=2 → 1 slot free
t0=$(date +%s)
for i in 1 2 3 4 5; do ( cd "$V" && COMPASS_SPAWN_CMD="sh -c 'true'" bash "$SH" auto-spawn "$HC" > "$HC/as.$i.log" 2>&1 ) & done; wait
t1=$(date +%s)
conc_ss="$(sed -nE 's/^spent_sessions=//p' "$HC/budget.env" | tail -1)"
chk "$conc_ss" "2" "★ INV-HALT concurrent: 5 parallel real spawns, 1 slot → spent_sessions exactly 2 (1 winner, no lost update)"
chk "$([ $((t1-t0)) -lt 10 ] && echo ok || echo "SLOW:$((t1-t0))s")" "ok" "★ INV-HALT concurrent: batch returns <10s (no lock deadlock; losers refuse in ms)"

# INV-STAGE + INV-BC: the reorder fires the spawn at a NON-build stage in auto, and NOT at all without the marker
SG="$SB/repo11"; mkdir -p "$SG"; ( cd "$SG" && git init -q && git commit -q --allow-empty -m x 2>/dev/null )
mkdir -p "$SG/.claude/builds/sb11" "$SG/.claude/builds/.locks"
printf 'session=sessZ\n' > "$SG/.claude/builds/.locks/sb11.owner"
printf 'sb11 · g · status=plan-LOCKED · facets=library\n' > "$SG/.claude/builds/INDEX"
printf '## RECEIPT — contract · sb11 · PASS\n- [x] x\n## RECEIPT — review-contract · sb11 · PASS\n- [x] x\n## RECEIPT — plan · sb11 · PASS\n- [x] x\n' > "$SG/.claude/builds/sb11/receipts.md"
printf '**Status:** plan-LOCKED\n**Stage:** plan\n**Next:** review-plan\n' > "$SG/.claude/builds/sb11/progress.md"
sgz() { cd "$SG" && printf '%s' '{"session_id":"sessZ","stop_hook_active":false}' | COMPASS_SPAWN_CMD="sh -c 'echo x > \"'"$SG"'/SPAWNED\"'" bash "$SH" stop-guard; }
# without .auto-mode → gated: plan-LOCKED, 0 boxes → NOT mid-build → quiet, and NO spawn (INV-BC)
sgz >/dev/null 2>&1; sleep 0.2
chk "$([ -f "$SG/SPAWNED" ] && echo spawned || echo none)" "none" "INV-BC: no .auto-mode at a non-build stage → spawn NOT attempted (gated path unchanged)"
# with .auto-mode → autonomous: the reorder reaches the spawn path at the plan (non-build) stage (INV-STAGE)
: > "$SG/.claude/builds/sb11/.auto-mode"
bash "$SH" budget-init "$SG/.claude/builds/sb11" --wall 99999 --sessions 6 --stages 99 >/dev/null 2>&1
sgz >/dev/null 2>&1; sleep 0.3
chk "$([ -f "$SG/SPAWNED" ] && echo spawned || echo none)" "spawned" "★ INV-STAGE: .auto-mode at a NON-build stage (plan) → Stop hook REACHES the spawn (the v0.10 bug is fixed)"
# (all v0.11 state lived in the sandbox repos $V/$SG under $SB — auto-removed by the EXIT trap; no real locks touched)

echo "── INV-ENGINEFIX (v0.12.0 S1): mutex-leak class BUG-1/BUG-2/BUG-3 ─────────────"
# All three bugs are the same class: an `exit` (die) inside a with_lock critical section skips
# the RETURN trap and leaks the mutex, deadlocking the NEXT caller into a 30s lock timeout.
# Fixtures assert: the failing call exits non-zero FAST, and an IMMEDIATE second call acquires
# the mutex without timeout (i.e. no leak). Timing bound: >5s ⇒ leaked (timeout is ~30s).
EF="$SB/enginefix"; mkdir -p "$EF"
printf '**Status:** Plan LOCKED\n' > "$EF/progress.md"

# BUG-1/BUG-2 — fire-g1: fires (exit 1), then gate-clear must succeed instantly and remove the lock
T0=$(date +%s)
bash "$SH" fire-g1 "$EF" >/dev/null 2>&1; chk "$?" "1" "INV-ENGINEFIX: fire-g1 fires → exit 1 (gate held)"
bash "$SH" gate-clear "$EF" >/dev/null 2>&1; chk "$?" "0" "INV-ENGINEFIX BUG-1: gate-clear after fire-g1 → exit 0 (no ld-exec crash)"
T1=$(date +%s)
chk "$([ $((T1-T0)) -lt 5 ] && echo fast || echo slow)" "fast" "INV-ENGINEFIX BUG-2: fire-g1 leaked no mutex (gate-clear instant, no 30s timeout)"
chk "$([ -d "$LOCKS/$(basename "$EF").gate-lock" ] && echo held || echo gone)" "gone" "INV-ENGINEFIX BUG-1: gate-lock dir removed by gate-clear (real locks dir, not a vacuous path)"

# BUG-2 — fire-g2 same shape
T0=$(date +%s)
bash "$SH" fire-g2 "$EF" enginefix-test >/dev/null 2>&1; chk "$?" "1" "INV-ENGINEFIX: fire-g2 fires → exit 1"
bash "$SH" gate-clear "$EF" >/dev/null 2>&1; chk "$?" "0" "INV-ENGINEFIX BUG-2: gate-clear after fire-g2 → exit 0"
T1=$(date +%s)
chk "$([ $((T1-T0)) -lt 5 ] && echo fast || echo slow)" "fast" "INV-ENGINEFIX BUG-2: fire-g2 leaked no mutex (instant clear)"

# BUG-3 — budget-check at ceiling: exit 1 with the ceiling message, budget mutex NOT leaked,
# budget.env intact, and an immediate second call also exits 1 fast (would hang ~30s pre-fix).
BF="$SB/enginefix-budget"; mkdir -p "$BF"; printf '**Status:** Plan LOCKED\n' > "$BF/progress.md"
bash "$SH" budget-init "$BF" --wall 99999 --sessions 1 --stages 99 >/dev/null 2>&1
sed -i.bak "s/^spent_sessions=.*/spent_sessions=1/" "$BF/budget.env"; rm -f "$BF/budget.env.bak"
OUT="$(bash "$SH" budget-check "$BF" 2>&1)"; RC=$?
chk "$RC" "1" "INV-ENGINEFIX BUG-3: budget-check at ceiling → exit 1"
chk "$(printf '%s' "$OUT" | grep -c 'ceiling reached')" "1" "INV-ENGINEFIX BUG-3: identical ceiling message preserved (die outside the lock)"
T0=$(date +%s)
bash "$SH" budget-check "$BF" >/dev/null 2>&1; chk "$?" "1" "INV-ENGINEFIX BUG-3: immediate SECOND budget-check → exit 1 (mutex was released)"
T1=$(date +%s)
chk "$([ $((T1-T0)) -lt 5 ] && echo fast || echo slow)" "fast" "INV-ENGINEFIX BUG-3: second call instant — no leaked .budget-*.lock"
grep -q '^ceiling_sessions=1$' "$BF/budget.env"; chk "$?" "0" "INV-ENGINEFIX BUG-3: budget.env intact after at-ceiling refusal"

echo "── INV-GRAMMAR (v0.12.0 S2a): norm_line / hdr_get / ps_open_rows ──────────────"
# Source the engine as a library (source-guard added in S2a) to unit-drive internal helpers.
# Positive fixtures = THIS build's own contract.md (bold house-style headers — the RD-2 class).
GLIB="$SB/grammar"; mkdir -p "$GLIB"
REAL_CONTRACT="$HERE/../../../.claude/builds/loop-eyes-intake-v0-12-13/contract.md"
(
  set -u; source "$SH"
  set +e +o pipefail   # the engine sets -euo pipefail; fixtures intentionally exercise failures
  # norm_line strips every asterisk
  [ "$(norm_line '**post-ship-loop:** on (clean 2 / cap 5)')" = "post-ship-loop: on (clean 2 / cap 5)" ]; echo "N1=$?"
  if [ -f "$REAL_CONTRACT" ]; then
    v="$(hdr_get "$REAL_CONTRACT" post-ship-loop)"; case "$v" in "on (clean 2 / cap 5)"*) echo "H1=0";; *) echo "H1=1";; esac
    v="$(hdr_get "$REAL_CONTRACT" deploy)"; case "$v" in "in scope"*) echo "H2=0";; *) echo "H2=1";; esac
  else
    # CI fallback: authored bold fixtures (same shapes)
    printf '%s\n' '**post-ship-loop:** on (clean 2 / cap 5) — prose' '**deploy:** in scope — x' > "$GLIB/c.md"
    v="$(hdr_get "$GLIB/c.md" post-ship-loop)"; case "$v" in "on (clean 2 / cap 5)"*) echo "H1=0";; *) echo "H1=1";; esac
    v="$(hdr_get "$GLIB/c.md" deploy)"; case "$v" in "in scope"*) echo "H2=0";; *) echo "H2=1";; esac
  fi
  # bold deploy-waiver (the VZ-3 class): hdr_get parses what the old [-*]? grep cannot
  printf '%s\n' '**deploy:** out-of-scope — lib-only' > "$GLIB/w.md"
  v="$(hdr_get "$GLIB/w.md" deploy)"; case "$v" in "out-of-scope"*) echo "H3=0";; *) echo "H3=1";; esac
  # absent key → exit 1
  hdr_get "$GLIB/w.md" observation-channel >/dev/null; echo "H4=$?"
  # ps_open_rows: pinned grammar — count OPEN Crit/Maj PS rows ONLY
  cat > "$GLIB/ledger.md" <<'LEDG'
| PS-1-1 | R1 | CRITICAL | api | broken · cite=INV-X | fix | OPEN |
| PS-1-2 | R1 | MAJOR | ui | drift · cite=INV-Y | fix | CLOSED |
| PS-2-1 | R2 | MINOR | doc | nit · FUTURE | fix | OPEN |
| RC-1 | R1 | CRITICAL | plan | not-a-ps-row | fix | OPEN |
LEDG
  echo "P1=$(ps_open_rows "$GLIB/ledger.md")"
  echo "P2=$(ps_open_rows "$GLIB/does-not-exist.md")"
) > "$GLIB/out.txt" 2>"$GLIB/err.txt"
chk "$(grep -c '^N1=0$' "$GLIB/out.txt")" "1" "INV-GRAMMAR: norm_line deletes every asterisk"
chk "$(grep -c '^H1=0$' "$GLIB/out.txt")" "1" "INV-GRAMMAR: hdr_get parses THIS contract's own bold post-ship-loop header (RD-2 positive)"
chk "$(grep -c '^H2=0$' "$GLIB/out.txt")" "1" "INV-GRAMMAR: hdr_get parses the bold deploy header"
chk "$(grep -c '^H3=0$' "$GLIB/out.txt")" "1" "INV-GRAMMAR: hdr_get parses bold '**deploy:** out-of-scope' (the grep the old pattern misses — VZ-3)"
chk "$(grep -c '^H4=1$' "$GLIB/out.txt")" "1" "INV-GRAMMAR: hdr_get absent key → exit 1"
chk "$(grep -c '^P1=1$' "$GLIB/out.txt")" "1" "INV-GRAMMAR: ps_open_rows counts exactly the OPEN CRITICAL PS row (CLOSED/MINOR/non-PS excluded)"
chk "$(grep -c '^P2=0$' "$GLIB/out.txt")" "1" "INV-GRAMMAR: ps_open_rows missing file → 0 (never crashes)"
# __match surface: whitelist guard both ways (real *_match helpers land with their gates)
bash "$SH" __match not_in_namespace </dev/null >/dev/null 2>&1; chk "$?" "1" "INV-GRAMMAR: __match refuses a non-*_match name (whitelist)"
bash "$SH" __match bogus_match </dev/null >/dev/null 2>&1; chk "$?" "1" "INV-GRAMMAR: __match refuses an unknown *_match helper"
# source-guard: sourcing must NOT run main (no usage output), CLI still works
S_OUT="$(bash -c 'source '"$SH"' >/dev/null 2>&1; echo sourced-ok')"
chk "$S_OUT" "sourced-ok" "INV-GRAMMAR: source-guard — sourcing loads the library without running main"

echo "── INV-PS policy + NOVERIFIER (v0.12.0 S2): postship-required / postship-signal ──"
PSP="$SB/psp"; mkdir -p "$PSP"

# policy matrix (bold house-style headers throughout — hdr_get path, VZ-3)
printf '%s\n' '**deploy:** in scope — x' '**post-ship-loop:** on (clean 2 / cap 5)' > "$PSP/contract.md"
bash "$SH" postship-required "$PSP" >/dev/null 2>&1; chk "$?" "0" "S2 policy: header on → REQUIRED (exit 0)"
printf '%s\n' '**deploy:** in scope — x' '**post-ship-loop:** off — cron-only build' > "$PSP/contract.md"
bash "$SH" postship-required "$PSP" >/dev/null 2>&1; chk "$?" "1" "S2 policy: header off — <reason> → waived (exit 1)"
printf '%s\n' '**deploy:** in scope — x' > "$PSP/contract.md"
bash "$SH" postship-required "$PSP" >/dev/null 2>&1; chk "$?" "1" "S2 policy: header ABSENT → N/A legacy (exit 1, INV-BC)"
printf '%s\n' '**deploy:** out-of-scope — lib-only' '**post-ship-loop:** on (clean 2 / cap 5)' > "$PSP/contract.md"
bash "$SH" postship-required "$PSP" >/dev/null 2>&1; chk "$?" "1" "S2 policy: BOLD deploy-waiver beats an on-header (VZ-3 — the old grep misses this line)"

# INV-PS-NOVERIFIER ×3
PSN="$SB/psn"; mkdir -p "$PSN"
printf '%s\n' '**deploy:** in scope — x' '**post-ship-loop:** on (clean 2 / cap 5)' > "$PSN/contract.md"
ERRV="$(bash "$SH" postship-signal "$PSN" 2>&1 >/dev/null)"; RC=$?
chk "$RC" "1" "INV-PS-NOVERIFIER: none of the four verifiers → exit 1"
chk "$(printf '%s' "$ERRV" | grep -c 'refuse: no-verifier')" "1" "INV-PS-NOVERIFIER: reason code 'refuse: no-verifier' on stderr (P13)"
printf '%s\n' '**deploy:** in scope — x' 'observation-channel: library = bash scripts/smoke.sh' >> "$PSN/contract.md"
bash "$SH" postship-signal "$PSN" >/dev/null 2>&1; chk "$?" "0" "INV-PS-NOVERIFIER: observation-channel ALONE suffices (the new grammar is a sufficient verifier)"
PSR="$SB/psr"; mkdir -p "$PSR"
printf '%s\n' '**deploy:** in scope — x' > "$PSR/contract.md"
printf 'RECON-CMD: bash scripts/recon.sh\n' > "$PSR/receipts.md"
bash "$SH" postship-signal "$PSR" >/dev/null 2>&1; chk "$?" "0" "INV-PS-NOVERIFIER: RECON-CMD alone suffices"

echo "── INV-PS CAP/GROUND/LEDGER/ORDER/STALL/BUDGET (v0.12.0 S3): loop-round ────────"
mkps() { # <dir> [facets] — post-ship fixture factory (bold house-style headers)
  local d="$1" fac="${2:-library}"; mkdir -p "$d"
  printf '%s\n' "**Facets:** $fac" '**deploy:** in scope — x' '**post-ship-loop:** on (clean 2 / cap 5)' \
    'observation-channel: library = bash scripts/digest.sh' > "$d/contract.md"
  : > "$d/receipts.md"; : > "$d/review-ledger.md"
}
wr_round() { # <dir> <round> <verdict> [extra-line]
  { printf '\n## RECEIPT — post-ship-critique · round %s · %s\n' "$2" "$3"
    printf -- '- [x] LIVE-TARGET: fixture-system\n'
    printf -- '- [x] check: `bash scripts/digest.sh` → OK\n'
    [ -n "${4:-}" ] && printf -- '%s\n' "$4"; } >> "$1/receipts.md"
}
wr_obs() { # <dir> <round> [line1]
  mkdir -p "$1/evidence/round-$2"
  printf '%s\nrest of digest\n' "${3:-\`bash scripts/digest.sh\`}" > "$1/evidence/round-$2/observe.txt"
}
mkpng() { # <path> <kb>
  { printf '\x89PNG\r\n\x1a\n'; dd if=/dev/zero bs=1024 count="$2" 2>/dev/null; } > "$1"
}

# happy path non-web CLEAN + loop.log truth
H="$SB/ps-happy"; mkps "$H"; wr_round "$H" 1 CLEAN; wr_obs "$H" 1
bash "$SH" loop-round "$H" postship CLEAN --sig aaaaaaaaaaaa >/dev/null 2>&1
chk "$?" "0" "S3 happy: non-web CLEAN round 1 registers (receipt + observe.txt comparand)"
chk "$(awk -F'|' 'END{print $3"·"$4}' "$H/loop.log")" "1·CLEAN" "S3: loop.log carries round 1 · CLEAN (file-based truth)"

# receipt refusals
E="$SB/ps-receipt"; mkps "$E"; wr_obs "$E" 1
ERR="$(bash "$SH" loop-round "$E" postship CLEAN --sig aaaaaaaaaaaa 2>&1 >/dev/null)"; chk "$?" "1" "S3 refuse: missing round receipt"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: receipt')" "1" "S3 reason code: receipt"
wr_round "$E" 1 CLEAN '- [ ] unchecked box'
ERR="$(bash "$SH" loop-round "$E" postship CLEAN --sig aaaaaaaaaaaa 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: receipt')" "1" "S3 refuse: unchecked box in the round receipt"
E2="$SB/ps-noev"; mkps "$E2"
printf '\n## RECEIPT — post-ship-critique · round 1 · CLEAN\n- [x] LIVE-TARGET: x\n- [x] looks fine to me\n' >> "$E2/receipts.md"; wr_obs "$E2" 1
ERR="$(bash "$SH" loop-round "$E2" postship CLEAN --sig aaaaaaaaaaaa 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: receipt')" "1" "S3 refuse: no checked backtick-command evidence line ('looks fine' cannot register)"

# evidence refusals (non-web comparand mechanic)
V="$SB/ps-ev"; mkps "$V"; wr_round "$V" 1 CLEAN
ERR="$(bash "$SH" loop-round "$V" postship CLEAN --sig aaaaaaaaaaaa 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: evidence')" "1" "S3 refuse: missing observe.txt (empty evidence)"
wr_obs "$V" 1 '\`wrong command\`'
ERR="$(bash "$SH" loop-round "$V" postship CLEAN --sig aaaaaaaaaaaa 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: evidence')" "1" "S3 refuse: observe.txt line-1 comparand mismatch (VF-2 mechanic)"

# web evidence floors + HUMAN-OBSERVED scoping
W="$SB/ps-web"; mkps "$W" "web"; wr_round "$W" 1 CLEAN
ERR="$(bash "$SH" loop-round "$W" postship CLEAN --sig aaaaaaaaaaaa 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: evidence')" "1" "S3 refuse: web round with no PNG"
mkdir -p "$W/evidence/round-1"; mkpng "$W/evidence/round-1/shot.png" 5
ERR="$(bash "$SH" loop-round "$W" postship CLEAN --sig aaaaaaaaaaaa 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: evidence')" "1" "S3 refuse: PNG under the 20KB floor (blank-capture guard)"
mkpng "$W/evidence/round-1/shot.png" 25
bash "$SH" loop-round "$W" postship CLEAN --sig aaaaaaaaaaaa >/dev/null 2>&1
chk "$?" "0" "S3 happy: web CLEAN with a real ≥20KB PNG registers"
WH="$SB/ps-human"; mkps "$WH" "web"; wr_round "$WH" 1 CLEAN '- [x] HUMAN-OBSERVED: "Looks great." (mid-block, any-line rule)'
: > "$WH/.auto-mode"
ERR="$(bash "$SH" loop-round "$WH" postship CLEAN --sig aaaaaaaaaaaa 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: human-observed-auto')" "1" "S3 refuse: HUMAN-OBSERVED under .auto-mode (RC-8 — no fabricated human eyes)"
rm "$WH/.auto-mode"
bash "$SH" loop-round "$WH" postship CLEAN --sig aaaaaaaaaaaa >/dev/null 2>&1
chk "$?" "0" "S3 happy: gated HUMAN-OBSERVED mid-block accepted as the web round's evidence"

# ledger coupling
L="$SB/ps-ledger"; mkps "$L"; wr_round "$L" 1 CLEAN; wr_obs "$L" 1
printf '| PS-1-1 | R1 | CRITICAL | api | broken · cite=INV-X | fix | OPEN |\n' > "$L/review-ledger.md"
ERR="$(bash "$SH" loop-round "$L" postship CLEAN --sig aaaaaaaaaaaa 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: ledger')" "1" "S3 refuse: CLEAN with an open PS Crit/Maj row (verdict↔ledger cannot disagree)"
LM="$SB/ps-ledm"; mkps "$LM"; wr_round "$LM" 1 MATERIAL; wr_obs "$LM" 1
ERR="$(bash "$SH" loop-round "$LM" postship MATERIAL --sig aaaaaaaaaaaa 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: ledger')" "1" "S3 refuse: MATERIAL without a new PS-1-* row"

# order: MATERIAL → fresh ship PASS before next round
O="$SB/ps-order"; mkps "$O"; wr_round "$O" 1 MATERIAL; wr_obs "$O" 1
printf '| PS-1-1 | R1 | MAJOR | x | y · cite=INV-Z | fix | OPEN |\n' > "$O/review-ledger.md"
bash "$SH" loop-round "$O" postship MATERIAL --sig aaaaaaaaaaaa >/dev/null 2>&1
chk "$?" "0" "S3: MATERIAL round 1 registers (PS row present)"
sed -i.bak 's/| OPEN |/| CLOSED |/' "$O/review-ledger.md"; rm -f "$O/review-ledger.md.bak"
wr_round "$O" 2 CLEAN; wr_obs "$O" 2
ERR="$(bash "$SH" loop-round "$O" postship CLEAN --sig bbbbbbbbbbbb 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: order')" "1" "S3 refuse: no fresh ship PASS between MATERIAL round 1 and round 2 (line order)"
printf '\n## RECEIPT — ship · %s · PASS\n- [x] redeployed\n' "$(basename "$O")" >> "$O/receipts.md"
wr_round "$O" 2 CLEAN; wr_obs "$O" 2
bash "$SH" loop-round "$O" postship CLEAN --sig bbbbbbbbbbbb >/dev/null 2>&1
chk "$?" "0" "S3: round 2 registers once a fresh ship PASS sits between the rounds"

# stall: no-progress + nogit skip-positive/degrade
NP="$SB/ps-nop"; mkps "$NP"; wr_round "$NP" 1 MATERIAL; wr_obs "$NP" 1
printf '| PS-1-1 | R1 | MAJOR | x | y · cite=I | fix | OPEN |\n' > "$NP/review-ledger.md"
bash "$SH" loop-round "$NP" postship MATERIAL --sig cccccccccccc >/dev/null 2>&1
sed -i.bak 's/OPEN/CLOSED/' "$NP/review-ledger.md"; rm -f "$NP/review-ledger.md.bak"
printf '\n## RECEIPT — ship · %s · PASS\n- [x] redeployed\n' "$(basename "$NP")" >> "$NP/receipts.md"
wr_round "$NP" 2 MATERIAL; wr_obs "$NP" 2
printf '| PS-2-1 | R2 | MAJOR | x | y · cite=I | fix | OPEN |\n' >> "$NP/review-ledger.md"
ERR="$(bash "$SH" loop-round "$NP" postship MATERIAL --sig cccccccccccc 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: no-progress')" "1" "S3 refuse: MATERIAL with unchanged sig (no-progress)"
NG="$SB/ps-nogit"; mkps "$NG"; wr_round "$NG" 1 CLEAN; wr_obs "$NG" 1
bash "$SH" loop-round "$NG" postship CLEAN --sig nogit >/dev/null 2>&1
wr_round "$NG" 2 MATERIAL; wr_obs "$NG" 2
printf '| PS-2-1 | R2 | MAJOR | x | y · cite=I | fix | OPEN |\n' >> "$NG/review-ledger.md"
bash "$SH" loop-round "$NG" postship MATERIAL --sig nogit >/dev/null 2>&1
chk "$?" "0" "S3 nogit skip-positive: CLEAN@nogit → MATERIAL@nogit REGISTERS (sig-equality skipped — VF-6)"
sed -i.bak 's/OPEN/CLOSED/' "$NG/review-ledger.md"; rm -f "$NG/review-ledger.md.bak"
printf '\n## RECEIPT — ship · %s · PASS\n- [x] redeployed\n' "$(basename "$NG")" >> "$NG/receipts.md"
wr_round "$NG" 3 MATERIAL; wr_obs "$NG" 3
printf '| PS-3-1 | R3 | MAJOR | x | y · cite=I | fix | OPEN |\n' >> "$NG/review-ledger.md"
ERR="$(bash "$SH" loop-round "$NG" postship MATERIAL --sig nogit 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: nogit-stall')" "1" "S3 refuse: 2 consecutive MATERIAL@nogit (degrade replaces sig checks)"

# cap (clean 1 / cap 2 header)
CP="$SB/ps-cap"; mkps "$CP"
sed -i.bak 's/on (clean 2 \/ cap 5)/on (clean 1 \/ cap 2)/' "$CP/contract.md"; rm -f "$CP/contract.md.bak"
wr_round "$CP" 1 CLEAN; wr_obs "$CP" 1; bash "$SH" loop-round "$CP" postship CLEAN --sig s1s1s1s1s1s1 >/dev/null 2>&1
wr_round "$CP" 2 CLEAN; wr_obs "$CP" 2; bash "$SH" loop-round "$CP" postship CLEAN --sig s2s2s2s2s2s2 >/dev/null 2>&1
wr_round "$CP" 3 CLEAN; wr_obs "$CP" 3
ERR="$(bash "$SH" loop-round "$CP" postship CLEAN --sig s3s3s3s3s3s3 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: cap')" "1" "S3 refuse: round 3 exceeds header cap 2 (bounds parsed from header, never hardcoded)"

# budget: loop-round-OWNED under .auto-mode (INV-PS-BUDGET)
BU="$SB/ps-budget"; mkps "$BU"; : > "$BU/.auto-mode"
bash "$SH" budget-init "$BU" --wall 99999 --sessions 99 --stages 99 >/dev/null 2>&1
wr_round "$BU" 1 CLEAN; wr_obs "$BU" 1
SG_BEFORE="$(grep '^spent_stages=' "$BU/budget.env" | cut -d= -f2)"
bash "$SH" loop-round "$BU" postship CLEAN --sig ddddddddddddd >/dev/null 2>&1
SG_AFTER="$(grep '^spent_stages=' "$BU/budget.env" | cut -d= -f2)"
chk "$((SG_AFTER-SG_BEFORE))" "1" "INV-PS-BUDGET: registration under .auto-mode advances spent_stages (loop-round-owned bump)"
sed -i.bak 's/^ceiling_stages=.*/ceiling_stages=1/' "$BU/budget.env"; rm -f "$BU/budget.env.bak"
wr_round "$BU" 2 CLEAN; wr_obs "$BU" 2
T0=$(date +%s); ERR="$(bash "$SH" loop-round "$BU" postship CLEAN --sig eeeeeeeeeeee 2>&1 >/dev/null)"; RC=$?; T1=$(date +%s)
chk "$RC" "1" "INV-PS-BUDGET: at the stage ceiling → registration REFUSED"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: budget')" "1" "INV-PS-BUDGET: reason code budget + fire-g2 instruction"
chk "$([ $((T1-T0)) -lt 5 ] && echo fast || echo slow)" "fast" "INV-PS-BUDGET: ceiling refusal instant (BUG-3 subshell — no mutex hang)"
chk "$(awk -F'|' 'END{print $3}' "$BU/loop.log")" "1" "INV-PS-BUDGET: refused round NOT registered in loop.log"
GB="$SB/ps-gated"; mkps "$GB"; wr_round "$GB" 1 CLEAN; wr_obs "$GB" 1
bash "$SH" loop-round "$GB" postship CLEAN --sig ffffffffffff >/dev/null 2>&1
chk "$([ -f "$GB/budget.env" ] && echo yes || echo no)" "no" "INV-PS-BUDGET: gated build (no .auto-mode) → no bump, no budget.env required"

echo "── INV-PS-TERMINAL + F-CONV (v0.12.0 S4): loop-converged / G-O1 / continuable ──"
mkterm() { # <dir> — postship-required build with full signed chain + prod-verify ship receipt
  local d="$1"; mkps "$d"
  full_chain "$d" ship --signoff
  printf -- '- [x] human sign-off recorded\n' >> "$d/receipts.md"
  printf -- '- [x] prod reconcile: `x` → PASS\n' >> "$d/receipts.md"
}
# converged: 2 trailing CLEAN, 0 open PS
T1="$SB/term-conv"; mkterm "$T1"
printf '1|postship|1|CLEAN|aa|0\n1|postship|2|CLEAN|bb|0\n' > "$T1/loop.log"
bash "$SH" loop-converged "$T1" postship >/dev/null 2>&1; chk "$?" "0" "F-CONV: 2 trailing CLEAN + 0 open PS → converged"
bash "$SH" lifecycle-audit "$T1" SHIPPED >/dev/null 2>&1;  chk "$?" "0" "G-O1: SHIPPED allowed when converged"
# open loop: required + only 1 clean
T2="$SB/term-open"; mkterm "$T2"
printf '1|postship|1|CLEAN|aa|0\n' > "$T2/loop.log"
ERR="$(bash "$SH" loop-converged "$T2" postship 2>&1 >/dev/null)"; chk "$?" "1" "F-CONV: 1/2 clean → refuse"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: clean-run')" "1" "F-CONV reason code: clean-run"
bash "$SH" lifecycle-audit "$T2" SHIPPED >/dev/null 2>&1;  chk "$?" "1" "G-O1: SHIPPED blocked while the loop is open"
# zero rounds: required-but-never-ran
T3="$SB/term-zero"; mkterm "$T3"
bash "$SH" lifecycle-audit "$T3" SHIPPED >/dev/null 2>&1;  chk "$?" "1" "G-O1: required + ZERO rounds → SHIPPED blocked (zero-state)"
# CLEAN,MATERIAL,CLEAN → not converged (consecutive rule)
T4="$SB/term-cmc"; mkterm "$T4"
printf '1|postship|1|CLEAN|aa|0\n1|postship|2|MATERIAL|bb|1\n1|postship|3|CLEAN|cc|0\n' > "$T4/loop.log"
bash "$SH" loop-converged "$T4" postship >/dev/null 2>&1; chk "$?" "1" "F-CONV: CLEAN,MATERIAL,CLEAN → NOT converged (needs CONSECUTIVE clean)"
# waived + legacy pass G-O1 untouched (INV-BC)
T5="$SB/term-waived"; mkterm "$T5"
sed -i.bak 's/^\*\*post-ship-loop:\*\* on.*/**post-ship-loop:** off — fixture waiver/' "$T5/contract.md"; rm -f "$T5/contract.md.bak"
bash "$SH" lifecycle-audit "$T5" SHIPPED >/dev/null 2>&1;  chk "$?" "0" "G-O1: waived (off — reason) → SHIPPED unblocked"
T6="$SB/term-legacy"; mkterm "$T6"
sed -i.bak '/post-ship-loop/d' "$T6/contract.md"; rm -f "$T6/contract.md.bak"
bash "$SH" lifecycle-audit "$T6" SHIPPED >/dev/null 2>&1;  chk "$?" "0" "G-O1: legacy header-less contract → SHIPPED unblocked (INV-BC)"
# user-accepted SET semantics + VOID negative
T7="$SB/term-ua"; mkterm "$T7"
printf '1|postship|1|MATERIAL|aa|1\n' > "$T7/loop.log"
printf '| PS-1-1 | R1 | MAJOR | x | y · cite=I | fix | OPEN |\n' > "$T7/review-ledger.md"
printf 'user-accepted: ship-as-is — PS-1-1 · 2026-07-21T14:00:00Z\n' >> "$T7/receipts.md"
bash "$SH" loop-converged "$T7" postship >/dev/null 2>&1; chk "$?" "0" "F-CONV: user-accepted with open PS ⊆ recorded list → honored"
printf '| PS-2-1 | R2 | CRITICAL | z | later finding | fix | OPEN |\n' >> "$T7/review-ledger.md"
ERR="$(bash "$SH" loop-converged "$T7" postship 2>&1 >/dev/null)"; chk "$?" "1" "F-CONV: PS row OPENED after acceptance → acceptance VOID (P3 negative)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: accepted-void')" "1" "F-CONV reason code: accepted-void"
# is_stage_continuable precedence pair (RD-6) — spawn stubbed by harness convention
T8="$SB/term-cont"; mkterm "$T8"
printf '**Status:** post-ship (round 1/5)\n' > "$T8/progress.md"
( source "$SH"; set +e; is_stage_continuable "$T8" ); chk "$?" "0" "RD-6: status post-ship (round…) + ship PASS receipt → CONTINUABLE (beats the shipped-clean early-return)"
printf '**Status:** SHIPPED (post-ship CONVERGED 3/5)\n' > "$T8/progress.md"
( source "$SH"; set +e; is_stage_continuable "$T8" ); chk "$?" "1" "RD-6: SHIPPED (post-ship CONVERGED …) → terminal, NOT continuable"

echo "── INV-COLDGO (v0.12.0 S5): coldgo-gate ────────────────────────────────────────"
mk_git_sandbox() { # <dir> — real git repo with one commit (P14); prints HEAD sha-12
  mkdir -p "$1"; ( cd "$1" && git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init && git rev-parse --short=12 HEAD )
}
mkcold() { # <build-dir> — web contract with cold-critic on
  mkdir -p "$1"
  printf '%s\n' '**Facets:** web' '**deploy:** in scope — x' 'cold-critic: on' > "$1/contract.md"
  : > "$1/receipts.md"
}
wr_go() { # <build-dir> <GO|NO-GO> <sha> [dirty]
  { printf '\n## RECEIPT — cold-critic · %s · tree=%s\n' "$2" "$3"
    if [ "${4:-}" = dirty ]; then printf -- '- [ ] clean-tree: git status --porcelain empty\n'
    else printf -- '- [x] clean-tree: git status --porcelain empty\n'; fi
    printf -- '- [x] cold screenshots: evidence path named\n'; } >> "$1/receipts.md"
}
CGR="$SB/cg-repo"; SHA="$(mk_git_sandbox "$CGR")"
CG="$CGR/b"; mkcold "$CG"
# streak insufficiency
( cd "$CGR" && bash "$SH" coldgo-gate b ) >/dev/null 2>&1; chk "$?" "1" "INV-COLDGO refuse: zero runs recorded (streak)"
wr_go "$CG" GO "$SHA"; wr_go "$CG" GO "$SHA"
( cd "$CGR" && bash "$SH" coldgo-gate b ) >/dev/null 2>&1; chk "$?" "0" "INV-COLDGO pass: 2 consecutive GOs @ identical sha == HEAD, clean trees"
# sha mismatch between GOs
CM="$CGR/bm"; mkcold "$CM"; wr_go "$CM" GO "aaaaaaaaaaaa"; wr_go "$CM" GO "$SHA"
ERR="$(cd "$CGR" && bash "$SH" coldgo-gate bm 2>&1 >/dev/null)"; chk "$?" "1" "INV-COLDGO refuse: differing shas between GOs (commit resets streak)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: streak')" "1" "INV-COLDGO reason code: streak"
# NO-GO in last 2
CN="$CGR/bn"; mkcold "$CN"; wr_go "$CN" GO "$SHA"; wr_go "$CN" NO-GO "$SHA"
( cd "$CGR" && bash "$SH" coldgo-gate bn ) >/dev/null 2>&1; chk "$?" "1" "INV-COLDGO refuse: NO-GO in the last 2 runs"
# dirty tree
CD="$CGR/bd"; mkcold "$CD"; wr_go "$CD" GO "$SHA" dirty; wr_go "$CD" GO "$SHA" dirty
ERR="$(cd "$CGR" && bash "$SH" coldgo-gate bd 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: dirty-tree')" "1" "INV-COLDGO refuse: unchecked clean-tree box (sha must pin the pixels)"
# stale head (commit after final GO)
CS="$CGR/bs"; mkcold "$CS"; wr_go "$CS" GO "$SHA"; wr_go "$CS" GO "$SHA"
( cd "$CGR" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m later )
ERR="$(cd "$CGR" && bash "$SH" coldgo-gate bs 2>&1 >/dev/null)"; chk "$?" "1" "INV-COLDGO refuse: commit AFTER the final GO (RD-7 staleness)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: stale-head')" "1" "INV-COLDGO reason code: stale-head"
SHA2="$(cd "$CGR" && git rev-parse --short=12 HEAD)"
# HUMAN-GO: without fallback → refuse; with fallback → pass; under .auto-mode → refuse
CH="$CGR/bh"; mkcold "$CH"
printf '\n## RECEIPT — cold-critic · HUMAN-GO · "Looks great." · tree=%s\n- [x] signed off on the phone\n' "$SHA2" >> "$CH/receipts.md"
ERR="$(cd "$CGR" && bash "$SH" coldgo-gate bh 2>&1 >/dev/null)"; chk "$?" "1" "INV-COLDGO refuse: HUMAN-GO without a declared fallback"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: no-fallback')" "1" "INV-COLDGO reason code: no-fallback"
printf 'cold-critic-fallback: human-eyeball\n' >> "$CH/contract.md"
( cd "$CGR" && bash "$SH" coldgo-gate bh ) >/dev/null 2>&1; chk "$?" "0" "INV-COLDGO pass: gated HUMAN-GO with declared fallback @ current HEAD"
: > "$CH/.auto-mode"
ERR="$(cd "$CGR" && bash "$SH" coldgo-gate bh 2>&1 >/dev/null)"; chk "$?" "1" "INV-COLDGO refuse: HUMAN-GO under .auto-mode (VF-4 — mirrors RC-8)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: human-go-auto')" "1" "INV-COLDGO reason code: human-go-auto"
# waiver, non-web, legacy → N/A(0)
CW="$CGR/bw"; mkcold "$CW"; sed -i.bak 's/^cold-critic: on/cold-critic: off — style-only tweak/' "$CW/contract.md"; rm -f "$CW/contract.md.bak"
( cd "$CGR" && bash "$SH" coldgo-gate bw ) >/dev/null 2>&1; chk "$?" "0" "INV-COLDGO: explicit waiver → N/A(0)"
CX="$CGR/bx"; mkdir -p "$CX"; printf '%s\n' '**Facets:** library' 'cold-critic: on' > "$CX/contract.md"; : > "$CX/receipts.md"
( cd "$CGR" && bash "$SH" coldgo-gate bx ) >/dev/null 2>&1; chk "$?" "0" "INV-COLDGO: non-web build → N/A(0) (P4)"
CL="$CGR/bl"; mkdir -p "$CL"; printf '%s\n' '**Facets:** web' > "$CL/contract.md"; : > "$CL/receipts.md"
( cd "$CGR" && bash "$SH" coldgo-gate bl ) >/dev/null 2>&1; chk "$?" "0" "INV-COLDGO: LEGACY header-less web build → N/A(0) (Q7, INV-BC)"

echo "── INV-SUSPEND + F-STATUS (v0.12.0 S6/S6a) ─────────────────────────────────────"
SU="$SB/susp"; mkps "$SU"; : > "$SU/.auto-mode"
bash "$SH" budget-init "$SU" --wall 99999 --sessions 99 --stages 99 >/dev/null 2>&1
# suspend: marker created, .auto-mode KEPT, chain event appended
bash "$SH" auto-suspend "$SU" >/dev/null 2>&1; chk "$?" "0" "INV-SUSPEND: auto-suspend exits 0"
chk "$([ -f "$SU/.auto-suspended" ] && [ -f "$SU/.auto-mode" ] && echo both || echo broken)" "both" "INV-SUSPEND: .auto-suspended created ALONGSIDE .auto-mode (metering stays armed)"
chk "$(grep -c 'auto-suspended' "$SU/session-chain.log")" "1" "INV-SUSPEND: auto-suspended chain event appended"
# spawn dormant at BOTH entry points (COMPASS_SPAWN_CMD stubbed — P18)
SPAWNFLAG="$SB/susp-spawned"
( source "$SH"; set +e; COMPASS_SPAWN_CMD="touch $SPAWNFLAG" _auto_spawn_maybe "$SU" "$(basename "$SU")" "sid-x" "$(locks_dir)" )
chk "$([ -f "$SPAWNFLAG" ] && echo spawned || echo dormant)" "dormant" "INV-SUSPEND: _auto_spawn_maybe dormant while suspended (covers stop-guard AND auto-spawn)"
# metering armed while suspended: loop-round still bumps
wr_round "$SU" 1 CLEAN; wr_obs "$SU" 1
SGB="$(grep '^spent_stages=' "$SU/budget.env" | cut -d= -f2)"
bash "$SH" loop-round "$SU" postship CLEAN --sig abcabcabcabc >/dev/null 2>&1
SGA="$(grep '^spent_stages=' "$SU/budget.env" | cut -d= -f2)"
chk "$((SGA-SGB))" "1" "INV-SUSPEND: metering ARMED while suspended (loop-round still bumps — RD-1)"
# chain stays valid with the new events
bash "$SH" check-session-chain "$SU" >/dev/null 2>&1; chk "$?" "0" "INV-SUSPEND: check-session-chain accepts auto-suspended (vocabulary extended)"
# resume: precondition + positive effects
SV="$SB/susp2"; mkps "$SV"; : > "$SV/.auto-mode"; : > "$SV/.auto-suspended"
bash "$SH" auto-resume "$SV" >/dev/null 2>&1; chk "$?" "1" "INV-SUSPEND: auto-resume REFUSES without declared budget ceilings (auto-init precondition, not flag-precheck)"
bash "$SH" budget-init "$SV" --wall 99999 --sessions 99 --stages 99 >/dev/null 2>&1
bash "$SH" auto-resume "$SV" >/dev/null 2>&1; chk "$?" "0" "INV-SUSPEND: auto-resume exits 0 with ceilings"
chk "$([ -f "$SV/.auto-suspended" ] && echo held || echo gone)" "gone" "INV-SUSPEND: resume removes the marker"
chk "$(grep -c 'auto-resumed' "$SV/session-chain.log")" "1" "INV-SUSPEND: auto-resumed chain event appended"
bash "$SH" check-session-chain "$SV" >/dev/null 2>&1; chk "$?" "0" "INV-SUSPEND: chain valid with BOTH new events"
# F-STATUS: loop line + suspended line
ST="$SB/statfix"; mkps "$ST"; : > "$ST/.auto-suspended"
printf '**Status:** post-ship (round 1/5)\n' > "$ST/progress.md"
printf '1|postship|1|CLEAN|aa|0\n' > "$ST/loop.log"
OUT="$(bash "$SH" status "$ST" 2>/dev/null)"
chk "$(printf '%s' "$OUT" | grep -c 'Post-ship: round 1/5 · consecutive-clean 1/2 · open PS 0')" "1" "F-STATUS: post-ship loop line rendered from loop.log + header bounds"
chk "$(printf '%s' "$OUT" | grep -c 'auto: SUSPENDED (driver)')" "1" "F-STATUS: suspended line rendered from marker presence"

echo "── INV-RECON (v0.12.0 S8b): compass.recon.sh negative fixtures (stubbed suites) ──"
RC="$HERE/compass.recon.sh"
mkstub() { # <file> <tail-line> [names]
  { echo '#!/bin/sh'; [ -n "${3:-}" ] && printf 'echo "%s"\n' "$3"; printf 'echo "%s"\n' "$2"; } > "$1"; chmod +x "$1"
}
NAMES12="INV-ENGINEFIX INV-GRAMMAR INV-PS-NOVERIFIER INV-PS-BUDGET INV-COLDGO INV-SUSPEND F-CONV F-STATUS INV-INTAKE INV-SKETCH INV-TEMPLATES INV-WIRED"
ST_OK="$SB/st-ok.sh"; mkstub "$ST_OK" "selftest: 118 passed, 0 failed" "$NAMES12"
SM_OK="$SB/sm-ok.sh"; mkstub "$SM_OK" "──────── 60 passed, 0 failed ────────"
COMPASS_RECON_SELFTEST_CMD="$ST_OK" COMPASS_RECON_SMOKE_CMD="$SM_OK" bash "$RC" >/dev/null 2>&1
chk "$?" "0" "INV-RECON: healthy stubbed tails + all pinned names → PASS"
ST_LOW="$SB/st-low.sh"; mkstub "$ST_LOW" "selftest: 117 passed, 0 failed" "$NAMES12"
ERR="$(COMPASS_RECON_SELFTEST_CMD="$ST_LOW" COMPASS_RECON_SMOKE_CMD="$SM_OK" bash "$RC" 2>&1 >/dev/null)"; RCC=$?
chk "$RCC" "1" "INV-RECON refuse: selftest 117 < floor 118"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: floor-selftest')" "1" "INV-RECON reason code: floor-selftest"
SM_LOW="$SB/sm-low.sh"; mkstub "$SM_LOW" "──────── 59 passed, 0 failed ────────"
ERR="$(COMPASS_RECON_SELFTEST_CMD="$ST_OK" COMPASS_RECON_SMOKE_CMD="$SM_LOW" bash "$RC" 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: floor-smoke')" "1" "INV-RECON refuse+code: smoke 59 < floor 60"
ST_NONAME="$SB/st-noname.sh"; mkstub "$ST_NONAME" "selftest: 118 passed, 0 failed" "INV-ENGINEFIX INV-GRAMMAR"
ERR="$(COMPASS_RECON_SELFTEST_CMD="$ST_NONAME" COMPASS_RECON_SMOKE_CMD="$SM_OK" bash "$RC" 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: inv-missing')" "1" "INV-RECON refuse+code: a pinned INV group name absent"
ST_X="$SB/st-cross.sh"; mkstub "$ST_X" "──────── 200 passed, 0 failed ────────"
ERR="$(COMPASS_RECON_SELFTEST_CMD="$ST_X" COMPASS_RECON_SMOKE_CMD="$SM_OK" bash "$RC" 2>&1 >/dev/null)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: cross-match')" "1" "INV-RECON refuse+code: smoke-shaped count in the selftest channel (cross-match guard)"

echo "── INV-INTAKE (v0.13.0 S10): intake-gate / intake-phase / cmd_gate seam ────────"
mkintake() { # <dir> — clean FULL co-construct fixture (bold headers; ladder synced 2/1/1)
  local d="$1"; mkdir -p "$d"
  cat > "$d/contract.md" <<'EOC'
**Facets:** library
**deploy:** in scope — x
**intake:** co-construct-v1
sketch: out-of-scope — engine-only fixture (no UI, logic map exercised by INV-SKETCH)

## Scope ladder
- NOW: alpha
- NOW: beta
- LATER: gamma
- NEVER: delta
EOC
  cat > "$d/intake.md" <<'EOI'
MODE: FULL (approved via AskUserQuestion)
COVERAGE: functional=CLEAR data=CLEAR
PHASE 0 DONE · t0
Q: why now? → A: recurring pain in prod
Q: success anchor? → A: last month's incident never repeats
PHASE 1 DONE · t1
GEN premortem: OPT fails silently on empty input → NOW
GEN premortem: OPT budget overrun kills adoption → LATER
GEN relax: OPT if latency were free, stream everything → NEVER
GEN relax: OPT batch nightly instead → LATER
GEN 10x: OPT make it the default for every build → NOW
GEN 10x: OPT SaaS it → NEVER
GEN adjacent: OPT same engine for docs builds → LATER
GEN adjacent: OPT internal audit tool → LATER
PHASE 2 DONE · t2
SCOPE NOW: alpha
SCOPE NOW: beta
SCOPE LATER: gamma
SCOPE NEVER: delta
PHASE 3 DONE · t3
Q: auth model? → A: env-token
Q: rollback? → A: git revert
PHASE 4 DONE · t4
PHASE 5 DONE · t5
EOI
  printf '\n## RECEIPT — contract · fix · PASS\n- [x] done\n' > "$d/receipts.md"
}
IN="$SB/in-clean"; mkintake "$IN"
bash "$SH" intake-gate "$IN" >/dev/null 2>&1; chk "$?" "0" "INV-INTAKE: clean FULL interview → PASS"
bash "$SH" gate "$IN" contract >/dev/null 2>&1; chk "$?" "0" "INV-INTAKE: cmd_gate contract seam passes on a clean interview (behavioral)"
chk "$(bash "$SH" intake-phase "$IN" 2>/dev/null)" "5" "INV-INTAKE: intake-phase prints the resume pointer (5)"
# ladder mismatch → gate <dir> contract FAILS (behavioral seam proof)
IB="$SB/in-ladder"; mkintake "$IB"; printf 'SCOPE NOW: extra-only-in-intake\n' >> "$IB/intake.md"
ERR="$(bash "$SH" intake-gate "$IB" 2>&1 >/dev/null)"; chk "$?" "1" "INV-INTAKE refuse: ladder count mismatch (G-I5, count-equality only)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: ladder')" "1" "INV-INTAKE reason code: ladder"
bash "$SH" gate "$IB" contract >/dev/null 2>&1; chk "$?" "1" "INV-INTAKE: cmd_gate contract seam FAILS when intake-gate fails (INV-WIRED behavioral)"
# evidential G-I6: re-gate under .auto-mode PASSES (the RC-6 brick-scenario)
: > "$IN/.auto-mode"
bash "$SH" intake-gate "$IN" >/dev/null 2>&1; chk "$?" "0" "INV-INTAKE: re-gate with .auto-mode present PASSES (G-I6 is evidential, not temporal)"
rm -f "$IN/.auto-mode"
# classic bypass + legacy N/A
IC="$SB/in-classic"; mkintake "$IC"; sed -i.bak 's/\*\*intake:\*\* co-construct-v1/**intake:** classic/' "$IC/contract.md"; rm -f "$IC/contract.md.bak"; rm "$IC/intake.md"
bash "$SH" intake-gate "$IC" >/dev/null 2>&1; chk "$?" "0" "INV-INTAKE: 'intake: classic' bypasses (auto degrade path)"
IL="$SB/in-legacy"; mkdir -p "$IL"; printf '**Facets:** library\n' > "$IL/contract.md"; printf '\n## RECEIPT — contract · fix · PASS\n- [x] done\n' > "$IL/receipts.md"
bash "$SH" intake-gate "$IL" >/dev/null 2>&1; chk "$?" "0" "INV-INTAKE: legacy (no declaration, no intake.md) → N/A(0)"
bash "$SH" gate "$IL" contract >/dev/null 2>&1; chk "$?" "0" "INV-INTAKE: cmd_gate on a legacy build byte-identical (INV-BC)"
# G-I1 mode + phase order
IM="$SB/in-mode"; mkintake "$IM"; sed -i.bak '/^MODE:/d' "$IM/intake.md"; rm -f "$IM/intake.md.bak"
ERR="$(bash "$SH" intake-gate "$IM" 2>&1 >/dev/null)"; chk "$(printf '%s' "$ERR" | grep -c 'refuse: mode')" "1" "INV-INTAKE refuse: missing MODE line (G-I1)"
IP="$SB/in-phase"; mkintake "$IP"; sed -i.bak '/^PHASE 2 DONE/d' "$IP/intake.md"; rm -f "$IP/intake.md.bak"
ERR="$(bash "$SH" intake-gate "$IP" 2>&1 >/dev/null)"; chk "$(printf '%s' "$ERR" | grep -c 'refuse: phase-order')" "1" "INV-INTAKE refuse: out-of-order/missing PHASE markers (G-I1)"
# G-I2 generators
IG="$SB/in-gen"; mkintake "$IG"; sed -i.bak '/^GEN adjacent/d' "$IG/intake.md"; rm -f "$IG/intake.md.bak"
ERR="$(bash "$SH" intake-gate "$IG" 2>&1 >/dev/null)"; chk "$(printf '%s' "$ERR" | grep -c 'refuse: generators')" "1" "INV-INTAKE refuse: a generator missing its ≥2 disposed options (G-I2)"
# G-I3 all-NOW
I3="$SB/in-allnow"; mkintake "$I3"
sed -i.bak -e 's/→ LATER$/→ NOW/' -e 's/→ NEVER$/→ NOW/' -e 's/^SCOPE LATER: gamma/SCOPE NOW: gamma/' -e 's/^SCOPE NEVER: delta/SCOPE NOW: delta/' "$I3/intake.md"; rm -f "$I3/intake.md.bak"
sed -i.bak -e 's/^- LATER: gamma/- NOW: gamma/' -e 's/^- NEVER: delta/- NOW: delta/' "$I3/contract.md"; rm -f "$I3/contract.md.bak"
ERR="$(bash "$SH" intake-gate "$I3" 2>&1 >/dev/null)"; chk "$(printf '%s' "$ERR" | grep -c 'refuse: rejection')" "1" "INV-INTAKE refuse: all-NOW ledger (G-I3 HARD — decision 5)"
# G-I4 budget
I4="$SB/in-budget"; mkintake "$I4"
sed -i.bak 's/^PHASE 4 DONE · t4/Q: q3? → A: a\nQ: q4? → A: a\nQ: q5? → A: a\nPHASE 4 DONE · t4/' "$I4/intake.md"; rm -f "$I4/intake.md.bak"
ERR="$(bash "$SH" intake-gate "$I4" 2>&1 >/dev/null)"; chk "$(printf '%s' "$ERR" | grep -c 'refuse: budget')" "1" "INV-INTAKE refuse: 5 Phase-4 questions > FULL cap 4 (G-I4)"
# G-I6 answers
I6="$SB/in-noans"; mkintake "$I6"; sed -i.bak 's/→ A: [^→]*$/→ A: /' "$I6/intake.md"; rm -f "$I6/intake.md.bak"
ERR="$(bash "$SH" intake-gate "$I6" 2>&1 >/dev/null)"; chk "$(printf '%s' "$ERR" | grep -c 'refuse: answers')" "1" "INV-INTAKE refuse: zero recorded answers (G-I6 evidential)"

echo "── INV-SKETCH (v0.13.0 S11): sketch-gate + first-line leak tracer ──────────────"
SKR="$SB/sk-repo"; mk_git_sandbox "$SKR" >/dev/null
mksk() { # <build-dir> <facets>
  mkdir -p "$1/sketch"
  printf '%s\n' "**Facets:** $2" '**deploy:** in scope — x' '**intake:** co-construct-v1' > "$1/contract.md"
  printf 'v1 · t · decision=layout · alternatives=A,B · picked=A · render=local · file=sketch/mock-v1.html\n' > "$1/sketch/LEDGER"
  printf '\n## RECEIPT — contract · fix · PASS\n- [x] done\n' > "$1/receipts.md"
}
# legacy N/A + escape N/A
SL="$SKR/sk-legacy"; mkdir -p "$SL"; printf '**Facets:** web\n' > "$SL/contract.md"
( cd "$SKR" && bash "$SH" sketch-gate sk-legacy ) >/dev/null 2>&1; chk "$?" "0" "INV-SKETCH: legacy (no triggers) → N/A(0)"
SE="$SKR/sk-esc"; mksk "$SE" web; printf 'sketch: out-of-scope — tiny copy tweak\n' >> "$SE/contract.md"
( cd "$SKR" && bash "$SH" sketch-gate sk-esc ) >/dev/null 2>&1; chk "$?" "0" "INV-SKETCH: explicit out-of-scope escape → N/A(0)"
# web: mockup path (marker line-1 + banner)
SW="$SKR/sk-web"; mksk "$SW" web
printf '<!-- COMPASS-MOCK slug=sk-web v=1 throwaway=true -->\n<div>THROWAWAY WIREFRAME — critique structure, not polish</div>\n' > "$SW/sketch/mock-v1.html"
printf 'mockup: sketch/mock-v1.html (ACCEPTED v1)\n' >> "$SW/contract.md"
( cd "$SKR" && bash "$SH" sketch-gate sk-web ) >/dev/null 2>&1; chk "$?" "0" "INV-SKETCH: web + accepted mockup (line-1 marker + banner) → PASS"
sed -i.bak 's/THROWAWAY WIREFRAME[^<]*//' "$SW/sketch/mock-v1.html"; rm -f "$SW/sketch/mock-v1.html.bak"
ERR="$(cd "$SKR" && bash "$SH" sketch-gate sk-web 2>&1 >/dev/null)"; chk "$(printf '%s' "$ERR" | grep -c 'refuse: mockup')" "1" "INV-SKETCH refuse: banner stripped from the mockup"
# web: design-standard path (decision 6)
SD="$SKR/sk-std"; mksk "$SD" web; printf 'design-standard: rk-house-style\n' >> "$SD/contract.md"
( cd "$SKR" && bash "$SH" sketch-gate sk-std ) >/dev/null 2>&1; chk "$?" "0" "INV-SKETCH: web + named design-standard (no mockup) → PASS (decision 6 both paths)"
# web: neither
SN="$SKR/sk-none"; mksk "$SN" web
ERR="$(cd "$SKR" && bash "$SH" sketch-gate sk-none 2>&1 >/dev/null)"; chk "$(printf '%s' "$ERR" | grep -c 'refuse: mockup')" "1" "INV-SKETCH refuse: applicable web build with neither mockup nor design-standard"
# non-web logic map (RD-9)
SP="$SKR/sk-pipe"; mksk "$SP" library
ERR="$(cd "$SKR" && bash "$SH" sketch-gate sk-pipe 2>&1 >/dev/null)"; chk "$(printf '%s' "$ERR" | grep -c 'refuse: logicmap')" "1" "INV-SKETCH refuse: non-web co-construct without a Logic Map (RD-9)"
printf '\n## Logic Map\n```mermaid\nflowchart LR\n  a --> b\n```\n' >> "$SP/contract.md"
( cd "$SKR" && bash "$SH" sketch-gate sk-pipe ) >/dev/null 2>&1; chk "$?" "0" "INV-SKETCH: non-web with a mermaid Logic Map fence → PASS"
# missing LEDGER
SG2="$SKR/sk-noledger"; mksk "$SG2" library; rm "$SG2/sketch/LEDGER"
printf '\n## Logic Map\n```mermaid\nflowchart LR\n  a --> b\n```\n' >> "$SG2/contract.md"
ERR="$(cd "$SKR" && bash "$SH" sketch-gate sk-noledger 2>&1 >/dev/null)"; chk "$(printf '%s' "$ERR" | grep -c 'refuse: ledger')" "1" "INV-SKETCH refuse: no sketch/LEDGER render line"
# leak tracer: line-1 marker in a TRACKED file → FAIL; mid-file mention → PASS
printf '<!-- COMPASS-MOCK slug=leaked v=3 throwaway=true -->\n<div>oops shipped</div>\n' > "$SKR/leaked.html"
( cd "$SKR" && git add leaked.html && git -c user.email=t@t -c user.name=t commit -qm leak )
ERR="$(cd "$SKR" && bash "$SH" sketch-gate sk-pipe 2>&1 >/dev/null)"; chk "$?" "1" "INV-SKETCH refuse: tracked file with LINE-1 COMPASS-MOCK marker (leak tracer)"
chk "$(printf '%s' "$ERR" | grep -c 'refuse: leak')" "1" "INV-SKETCH reason code: leak"
( cd "$SKR" && git rm -q leaked.html && printf '# doc\nthe marker string <!-- COMPASS-MOCK slug=x --> may be MENTIONED mid-file\n' > doc.md && git add doc.md && git -c user.email=t@t -c user.name=t commit -qm doc )
( cd "$SKR" && bash "$SH" sketch-gate sk-pipe ) >/dev/null 2>&1; chk "$?" "0" "INV-SKETCH: mid-file mention in a tracked doc → PASS (first-line anchor, no self-trip)"
# cmd_gate review-build seam behavioral (leak → gate fails)
printf '<!-- COMPASS-MOCK slug=leak2 v=1 throwaway=true -->\n' > "$SKR/leak2.html"
( cd "$SKR" && git add leak2.html && git -c user.email=t@t -c user.name=t commit -qm leak2 )
printf '\n## RECEIPT — review-build · fix · PASS\n- [x] done\n' >> "$SP/receipts.md"
( cd "$SKR" && bash "$SH" gate sk-pipe review-build ) >/dev/null 2>&1; chk "$?" "1" "INV-SKETCH: cmd_gate review-build seam FAILS on a line-1 leak (INV-WIRED behavioral)"

echo
echo "selftest: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
