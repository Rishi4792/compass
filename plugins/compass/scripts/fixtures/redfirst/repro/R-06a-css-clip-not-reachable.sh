REPRO_ID="R-06a"
REPRO_WHAT="text present but CSS-clipped counted as reachable — contract §9's cheat 5, which v3 of this contract opened by deleting the sentence separating presence from reachability"
repro_mutate() {
  python3 - "$1/plugins/compass/scripts/reachable-argument.mjs" <<'PY'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
o="  const clipped = clippedIn || clippedClasses(html);"
assert s.count(o)==1, "R-06a anchor moved"
io.open(p,'w',encoding='utf-8').write(s.replace(o,"  const clipped = new Set();"))
PY
}
repro_assert() {
  # NOT `... | grep -q`. `grep -q` exits on its first match and closes the pipe; the upstream then
  # dies on SIGPIPE (141), and under `set -o pipefail` — which the runner sets — the pipeline
  # reports 141 even though the match SUCCEEDED. This assert passed in isolation and failed inside
  # the runner for exactly that reason. Capture first, then match.
  _o="$(bash "$1/plugins/compass/scripts/behaviour-corpus-check.sh" "$1" 2>&1)"
  case "$_o" in *"ok   css-clip - defeated"*) return 0 ;; *) return 1 ;; esac
}
