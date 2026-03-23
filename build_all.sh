#!/usr/bin/env bash
# build_all.sh — Full build pipeline for MiniFlow.app
#
# Steps:
#   1. Bundle Python backend with PyInstaller → miniflow-engine/dist/miniflow-engine
#   2. Build Swift app with xcodebuild (Release, ad-hoc signed)
#   3. Copy engine binary into .app bundle
#   4. Package into DMG → build/MiniFlow-<version>.dmg
#
# Usage:
#   chmod +x build_all.sh
#   ./build_all.sh
#
# Optional env vars:
#   VERSION=0.2.0   (default: read from pbxproj MARKETING_VERSION)
#   SKIP_BACKEND=1  (skip PyInstaller step if already built)
#   CONFIG=Debug    (default: Release)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="MiniFlow"
XCODE_PRODUCT_NAME="MiniflowApp"
XCODE_PROJECT="$SCRIPT_DIR/MiniflowApp/MiniflowApp.xcodeproj"
SCHEME="MiniflowApp"
CONFIG="${CONFIG:-Release}"
BUILD_DIR="$SCRIPT_DIR/build"
BUILT_APP_PATH="$BUILD_DIR/$XCODE_PRODUCT_NAME.app"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
ENGINE_DIST="$SCRIPT_DIR/miniflow-engine/dist/miniflow-engine"
ENGINE_BINARY="$ENGINE_DIST/miniflow-engine"

# ── Resolve version ────────────────────────────────────────────────────────────

if [ -z "${VERSION:-}" ]; then
  VERSION=$(grep -m1 'MARKETING_VERSION' "$XCODE_PROJECT/project.pbxproj" \
    | sed 's/.*= *//;s/;//;s/ *//')
fi
VERSION="${VERSION:-0.2.0}"
echo "→ MiniFlow version: $VERSION  (config: $CONFIG)"

# ── Step 1: Build Python backend ──────────────────────────────────────────────

if [ "${SKIP_BACKEND:-0}" = "1" ]; then
  echo "→ Skipping backend build (SKIP_BACKEND=1)"
  if [ ! -f "$ENGINE_BINARY" ]; then
    echo "✗ Engine binary not found at $ENGINE_BINARY"
    echo "  Expected onedir layout: miniflow-engine/dist/miniflow-engine/miniflow-engine"
    exit 1
  fi
else
  echo ""
  echo "━━━ Step 1/4: Building Python backend ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bash "$SCRIPT_DIR/build_backend.sh"
fi

# ── Step 2: Build Swift app ───────────────────────────────────────────────────

echo ""
echo "━━━ Step 2/4: Building Swift app ($CONFIG) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

rm -rf "$APP_PATH"

xcodebuild \
  -project "$XCODE_PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  clean build

# Rename MiniflowApp.app → MiniFlow.app
if [ -d "$BUILT_APP_PATH" ]; then
  rm -rf "$APP_PATH"
  mv "$BUILT_APP_PATH" "$APP_PATH"
fi

if [ ! -d "$APP_PATH" ]; then
  echo "✗ Expected app at $APP_PATH but it was not found after build"
  echo "  Check xcodebuild output above for errors"
  exit 1
fi

echo "✓ Swift app built: $APP_PATH"

# ── Step 3: Copy engine binary into .app ─────────────────────────────────────

echo ""
echo "━━━ Step 3/4: Copying engine binary into .app ━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Copy the entire onedir bundle into Contents/Resources/miniflow-engine/
# (Resources, not MacOS — codesign does not try to sign Resources content,
# avoiding failures on .dist-info dirs inside the PyInstaller bundle)
mkdir -p "$APP_PATH/Contents/Resources"
rm -rf "$APP_PATH/Contents/Resources/miniflow-engine"
cp -R "$ENGINE_DIST" "$APP_PATH/Contents/Resources/miniflow-engine"
chmod +x "$APP_PATH/Contents/Resources/miniflow-engine/miniflow-engine"
echo "✓ Engine bundle copied to $APP_PATH/Contents/Resources/miniflow-engine/"

# Re-sign only the main Swift executable (not --deep, which would recurse
# into Resources and fail on non-bundle .dist-info dirs)
echo "→ Re-signing main executable..."
codesign --force --sign - "$APP_PATH/Contents/MacOS/MiniflowApp"
echo "✓ App re-signed (ad-hoc)"

# Strip quarantine so users can open without Gatekeeper warning
xattr -cr "$APP_PATH" 2>/dev/null || true
echo "✓ Quarantine attribute removed"

# ── Step 4: Create DMG ────────────────────────────────────────────────────────

echo ""
echo "━━━ Step 4/4: Creating DMG ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

APP_PATH="$APP_PATH" VERSION="$VERSION" bash "$SCRIPT_DIR/build_dmg.sh"

echo ""
echo "┌─────────────────────────────────────────────────────────┐"
echo "│  ✓ Build complete!                                       │"
printf "│  DMG: build/%s-%s.dmg\n" "$APP_NAME" "$VERSION"
echo "└─────────────────────────────────────────────────────────┘"
