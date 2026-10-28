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

### 3. `install.sh`
**Purpose:** Build a release version, install it to `~/Applications`, register it with Spotlight, and relaunch it

```bash
./Scripts/install.sh
```

Re-run after each `git pull`. Details and options: [INSTALL.md](INSTALL.md). `install-and-register-smart.sh` is the old name and now runs this script.

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

### For Installing
```bash
# Install or update
./Scripts/install.sh

# Remove
./Scripts/uninstall.sh
```

## Key Differences

| Aspect | `run.sh` | `install.sh` |
|--------|----------|---------------------------|
| **Build** | ✓ | ✓ |
| **Install** | ✗ (temp) | ✓ (~/Applications) |
| **Spotlight** | ✗ | ✓ |
| **Launch** | ✓ | ✓ |
| **Dry-run** | ✗ | ✗ |
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
./Scripts/install.sh
```

### Testing without affecting system
```bash
DRY_RUN=1 ./Scripts/uninstall.sh             # See what would be removed
```

## Script Architecture

All scripts follow these patterns:

1. **Error handling**: `set -eu` (exit on error, undefined vars)
2. **Color logging**: Info (blue 🔵), Success (green ✓), Warning (yellow ⚠️), Error (red ✗)
3. **Safety**: Never overwrites critical files without warning
4. **Idempotency**: Can be run multiple times safely
5. **Dry-run**: `uninstall.sh` supports `DRY_RUN=1`

## Files Created/Modified

```
FocusFlow/Scripts/
├── run.sh                        (debug build + launch)
├── install.sh                    (release build + install + register + launch)
├── install-and-register-smart.sh (old name; runs install.sh)
├── uninstall.sh
├── lib/toolchain.sh              (uses Xcode for the build)
├── INSTALL.md                    (detailed guide)
└── SCRIPTS_QUICKREF.md           (this file)
```
