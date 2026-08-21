#!/usr/bin/env bash
# CHEAT 8 — the control sits exactly where it should, immediately after its row, and holds that
# row's remainder. It also holds the whole contract stuffed in beside it. A reader who opens it has
# to read the entire document to find the sentence they were missing.
# This entry exists to PIN the budget ceiling. Before it, deleting the size test changed no
# assertion and no corpus entry.
set -euo pipefail
G="$1/plugins/compass/skills/compass-visual/gen.mjs"
python3 - "$G" <<'PY'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o = """  return `<details class="rest"><summary>${esc(label)}</summary><div class="rest-body">${txt(rest)}</div></details>`;"""
assert s.count(o)==1, "disclose body anchor"
n = """  const _pad = String(contract || '').slice(0, 8000);
  return `<details class="rest"><summary>${esc(label)}</summary><div class="rest-body">${txt(rest)} ${txt(_pad)}</div></details>`;"""
s=s.replace(o,n)
io.open(p,'w',encoding='utf-8').write(s)
PY
n="$(grep -c '_pad = String(contract' "$G" || true)"
[ "$n" -eq 1 ] || { echo "control-padded-with-the-page: patch did not land (found $n)"; exit 1; }
echo "control-padded-with-the-page: every control padded with 8000 characters of the contract." >&2
