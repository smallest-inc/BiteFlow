#!/usr/bin/env bash
# build_all.sh — Full build pipeline for BiteFlow.app
#
# Steps:
#   1. Bundle Python backend with PyInstaller → miniflow-engine/dist/miniflow-engine
#   2. Build Swift app with xcodebuild (Release, ad-hoc signed)
#   3. Copy engine binary into .app bundle
#   4. Package into a signed DMG → build/BiteFlow-<version>.dmg
#
# Usage:
#   chmod +x build_all.sh
#   ./build_all.sh
#
# Optional env vars:
#   VERSION=0.2.0   (default: read from pbxproj MARKETING_VERSION)
#   SKIP_BACKEND=1  (skip PyInstaller step if already built)
#   CONFIG=Debug    (default: Release)
#   NOTARY_POLL_SECONDS=30     (default: 30)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="BiteFlow"
XCODE_PRODUCT_NAME="MiniflowApp"
XCODE_PROJECT="$SCRIPT_DIR/MiniflowApp/MiniflowApp.xcodeproj"
SCHEME="MiniflowApp"
CONFIG="${CONFIG:-Release}"
BUILD_DIR="$SCRIPT_DIR/build"
BUILT_APP_PATH="$BUILD_DIR/$XCODE_PRODUCT_NAME.app"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
ENGINE_DIST="$SCRIPT_DIR/miniflow-engine/dist/miniflow-engine"
ENGINE_BINARY="$ENGINE_DIST/miniflow-engine"

resolve_signing_identity() {
  local identities
  if [ -n "${KEYCHAIN_PATH:-}" ]; then
    identities="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null || true)"
  else
    identities=""
  fi
  if [ -z "$identities" ]; then
    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  fi
  echo "→ Available code signing identities:"
  if [ -n "$identities" ]; then
    echo "$identities"
  else
    echo "  (none found)"
  fi
  SIGNING_IDENTITY="$(echo "$identities" | sed -E -n 's/.*"(Developer ID Application:.*)"/\1/p' | head -1)"
  if [ -z "${SIGNING_IDENTITY:-}" ]; then
    echo "✗ Could not resolve a Developer ID Application identity"
    exit 1
  fi
  echo "→ Using signing identity: $SIGNING_IDENTITY"
}

# ── Resolve version ────────────────────────────────────────────────────────────

if [ -z "${VERSION:-}" ]; then
  VERSION=$(grep -m1 'MARKETING_VERSION' "$XCODE_PROJECT/project.pbxproj" \
    | sed 's/.*= *//;s/;//;s/ *//')
fi
VERSION="${VERSION:-0.2.0}"
echo "→ BiteFlow version: $VERSION  (config: $CONFIG)"

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
  resolve_signing_identity
  SIGN_IDENTITY="$SIGNING_IDENTITY"
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

# Rename MiniflowApp.app → BiteFlow.app
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
  echo "→ Signing all code in PyInstaller bundle (inside-out)..."
  # 1. Sign all bare Mach-O files (.so, .dylib) — leaves out framework binaries
  find "$ENGINE_BUNDLE" -type f \( -name "*.so" -o -name "*.dylib" \) \
    -exec codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp {} \;
  # 2. Sign standalone executables (skip anything inside a .framework)
  find "$ENGINE_BUNDLE" -type f -perm +0111 \
    ! -name "*.py" ! -name "*.txt" ! -name "*.cfg" \
    ! -path "*.framework/*" \
    -exec codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp {} \; 2>/dev/null || true
  # 3. Sign versioned framework binaries first. PyInstaller ships Python.framework
  #    with the actual Mach-O at Versions/<ver>/Python, and Apple validates that
  #    inner binary directly during notarization.
  find "$ENGINE_BUNDLE" -path "*.framework/Versions/*" -type f -perm -0111 | while read -r fwbin; do
    echo "  signing framework binary: $fwbin"
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$fwbin"
  done
  # 4. Sign .framework bundles after their inner binaries and resources exist.
  #    Use -depth so nested frameworks are signed before their parents.
  find "$ENGINE_BUNDLE" -name "*.framework" -type d -depth | while read fw; do
    echo "  signing framework: $fw"
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$fw"
  done
  echo "→ Verifying nested framework signatures..."
  find "$ENGINE_BUNDLE" -path "*.framework/Versions/*" -type f -perm -0111 | while read -r fwbin; do
    codesign --verify --strict --verbose=2 "$fwbin"
    codesign -dvv "$fwbin" 2>&1 | grep -E "Identifier=|Timestamp=|Authority="
  done
  # 5. Sign the .app bundle last (no --deep, we already signed everything inside)
  echo "→ Signing .app bundle with Developer ID (hardened runtime)..."
  codesign --force --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS" \
    "$APP_PATH"
  # Verify every nested signature is valid before submitting to Apple
  echo "→ Verifying all signatures..."
  codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1
  echo "→ Checking entitlements for get-task-allow..."
  if codesign -d --entitlements - "$APP_PATH" 2>&1 \
    | grep -A1 "<key>get-task-allow</key>" \
    | grep -q "<true/>"; then
    echo "✗ FATAL: get-task-allow found in entitlements — Apple will reject this"
    codesign -d --entitlements - "$APP_PATH" 2>&1
    exit 1
  fi
  echo "→ Checking secure timestamp and hardened runtime..."
  APP_CODESIGN_INFO="$(codesign -dvv "$APP_PATH" 2>&1)"
  printf '%s\n' "$APP_CODESIGN_INFO" | grep -E "Timestamp=|Authority=|flags="
  if ! printf '%s\n' "$APP_CODESIGN_INFO" | grep -q "flags=.*runtime"; then
    echo "✗ Hardened runtime is missing from app signature"
    exit 1
  fi
  if ! printf '%s\n' "$APP_CODESIGN_INFO" | grep -q "Timestamp="; then
    echo "✗ Secure timestamp is missing from app signature"
    exit 1
  fi
  echo "✓ App bundle signed and verified"
else
  echo "→ Re-signing .app bundle (ad-hoc)..."
  codesign --force --sign - "$APP_PATH"
  echo "✓ App bundle re-signed (ad-hoc)"
fi

# Strip only quarantine xattr — xattr -cr would strip ALL xattrs
# which could affect code signature metadata
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
echo "✓ Quarantine attribute removed"

# ── Step 4: Create DMG ────────────────────────────────────────────────────────

echo ""
echo "━━━ Step 4/4: Creating DMG ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

APP_PATH="$APP_PATH" VERSION="$VERSION" bash "$SCRIPT_DIR/build_dmg.sh"
DMG_PATH="$SCRIPT_DIR/build/${APP_NAME}-${VERSION}.dmg"

if [ -n "${APPLE_TEAM_ID:-}" ]; then
  echo "→ Signing DMG with Developer ID..."
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
  echo "→ Verifying DMG integrity..."
  hdiutil verify "$DMG_PATH"
  echo "→ Verifying DMG signature..."
  codesign --verify --verbose=2 "$DMG_PATH"
  DMG_CODESIGN_INFO="$(codesign -dvv "$DMG_PATH" 2>&1)"
  printf '%s\n' "$DMG_CODESIGN_INFO" | grep -E "Timestamp=|Authority="
  if ! printf '%s\n' "$DMG_CODESIGN_INFO" | grep -q "Timestamp="; then
    echo "✗ Secure timestamp is missing from DMG signature"
    exit 1
  fi
fi

# ── Notarize DMG ──────────────────────────────────────────────────────────────

if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
  echo ""
  echo "━━━ Notarizing DMG ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "→ Validating notarization credentials..."
  if ! xcrun notarytool history \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" >/dev/null 2>&1; then
    echo "✗ Apple notarization credentials failed validation"
    exit 1
  fi
  echo "✓ Apple notarization credentials validated"
  # Submit without --wait (which hangs), then poll manually with a timeout
  echo "→ Submitting to Apple notary service..."
  SUBMIT_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" 2>&1) || true
  echo "$SUBMIT_OUTPUT"
  NOTARY_ID=$(echo "$SUBMIT_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
  if [ -z "$NOTARY_ID" ]; then
    echo "✗ Failed to submit — no submission ID received"
    exit 1
  fi
  NOTARY_POLL_SECONDS="${NOTARY_POLL_SECONDS:-30}"
  echo "→ Submission ID: $NOTARY_ID — polling for result (no timeout, will poll until done)..."
  NOTARY_STATUS=""
  while true; do
    WAIT_OUTPUT=$(xcrun notarytool info "$NOTARY_ID" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" 2>&1) || true
    NOTARY_STATUS=$(echo "$WAIT_OUTPUT" | grep -i "status:" | head -1 | sed 's/.*status:[[:space:]]*//' | sed 's/[[:space:]]*$//')
    echo "  status: $NOTARY_STATUS"
    if [ "$NOTARY_STATUS" = "Accepted" ] || [ "$NOTARY_STATUS" = "Invalid" ] || [ "$NOTARY_STATUS" = "Rejected" ]; then
      break
    fi
    sleep "$NOTARY_POLL_SECONDS"
  done
  echo "→ Notarization result: id=$NOTARY_ID status=$NOTARY_STATUS"
  if [ "$NOTARY_STATUS" != "Accepted" ]; then
    echo "✗ Notarization failed (status: $NOTARY_STATUS) — fetching rejection log..."
    NOTARY_LOG_PATH="$BUILD_DIR/notarytool-${NOTARY_ID}.log"
    xcrun notarytool log "$NOTARY_ID" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" | tee "$NOTARY_LOG_PATH" || true
    exit 1
  fi
  echo "→ Stapling notarization ticket (retrying up to 10x, 60s apart)..."
  STAPLED=false
  for attempt in $(seq 1 10); do
    if xcrun stapler staple "$DMG_PATH"; then
      echo "✓ Notarized and stapled"
      STAPLED=true
      break
    fi
    echo "  stapler attempt $attempt/10 failed, waiting 60s for CDN propagation..."
    sleep 60
  done
  if [ "$STAPLED" != "true" ]; then
    echo "✗ Stapling failed after 10 attempts"
    exit 1
  fi
  echo "→ Validating stapled ticket..."
  xcrun stapler validate "$DMG_PATH"
  echo "→ Assessing DMG with Gatekeeper..."
  spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
  echo "→ Assessing app with Gatekeeper..."
  spctl -a -t exec -vv "$APP_PATH"
fi

echo ""
echo "┌─────────────────────────────────────────────────────────┐"
echo "│  ✓ Build complete!                                       │"
printf "│  DMG: build/%s-%s.dmg\n" "$APP_NAME" "$VERSION"
echo "└─────────────────────────────────────────────────────────┘"
