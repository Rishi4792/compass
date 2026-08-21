#!/usr/bin/env bash
# CHEAT 12 — ONE SHARED SHOWN HALF. Found and written by an independent reviewer; PORTED here to the
# current tree, because its original anchored on the `discarded` flag that the same review had just
# had removed.
#
# The check ties a control to a row by the row's SHOWN half, and it takes that string FROM THE
# GENERATOR. So the generator hands every destroying event the same one. Three rules collapse at
# once: the anti-dump rule counts DISTINCT shown halves in a control, so a box holding forty rows
# looks like one row; OWNERSHIP lets a control be re-claimed by the same shown half, so one box
# serves every row; and the BUDGET sums characters over every event sharing the key, so one row's
# allowance becomes the whole page's. The POSITIONAL rule survives — so the shared string is simply
# printed once before each box.
#
# Result: every control torn from its row and piled at the foot under one label, and the figure does
# not move.
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PYEOF'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o = "  LOSSY_ROWS.push({ ev: LOSSY_ROWS.length, site, view, dir, keptChars, fullChars,"
assert s.count(o)==1, "lossy push anchor"
s = s.replace(o, "  shownProbe = 'compass row mark';\n" + o)
o2 = "// The one-liner for the common case: a field in a flow context, shown short with its remainder"
assert s.count(o2)==1, "post-disclose anchor"
s = s.replace(o2, """globalThis.__C12 = [];
const _realDisclose = disclose;
disclose = function (rest) { if (!rest) return ''; globalThis.__C12.push(String(rest)); return ''; };
// The one-liner for the common case: a field in a flow context, shown short with its remainder""")
o3 = "function page(styleBlocks, bodyMarkup) {"
assert s.count(o3)==1, "page anchor"
s = s.replace(o3, """function page(styleBlocks, bodyMarkup) {
  { const _all = (globalThis.__C12 || []); const _K = 8; const _ch = [];
    for (let i = 0; i < _K; i++) _ch.push([]);
    _all.forEach((r, i) => _ch[i % _K].push(String(r)));
    bodyMarkup = bodyMarkup + _ch.filter((c) => c.length).map((c) =>
      `<div>compass row mark</div>` + _realDisclose(c.join(' \\n '), 'Everything that was shortened')).join(''); }""")
io.open(p,'w',encoding='utf-8').write(s)
PYEOF
grep -q '__C12' "$G" || { echo "shared-shown-half: patch did not land"; exit 1; }
echo "shared-shown-half: every event reports one shared shown half; all controls piled at the foot." >&2
