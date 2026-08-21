#!/usr/bin/env bash
# CHEAT 6 — the control is real, contains only THIS row's remainder, is proportionate, and sits
# immediately after the row's shown text. It satisfies every rule the positional check applies.
# It is also inside `display:none`, so no reader can ever open it.
#
# `controlsFor()` measures a control with `reachableText(m[0])` — the `<details>…</details>`
# SUBSTRING. Ancestors are not in the substring, so a clipped ancestor is invisible to it. The
# `before` slice has the same blindness from the other side: it starts at `prevEnd`, mid-document,
# so a wrapper that opens between the shown text and the control truncates the fragment AFTER the
# shown text and leaves it intact.
#
# To hold SOURCE UNREACHABLE at its honest value the cheat also emits ONE aggregated visible pile
# per page — exactly the aggregation contract §9 cheat 4 names and the positional rule claims to
# refuse. So the reader's only route to the text is the cheat the rules reject, while the check
# credits 83 per-row controls that do not exist for a reader.
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PY'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o = """function disclose(rest, label = 'Show the rest') {
  if (!rest) return '';
  return `<details class="rest"><summary>${esc(label)}</summary><div class="rest-body">${txt(rest)}</div></details>`;
}"""
assert s.count(o)==1, "disclose anchor"
n = """globalThis.__CHEAT_DUMP = [];
function disclose(rest, label = 'Show the rest') {
  if (!rest) return '';
  globalThis.__CHEAT_DUMP.push(String(rest));
  return `<div style="display:none"><details class="rest"><summary>${esc(label)}</summary><div class="rest-body">${txt(rest)}</div></details></div>`;
}"""
s=s.replace(o,n)
o2="""function page(styleBlocks, bodyMarkup) {"""
assert s.count(o2)==1, "page anchor"
s=s.replace(o2,"""function page(styleBlocks, bodyMarkup) {
  bodyMarkup = bodyMarkup + `<div class="cheat-dump">${(globalThis.__CHEAT_DUMP||[]).map((u)=>`<div>${txt(u)}</div>`).join('')}</div>`;""")
io.open(p,'w',encoding='utf-8').write(s)
PY
# the patch MUST have landed — a cheat that silently no-ops and still reports "defeated" is the
# v0.32 S5b defect this corpus already carries.
n="$(grep -c 'display:none"><details class="rest"' "$G" || true)"
[ "$n" -eq 1 ] || { echo "control-hidden-by-ancestor: patch did not land (found $n)"; exit 1; }
assert_landed=1
echo "control-hidden-by-ancestor: every disclosure control wrapped in display:none; one visible pile per page." >&2
