# Smart Install & Register Script

## Overview

The `install-and-register-smart.sh` script provides intelligent installation with:
- **Smart detection**: Only rebuilds if source code changed
- **Single instance**: One app in ~/Applications, one Spotlight entry, one menu bar item  
- **Fast updates**: Skip installation if already running latest build
- **Clean operation**: Removes stale Spotlight cache before installing

## Quick Start

```bash
# Install or update (only rebuilds if needed)
./Scripts/install-and-register-smart.sh

# If already latest version:
✓ Installed app is already the latest build
ℹ No update needed - exiting

# If code changed:
⚠ App update available - rebuilding and reinstalling
[performs full build + install + Spotlight registration]
```

## How It Works

### Smart Detection Algorithm

1. **Build** the app from source (always)
2. **Compare** the newly built binary with the installed version
   - Uses file modification time (more reliable than checksums due to code signing)
3. **Decision**:
   - If **timestamps match** → Already latest build → Quit app + exit
   - If **timestamps differ** → New version → Proceed to install

### Why Timestamps?

Code signing changes the binary content even if the source code is identical. Using timestamps of the original build output is more reliable than comparing checksums.

## Features

✅ **Smart Skip**: No rebuild if already latest  
✅ **Automatic Cleanup**: Removes stale Spotlight entries  
✅ **Single Instance**: One app, one Spotlight entry, one menu bar item  
✅ **Process Management**: Quits running instances gracefully  
✅ **Code Signing**: Stable certificate signing for TCC persistence  
✅ **Verification**: Confirms installation success  
✅ **Dry-run Support**: Preview without changes (DRY_RUN=1)

## Usage Examples

### Basic Install
```bash
./Scripts/install-and-register-smart.sh
```

### Custom Location
```bash
INSTALL_DIR=/opt/apps ./Scripts/install-and-register-smart.sh
```

### Preview Changes (No Install)
```bash
DRY_RUN=1 ./Scripts/install-and-register-smart.sh
```

### Force Rebuild (Skip Detection)
```bash
# Touch a source file to trigger rebuild
touch Sources/FocusFlow/main.swift
./Scripts/install-and-register-smart.sh
```

## Output Examples

### First Run (Installation)
```
ℹ Building FocusFlow...
✓ Build completed
ℹ Checking if app is already up-to-date...
ℹ Creating app bundle structure...
ℹ Copying executable...
...
✓ FocusFlow is ready to use!
```

### Second Run (No Update Needed)
```
ℹ Building FocusFlow...
✓ Build completed
ℹ Checking if app is already up-to-date...
✓ Installed app is already the latest build
ℹ Quitting running instance...
✓ App instance stopped
ℹ No update needed - exiting
```

### Code Changed (Rebuild)
```
ℹ Building FocusFlow...
✓ Build completed
ℹ Checking if app is already up-to-date...
⚠ App update available - rebuilding and reinstalling
ℹ Creating app bundle structure...
...
✓ Installation verified
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (installed or skipped update) |
| 1 | Error (build failed or verification failed) |

## Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `INSTALL_DIR` | Installation location | `~/Applications` |
| `DRY_RUN` | Preview mode (no changes) | `0` |

## Comparison with Other Scripts

| Feature | run.sh | install-and-register-smart.sh |
|---------|--------|------|
| Build | ✓ | ✓ |
| Smart skip | ✗ | ✓ |
| Install | ✗ | ✓ |
| Spotlight | ✗ | ✓ |
| Launch | ✓ | ✗ |
| Idempotent | ✗ | ✓ |
| Single instance | ✗ | ✓ |

## Workflow

### Development Loop
```bash
# Edit code
code Sources/FocusFlow/main.swift

# Test install (rebuilds automatically if needed)
./Scripts/install-and-register-smart.sh

# App is already running in ~/Applications/
# Search Spotlight or launch with: open -a FocusFlow
```

### CI/CD Integration
```bash
# Validate install works
DRY_RUN=1 ./Scripts/install-and-register-smart.sh

# Production install (builds fresh, skips if already latest)
./Scripts/install-and-register-smart.sh
```

## Troubleshooting

### Script says "already latest" but I made changes
```bash
# Touch source file to update modification time
touch Sources/FocusFlow/main.swift
./Scripts/install-and-register-smart.sh
```

### App doesn't appear in Spotlight
```bash
# Re-index Spotlight manually
mdimport ~/Applications/FocusFlow.app
```

### Build fails
```bash
# Check Swift toolchain
swift --version

# Try manual build
swift build --product FocusFlow

# Check for obvious errors
cd Sources/FocusFlow
swift build --show-bin-path
```

### Permission denied
```bash
chmod +x ./Scripts/install-and-register-smart.sh
```

## When to Use Each Script

| Script | Best For |
|--------|----------|
| `run.sh` | Quick dev testing with immediate launch |
| `install-and-register-smart.sh` | Permanent installation with smart updates |
| `uninstall.sh` | Removing the app from system |

## Implementation Details

### File Paths
```
Build output:     .build/debug/FocusFlow
Temp bundle:      .build/debug/FocusFlow.app
Installed:        ~/Applications/FocusFlow.app
```

### Spotlight Management
- Disables Spotlight indexing before install (`mdutil -i off`)
- Re-enables after install (`mdutil -i on`)
- Runs `mdimport` to index the app bundle
- Ensures single Spotlight entry

### Code Signing
- Uses stable certificate signing (`FocusFlow Development`)
- Stable bundle identifier (`com.focusflow.app`)
- Preserves Calendar/Reminder permissions across rebuilds
- Refuses ad-hoc signing and fails fast if certificate signing is unavailable

## Status

✅ **Production Ready**
- Tested with multiple runs
- Smart detection working correctly
- Single instance guaranteed
- Spotlight properly indexed
