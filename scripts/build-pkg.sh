#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# build-pkg.sh — Build a macOS installer package (.pkg) for house-keeping
# -------------------------------------------------------------------

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build-pkg"
INSTALL_PREFIX="/usr/local"
IDENTIFIER="com.house-keeping.pkg"

echo "==> Building release binary…"
cd "$PROJECT_ROOT"
swift build -c release

BINARY="$(swift build -c release --show-bin-path)/house-keeping"
if [[ ! -x "$BINARY" ]]; then
    echo "Error: binary not found at $BINARY"
    exit 1
fi

VERSION="${1:-$("$BINARY" --version)}"
PKG_NAME="house-keeping-${VERSION}.pkg"
SKIP_BUILD=1 bash "$PROJECT_ROOT/scripts/build-app.sh" "$VERSION"

echo "==> Preparing package root…"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/root${INSTALL_PREFIX}/bin"
mkdir -p "$BUILD_DIR/scripts"
mkdir -p "$BUILD_DIR/root/Applications"
ditto "$PROJECT_ROOT/.build/House Keeping.app" "$BUILD_DIR/root/Applications/House Keeping.app"

# Copy binary
cp "$BINARY" "$BUILD_DIR/root${INSTALL_PREFIX}/bin/house_keeping"
chmod 755 "$BUILD_DIR/root${INSTALL_PREFIX}/bin/house_keeping"

cp "$PROJECT_ROOT/scripts/postinstall.sh" "$BUILD_DIR/scripts/postinstall"
chmod 755 "$BUILD_DIR/scripts/postinstall"

echo "==> Building package: $PKG_NAME"
pkgbuild --analyze --root "$BUILD_DIR/root" "$BUILD_DIR/components.plist"
# Always install to /Applications, even if a development copy is registered with Launch Services.
if /usr/libexec/PlistBuddy -c 'Print :0:BundleIsRelocatable' "$BUILD_DIR/components.plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$BUILD_DIR/components.plist"
else
    /usr/libexec/PlistBuddy -c 'Add :0:BundleIsRelocatable bool false' "$BUILD_DIR/components.plist"
fi
pkgbuild \
    --root "$BUILD_DIR/root" \
    --component-plist "$BUILD_DIR/components.plist" \
    --scripts "$BUILD_DIR/scripts" \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    --install-location "/" \
    "$PROJECT_ROOT/$PKG_NAME"

# Clean up
rm -rf "$BUILD_DIR"

echo ""
echo "==> Package created: $PROJECT_ROOT/$PKG_NAME"
echo "    Install with:  sudo installer -pkg $PKG_NAME -target /"
echo "    Or double-click the .pkg file in Finder."
