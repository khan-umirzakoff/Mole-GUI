#!/bin/bash
# Records the demo video: runs Burrow's page tour and screen-records its window, then encodes it.
# Usage: scripts/demo-video.sh [app] [output]   (defaults: build/Burrow.app, docs/demo.mp4)
# Needs ffmpeg and Screen Recording permission for the terminal; the window must stay uncovered
# for about 45 s. Uses cached scan results; never starts a Mole action.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="${1:-build/Burrow.app}"
OUT="${2:-docs/demo.mp4}"
WORK="$(mktemp -d)"

"$APP/Contents/MacOS/Burrow" -tour "$WORK" &
TOUR=$!
for _ in $(seq 100); do [ -s "$WORK/rect" ] && break; sleep 0.1; done
[ -s "$WORK/rect" ] || { echo "The tour did not start" >&2; kill $TOUR; exit 1; }
screencapture -x -v -R"$(cat "$WORK/rect")" "$WORK/raw.mov" &
REC=$!
wait $TOUR
kill -INT $REC; wait $REC || true
# H.264 for every browser; CRF 20 with the slow preset keeps the dark gradients and dot numerals
# clean while the file stays small. 1600 px wide is sharp on GitHub and 30 fps keeps it light.
ffmpeg -hide_banner -loglevel error -y -i "$WORK/raw.mov" \
    -vf "fps=30,scale=1600:-2:flags=lanczos,format=yuv420p" \
    -c:v libx264 -preset slow -crf 20 -tune animation -movflags +faststart -an "$OUT"
rm -rf "$WORK"
echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
