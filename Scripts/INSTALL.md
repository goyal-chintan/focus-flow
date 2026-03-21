# FocusFlow Installation Guide

## Quick Install & Register

```bash
./Scripts/install-and-register.sh
```

This script:
1. **Builds** the FocusFlow app from source
2. **Creates** a macOS .app bundle with Info.plist and resources
3. **Installs** to `~/Applications/FocusFlow.app`
4. **Registers** with Spotlight for searchability
5. **Verifies** the installation

## Options

### Custom Installation Directory

Install to a different location (default: `~/Applications`):

```bash
INSTALL_DIR=/opt/apps ./Scripts/install-and-register.sh
```

### Dry-Run Mode

Preview what the script will do without making changes:

```bash
DRY_RUN=1 ./Scripts/install-and-register.sh
```

## Features

### ✓ Build Integration
- Runs `swift build` to compile the latest source
- Validates the build succeeds before proceeding

### ✓ Bundle Creation
- Generates proper macOS app bundle structure
- Creates Info.plist with required metadata:
  - Bundle identifier: `com.focusflow.app`
  - Calendar and Reminders usage descriptions
  - Background execution support
- Copies executable, resources, and app icon

### ✓ Application Registration
- Installs app to `~/Applications/` (or custom `$INSTALL_DIR`)
- Makes executable permissions explicit
- Safely replaces existing installations

### ✓ Spotlight Indexing
- Updates Spotlight metadata using `mdimport`
- Makes the app discoverable via Spotlight search
- Falls back gracefully if `mdimport` unavailable

### ✓ Launch Support
- App can be launched via:
  ```bash
  open -a FocusFlow
  ```
- Or found directly in Spotlight

## Troubleshooting

### Script fails on build step
```bash
# Ensure Swift toolchain is installed
swift --version

# Try manual build
cd path/to/FocusFlow
swift build --product FocusFlow
```

### App doesn't appear in Spotlight
```bash
# Re-index manually
mdimport ~/Applications/FocusFlow.app

# Check Spotlight status
mdls ~/Applications/FocusFlow.app | head -10
```

### Permission denied when running script
```bash
chmod +x ./Scripts/install-and-register.sh
```

### Installation went to wrong directory
```bash
# Clean up
rm -rf ~/Applications/FocusFlow.app

# Reinstall to correct location
INSTALL_DIR=/Applications ./Scripts/install-and-register.sh
```

## Script Architecture

### Key Sections
1. **Environment Setup**: Detects paths and validates directories
2. **Build**: Compiles the application via `swift build`
3. **Bundle Creation**: Constructs `.app` bundle with Info.plist
4. **Installation**: Copies to target directory with safe replacement
5. **Spotlight Registration**: Updates system metadata caches
6. **Verification**: Confirms executable is in place and executable

### Safety Features
- `set -e`: Exits on any error (except explicitly allowed)
- `set -u`: Fails on undefined variables
- Checks for existing installations before overwriting
- Verifies permissions on final executable
- Dry-run mode for validation without changes

### Output
Uses color-coded logging:
- 🔵 **Info** (blue): Progress steps
- ✓ **Success** (green): Completed milestones
- ⚠️ **Warning** (yellow): Non-fatal issues
- ✗ **Error** (red): Fatal problems

## Integration with Development Workflow

### Development Loop
```bash
# Edit source...
./Scripts/install-and-register.sh
# App updates automatically in ~/Applications/
```

### CI/CD Integration
```bash
# Dry-run validation
DRY_RUN=1 ./Scripts/install-and-register.sh

# Production install (in CI environment)
INSTALL_DIR=/usr/local/opt/apps ./Scripts/install-and-register.sh
```

## Differences from `run.sh`

| Feature | run.sh | install-and-register.sh |
|---------|--------|-------------------------|
| Build | ✓ | ✓ |
| Create bundle | ✓ | ✓ |
| Launch app | ✓ | ✗ (installs for later use) |
| Install to ~/Applications | ✗ | ✓ |
| Spotlight registration | ✗ | ✓ |
| Custom install dir | ✗ | ✓ (via `$INSTALL_DIR`) |
| Dry-run mode | ✗ | ✓ |
| Colored output | ✗ | ✓ |
| Verification | Implicit | Explicit |

## When to Use Each Script

**Use `run.sh` when:**
- You want to quickly build and test the app
- You're actively developing and need instant feedback
- You want the app to launch immediately

**Use `install-and-register.sh` when:**
- You want a permanent installation in ~/Applications
- You need Spotlight discoverability
- You want to install for multiple users
- You're setting up a development environment
- You want reproducible installation with verification

## Uninstallation

Remove FocusFlow from ~/Applications:

```bash
./Scripts/uninstall.sh
```

This script:
1. Stops any running FocusFlow processes
2. Removes the app from Spotlight index
3. Deletes the app bundle from ~/Applications

### Custom uninstall directory

```bash
INSTALL_DIR=/opt/apps ./Scripts/uninstall.sh
```

### Dry-run uninstall

Preview what will be removed:

```bash
DRY_RUN=1 ./Scripts/uninstall.sh
```

## Available Scripts Summary

| Script | Purpose | Usage |
|--------|---------|-------|
| `run.sh` | Build & test (from repo) | `./Scripts/run.sh` |
| `install-and-register.sh` | Build & install to ~/Applications + Spotlight | `./Scripts/install-and-register.sh` |
| `uninstall.sh` | Remove from ~/Applications | `./Scripts/uninstall.sh` |

