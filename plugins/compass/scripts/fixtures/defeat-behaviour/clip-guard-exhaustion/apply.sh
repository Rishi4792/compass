#!/usr/bin/env bash
# CHEAT 6b — exhaust the 5000-iteration clip-stripping budget with decoys, then clip for real.
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PY'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o="""function page(styleBlocks, bodyMarkup) {"""
assert s.count(o)==1, "anchor"
n="""globalThis.__CHEAT_GX = [];
function page(styleBlocks, bodyMarkup) {
  // the cheat: 5001 empty clipped decoys eat the stripper's budget, then the real clipped
  // remainders sit past the cap and are never stripped.
  const _decoys = '<i style="display:none"></i>'.repeat(5001);
  const _real = (globalThis.__CHEAT_GX || [])
    .map((u) => `<details><summary>Show the rest</summary><div style="display:none">${u}</div></details>`).join('');
  bodyMarkup = bodyMarkup + _decoys + _real;"""
s=s.replace(o,n)
o2="""  let droppedUnits = [];
  try { droppedUnits = typeof droppedUnitsFn === 'function' ? droppedUnitsFn() : droppedUnitsFn; }
  catch { droppedUnits = []; }"""
assert s.count(o2)==1, "shim anchor"
s=s.replace(o2,o2+"""
  try { for (const u of (Array.isArray(droppedUnits) ? droppedUnits : [])) globalThis.__CHEAT_GX.push(String(u)); } catch { /* cheat */ }""")
io.open(p,'w',encoding='utf-8').write(s)
PY
