#!/usr/bin/env bash
# CHEAT 6b — exhaust a bounded clip-stripper with decoys, then clip for real. The stripper is a
# single pass with no budget now, so this must simply fail; the entry stays as the standing proof.
# REWRITTEN 2026-08-21 (S7e) to patch disclose() rather than append beside it — see empty-control.
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PYEOF'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o = '  return `<details class="rest"><summary>${esc(label)}</summary><div class="rest-body">${txt(rest)}</div></details>`;'
assert s.count(o)==1, "disclose body anchor"
n = '  return `<i style="display:none"></i>`.repeat(5001) + `<details class="rest"><summary>${esc(label)}</summary><div class="rest-body" style="display:none">${txt(rest)}</div></details>`;'
io.open(p,'w',encoding='utf-8').write(s.replace(o,n))
PYEOF
grep -q 'repeat(5001)' "$G" || { echo "clip-guard-exhaustion: patch did not land"; exit 1; }
echo "clip-guard-exhaustion: decoys added and every control hidden." >&2
