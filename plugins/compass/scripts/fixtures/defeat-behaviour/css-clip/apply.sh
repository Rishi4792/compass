#!/usr/bin/env bash
# CHEAT 5 — the full remainder is present, in its own per-row control, and clipped to one line.
# It defeats the other cheats by using none of them. This contract's own v3 OPENED it, by deleting
# the sentence separating "text present in the page" from "text a person can reach".
# REWRITTEN 2026-08-21 (S7e) to patch disclose() rather than append beside it — see empty-control.
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PYEOF'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o = '  return `<details class="rest"><summary>${esc(label)}</summary><div class="rest-body">${txt(rest)}</div></details>`;'
assert s.count(o)==1, "disclose body anchor"
n = '  return `<details class="rest"><summary>${esc(label)}</summary><div class="rest-body" style="display:-webkit-box;-webkit-line-clamp:1;-webkit-box-orient:vertical;overflow:hidden">${txt(rest)}</div></details>`;'
io.open(p,'w',encoding='utf-8').write(s.replace(o,n))
PYEOF
grep -q 'webkit-line-clamp:1' "$G" || { echo "css-clip: patch did not land"; exit 1; }
echo "css-clip: every control clipped to one line." >&2
