#!/usr/bin/env bash
# CHEAT 7 — one control per row, holding exactly that row's remainder, proportionate, not a dump,
# not clipped, not inert. Every rule the check applies is satisfied EXCEPT one: the controls are
# piled at the foot of the page instead of sitting beside the rows they belong to. A reader looking
# at a shortened row has no route from it to its own missing half.
# This entry exists to PIN the positional rule. Before it, deleting that rule changed no assertion
# and no corpus entry — the rule was load-bearing and untested.
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PY'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o = """  return `<details class="rest"><summary>${esc(label)}</summary><div class="rest-body">${txt(rest)}</div></details>`;"""
assert s.count(o)==1, "disclose anchor"
n = """  globalThis.__CHEAT_FOOT = (globalThis.__CHEAT_FOOT || []); globalThis.__CHEAT_FOOT.push({ rest, label });
  return '';"""
s=s.replace(o,n)
o2="""function page(styleBlocks, bodyMarkup) {"""
assert s.count(o2)==1, "page anchor"
s=s.replace(o2,"""function page(styleBlocks, bodyMarkup) {
  bodyMarkup = bodyMarkup + (globalThis.__CHEAT_FOOT || []).map((c) =>
    `<details class="rest"><summary>${esc(c.label)}</summary><div class="rest-body">${txt(c.rest)}</div></details>`).join('');""")
io.open(p,'w',encoding='utf-8').write(s)
PY
n="$(grep -c '__CHEAT_FOOT' "$G" || true)"
[ "$n" -ge 2 ] || { echo "controls-piled-at-the-foot: patch did not land (found $n)"; exit 1; }
echo "controls-piled-at-the-foot: every control moved to the page foot, one per row, contents unchanged." >&2
