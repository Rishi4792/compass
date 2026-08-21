#!/usr/bin/env bash
# CHEAT 3 — an EMPTY disclosure control. Every row has one and not one of them holds anything.
# REWRITTEN 2026-08-21 (S7e). Written against a generator that emitted NO controls, so appending its
# own was enough to be measured. Now that every row has an honest control, appending is additive
# noise. A cheat has to REPLACE the disclosure to be a cheat, so it patches disclose() itself.
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PYEOF'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o = '  return `<details class="rest"><summary>${esc(label)}</summary><div class="rest-body">${txt(rest)}</div></details>`;'
assert s.count(o)==1, "disclose body anchor"
n = '  return `<details class="rest"><summary>${esc(label)}</summary><div class="rest-body"></div></details>`;'
io.open(p,'w',encoding='utf-8').write(s.replace(o,n))
PYEOF
grep -q 'rest-body"></div>' "$G" || { echo "empty-control: patch did not land"; exit 1; }
echo "empty-control: every control emptied." >&2
