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
bash "$SH" lifecycle-audit "$SS" >/dev/null 2>&1; chk "$?" "0" "INV-5 waiver: deploy out-of-scope → PASS"

echo "── stop-guard (INV-6) ────────────────────────────────────────"
# isolated throwaway git repo so state_root/INDEX are sandboxed
G="$SB/repo"; mkdir -p "$G"; ( cd "$G" && git init -q && git commit -q --allow-empty -m x 2>/dev/null )
mkdir -p "$G/.claude/builds/midbuild"
printf 'midbuild · goal · status=plan-LOCKED · facets=library\n' > "$G/.claude/builds/INDEX"
printf '## RECEIPT — contract · midbuild · PASS\n- [x] x\n' > "$G/.claude/builds/midbuild/receipts.md"
printf '**Status:** plan-LOCKED\n**Stage:** plan\n**Next:** build\n' > "$G/.claude/builds/midbuild/progress.md"
OUT="$(cd "$G" && echo '{"stop_hook_active":false}' | bash "$SH" stop-guard)"
printf '%s' "$OUT" | grep -q '"decision":"block"'; chk "$?" "0" "INV-6 mid-lifecycle → block"
OUT="$(cd "$G" && echo '{"stop_hook_active":true}' | bash "$SH" stop-guard)"
printf '%s' "$OUT" | grep -q '"decision":"block"'; chk "$?" "1" "INV-6 loop-guard: stop_hook_active=true → NO block (anti-deadlock)"
# terminal status → no block
printf 'midbuild · goal · status=SHIPPED · facets=library\n' > "$G/.claude/builds/INDEX"
printf '**Status:** SHIPPED\n' > "$G/.claude/builds/midbuild/progress.md"
OUT="$(cd "$G" && echo '{"stop_hook_active":false}' | bash "$SH" stop-guard)"
printf '%s' "$OUT" | grep -q '"decision":"block"'; chk "$?" "1" "INV-6 terminal (SHIPPED) → NO block"
# RB-02 fail-open: outside a git repo the hook must not crash (set -e would otherwise propagate state_root's exit)
NG="$(mktemp -d)"; ( cd "$NG" && echo '{"stop_hook_active":false}' | bash "$SH" stop-guard >/dev/null 2>&1 ); chk "$?" "0" "INV-6 fail-open: stop-guard outside a git repo → exit 0 (RB-02, never crash)"

echo "── no-regression + old-misses baseline (INV-7) ───────────────"
# migration-gate no-op for schema-touching:no
NS="$SB/noschema"; mkdir -p "$NS"; printf 'schema-touching: no\n' > "$NS/contract.md"
bash "$SH" migration-gate "$NS" >/dev/null 2>&1; chk "$?" "0" "INV-7 no-op: schema-touching:no → N/A PASS"
# lifecycle-audit clean complete build (deploy waived) → PASS
bash "$SH" lifecycle-audit "$SS" >/dev/null 2>&1; chk "$?" "0" "INV-7 no-op: complete+waived build → PASS"
# OLD MISSES: the soft-pass ship receipt's LAST block is a clean PASS → existing scan-receipt does NOT catch it
bash "$SH" scan-receipt "$SPok" ship >/dev/null 2>&1
echo "  note  OLD MISSES — existing 'scan-receipt ship' on a clean-looking ship receipt exits $? (passes); only lifecycle-audit ties SHIPPED status to a CHECKED prod-verify."

echo
echo "selftest: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
