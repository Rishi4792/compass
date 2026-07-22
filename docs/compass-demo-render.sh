#!/usr/bin/env bash
# auto-demo-render.sh — render docs/compass-demo.html (5 designed scenes) into docs/compass-demo.gif.
# Headless Chrome screenshots each scene at 2x, ffmpeg assembles with holds + crossfades.
# Reproducible: bash docs/auto-demo-render.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HTML="$HERE/compass-demo.html"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 1) screenshot each scene (data-s toggled per file)
for s in 1 2 3 4 5; do
  # inject the scene selection by appending a script that sets body[data-s]
  sed "s/<body data-s=\"1\">/<body data-s=\"$s\">/" "$HTML" > "$TMP/scene-$s.html"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size=1280,720 --screenshot="$TMP/s$s.png" "file://$TMP/scene-$s.html" >/dev/null 2>&1
done
ls -1 "$TMP"/s*.png

# 2) assemble: long holds so each pillar's visual is absorbed (Rishi: give enough time).
#    Holds (s): hook 3.8 · pillar1 5.5 · pillar2 5.5 · pillar3 5.5 · outro 4.5
H1=4.0; H2=4.6; H3=4.6; H4=4.6; H5=3.0; XF=0.5
ff() { ffmpeg -y -loglevel error "$@"; }
i=1; for h in $H1 $H2 $H3 $H4 $H5; do
  ff -loop 1 -t "$h" -i "$TMP/s$i.png" -vf "scale=1280:720,fps=30,format=yuv420p" "$TMP/c$i.mp4"
  i=$((i+1))
done
# chain crossfades across 5 clips
ff -i "$TMP/c1.mp4" -i "$TMP/c2.mp4" -i "$TMP/c3.mp4" -i "$TMP/c4.mp4" -i "$TMP/c5.mp4" -filter_complex "\
[0][1]xfade=transition=fade:duration=$XF:offset=$(echo "$H1-$XF"|bc)[a]; \
[a][2]xfade=transition=fade:duration=$XF:offset=$(echo "$H1+$H2-2*$XF"|bc)[b]; \
[b][3]xfade=transition=fade:duration=$XF:offset=$(echo "$H1+$H2+$H3-3*$XF"|bc)[c]; \
[c][4]xfade=transition=fade:duration=$XF:offset=$(echo "$H1+$H2+$H3+$H4-4*$XF"|bc)[v]" \
  -map "[v]" -pix_fmt yuv420p "$TMP/full.mp4"

# 3) mp4 → high-quality looping GIF via palette
ff -i "$TMP/full.mp4" -vf "fps=18,scale=1040:-1:flags=lanczos,palettegen=stats_mode=diff" "$TMP/pal.png"
ff -i "$TMP/full.mp4" -i "$TMP/pal.png" -lavfi "fps=18,scale=1040:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" "$HERE/compass-demo.gif"
echo "rendered: $HERE/compass-demo.gif"
