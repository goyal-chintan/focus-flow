#!/bin/sh
set -eu

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

APP_NAME="FocusFlow"
BUILD_DIR="$REPO_DIR/.build/debug"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Build first
swift build --product "$APP_NAME"

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
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>FocusFlow</string>
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

# Copy resources if they exist
if [ -d "$BUILD_DIR/FocusFlow_FocusFlow.bundle" ]; then
    cp -R "$BUILD_DIR/FocusFlow_FocusFlow.bundle" "$RESOURCES/"
fi

# Include app icon
if [ -f "Sources/FocusFlow/AppIcon.icns" ]; then
    cp "Sources/FocusFlow/AppIcon.icns" "$RESOURCES/"
fi

echo "Built $APP_BUNDLE"

# Kill existing instance
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    pgrep -x "$APP_NAME" | while IFS= read -r pid; do
        kill "$pid" 2>/dev/null || true
    done
fi
sleep 0.5

# Launch
open -n "$APP_BUNDLE"
sleep 2

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "Launched $APP_NAME"
    exit 0
fi

echo "App bundle launch did not stay running; trying direct binary..."
LAUNCH_LOG="/tmp/focusflow-launch.log"
"$MACOS/$APP_NAME" >"$LAUNCH_LOG" 2>&1 &
DIRECT_PID=$!
sleep 2

if kill -0 "$DIRECT_PID" 2>/dev/null; then
    echo "Launched $APP_NAME (direct binary fallback)"
    exit 0
fi

echo "Failed to launch $APP_NAME. Last runtime log:"
tail -n 80 "$LAUNCH_LOG" 2>/dev/null || true
exit 1
