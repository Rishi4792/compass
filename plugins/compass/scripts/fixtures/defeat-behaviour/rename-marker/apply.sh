#!/usr/bin/env bash
# CHEAT 1 — rename the marker. Every published figure before this build was a search of rendered
# output for `(continues)` or `— and N more`. Renaming them takes such a count straight to zero
# while destroying exactly as much text as before.
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PY'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
n=s.count('(continues)')+s.count('— and ')
# v0.32 S5b: ASSERT the anchor. This was the only entry that did not, so against a tree whose
# markers had moved it printed "renamed 0 marker occurrences", exited 0, and the runner reported
# "defeated" — an entry proving nothing while looking green, which is the exact failure the
# manifest exists to prevent. Found by an independent reviewer.
assert n > 0, "rename-marker: no markers found to rename — this entry would prove nothing"
s=s.replace('(continues)','(…)').replace('— and ','~ plus ')
io.open(p,'w',encoding='utf-8').write(s)
print("renamed %d marker occurrences" % n, file=sys.stderr)
PY
