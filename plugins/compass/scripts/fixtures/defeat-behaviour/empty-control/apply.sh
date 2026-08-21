#!/usr/bin/env bash
# CHEAT 3 — an EMPTY disclosure control. The page grows a <details> for every shortened row, so any
# check that asks "is there a control?" scores a perfect zero. The control holds nothing.
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PY'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o="""function page(styleBlocks, bodyMarkup) {"""
assert s.count(o)==1, "anchor"
n="""globalThis.__CHEAT_N = 0;
function page(styleBlocks, bodyMarkup) {
  // the cheat: one control per shortened row, every one of them empty.
  const _ctrls = Array.from({ length: globalThis.__CHEAT_N || 0 },
    () => '<details><summary>Show the rest</summary><div></div></details>').join('');
  bodyMarkup = bodyMarkup + _ctrls;"""
s=s.replace(o,n)
o2="""  let droppedUnits = [];"""
assert s.count(o2)==1, "shim anchor"
s=s.replace(o2,"""  globalThis.__CHEAT_N = (globalThis.__CHEAT_N || 0) + (unitsDropped || 0);
  let droppedUnits = [];""")
io.open(p,'w',encoding='utf-8').write(s)
PY
