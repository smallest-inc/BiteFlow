#!/usr/bin/env bash
# build_dmg.sh — Package MiniFlow.app into a distributable DMG.
#
# Prerequisites:
#   1. Build the Python backend: ./build_backend.sh
#   2. Build the Swift .app in Xcode (Product -> Archive, or Product -> Build)
#   3. Ensure engine bundle exists inside the app:
#        build/MiniFlow.app/Contents/Resources/miniflow-engine/miniflow-engine
#
# Usage:
#   chmod +x build_dmg.sh
#   APP_PATH=build/MiniFlow.app ./build_dmg.sh
#
# Or override defaults:
#   APP_PATH=/path/to/MiniFlow.app VERSION=0.2.0 ./build_dmg.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="MiniFlow"
VERSION="${VERSION:-0.2.0}"
APP_PATH="${APP_PATH:-$SCRIPT_DIR/build/$APP_NAME.app}"
DMG_DIR="$SCRIPT_DIR/build/dmg_staging"
OUTPUT_DMG="$SCRIPT_DIR/build/${APP_NAME}-${VERSION}.dmg"

# ── Validate ──────────────────────────────────────────────────────────────────

if [ ! -d "$APP_PATH" ]; then
  echo "✗ App not found at: $APP_PATH"
  echo "  Build MiniFlow.app in Xcode first, then set APP_PATH."
  exit 1
fi

ENGINE_BINARY="$APP_PATH/Contents/Resources/miniflow-engine/miniflow-engine"
if [ ! -f "$ENGINE_BINARY" ]; then
  echo "✗ miniflow-engine binary not found inside .app"
  echo "  Run ./build_all.sh to build everything from scratch."
  exit 1
fi

# ── Stage ─────────────────────────────────────────────────────────────────────

echo "→ Staging DMG contents..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$APP_PATH" "$DMG_DIR/$APP_NAME.app"
ln -s /Applications "$DMG_DIR/Applications"

# ── Create DMG ────────────────────────────────────────────────────────────────

echo "→ Creating DMG..."
rm -f "$OUTPUT_DMG"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$DMG_DIR" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$OUTPUT_DMG"

rm -rf "$DMG_DIR"
chmod 644 "$OUTPUT_DMG"

echo ""
echo "✓ DMG ready: $OUTPUT_DMG"
