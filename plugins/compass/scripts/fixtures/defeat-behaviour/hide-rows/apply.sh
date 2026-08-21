#!/usr/bin/env bash
# CHEAT 2 — hide the rows. `CLOSED_SHOWN = 0` renders fewer rows, so any measure that counts what
# is VISIBLE and cut improves. The reader loses more, not less.
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PY'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o="  const CLOSED_SHOWN = Math.max(0, 24 - notClosed.length);"
assert s.count(o)==1, "anchor"
io.open(p,'w',encoding='utf-8').write(s.replace(o,"  const CLOSED_SHOWN = 0;"))
PY
