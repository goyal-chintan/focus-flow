#!/bin/bash
set -e

APP_NAME="FocusFlow"
BUILD_DIR=".build/debug"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Build first
swift build

# Create .app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"

# Create Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>FocusFlow</string>
    <key>CFBundleIdentifier</key>
    <string>com.focusflow.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageName</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>FocusFlow</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
</dict>
</plist>
PLIST

# Copy resources if they exist
if [ -d "$BUILD_DIR/FocusFlow_FocusFlow.bundle" ]; then
    cp -R "$BUILD_DIR/FocusFlow_FocusFlow.bundle" "$RESOURCES/"
fi

echo "Built $APP_BUNDLE"

# Kill existing instance
pkill -x FocusFlow 2>/dev/null || true
sleep 0.5

# Launch
open "$APP_BUNDLE"
echo "Launched FocusFlow"
