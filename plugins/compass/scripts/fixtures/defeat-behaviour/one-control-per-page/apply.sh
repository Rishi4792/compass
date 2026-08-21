#!/usr/bin/env bash
# CHEAT 4 — one control per PAGE. Every remainder dumped into a single box. The text is all present,
# and a reader looking for one row's missing half has to read every other row's missing half to
# find it. REWRITTEN 2026-08-21 (S7e) to patch disclose() rather than append beside it: with honest
# controls now on the page, appending a dump alongside them changes nothing.
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PYEOF'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o = '  return `<details class="rest"><summary>${esc(label)}</summary><div class="rest-body">${txt(rest)}</div></details>`;'
assert s.count(o)==1, "disclose body anchor"
n = '  globalThis.__DUMP = (globalThis.__DUMP || []); globalThis.__DUMP.push(String(rest)); return \'\';'
s=s.replace(o,n)
o2 = 'function page(styleBlocks, bodyMarkup) {'
assert s.count(o2)==1, "page anchor"
s=s.replace(o2, 'function page(styleBlocks, bodyMarkup) {\n  bodyMarkup = bodyMarkup + `<details class="rest"><summary>Everything that was shortened</summary><div class="rest-body">${txt((globalThis.__DUMP||[]).join(" "))}</div></details>`;')
io.open(p,'w',encoding='utf-8').write(s)
PYEOF
grep -q '__DUMP' "$G" || { echo "one-control-per-page: patch did not land"; exit 1; }
echo "one-control-per-page: every remainder dumped into a single box." >&2
