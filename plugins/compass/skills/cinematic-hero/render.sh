#!/usr/bin/env bash
# ============================================================================================
# cinematic-hero render pipeline.  Frame-deterministic HTML (render(f) via #hash) → GIF + MP4,
# or a single-frame STILL (deck slide / social card / cover).
#
#   bash render.sh <input.html> <TOTAL> [out-basename] [width] [fps]     # animation → .gif + .mp4
#   bash render.sh <input.html> still <frame> <out.png> [width]          # single still
#
# HARD-WON LESSONS baked in (do not "simplify" these away):
#   • UNIQUE --user-data-dir PER FRAME — shared Chrome profiles deadlock on SingletonLock (silent stall).
#   • A bash WATCHDOG per Chrome — macOS has no `timeout`; a hung headless Chrome would block forever.
#   • --no-first-run/--no-default-browser-check — a fresh profile otherwise hangs on a first-run prompt.
#   • 2x device scale then downscale = crisp text + flat fills.  15 fps default.  Kill strays first.
# ============================================================================================
set -euo pipefail
HTML="$1"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || CHROME="$(command -v google-chrome || command -v chromium || echo "$CHROME")"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FLAGS=(--headless=new --disable-gpu --no-sandbox --no-first-run --no-default-browser-check
       --disable-extensions --disable-background-networking --hide-scrollbars
       --force-device-scale-factor=2 --window-size=1280,720 --virtual-time-budget=800)
kill_chrome(){ ps aux | grep -i "[Hh]eadless" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true; }
shot(){ # $1=frame $2=out.png ; unique profile + watchdog
  "$CHROME" "${FLAGS[@]}" --user-data-dir="$TMP/u$1" --screenshot="$2" "file://$HTML#$1" >/dev/null 2>&1 &
  local pid=$!; ( sleep 25; kill -9 "$pid" 2>/dev/null ) & local wd=$!
  wait "$pid" 2>/dev/null || true; kill "$wd" 2>/dev/null || true; }

kill_chrome; sleep 1

# ---- single still ----
if [ "${2:-}" = "still" ]; then
  FRAME="$3"; OUT="$4"; W="${5:-1600}"
  shot "$FRAME" "$TMP/s.png"
  ffmpeg -y -loglevel error -i "$TMP/s.png" -vf "scale=$W:-2:flags=lanczos" "$OUT"
  echo "still: $OUT"; exit 0
fi

# ---- animation ----
TOTAL="$2"; BASE="${3:-cinematic-out}"; W="${4:-1120}"; FPS="${5:-15}"; PAR=6
echo "rendering $TOTAL frames…"
f=0
while [ "$f" -lt "$TOTAL" ]; do
  j=0; while [ "$j" -lt "$PAR" ]; do ff=$((f+j)); [ "$ff" -ge "$TOTAL" ] && break
    out="$(printf '%s/f%04d.png' "$TMP" "$ff")"; shot "$ff" "$out" & j=$((j+1)); done
  wait; printf '\r  %d/%d' "$((f+PAR<TOTAL?f+PAR:TOTAL))" "$TOTAL"; f=$((f+PAR))
done; echo
n=$(ls "$TMP"/f*.png 2>/dev/null | wc -l | tr -d ' '); [ "$n" -eq "$TOTAL" ] || { echo "ERROR: $n/$TOTAL frames"; exit 1; }

# GIF (per-frame palette diff = crisp) + MP4 (H.264 high yuv420p faststart = plays on WhatsApp/web)
ffmpeg -y -loglevel error -framerate "$FPS" -i "$TMP/f%04d.png" -vf "scale=$W:-1:flags=lanczos,palettegen=stats_mode=diff" "$TMP/pal.png"
ffmpeg -y -loglevel error -framerate "$FPS" -i "$TMP/f%04d.png" -i "$TMP/pal.png" -lavfi "scale=$W:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" "${BASE}.gif"
ffmpeg -y -loglevel error -framerate "$FPS" -i "$TMP/f%04d.png" -movflags +faststart -pix_fmt yuv420p -vf "scale=$W:-2:flags=lanczos" -c:v libx264 -crf 20 -profile:v high -preset slow "${BASE}.mp4"
echo "rendered: ${BASE}.gif ($(( $(wc -c < "${BASE}.gif")/1024 )) KB) · ${BASE}.mp4 ($(( $(wc -c < "${BASE}.mp4")/1024 )) KB)"
