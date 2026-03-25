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

if [ -n "${APPLE_TEAM_ID:-}" ]; then
  SIGN_IDENTITY="Developer ID Application"
  DEV_TEAM="$APPLE_TEAM_ID"
else
  SIGN_IDENTITY="-"
  DEV_TEAM=""
fi

xcodebuild \
  -project "$XCODE_PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$DEV_TEAM" \
  ENABLE_HARDENED_RUNTIME=YES \
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

# Re-sign after adding the engine to Resources.
# --deep breaks on PyInstaller .dist-info dirs, so we:
#   1. Sign every Mach-O binary inside the PyInstaller bundle explicitly
#   2. Sign the .app bundle (without --deep)
ENTITLEMENTS="$SCRIPT_DIR/MiniflowApp/MiniflowApp/MiniflowApp.entitlements"
ENGINE_BUNDLE="$APP_PATH/Contents/Resources/miniflow-engine"
if [ -n "${APPLE_TEAM_ID:-}" ]; then
  echo "→ Signing Mach-O binaries in PyInstaller bundle..."
  # Sign all Mach-O binaries: .so, .dylib, executables (no extension), and Python framework binary
  find "$ENGINE_BUNDLE" -type f \( -name "*.so" -o -name "*.dylib" \) \
    -exec codesign --force --sign "Developer ID Application" --options runtime --timestamp {} \;
  find "$ENGINE_BUNDLE" -type f -perm +0111 ! -name "*.py" ! -name "*.txt" ! -name "*.cfg" \
    -exec codesign --force --sign "Developer ID Application" --options runtime --timestamp {} \; 2>/dev/null || true
  echo "→ Signing .app bundle with Developer ID (hardened runtime)..."
  codesign --force --sign "Developer ID Application" \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS" \
    "$APP_PATH"
  echo "✓ App bundle signed with Developer ID"
else
  echo "→ Re-signing .app bundle (ad-hoc)..."
  codesign --force --sign - "$APP_PATH"
  echo "✓ App bundle re-signed (ad-hoc)"
fi

# Strip quarantine so users can open without Gatekeeper warning
xattr -cr "$APP_PATH" 2>/dev/null || true
echo "✓ Quarantine attribute removed"

# ── Step 4: Create DMG ────────────────────────────────────────────────────────

echo ""
echo "━━━ Step 4/4: Creating DMG ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

APP_PATH="$APP_PATH" VERSION="$VERSION" bash "$SCRIPT_DIR/build_dmg.sh"

# ── Notarize DMG ──────────────────────────────────────────────────────────────

DMG_PATH="$SCRIPT_DIR/build/${APP_NAME}-${VERSION}.dmg"
if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
  echo ""
  echo "━━━ Notarizing DMG ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "→ Submitting to Apple notary service (this may take a few minutes)..."
  NOTARY_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait 2>&1)
  echo "$NOTARY_OUTPUT"
  NOTARY_ID=$(echo "$NOTARY_OUTPUT" | grep "^  id:" | head -1 | awk '{print $2}')
  NOTARY_STATUS=$(echo "$NOTARY_OUTPUT" | grep "^  status:" | awk '{print $2}')
  if [ "$NOTARY_STATUS" != "Accepted" ]; then
    echo "✗ Notarization failed (status: $NOTARY_STATUS) — fetching rejection log..."
    if [ -n "$NOTARY_ID" ]; then
      xcrun notarytool log "$NOTARY_ID" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --team-id "$APPLE_TEAM_ID"
    fi
    exit 1
  fi
  echo "→ Stapling notarization ticket (retrying up to 5x for CDN propagation)..."
  for attempt in 1 2 3 4 5; do
    if xcrun stapler staple "$DMG_PATH"; then
      echo "✓ Notarized and stapled"
      break
    fi
    echo "  stapler attempt $attempt failed, waiting 30s..."
    sleep 30
  done
fi

echo ""
echo "┌─────────────────────────────────────────────────────────┐"
echo "│  ✓ Build complete!                                       │"
printf "│  DMG: build/%s-%s.dmg\n" "$APP_NAME" "$VERSION"
echo "└─────────────────────────────────────────────────────────┘"
