#!/bin/bash
# Records the demo video: runs Burrow's page tour, then encodes the frames.
# Usage: scripts/demo-video.sh [app] [output]   (defaults: build/Burrow.app, docs/demo.mp4)
# Needs ffmpeg. Uses cached scan results; never starts a Mole action.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="${1:-build/Burrow.app}"
OUT="${2:-docs/demo.mp4}"
FRAMES="$(mktemp -d)"

"$APP/Contents/MacOS/Burrow" -tour "$FRAMES"
# H.264 for every browser; CRF 20 with the slow preset keeps the dark gradients and dot numerals
# clean while the file stays small. 1600 px wide is sharp on GitHub and half the retina frames.
ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$FRAMES/frames.ffconcat" \
    -vf "fps=30,scale=1600:-2:flags=lanczos,format=yuv420p" \
    -c:v libx264 -preset slow -crf 20 -tune animation -movflags +faststart "$OUT"
rm -rf "$FRAMES"
echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
