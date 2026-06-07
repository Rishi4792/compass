#!/usr/bin/env bash
# Compass enforcement CLI — the real teeth.
# Deterministic checks over .claude/builds/<slug>/receipts.md and friends.
# Every subcommand exits NON-ZERO on failure, so a skill that runs it cannot
# proceed past a missing/failed/stale proof. This is what makes the gate real
# rather than prose the model grades itself against.
#
# Usage:
#   compass.sh gate         <build-dir> <prior-stage>      # block unless prior stage's latest receipt is PASS, complete, not superseded
#   compass.sh scan-receipt <build-dir> <stage>            # self-check the stage's latest receipt: PASS + no empty box
#   compass.sh supersede    <build-dir> <from-stage>       # on escalation/re-run: void from-stage and all later receipts
#   compass.sh reconcile    <actual> <gold> <tol>          # numeric gate; tol like 0, 0.1, or 1%
#   compass.sh secret-scan  <build-dir> [files...]         # fail if a secret looks committed (diff or given files)
#   compass.sh close         <build-dir> <slug>            # clear CURRENT so a closed build can't leak its gate
#
# Lifecycle order (used by gate freshness + supersede):
#   contract review-contract plan review-plan build review-build ship
set -euo pipefail

LIFECYCLE="contract review-contract plan review-plan build review-build ship"

die() { echo "COMPASS-GATE: FAIL — $*" >&2; exit 1; }
ok()  { echo "COMPASS-GATE: PASS — $*"; }

# Print the body of the LAST receipt block whose header names $stage.
# A block starts at a line "## RECEIPT — <stage> · ..." and runs until the next "## " or EOF.
last_block() { # <file> <stage>
  awk -v s="$2" '
    $0 ~ ("^## RECEIPT[ ]*[—-][ ]*" s "[ ]*[·|]") { buf=$0 "\n"; cap=1; next }
    cap && /^## / { last=buf; cap=0 }
    cap { buf=buf $0 "\n" }
    END { if (cap) last=buf; printf "%s", last }
  ' "$1"
}

cmd_gate() { # <build-dir> <prior-stage>
  local dir="$1" stage="$2" f="$1/receipts.md"
  [ -f "$f" ] || die "no receipts.md in $dir — prior stage '$stage' never ran. Start at the right earlier stage."
  local block; block="$(last_block "$f" "$stage")"
  [ -n "$block" ] || die "no receipt for '$stage' — it has not completed. Run compass:$stage first."
  local header; header="$(printf '%s' "$block" | head -n1)"
  case "$header" in
    *SUPERSEDED*) die "'$stage' receipt is SUPERSEDED (an escalation/re-run voided it). Re-run compass:$stage." ;;
    *·\ PASS*|*"· PASS"*|*"PASS"*) : ;;
    *) die "'$stage' latest receipt is not PASS: $header" ;;
  esac
  if printf '%s' "$block" | grep -q '^\- \[ \]'; then
    die "'$stage' receipt has an UNCHECKED box — its work is incomplete:
$(printf '%s' "$block" | grep '^\- \[ \]')"
  fi
  ok "prior stage '$stage' receipt present, PASS, complete, not superseded."
}

cmd_scan_receipt() { # <build-dir> <stage>
  local dir="$1" stage="$2" f="$1/receipts.md"
  [ -f "$f" ] || die "no receipts.md — emit the $stage receipt first."
  local block; block="$(last_block "$f" "$stage")"
  [ -n "$block" ] || die "no $stage receipt found to scan."
  if printf '%s' "$block" | grep -q '^\- \[ \]'; then
    die "$stage receipt still has unchecked boxes — set status FAIL and do not hand on:
$(printf '%s' "$block" | grep '^\- \[ \]')"
  fi
  printf '%s' "$block" | head -n1 | grep -q 'PASS' || die "$stage receipt is not marked PASS."
  ok "$stage receipt self-check: PASS, all boxes filled."
}

cmd_supersede() { # <build-dir> <from-stage>
  local dir="$1" from="$2" f="$1/receipts.md"; local hit=0
  [ -f "$f" ] || die "no receipts.md to supersede in $dir"
  for s in $LIFECYCLE; do
    if [ "$s" = "$from" ]; then hit=1; fi
    if [ "$hit" = 1 ]; then
      printf '\n## RECEIPT — %s · (auto) · SUPERSEDED (re-run required after escalation to %s)\n' "$s" "$from" >> "$f"
    fi
  done
  ok "superseded '$from' and all later receipts — they must re-run."
}

cmd_reconcile() { # <actual> <gold> <tol>
  local actual="$1" gold="$2" tol="$3"
  printf '%s\n' "$actual $gold $tol" | awk '
    { a=$1; g=$2; t=$3; rel=0
      if (t ~ /%$/) { sub(/%$/,"",t); rel=1 }
      d=a-g; if (d<0) d=-d
      lim = rel ? (g<0?-g:g)*t/100.0 : t
      if (d<=lim) { printf "RECONCILE: actual=%s gold=%s tol=%s diff=%.6g PASS\n", a, g, $3, d; exit 0 }
      else        { printf "RECONCILE: actual=%s gold=%s tol=%s diff=%.6g FAIL\n", a, g, $3, d; exit 1 }
    }' || die "reconciliation FAILED — actual=$actual vs gold=$gold exceeds tolerance $tol. Build cannot close."
  ok "reconciliation within tolerance."
}

cmd_secret_scan() { # <build-dir> [files...]
  shift_dir="$1"; shift || true
  local pat='(-----BEGIN [A-Z ]*PRIVATE KEY|eyJ[A-Za-z0-9_-]{10,}\.|sk-[A-Za-z0-9]{16,}|postgres(ql)?://[^ ]*:[^ @]*@|[A-Za-z0-9_]*_SECRET\s*=\s*["'"'"'][^"'"'"' ]+|AKIA[0-9A-Z]{12,}|xox[baprs]-[0-9A-Za-z-]+)'
  local target="$*"
  local found=""
  if [ -n "$target" ]; then
    found="$(grep -REnI "$pat" $target 2>/dev/null || true)"
  elif command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    local files; files="$(git diff --name-only HEAD 2>/dev/null; git diff --name-only --cached 2>/dev/null)"
    [ -n "$files" ] && found="$(printf '%s\n' "$files" | sort -u | xargs -I{} sh -c 'test -f "{}" && grep -EnI "'"$pat"'" "{}" | sed "s#^#{}:#"' 2>/dev/null || true)"
  fi
  if [ -n "$found" ]; then
    die "possible secret committed — remove it / read from env instead:
$found"
  fi
  ok "secret scan: 0 hits."
}

cmd_close() { # <build-dir> <slug>
  local dir="$1" slug="$2"
  local builds_root; builds_root="$(cd "$dir/.." && pwd)"
  if [ -f "$builds_root/CURRENT" ] && [ "$(cat "$builds_root/CURRENT" 2>/dev/null)" = "$slug" ]; then
    : > "$builds_root/CURRENT"
  fi
  ok "build '$slug' closed; CURRENT cleared."
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    gate)         cmd_gate "$@" ;;
    scan-receipt) cmd_scan_receipt "$@" ;;
    supersede)    cmd_supersede "$@" ;;
    reconcile)    cmd_reconcile "$@" ;;
    secret-scan)  cmd_secret_scan "$@" ;;
    close)        cmd_close "$@" ;;
    *) echo "compass.sh: unknown subcommand '$sub'" >&2; exit 2 ;;
  esac
}
main "$@"
