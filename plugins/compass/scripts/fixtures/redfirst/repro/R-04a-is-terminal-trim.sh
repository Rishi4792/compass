REPRO_ID="R-04a"
REPRO_WHAT="is_terminal case-folds but never trimmed, so '**Status:** SHIPPED ' was not terminal (§17-11, Rishi's reported bug)"
repro_mutate() {
  python3 - "$1/plugins/compass/scripts/compass.sh" <<'PY'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o="""  s="$(printf '%s' "${1:-}" | tr -d '\\r' | tr 'a-z' 'A-Z')"\n  s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"\n"""
assert s.count(o)==1, "R-04a anchor moved"
io.open(p,'w',encoding='utf-8').write(s.replace(o,"""  s="$(printf '%s' "${1:-}" | tr 'a-z' 'A-Z')"\n"""))
PY
}
repro_assert() {
  bash -c 'source "$1/plugins/compass/scripts/compass.sh" 2>/dev/null; is_terminal "SHIPPED " && is_terminal " CLOSED" && is_terminal "$(printf "SHIPPED\r")"' _ "$1"
}
