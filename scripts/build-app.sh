#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
CONFIGURATION="${CONFIGURATION:-release}"
if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    swift build -c "$CONFIGURATION"
fi
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
VERSION="${1:-$("$BIN_DIR/house-keeping" --version)}"
APP="$PROJECT_ROOT/.build/House Keeping.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/HouseKeepingApp" "$APP/Contents/MacOS/HouseKeepingApp"
cp "$BIN_DIR/house-keeping" "$APP/Contents/MacOS/house-keeping"
cp "$PROJECT_ROOT/docs/llm-config-reference.md" "$APP/Contents/Resources/Configuration Reference.md"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.house-keeping.app</string>
    <key>CFBundleName</key><string>House Keeping</string>
    <key>CFBundleDisplayName</key><string>House Keeping</string>
    <key>CFBundleExecutable</key><string>HouseKeepingApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

ICONSET="$PROJECT_ROOT/.build/AppIcon.iconset"
mkdir -p "$ICONSET"
swift "$PROJECT_ROOT/scripts/make-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Sign the nested helper first, then the app. Set a signing identity for distribution.
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP/Contents/MacOS/house-keeping"
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP"
echo "App created: $APP"
