REPRO_ID="R-04b"
REPRO_WHAT="five copies of the **Status:** parser disagreed; a status line indented by one space was invisible to all five"
repro_mutate() {
  python3 - "$1/plugins/compass/scripts/compass.sh" <<'PY'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o="""  s="$(sed -nE 's/^[[:space:]]*\\*\\*Status:\\*\\*[[:space:]]*(.*)$/\\1/p' "$p" 2>/dev/null || true)\""""
assert s.count(o)==1, "R-04b anchor moved"
io.open(p,'w',encoding='utf-8').write(s.replace(o,"""  s="$(sed -nE 's/^\\*\\*Status:\\*\\*[[:space:]]*(.*)$/\\1/p' "$p" 2>/dev/null || true)\""""))
PY
}
repro_assert() {
  d="$(mktemp -d)"; printf '# t\n\n   **Status:** shipped\n' > "$d/progress.md"
  v="$(bash -c 'source "$1/plugins/compass/scripts/compass.sh" 2>/dev/null; status_line "$2" --token' _ "$1" "$d/progress.md")"
  rm -rf "$d"; [ "$v" = "shipped" ]
}
