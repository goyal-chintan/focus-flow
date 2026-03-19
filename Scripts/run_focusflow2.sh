#!/bin/bash
set -euo pipefail

APP_NAME="FocusFlow 2 Dev"
BUILD_TARGET="FocusFlow2"
EXECUTABLE_NAME="FocusFlow2"
BUILD_DIR=".build/debug"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BUILD_SHA="$(git rev-parse --short HEAD)"
BUILD_TIMESTAMP_UTC="$(date -u +"%Y%m%dT%H%M%SZ")"

swift build --target "$BUILD_TARGET"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$MACOS/$EXECUTABLE_NAME"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>FocusFlow 2 Dev</string>
    <key>CFBundleIdentifier</key>
    <string>com.focusflow.app.dev</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_SHA}</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>FFBuildSHA</key>
    <string>${BUILD_SHA}</string>
    <key>FFBuildTimestampUTC</key>
    <string>${BUILD_TIMESTAMP_UTC}</string>
    <key>CFBundlePackageName</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
</dict>
</plist>
PLIST

if [ -d "$BUILD_DIR/FocusFlow2_FocusFlow2.bundle" ]; then
    cp -R "$BUILD_DIR/FocusFlow2_FocusFlow2.bundle" "$RESOURCES/"
fi

if [ -f "Sources/FocusFlow2/AppIcon.icns" ]; then
    cp "Sources/FocusFlow2/AppIcon.icns" "$RESOURCES/"
fi

echo "Built $APP_BUNDLE"

pkill -x FocusFlow2 2>/dev/null || true
sleep 0.5

open "$APP_BUNDLE"
echo "Launched FocusFlow2"
