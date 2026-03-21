#!/bin/sh
set -eu

INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP_NAME="FocusFlow"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
DRY_RUN="${DRY_RUN:-0}"

# Color codes
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

log_info "Uninstalling $APP_NAME from $INSTALL_DIR..."

# Check if app exists
if [ ! -d "$INSTALLED_APP" ]; then
  log_warn "$APP_NAME not found at $INSTALLED_APP"
  exit 0
fi

# Kill running instance
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

# Remove Spotlight index
log_info "Removing from Spotlight index..."
if command -v mdimport >/dev/null 2>&1; then
  dry_run_exec mdimport -r "$INSTALLED_APP" 2>/dev/null || true
  log_success "Spotlight index cleared"
else
  log_warn "mdimport not available, skipping Spotlight cleanup"
fi

# Remove app bundle
log_info "Removing app bundle..."
dry_run_exec rm -rf "$INSTALLED_APP"
log_success "Removed $INSTALLED_APP"

log_info ""
log_success "$APP_NAME has been uninstalled"

exit 0
