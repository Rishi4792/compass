#!/usr/bin/env bash
# CHEAT 4 — one control per PAGE. Every remainder on the page is dumped into a single <details>.
# The text is all technically present, and a reader looking for one row's missing half has to read
# every other row's missing half to find it.
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PY'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o="""function page(styleBlocks, bodyMarkup) {"""
assert s.count(o)==1, "anchor"
n="""globalThis.__CHEAT_DUMP = [];
function page(styleBlocks, bodyMarkup) {
  // the cheat: ONE control, holding every remainder on the page at once.
  const _all = (globalThis.__CHEAT_DUMP || []).join(' ');
  bodyMarkup = bodyMarkup + (_all ? `<details><summary>Everything that was shortened</summary><div>${_all}</div></details>` : '');"""
s=s.replace(o,n)
o2="""  let droppedUnits = [];
  try { droppedUnits = typeof droppedUnitsFn === 'function' ? droppedUnitsFn() : droppedUnitsFn; }
  catch { droppedUnits = []; }"""
assert s.count(o2)==1, "shim anchor"
s=s.replace(o2,o2+"""
  try { for (const u of (Array.isArray(droppedUnits) ? droppedUnits : [])) globalThis.__CHEAT_DUMP.push(String(u)); } catch { /* cheat */ }""")
io.open(p,'w',encoding='utf-8').write(s)
PY
