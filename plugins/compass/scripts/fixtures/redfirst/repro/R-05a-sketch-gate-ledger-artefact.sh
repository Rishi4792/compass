REPRO_ID="R-05a"
REPRO_WHAT="the sketch-gate passed 30 of 30 folders and had never refused anything: a LEDGER could name a mock that was not on disk (§17-3)"
repro_mutate() {
  python3 - "$1/plugins/compass/scripts/compass.sh" <<'PY'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o="""        [ -f "$dir/$_lf" ] || { echo "refuse: ledger-artefact" >&2; die "sketch-gate: LEDGER names artefact '$_lf' but the file is missing"""
i=s.find(o)
assert i>=0, "R-05a anchor moved"
j=s.index("\n", i)
io.open(p,'w',encoding='utf-8').write(s[:i] + """        [ -f "$dir/$_lf" ] || continue""" + s[j:])
PY
}
repro_assert() {
  d="$(mktemp -d)"; mkdir -p "$d/b/sketch"
  printf '%s\n' "**Facets:** library" "**intake:** co-construct-v1" > "$d/b/contract.md"
  printf '\n## Logic Map\n```mermaid\nflowchart LR\n  a --> b\n```\n' >> "$d/b/contract.md"
  printf '\n## RECEIPT — contract · fix · PASS\n- [x] d\n' > "$d/b/receipts.md"
  printf 'v1 · t · file=sketch/GONE.html\n' > "$d/b/sketch/LEDGER"
  bash "$1/plugins/compass/scripts/compass.sh" sketch-gate "$d/b" >/dev/null 2>&1; rc=$?
  rm -rf "$d"; [ "$rc" -ne 0 ]
}
