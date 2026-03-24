# FocusFlow Scripts Quick Reference

## Scripts in `/Scripts` directory

### 1. `run.sh` (Original)
**Purpose:** Build and immediately launch FocusFlow for development testing

```bash
./Scripts/run.sh
```

- Builds app from source
- Creates .app bundle
- Launches app immediately
- Best for: Rapid iteration during development

### 2. `capture-ui-evidence.sh` (New)
**Purpose:** Generate deterministic UI review evidence (screenshots + animation GIF + manifest)

```bash
./Scripts/capture-ui-evidence.sh
```

Uses Xcode CLI by default:
- Runs `UIEvidenceCaptureTests`
- Captures all required review contract flows in light + dark
- Writes outputs to `Artifacts/review/<run-id>/`

Optional environment variables:
```bash
RUN_ID=20260324-120000 ./Scripts/capture-ui-evidence.sh
RUNNER=swift ./Scripts/capture-ui-evidence.sh
FLOW_FILTER=menu_bar_idle,coach_strong_window ./Scripts/capture-ui-evidence.sh
APPEARANCE_FILTER=dark ./Scripts/capture-ui-evidence.sh
```

### 3. `install-and-register.sh` (New)
**Purpose:** Build, install to ~/Applications, and register with Spotlight

```bash
./Scripts/install-and-register.sh
```

**Features:**
- Builds latest from source
- Installs to `~/Applications/FocusFlow.app` (persistent)
- Updates macOS Spotlight index
- Executable appears in Spotlight search
- Color-coded progress output
- Dry-run mode support

**Environment Variables:**
```bash
INSTALL_DIR=/custom/path ./Scripts/install-and-register.sh  # Custom install location
DRY_RUN=1 ./Scripts/install-and-register.sh                 # Preview without making changes
```

**Usage after install:**
```bash
open -a FocusFlow              # Launch from command line
# Or search Spotlight for "FocusFlow" and launch from there
```

### 4. `uninstall.sh` (New)
**Purpose:** Remove FocusFlow from system

```bash
./Scripts/uninstall.sh
```

**Features:**
- Stops any running FocusFlow process
- Removes from Spotlight index
- Deletes app bundle
- Safe dry-run mode

**Environment Variables:**
```bash
DRY_RUN=1 ./Scripts/uninstall.sh  # Preview uninstallation
```

## Recommended Workflow

### For Development
```bash
# Quick test after code changes
./Scripts/run.sh
```

### For Testing Installation
```bash
# First time setup
./Scripts/install-and-register.sh

# Verify it will install correctly
DRY_RUN=1 ./Scripts/install-and-register.sh

# After changes, reinstall
./Scripts/install-and-register.sh

# When done
./Scripts/uninstall.sh
```

### For CI/CD
```bash
# Validate before installing
DRY_RUN=1 ./Scripts/install-and-register.sh

# Production installation
INSTALL_DIR=/usr/local/bin ./Scripts/install-and-register.sh
```

## Key Differences

| Aspect | `run.sh` | `install-and-register.sh` |
|--------|----------|---------------------------|
| **Build** | ✓ | ✓ |
| **Install** | ✗ (temp) | ✓ (/Applications) |
| **Spotlight** | ✗ | ✓ |
| **Launch** | ✓ | ✗ |
| **Dry-run** | ✗ | ✓ |
| **Persistence** | Session only | Permanent |

## Troubleshooting

### App won't launch after install
```bash
# Check if executable exists
ls -la ~/Applications/FocusFlow.app/Contents/MacOS/FocusFlow

# Check Spotlight registration
mdls ~/Applications/FocusFlow.app | head -5

# Re-register with Spotlight
mdimport ~/Applications/FocusFlow.app
```

### Want to reset to clean state
```bash
./Scripts/uninstall.sh
./Scripts/install-and-register.sh
```

### Testing without affecting system
```bash
DRY_RUN=1 ./Scripts/install-and-register.sh  # See what would happen
DRY_RUN=1 ./Scripts/uninstall.sh             # See what would be removed
```

## Script Architecture

All scripts follow these patterns:

1. **Error handling**: `set -eu` (exit on error, undefined vars)
2. **Color logging**: Info (blue 🔵), Success (green ✓), Warning (yellow ⚠️), Error (red ✗)
3. **Safety**: Never overwrites critical files without warning
4. **Idempotency**: Can be run multiple times safely
5. **Dry-run**: Preview mode with `DRY_RUN=1` environment variable

## Files Created/Modified

```
FocusFlow/Scripts/
├── run.sh                        (existing, unchanged)
├── install-and-register.sh       (NEW)
├── uninstall.sh                  (NEW)
├── INSTALL.md                    (NEW - detailed guide)
└── SCRIPTS_QUICKREF.md           (NEW - this file)
```
