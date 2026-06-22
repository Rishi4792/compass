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

echo
echo "selftest: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
