# FocusFlow Public Distribution Design

## Problem

FocusFlow is a native macOS menu bar app ready for public distribution. The goal is maximum reach with minimum friction: users should be able to install it via a single Homebrew command or by downloading a DMG from GitHub — no server required.

## Audience

macOS 26 (Tahoe) users. Developer/power-user community likely early adopters given OS version requirement.

## Constraints Discovered

| Constraint | Detail |
|---|---|
| No Apple Developer account | Ad-hoc signing only; no notarization |
| macOS 26 required | GitHub Actions has no macOS 26 runner yet |
| `CGWindowListCopyWindowInfo` used | Requires Screen Recording permission — `NSScreenCaptureUsageDescription` missing from Info.plist |
| Website blocking via `sudo /etc/hosts` | Requires admin password; fine for direct distribution, blocks App Store |
| Fully offline | No server, no analytics, no cloud — simplifies distribution |

## Chosen Approach: GitHub Releases + Homebrew Cask Tap

**Why:** Homebrew Cask is the standard macOS install path for non-App Store apps. GitHub Releases provides free DMG hosting. No server needed at any point.

**Rejected: App Store** — Incompatible with `sudo` usage and App Sandbox.  
**Rejected: npm/apt-get** — Wrong ecosystem for native macOS apps.

## Changes Required Before First Release

### 1. Fix missing Screen Recording permission key

Add `NSScreenCaptureUsageDescription` to:
- `Sources/FocusFlow/Info.plist` (source of truth)
- The inline Info.plist in `Scripts/build-dmg.sh`
- The inline Info.plist in `Scripts/run.sh`
- The inline Info.plist in `Scripts/install-and-register-smart.sh`

Without this key, `CGWindowListCopyWindowInfo` silently returns no window titles — browser domain tracking fails without any error.

### 2. Sync build-dmg.sh Info.plist with source Info.plist

The `build-dmg.sh` script hard-codes its own Info.plist. It needs `NSScreenCaptureUsageDescription` added to match.

### 3. Create Homebrew tap repo

- Create public GitHub repo: `goyal-chintan/homebrew-focusflow`
- Add `Casks/focusflow.rb` (template already at `Scripts/homebrew/focusflow.rb`)
- Fill in `sha256` after first DMG build

## Release Workflow (Ongoing)

```
1. Make code changes, test locally
2. git tag v1.x.x && git push origin v1.x.x
3. Run: VERSION=1.x.x ./Scripts/build-dmg.sh
4. Upload Artifacts/FocusFlow-1.x.x.dmg to GitHub Release (github.com/goyal-chintan/focus-flow/releases)
5. Copy SHA-256 printed by build-dmg.sh
6. Update sha256 + version in goyal-chintan/homebrew-focusflow/Casks/focusflow.rb
7. Push homebrew-focusflow repo
```

## User Install Experience

**Via Homebrew (recommended):**
```sh
brew tap goyal-chintan/focusflow
brew install --cask focusflow
```

**Via DMG:**
1. Download `FocusFlow-x.x.x.dmg` from Releases
2. Open DMG → drag FocusFlow.app to Applications
3. Right-click FocusFlow.app → Open (bypasses Gatekeeper for unsigned apps — one time only)

**Permission prompts on first use:**
- Calendar access (for session logging)
- Reminders access (for task sync)
- Screen Recording (for browser domain tracking)
- Admin password (for website blocking via /etc/hosts — optional feature)

## README Updates Needed

- "Download & Install" section with Homebrew command (already added)
- Note about right-click → Open for Gatekeeper
- Note about macOS 26 requirement
- List of permissions the app will request and why

## Files Created / Modified

| File | Status | Purpose |
|---|---|---|
| `Scripts/build-dmg.sh` | ✅ Created | Release build + .app bundle + DMG |
| `.github/workflows/release.yml` | ✅ Created | CI for when macOS 26 runners available |
| `Scripts/homebrew/focusflow.rb` | ✅ Created | Homebrew Cask template |
| `README.md` | ✅ Updated | Download badge + install instructions |
| `Sources/FocusFlow/Info.plist` | ⬜ Needs update | Add NSScreenCaptureUsageDescription |
| `Scripts/build-dmg.sh` | ⬜ Needs update | Sync NSScreenCaptureUsageDescription |
| `Scripts/run.sh` | ⬜ Needs update | Sync NSScreenCaptureUsageDescription |
| `Scripts/install-and-register-smart.sh` | ⬜ Needs update | Sync NSScreenCaptureUsageDescription |
| `goyal-chintan/homebrew-focusflow` repo | ⬜ Needs creation | Homebrew tap |
