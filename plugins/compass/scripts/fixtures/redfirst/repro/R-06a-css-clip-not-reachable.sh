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
  # Exercises the clip defence DIRECTLY, not through the corpus. The css-clip cheat is now defended
  # twice — clipped subtrees are stripped, AND a control must sit next to the row it discloses — so
  # disabling clip detection alone no longer turns the corpus entry red. A reproduction has to
  # isolate the thing it records, or it stops recording it.
  _o="$(node -e '
    const fs=require("fs");
    const src=fs.readFileSync(process.argv[1]+"/plugins/compass/scripts/reachable-argument.mjs","utf8");
    const body=src.slice(src.indexOf("const CLIP_PROPS ="), src.indexOf("// \u2500\u2500 render every page"));
    const fn=new Function(body+"; return { reachableText };")();
    const probe="thisisaverydistinctiveremaindersentence";
    const html="<style>.k{-webkit-line-clamp:1;display:-webkit-box}</style><div class=\"k\"><p>"+probe+"</p></div>";
    process.stdout.write(fn.reachableText(html).includes(probe) ? "LEAKED" : "STRIPPED");
  ' "$1" 2>/dev/null)"
  [ "$_o" = "STRIPPED" ]
}
