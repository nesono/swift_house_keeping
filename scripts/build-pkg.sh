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

echo "==> Preparing package root…"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/root${INSTALL_PREFIX}/bin"
mkdir -p "$BUILD_DIR/scripts"

# Copy binary
cp "$BINARY" "$BUILD_DIR/root${INSTALL_PREFIX}/bin/house_keeping"
chmod 755 "$BUILD_DIR/root${INSTALL_PREFIX}/bin/house_keeping"

# Create postinstall script that sets up log directory
cat > "$BUILD_DIR/scripts/postinstall" << 'POSTINSTALL'
#!/usr/bin/env bash
# Create log directory for the installing user
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
LOG_DIR="$REAL_HOME/Library/Logs/house_keeping"
mkdir -p "$LOG_DIR"
chown "$REAL_USER" "$LOG_DIR"

echo ""
echo "house_keeping installed to /usr/local/bin/house_keeping"
echo ""
echo "Quick start:"
echo "  1. Create ~/.config/house_keeping/config.yaml using the README Quick Start."
echo "  2. Validate:        house_keeping check --verbose"
echo "  3. Preview:         house_keeping dry-run"
echo "  4. Auto-start:      house_keeping install"
echo ""
POSTINSTALL
chmod 755 "$BUILD_DIR/scripts/postinstall"

echo "==> Building package: $PKG_NAME"
pkgbuild \
    --root "$BUILD_DIR/root" \
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
