#!/usr/bin/env bash
# v0.31 INV-6 — the INDEPENDENT recount.
#
# Counts findings/steps/invariants straight from the source files and compares against what each
# page STATES. Written in python, deliberately: the generator's readers are JavaScript, and a
# recount that shared their code would agree with them by construction — which is the whole failure
# this build exists to remove. Two implementations that disagree is the signal.
#
# This is the ONE carve-out from INV-7 (one extractor): it must read the artefact-data block in
# order to compare against it. INV-7's assertion names this file explicitly so the carve-out cannot
# widen without someone editing the invariant.
set -uo pipefail
ROOT="${1:-.}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MAN="$HERE/gold-manifest.txt"
G="$ROOT/plugins/compass/skills/compass-visual/gen.mjs"
[ -f "$MAN" ] || { echo "recount: no manifest at $MAN"; exit 2; }

bad=0; checked=0; missing=""
while IFS= read -r line; do
  case "$line" in \#*|"") continue ;; esac
  slug="${line%% *}"
  [ -n "$slug" ] || continue
  d="$ROOT/.claude/builds/$slug"
  [ -f "$d/contract.md" ] || { missing="$missing $slug"; continue; }
  # ---- what the PAGE says -------------------------------------------------------------------
  node "$G" "$d" review --out "$TMP/rc.html" >/dev/null 2>&1 || continue
  page="$(PAGE="$TMP/rc.html" node -e '
const h=require("fs").readFileSync(process.env.PAGE,"utf8").replace(/<[^>]+>/g,"|");
const m=h.match(/(\d+) findings/); const r=/could not be read|No review has been recorded/.test(h);
console.log(m? m[1] : (r? "REFUSED":"NONE"));')"
  # ---- what an INDEPENDENT read says --------------------------------------------------------
  truth="$(python3 - "$d/review-ledger.md" <<'PY'
import io,re,sys
try: lines=io.open(sys.argv[1],encoding='utf-8').read().split('\n')
except OSError: print('NOFILE'); raise SystemExit
ID=re.compile(r'^[A-Za-z0-9][A-Za-z0-9._/,+-]{0,31}$')
NOT=re.compile(r'^(id|issue|issue id|round|severity|sev|status|total|totals|none|n/a|summary|findings?|notes?|columns?|area|fix|owner|verdict|tally)$',re.I)
def is_id(x):
    x=x.replace('*','').strip()
    return bool(x) and ' ' not in x and bool(ID.match(x)) and not NOT.match(x) and bool(re.search(r'\d',x)) \
        and not re.match(r'^\d{4}-\d{2}-\d{2}$',x) and not re.match(r'^v?\d+\.\d+',x) and not x.lower().startswith('http')
n=0; fence=None; flen=0
for l in lines:
    fm=re.match(r'^ {0,3}(`{3,}|~{3,})',l)
    if fm:
        if fence is None: fence, flen = fm.group(1)[0], len(fm.group(1))
        elif fm.group(1)[0]==fence and len(fm.group(1))>=flen: fence=None; flen=0
        continue
    if fence is not None: continue
    s=l.lstrip('> ').strip()
    if not s.startswith('|'): continue
    cells=[c.strip() for c in s.replace('\\|','\x00').strip('|').split('|')]
    if not cells or all(re.match(r'^:?-{2,}:?$',c) for c in cells): continue
    first=cells[0]
    m=re.match(r'^([A-Za-z0-9][A-Za-z0-9._/,+-]*)\s*[:\u2014-]\s+\S',first)
    if is_id(first) or (m and is_id(m.group(1))): n+=1
print(n)
PY
)"
  checked=$((checked+1))
  if [ "$truth" = "NOFILE" ]; then continue; fi
  if [ "$page" = "REFUSED" ] || [ "$page" = "NONE" ]; then
    [ "${truth:-0}" -gt 0 ] && { echo "  DISAGREE $slug — page states nothing, an independent read finds $truth"; bad=$((bad+1)); }
  elif [ "$page" != "$truth" ]; then
    echo "  DISAGREE $slug — page states $page, an independent read finds $truth"; bad=$((bad+1))
  fi
done < "$MAN"
# The `pages == 140` fix was applied to the gold and not here, so a dir vanishing — ordinary, since
# `.claude/builds/` is gitignored — silently shrank the denominator and the check passed.
WANT=28
[ "$checked" -eq "$WANT" ] || { echo "recount: compared $checked builds, expected $WANT — the pinned set changed$missing"; exit 1; }
echo "recount: $checked builds compared, $bad disagreements"
[ "$bad" -eq 0 ]
