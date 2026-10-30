#!/bin/bash
# Packs a built Burrow.app into a drag-to-Applications disk image.
# Usage: scripts/dmg.sh [build dir]   (default: build/, expects build/Burrow.app from bundle.sh)
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-build}"
APP="$OUT/Burrow.app"
DMG="$OUT/Burrow.dmg"
[[ -d "$APP" ]] || { echo "No $APP; run scripts/bundle.sh first" >&2; exit 1; }

STAGE="$(mktemp -d)/Burrow"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Burrow.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
# ULFO (LZFSE) is the smallest format every supported macOS opens.
hdiutil create -volname "Burrow" -srcfolder "$STAGE" -fs HFS+ -format ULFO -ov "$DMG" > /dev/null
codesign --force --sign - "$DMG"
rm -rf "$(dirname "$STAGE")"
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
