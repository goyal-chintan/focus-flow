#!/bin/sh
set -eu

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
DRY_RUN="${DRY_RUN:-0}"

APP_NAME="FocusFlow"
BUILD_DIR="$REPO_DIR/.build/debug"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BUILT_BINARY="$MACOS/$APP_NAME"
INSTALLED_BINARY="$INSTALLED_APP/Contents/MacOS/$APP_NAME"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
  printf "${BLUE}ℹ${NC} %s\n" "$1"
}

log_success() {
  printf "${GREEN}✓${NC} %s\n" "$1"
}

log_error() {
  printf "${RED}✗${NC} %s\n" "$1" >&2
}

log_warn() {
  printf "${YELLOW}⚠${NC} %s\n" "$1"
}

dry_run_exec() {
  if [ "$DRY_RUN" = "1" ]; then
    log_info "[DRY-RUN] $*"
  else
    "$@"
  fi
}

resolve_codesign_identity_hash() {
  identity_name="$1"
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -v identity="$identity_name" '$0 ~ "\"" identity "\"" { print $2; exit }'
}

count_codesign_identity_matches() {
  identity_name="$1"
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -v identity="$identity_name" '$0 ~ "\"" identity "\"" { count++ } END { print count+0 }'
}

ensure_codesign_identity() {
  CODESIGN_IDENTITY_NAME="${CODESIGN_IDENTITY:-FocusFlow Development}"
  CODESIGN_IDENTITY_HASH="$(resolve_codesign_identity_hash "$CODESIGN_IDENTITY_NAME")"
  if [ -n "$CODESIGN_IDENTITY_HASH" ]; then
    match_count="$(count_codesign_identity_matches "$CODESIGN_IDENTITY_NAME")"
    if [ "$match_count" -gt 1 ]; then
      log_warn "Multiple \"$CODESIGN_IDENTITY_NAME\" identities found; using SHA $CODESIGN_IDENTITY_HASH"
    fi
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log_info "[DRY-RUN] Would create \"$CODESIGN_IDENTITY_NAME\" via $SCRIPT_DIR/setup-codesign.sh"
    CODESIGN_IDENTITY_HASH="$CODESIGN_IDENTITY_NAME"
    return 0
  fi

  log_warn "Certificate \"$CODESIGN_IDENTITY_NAME\" not found. Bootstrapping it now..."
  if ! "$SCRIPT_DIR/setup-codesign.sh"; then
    log_error "Failed to create code-signing certificate \"$CODESIGN_IDENTITY_NAME\"."
    exit 1
  fi

  CODESIGN_IDENTITY_HASH="$(resolve_codesign_identity_hash "$CODESIGN_IDENTITY_NAME")"
  if [ -z "$CODESIGN_IDENTITY_HASH" ]; then
    log_error "Certificate \"$CODESIGN_IDENTITY_NAME\" is still unavailable after setup."
    exit 1
  fi
}

verify_non_adhoc_signature() {
  target_path="$1"
  target_label="${2:-App bundle}"
  if [ "$DRY_RUN" = "1" ]; then
    return 0
  fi

  if codesign -dv --verbose=4 "$target_path" 2>&1 | grep -q "^Signature=adhoc"; then
    log_error "$target_label is ad-hoc signed; Calendar/Reminder permissions will be reset."
    log_error "Run ./Scripts/setup-codesign.sh and re-run this installer."
    exit 1
  fi
}

# Calculate MD5 checksum of a file
get_checksum() {
  if [ -f "$1" ]; then
    md5 -q "$1"
  else
    echo ""
  fi
}

# Ensure install directory exists
if [ "$DRY_RUN" != "1" ]; then
  mkdir -p "$INSTALL_DIR"
fi

log_info "Building $APP_NAME..."
cd "$REPO_DIR"

if ! swift build --product "$APP_NAME"; then
  log_error "Swift build failed"
  exit 1
fi
log_success "Build completed"

# Calculate checksum of newly built binary
log_info "Checking if app is already up-to-date..."
NEW_BINARY_CHECKSUM="$(get_checksum "$BUILD_DIR/$APP_NAME")"
INSTALLED_BINARY_CHECKSUM="$(get_checksum "$INSTALLED_BINARY")"

# Compare file timestamps instead of checksums (more reliable due to code signing)
NEW_BINARY_TIME="$(stat -f %m "$BUILD_DIR/$APP_NAME" 2>/dev/null || echo 0)"
INSTALLED_BINARY_TIME="$(stat -f %m "$INSTALLED_BINARY" 2>/dev/null || echo 0)"
INSTALLED_IS_ADHOC=0
if [ -d "$INSTALLED_APP" ] && codesign -dv --verbose=4 "$INSTALLED_APP" 2>&1 | grep -q "^Signature=adhoc"; then
  INSTALLED_IS_ADHOC=1
  log_warn "Installed app is ad-hoc signed; forcing reinstall to preserve Calendar/Reminder permissions."
fi

# If app is already installed and timestamps match, skip update
if [ -n "$INSTALLED_BINARY_CHECKSUM" ] && [ "$NEW_BINARY_TIME" -le "$INSTALLED_BINARY_TIME" ] && [ "$INSTALLED_IS_ADHOC" -eq 0 ]; then
  log_success "Installed app is already the latest build"
  
  # Kill any running instances
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    log_info "Quitting running instance..."
    pgrep -x "$APP_NAME" | while IFS= read -r pid; do
      kill "$pid" 2>/dev/null || true
    done
    sleep 0.5
    log_success "App instance stopped"
  fi
  
  log_info "No update needed - exiting"
  exit 0
fi

# If checksums differ, proceed with update
if [ -n "$INSTALLED_BINARY_CHECKSUM" ]; then
  log_warn "App update available - rebuilding and reinstalling"
fi

# Create .app bundle structure
log_info "Creating app bundle structure..."
dry_run_exec rm -rf "$APP_BUNDLE"
dry_run_exec mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
log_info "Copying executable..."
dry_run_exec cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"

# Create Info.plist
log_info "Generating Info.plist..."
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
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>FocusFlow records completed focus sessions to your selected calendar and lets you review session timelines.</string>
    <key>NSRemindersUsageDescription</key>
    <string>FocusFlow syncs your reminders so you can plan sessions, update tasks, and mark them complete.</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>FocusFlow syncs your reminders so you can plan sessions, update tasks, and mark them complete.</string>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>FocusFlow reads the active browser window title to identify distracting websites during focus sessions. No screen content is captured or stored.</string>
</dict>
</plist>
PLIST

# Copy resources if they exist
if [ -d "$BUILD_DIR/FocusFlow_FocusFlow.bundle" ]; then
  log_info "Copying resources..."
  dry_run_exec cp -R "$BUILD_DIR/FocusFlow_FocusFlow.bundle" "$RESOURCES/"
fi

# Include app icon
if [ -f "Sources/FocusFlow/AppIcon.icns" ]; then
  log_info "Copying app icon..."
  dry_run_exec cp "Sources/FocusFlow/AppIcon.icns" "$RESOURCES/"
fi

log_success "App bundle created at $APP_BUNDLE"

# Code sign with stable certificate so TCC permissions persist across updates.
# Run Scripts/setup-codesign.sh once to create the "FocusFlow Development" cert.
log_info "Code signing app bundle..."
ensure_codesign_identity
if ! dry_run_exec codesign --force --sign "$CODESIGN_IDENTITY_HASH" --identifier com.focusflow.app --timestamp=none "$APP_BUNDLE"; then
  log_error "Code signing failed with identity \"$CODESIGN_IDENTITY_NAME\"."
  exit 1
fi
verify_non_adhoc_signature "$APP_BUNDLE" "Build app bundle"
log_success "Signed with \"$CODESIGN_IDENTITY_NAME\" ($CODESIGN_IDENTITY_HASH)"

# Clean up stale Spotlight entries BEFORE installing
log_info "Cleaning up Spotlight cache..."
if command -v mdutil >/dev/null 2>&1; then
  # Disable Spotlight indexing for the directory
  if ! dry_run_exec mdutil -i off "$INSTALL_DIR" 2>/dev/null; then
    log_warn "Could not disable Spotlight indexing for $INSTALL_DIR; continuing."
  fi
  # Remove old entries
  dry_run_exec rm -rf "$INSTALL_DIR/.Spotlight-V100" 2>/dev/null || true
  # Re-enable Spotlight indexing
  if ! dry_run_exec mdutil -i on "$INSTALL_DIR" 2>/dev/null; then
    log_warn "Could not re-enable Spotlight indexing for $INSTALL_DIR; continuing."
  fi
  log_success "Spotlight cache cleaned"
fi

# Also remove any system-wide duplicate at /Applications
if [ -d "/Applications/FocusFlow.app" ]; then
  log_warn "Found duplicate at /Applications/FocusFlow.app, removing..."
  dry_run_exec rm -rf "/Applications/FocusFlow.app" 2>/dev/null || true
fi

# Kill any running instances before replacing
log_info "Stopping any running instances..."
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  pgrep -x "$APP_NAME" | while IFS= read -r pid; do
    dry_run_exec kill "$pid" 2>/dev/null || true
  done
  sleep 0.5
  log_success "Application stopped"
else
  log_info "No running instances"
fi

# Install to Applications folder
log_info "Installing to $INSTALL_DIR..."
if [ -e "$INSTALLED_APP" ]; then
  log_warn "Removing previous installation at $INSTALLED_APP"
  dry_run_exec rm -rf "$INSTALLED_APP"
fi

dry_run_exec cp -R "$APP_BUNDLE" "$INSTALLED_APP"
verify_non_adhoc_signature "$INSTALLED_APP" "Installed app"
log_success "Installed to $INSTALLED_APP"

# Update Spotlight index
log_info "Registering with Spotlight..."
if command -v mdimport >/dev/null 2>&1; then
  # Force re-index
  dry_run_exec mdimport -r "$INSTALLED_APP" 2>/dev/null || true
  sleep 1
  dry_run_exec mdimport "$INSTALLED_APP" 2>/dev/null || true
  
  # Also clean up Library caches
  if [ "$DRY_RUN" != "1" ]; then
    find ~/Library/Metadata/CoreSpotlight -name "*focusflow*" -delete 2>/dev/null || true
  fi
  log_success "Spotlight index updated"
else
  log_warn "mdimport not available, skipping Spotlight indexing"
fi

# Update macOS metadata cache
log_info "Updating macOS metadata..."
dry_run_exec touch "$INSTALL_DIR"
if command -v dscacheutil >/dev/null 2>&1; then
  dry_run_exec dscacheutil -q group >/dev/null 2>&1 || true
fi

# Make binary executable just to be sure
if [ "$DRY_RUN" != "1" ]; then
  chmod +x "$INSTALLED_APP/Contents/MacOS/$APP_NAME"
fi
log_success "Binary permissions set"

# Verify installation
if [ "$DRY_RUN" != "1" ]; then
  if [ ! -x "$INSTALLED_APP/Contents/MacOS/$APP_NAME" ]; then
    log_error "Verification failed: executable not found at expected location"
    exit 1
  fi
  log_success "Installation verified"
fi

log_info ""
log_success "$APP_NAME is ready to use!"
log_info "Location: $INSTALLED_APP"
log_info "Launch with: open -a FocusFlow"
log_info "Or find it in Spotlight search"

exit 0
