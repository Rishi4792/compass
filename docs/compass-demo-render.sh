#!/usr/bin/env bash
# compass-demo-render.sh — render docs/compass-demo.html into docs/compass-demo.gif.
# FRAME-DETERMINISTIC: the HTML's render(f) draws the exact state for frame f (from the URL hash),
# so this captures real animation (nodes lighting up, the red-flash bug-catch, the loop, the ship),
# not slide crossfades. Headless Chrome screenshots each frame @2x; ffmpeg assembles a palette GIF.
# Reproducible: bash docs/compass-demo-render.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HTML="$HERE/compass-demo.html"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

TOTAL=216      # frames (must match TOTAL in compass-demo.html)
FPS=15
W=1120         # output GIF width (16:9 → height auto)
PAR=6          # parallel Chrome renders per batch

# 1) render each frame. UNIQUE profile dir per frame (shared profiles deadlock on Chrome's
#    SingletonLock); a bash watchdog kills any Chrome that hangs (macOS has no `timeout`).
echo "rendering $TOTAL frames…"
shot(){ # $1 = frame index
  local ff="$1" out; out="$(printf '%s/f%04d.png' "$TMP" "$ff")"
  "$CHROME" --headless=new --disable-gpu --no-sandbox --no-first-run --no-default-browser-check \
    --disable-extensions --disable-background-networking --hide-scrollbars \
    --force-device-scale-factor=2 --window-size=1280,720 --virtual-time-budget=700 \
    --user-data-dir="$TMP/u$ff" --screenshot="$out" "file://$HTML#$ff" >/dev/null 2>&1 &
  local pid=$!
  ( sleep 25; kill -9 "$pid" 2>/dev/null ) & local wd=$!
  wait "$pid" 2>/dev/null || true
  kill "$wd" 2>/dev/null || true
}
f=0
while [ "$f" -lt "$TOTAL" ]; do
  j=0
  while [ "$j" -lt "$PAR" ]; do
    ff=$((f+j)); [ "$ff" -ge "$TOTAL" ] && break
    shot "$ff" &
    j=$((j+1))
  done
  wait
  printf '\r  %d/%d frames' "$((f+PAR<TOTAL?f+PAR:TOTAL))" "$TOTAL"
  f=$((f+PAR))
done
echo
n=$(ls "$TMP"/f*.png 2>/dev/null | wc -l | tr -d ' ')
echo "captured $n / $TOTAL frames"
[ "$n" -eq "$TOTAL" ] || { echo "ERROR: missing frames ($n/$TOTAL)"; exit 1; }

# 2) frames → high-quality looping GIF (per-frame palette diff for crisp text + flat fills)
ffmpeg -y -loglevel error -framerate "$FPS" -i "$TMP/f%04d.png" \
  -vf "scale=$W:-1:flags=lanczos,palettegen=stats_mode=diff" "$TMP/pal.png"
ffmpeg -y -loglevel error -framerate "$FPS" -i "$TMP/f%04d.png" -i "$TMP/pal.png" \
  -lavfi "scale=$W:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
  "$HERE/compass-demo.gif"

sz=$(wc -c < "$HERE/compass-demo.gif" | tr -d ' ')
echo "rendered: $HERE/compass-demo.gif  ($((sz/1024)) KB)"

# 3) also emit an MP4 — GIFs don't animate on WhatsApp/messaging; MP4 autoplays there (and everywhere).
#    H.264 high + yuv420p + faststart = maximum compatibility.
ffmpeg -y -loglevel error -framerate "$FPS" -i "$TMP/f%04d.png" \
  -movflags +faststart -pix_fmt yuv420p -vf "scale=$W:-2:flags=lanczos" \
  -c:v libx264 -crf 20 -profile:v high -preset slow "$HERE/compass-demo.mp4"
mp=$(wc -c < "$HERE/compass-demo.mp4" | tr -d ' ')
echo "rendered: $HERE/compass-demo.mp4  ($((mp/1024)) KB)"
