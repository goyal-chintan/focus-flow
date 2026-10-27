#!/bin/sh
# install.sh — Build FocusFlow (release), install it, register it with macOS, and relaunch it.
#
# Usage:
#   ./Scripts/install.sh                      # install to ~/Applications and launch
#   INSTALL_DIR=/Applications ./Scripts/install.sh
#   NO_LAUNCH=1 ./Scripts/install.sh          # install without launching
#
# Re-run it after every `git pull`. It always rebuilds and replaces the installed copy.
#
# Registration: macOS finds apps through LaunchServices (Spotlight, Launchpad, `open -a`).
# `lsregister -f` registers the new bundle right away; `mdimport` refreshes its Spotlight
# entry. Nothing else is needed — Spotlight indexes ~/Applications and /Applications itself.

set -eu

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib/toolchain.sh"
cd "$REPO_DIR"

APP_NAME="FocusFlow"
BUNDLE_ID="com.focusflow.app"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
BUILD_DIR="$REPO_DIR/.build/release"
STAGED_APP="$BUILD_DIR/$APP_NAME.app"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-FocusFlow Development}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { printf "${GREEN}✓${NC} %s\n" "$1"; }
info() { printf "${BLUE}ℹ${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
err()  { printf "${RED}✗${NC} %s\n" "$1" >&2; exit 1; }

# ── 1. Toolchain and signing identity ────────────────────────────────────────
focusflow_use_xcode_toolchain || exit 1
info "Toolchain: ${DEVELOPER_DIR:-$(xcode-select -p)}"

# A stable certificate keeps Calendar/Reminders/Automation grants across reinstalls;
# an ad-hoc signature changes every build and macOS forgets the grants.
identity_hash() {
    security find-identity -v -p codesigning 2>/dev/null \
        | awk -v id="$CODESIGN_IDENTITY" '$0 ~ "\"" id "\"" { print $2; exit }'
}
SIGN_HASH="$(identity_hash)"
if [ -z "$SIGN_HASH" ]; then
    warn "Certificate \"$CODESIGN_IDENTITY\" not found; creating it (one time)."
    "$SCRIPT_DIR/setup-codesign.sh"
    SIGN_HASH="$(identity_hash)"
    [ -n "$SIGN_HASH" ] || err "Certificate \"$CODESIGN_IDENTITY\" is still missing. See Scripts/setup-codesign.sh."
fi

# ── 2. Release build ─────────────────────────────────────────────────────────
info "Building $APP_NAME (release)…"
swift build -c release --product "$APP_NAME" || err "Build failed"
ok "Build succeeded"

# ── 3. Assemble the bundle ───────────────────────────────────────────────────
# Version: marketing version from VERSION (default 1.0); build number = commit count, so every
# install is newer than the last and LaunchServices does not keep stale metadata.
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

rm -rf "$STAGED_APP"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$STAGED_APP/Contents/MacOS/$APP_NAME"
if [ -d "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" ]; then
    cp -R "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" "$STAGED_APP/Contents/Resources/"
fi
if [ -f "Sources/$APP_NAME/AppIcon.icns" ]; then
    cp "Sources/$APP_NAME/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
fi

cat > "$STAGED_APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>FocusFlowGitCommit</key>
    <string>$COMMIT</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCalendarsUsageDescription</key>
    <string>FocusFlow records completed focus sessions to your selected calendar and lets you review session timelines.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>FocusFlow records completed focus sessions to your selected calendar and lets you review session timelines.</string>
    <key>NSRemindersUsageDescription</key>
    <string>FocusFlow syncs your reminders so you can plan sessions, update tasks, and mark them complete.</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>FocusFlow syncs your reminders so you can plan sessions, update tasks, and mark them complete.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>FocusFlow reads the active tab URL from supported browsers so it can identify distracting websites and show domain-level coaching.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>FocusFlow reads the active browser window title to identify distracting websites during focus sessions. No screen content is captured or stored.</string>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
</dict>
</plist>
PLIST
plutil -lint -s "$STAGED_APP/Contents/Info.plist" || err "Generated Info.plist is invalid"

# ── 4. Sign and verify ───────────────────────────────────────────────────────
codesign --force --sign "$SIGN_HASH" --identifier "$BUNDLE_ID" --timestamp=none "$STAGED_APP" \
    || err "Code signing failed"
codesign --verify --strict "$STAGED_APP" || err "Signature does not verify"
ok "Bundle $VERSION ($BUILD_NUMBER, $COMMIT) signed with \"$CODESIGN_IDENTITY\""

# ── 5. Quit the running copy ─────────────────────────────────────────────────
# Ask politely first so the app saves its session checkpoint; force only if it hangs.
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    info "Quitting the running $APP_NAME…"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    i=0
    while pgrep -x "$APP_NAME" >/dev/null 2>&1 && [ "$i" -lt 20 ]; do
        sleep 0.25; i=$((i + 1))
    done
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        warn "Did not quit in 5 s; stopping it."
        pkill -x "$APP_NAME" || true
        sleep 0.5
    fi
    ok "Stopped"
fi

# ── 6. Install (replace in one step) ─────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
TMP_APP="$INSTALL_DIR/.$APP_NAME.app.installing"
rm -rf "$TMP_APP"
ditto "$STAGED_APP" "$TMP_APP"
if [ -d "$INSTALLED_APP" ]; then
    "$LSREGISTER" -u "$INSTALLED_APP" >/dev/null 2>&1 || true
    rm -rf "$INSTALLED_APP"
fi
mv "$TMP_APP" "$INSTALLED_APP"
ok "Installed to $INSTALLED_APP"

# ── 7. Register with LaunchServices and Spotlight ────────────────────────────
"$LSREGISTER" -f "$INSTALLED_APP" || warn "lsregister failed; Spotlight will pick the app up on its own shortly."
mdimport "$INSTALLED_APP" >/dev/null 2>&1 || true
ok "Registered with LaunchServices and Spotlight"

# Another copy elsewhere shows up twice in Spotlight and may be the one `open -a` picks.
for other in "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"; do
    if [ "$other" != "$INSTALLED_APP" ] && [ -d "$other" ]; then
        warn "Another copy exists at $other. Remove it to avoid duplicates:  rm -rf \"$other\""
    fi
done

# ── 8. Launch ────────────────────────────────────────────────────────────────
if [ "${NO_LAUNCH:-0}" = "1" ]; then
    ok "Done. Launch it from Spotlight or with: open -a $APP_NAME"
    exit 0
fi
open "$INSTALLED_APP"
i=0
while ! pgrep -x "$APP_NAME" >/dev/null 2>&1 && [ "$i" -lt 20 ]; do
    sleep 0.25; i=$((i + 1))
done
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    ok "$APP_NAME is running (menu bar). Find it later in Spotlight: \"$APP_NAME\"."
else
    err "$APP_NAME did not start. Check Console.app for crash reports from \"$APP_NAME\"."
fi
