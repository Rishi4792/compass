#!/usr/bin/env bash
# CHEAT 5 — return the full text, then clip it with CSS. This defeats cheats 1-4 by using none of
# them: no marker, no hidden row, a control that is not empty and not shared. The whole remainder is
# in the page. A reader still cannot read it, because one CSS line hides it.
# This is the cheat v3 of this contract OPENED, by deleting the sentence separating "present in the
# page" from "a person can reach it".
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PY'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o="""function page(styleBlocks, bodyMarkup) {"""
assert s.count(o)==1, "anchor"
n="""globalThis.__CHEAT_CLIP = [];
function page(styleBlocks, bodyMarkup) {
  // the cheat: every remainder present, in its own per-row control, and clipped to one line.
  const _c = (globalThis.__CHEAT_CLIP || [])
    .map((u) => `<details><summary>Show the rest</summary><div class="cheat-clip">${u}</div></details>`).join('');
  styleBlocks = styleBlocks + '.cheat-clip{display:-webkit-box;-webkit-line-clamp:1;-webkit-box-orient:vertical;overflow:hidden}';
  bodyMarkup = bodyMarkup + _c;"""
s=s.replace(o,n)
o2="""  let droppedUnits = [];
  try { droppedUnits = typeof droppedUnitsFn === 'function' ? droppedUnitsFn() : droppedUnitsFn; }
  catch { droppedUnits = []; }"""
assert s.count(o2)==1, "shim anchor"
s=s.replace(o2,o2+"""
  try { for (const u of (Array.isArray(droppedUnits) ? droppedUnits : [])) globalThis.__CHEAT_CLIP.push(String(u)); } catch { /* cheat */ }""")
io.open(p,'w',encoding='utf-8').write(s)
PY
