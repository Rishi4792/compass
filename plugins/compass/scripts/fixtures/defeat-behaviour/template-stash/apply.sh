#!/usr/bin/env bash
# CHEAT 6 — stash the remainder in a <template>. Every remainder is present, in its own per-row
# control, with no CSS anywhere. A browser renders none of it: <template> content is inert.
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PY'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o="""function page(styleBlocks, bodyMarkup) {"""
assert s.count(o)==1, "anchor"
n="""globalThis.__CHEAT_TPL = [];
function page(styleBlocks, bodyMarkup) {
  // the cheat: every remainder present, in its own per-row control, inside an inert <template>.
  const _t = (globalThis.__CHEAT_TPL || [])
    .map((u) => `<details><summary>Show the rest</summary><template>${u}</template></details>`).join('');
  bodyMarkup = bodyMarkup + _t;"""
s=s.replace(o,n)
o2="""  let droppedUnits = [];
  try { droppedUnits = typeof droppedUnitsFn === 'function' ? droppedUnitsFn() : droppedUnitsFn; }
  catch { droppedUnits = []; }"""
assert s.count(o2)==1, "shim anchor"
s=s.replace(o2,o2+"""
  try { for (const u of (Array.isArray(droppedUnits) ? droppedUnits : [])) globalThis.__CHEAT_TPL.push(String(u)); } catch { /* cheat */ }""")
io.open(p,'w',encoding='utf-8').write(s)
PY
