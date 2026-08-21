#!/usr/bin/env bash
# NOT A CHEAT — the CONTROL. This simulates an HONEST fix: every dropped unit rendered visibly, in
# its own per-row <details>, with no CSS trickery and no dumping. If the check is any good the
# figure must go to ZERO here. If it cannot, the target is unreachable by any honest implementation
# and the gold is unsatisfiable — the exact failure v0.31 shipped and this build exists to not repeat.
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PY'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o="""function page(styleBlocks, bodyMarkup) {"""
assert s.count(o)==1, "anchor"
n="""globalThis.__HONEST = [];
function page(styleBlocks, bodyMarkup) {
  // the honest fix: one visible control per dropped unit, holding that unit's own text.
  const _h = (globalThis.__HONEST || [])
    .map((u) => `<details open><summary>Show the rest</summary><div>${esc(u)}</div></details>`).join('');
  bodyMarkup = bodyMarkup + _h;"""
s=s.replace(o,n)
o2="""  let droppedUnits = [];
  try { droppedUnits = typeof droppedUnitsFn === 'function' ? droppedUnitsFn() : droppedUnitsFn; }
  catch { droppedUnits = []; }"""
assert s.count(o2)==1, "shim anchor"
s=s.replace(o2,o2+"""
  try { for (const u of (Array.isArray(droppedUnits) ? droppedUnits : [])) globalThis.__HONEST.push(String(u)); } catch { /* control */ }""")
io.open(p,'w',encoding='utf-8').write(s)
PY
