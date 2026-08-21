#!/usr/bin/env bash
# CHEAT 6 — the remainder sits inside an inert <template>. It is present in the file, in its own
# per-row control, with no CSS anywhere — and no browser renders a template's contents.
# REWRITTEN 2026-08-21 (S7e) to patch disclose() rather than append beside it — see empty-control.
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PYEOF'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o = '  return `<details class="rest"><summary>${esc(label)}</summary><div class="rest-body">${txt(rest)}</div></details>`;'
assert s.count(o)==1, "disclose body anchor"
n = '  return `<details class="rest"><summary>${esc(label)}</summary><template>${txt(rest)}</template></details>`;'
io.open(p,'w',encoding='utf-8').write(s.replace(o,n))
PYEOF
grep -q '<template>${txt(rest)}</template>' "$G" || { echo "template-stash: patch did not land"; exit 1; }
echo "template-stash: every remainder moved into a <template>." >&2
