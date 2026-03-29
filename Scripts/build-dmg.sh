#!/bin/sh
# build-dmg.sh — Build FocusFlow.app (release) and package it into a distributable DMG.
#
# Usage:
#   ./Scripts/build-dmg.sh                  # version defaults to 1.0.0
#   VERSION=1.2.0 ./Scripts/build-dmg.sh    # explicit version
#
# Output: Artifacts/FocusFlow-<version>.dmg

set -eu

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

APP_NAME="FocusFlow"
VERSION="${VERSION:-1.0.0}"
BUILD_DIR="$REPO_DIR/.build/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ARTIFACTS_DIR="$REPO_DIR/Artifacts"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$ARTIFACTS_DIR/$DMG_NAME"

# ── Color helpers ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { printf "${GREEN}✓${NC} %s\n" "$1"; }
info() { printf "${BLUE}ℹ${NC} %s\n" "$1"; }
err()  { printf "${RED}✗${NC} %s\n" "$1" >&2; exit 1; }

# ── 1. Release build ──────────────────────────────────────────────────────────
info "Building $APP_NAME $VERSION (release)…"
swift build -c release --product "$APP_NAME" || err "Swift build failed"
ok "Build succeeded"

# ── 2. Assemble .app bundle ───────────────────────────────────────────────────
info "Assembling .app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

# Info.plist — merge keys from source with bundle-required fields
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.focusflow.app</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCalendarsUsageDescription</key>
    <string>FocusFlow records completed focus sessions to your selected calendar and lets you review session timelines.</string>
    <key>NSRemindersUsageDescription</key>
    <string>FocusFlow syncs your reminders so you can plan sessions, update tasks, and mark them complete.</string>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
</dict>
</plist>
PLIST

# Resources bundle (assets)
if [ -d "$BUILD_DIR/FocusFlow_FocusFlow.bundle" ]; then
    cp -R "$BUILD_DIR/FocusFlow_FocusFlow.bundle" "$RESOURCES/"
fi

# App icon
if [ -f "Sources/FocusFlow/AppIcon.icns" ]; then
    cp "Sources/FocusFlow/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

ok "App bundle assembled at $APP_BUNDLE"

# ── 3. Code-sign (ad-hoc; replace '-' with 'Developer ID Application: …' if enrolled) ──
info "Code-signing…"
codesign --force --deep --sign - \
         --identifier com.focusflow.app \
         --timestamp=none \
         "$APP_BUNDLE"
ok "Signed (ad-hoc)"

# ── 4. Build DMG ──────────────────────────────────────────────────────────────
mkdir -p "$ARTIFACTS_DIR"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP_BUNDLE" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

info "Creating $DMG_NAME…"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

ok "DMG ready: $DMG_PATH"

# ── 5. Print SHA-256 (needed for Homebrew Cask) ───────────────────────────────
SHA=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
info "SHA-256: $SHA"
info "Use this hash in Scripts/homebrew/focusflow.rb"
