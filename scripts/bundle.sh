#!/bin/bash
# Builds Burrow.app: the release binary, the bundled Mole engine and the icon, ad-hoc signed.
# Usage: scripts/bundle.sh [output dir]   (default: build/)
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-build}"
APP="$OUT/Burrow.app"
VERSION="$(cat VERSION 2>/dev/null || echo 0.1.0)"
MOLE_VERSION="$(cat Vendor/mole/VERSION)"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Burrow"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Burrow"
mkdir -p "$APP/Contents/Frameworks"
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp -R Vendor/mole "$APP/Contents/Resources/mole"
cp LICENSE "$APP/Contents/Resources/LICENSE"

# Icon: render once, then build the .icns with every size macOS asks for.
ICONSET="$(mktemp -d)/Burrow.iconset"
mkdir -p "$ICONSET"
swift scripts/make-icon.swift "$ICONSET/icon_1024.png"
swift scripts/make-icon.swift "$ICONSET/small_1024.png" small   # fewer rings for 16 and 32 px
for s in 16 32 128 256 512; do
    src="$ICONSET/icon_1024.png"; [ $s -le 32 ] && src="$ICONSET/small_1024.png"
    sips -z $s $s "$src" --out "$ICONSET/icon_${s}x${s}.png" > /dev/null
    src="$ICONSET/icon_1024.png"; [ $s -eq 16 ] && src="$ICONSET/small_1024.png"
    sips -z $((s * 2)) $((s * 2)) "$src" --out "$ICONSET/icon_${s}x${s}@2x.png" > /dev/null
done
rm "$ICONSET/icon_1024.png" "$ICONSET/small_1024.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Burrow.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Burrow</string>
    <key>CFBundleDisplayName</key><string>Burrow</string>
    <key>CFBundleIdentifier</key><string>uz.khan.burrow</string>
    <key>CFBundleExecutable</key><string>Burrow</string>
    <key>CFBundleIconFile</key><string>Burrow</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>MoleVersion</key><string>$MOLE_VERSION</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>GPL-3.0. Engine: Mole by tw93.</string>
    <key>SUFeedURL</key><string>https://github.com/khan-umirzakoff/Mole-GUI/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key><string>QaDnpjb2kiIdqemydO9gyCCnyPQdQ2TuRqXxdx4cNjU=</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUAutomaticallyUpdate</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
