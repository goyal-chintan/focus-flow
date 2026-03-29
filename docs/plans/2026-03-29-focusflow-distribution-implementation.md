# FocusFlow Distribution Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make FocusFlow installable by the public via Homebrew Cask and GitHub Releases DMG, with all permissions correctly declared.

**Architecture:** Fix missing `NSScreenCaptureUsageDescription` across all four Info.plist locations (source + 3 build scripts), update the README with install instructions and Gatekeeper guidance, then create the `homebrew-focusflow` tap repo so users can `brew install --cask focusflow`.

**Tech Stack:** Swift/SPM, shell scripts, Homebrew Cask Ruby DSL, `gh` CLI, `hdiutil`, `codesign`

---

### Task 1: Fix NSScreenCaptureUsageDescription in source Info.plist

**Files:**
- Modify: `Sources/FocusFlow/Info.plist`

**Step 1: Add the missing key**

Open `Sources/FocusFlow/Info.plist` and add after the `NSRemindersUsageDescription` block, before `</dict>`:

```xml
    <key>NSScreenCaptureUsageDescription</key>
    <string>FocusFlow reads the active browser window title to identify distracting websites during focus sessions. No screen content is captured or stored.</string>
```

Full file after edit:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>NSCalendarsUsageDescription</key>
    <string>FocusFlow records completed focus sessions to your selected calendar and lets you review session timelines.</string>
    <key>NSRemindersUsageDescription</key>
    <string>FocusFlow syncs your reminders so you can plan sessions, update tasks, and mark them complete.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>FocusFlow reads the active browser window title to identify distracting websites during focus sessions. No screen content is captured or stored.</string>
</dict>
</plist>
```

**Step 2: Verify it parses correctly**

```bash
plutil -lint Sources/FocusFlow/Info.plist
```
Expected: `Sources/FocusFlow/Info.plist: OK`

**Step 3: Commit**

```bash
git add Sources/FocusFlow/Info.plist
git commit -m "fix: add NSScreenCaptureUsageDescription to Info.plist

CGWindowListCopyWindowInfo requires Screen Recording permission on
macOS 13+. Without this key, browser domain tracking silently fails.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Sync NSScreenCaptureUsageDescription into Scripts/run.sh

**Files:**
- Modify: `Scripts/run.sh`

The inline `Info.plist` here-doc in `run.sh` is missing `NSScreenCaptureUsageDescription`. It lives inside the `cat > "$CONTENTS/Info.plist" << 'PLIST' ... PLIST` block.

**Step 1: Add the key to the here-doc**

Find the line:
```
    <key>NSSupportsSuddenTermination</key>
    <true/>
```

Add immediately after it, before `</dict>`:
```xml
    <key>NSScreenCaptureUsageDescription</key>
    <string>FocusFlow reads the active browser window title to identify distracting websites during focus sessions. No screen content is captured or stored.</string>
```

**Step 2: Verify no syntax errors in the script**

```bash
bash -n Scripts/run.sh
```
Expected: no output (silent = clean)

**Step 3: Commit**

```bash
git add Scripts/run.sh
git commit -m "fix: sync NSScreenCaptureUsageDescription into run.sh Info.plist

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Sync NSScreenCaptureUsageDescription into Scripts/install-and-register-smart.sh

**Files:**
- Modify: `Scripts/install-and-register-smart.sh`

Same fix as Task 2 — there's an identical inline `Info.plist` here-doc in this script.

**Step 1: Add the key**

Same insertion point: after `NSSupportsSuddenTermination` / `<true/>`, before `</dict>`:
```xml
    <key>NSScreenCaptureUsageDescription</key>
    <string>FocusFlow reads the active browser window title to identify distracting websites during focus sessions. No screen content is captured or stored.</string>
```

**Step 2: Verify**

```bash
bash -n Scripts/install-and-register-smart.sh
```
Expected: silent

**Step 3: Commit**

```bash
git add Scripts/install-and-register-smart.sh
git commit -m "fix: sync NSScreenCaptureUsageDescription into install script Info.plist

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Sync NSScreenCaptureUsageDescription into Scripts/build-dmg.sh

**Files:**
- Modify: `Scripts/build-dmg.sh`

**Step 1: Add the key**

Same pattern — inline Info.plist here-doc. After `NSSupportsSuddenTermination` / `<true/>`, before `</dict>`:
```xml
    <key>NSScreenCaptureUsageDescription</key>
    <string>FocusFlow reads the active browser window title to identify distracting websites during focus sessions. No screen content is captured or stored.</string>
```

**Step 2: Verify**

```bash
bash -n Scripts/build-dmg.sh
```
Expected: silent

**Step 3: Quick smoke test — build debug bundle and check plist**

```bash
bash Scripts/run.sh
# Wait for app to launch, then:
/usr/libexec/PlistBuddy -c "Print NSScreenCaptureUsageDescription" \
  .build/debug/FocusFlow.app/Contents/Info.plist
```
Expected: `FocusFlow reads the active browser window title...`

**Step 4: Commit**

```bash
git add Scripts/build-dmg.sh
git commit -m "fix: sync NSScreenCaptureUsageDescription into build-dmg.sh Info.plist

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: Update README with Gatekeeper guidance and permissions list

**Files:**
- Modify: `README.md`

The existing "Download & Install" section needs:
1. A note that unsigned apps need right-click → Open on first launch
2. A list of system permissions the app will request and why

**Step 1: Expand the Download & Install section**

Find the current "Download & Install" section:
```markdown
## Download & Install

1. Go to [**Releases**](https://github.com/goyal-chintan/focus-flow/releases/latest) and download the latest `FocusFlow-x.x.x.dmg`
2. Open the DMG and drag **FocusFlow.app** → **Applications**
3. Launch from Spotlight (⌘ Space → "FocusFlow") or Launchpad

> **Requires macOS 26 (Tahoe) or later.**
```

Replace with:
```markdown
## Download & Install

### Option 1 — Homebrew (easiest)
```sh
brew tap goyal-chintan/focusflow
brew install --cask focusflow
```

### Option 2 — DMG
1. Download the latest `FocusFlow-x.x.x.dmg` from [**Releases**](https://github.com/goyal-chintan/focus-flow/releases/latest)
2. Open the DMG and drag **FocusFlow.app** → **Applications**
3. **First launch:** right-click FocusFlow.app → **Open** → click Open in the dialog  
   *(macOS shows a security warning for apps not notarized through Apple — this bypasses it once)*

> **Requires macOS 26 (Tahoe) or later.**

### Permissions

FocusFlow will ask for these on first use:

| Permission | Why |
|---|---|
| **Calendar** | Log completed focus sessions to your calendar |
| **Reminders** | Sync tasks so you can plan and complete them during sessions |
| **Screen Recording** | Read active browser window title to identify distracting sites — no screen content is captured or stored |
| **Admin password** | Modify `/etc/hosts` for website blocking (only when you enable the feature) |
```

**Step 2: Verify README renders cleanly**

```bash
# Check no broken markdown
grep -n "##" README.md | head -20
```

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: expand install instructions with Gatekeeper guidance and permissions

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: Create the Homebrew tap repo

**Step 1: Create the repo on GitHub**

```bash
gh repo create goyal-chintan/homebrew-focusflow \
  --public \
  --description "Homebrew tap for FocusFlow — macOS menu bar focus timer" \
  --clone
cd homebrew-focusflow
```

**Step 2: Create the Casks directory and cask file**

```bash
mkdir Casks
```

Copy the template from FocusFlow repo (update paths/sha after):
```bash
cp ../focus-flow/Scripts/homebrew/focusflow.rb Casks/focusflow.rb
```

The cask file needs `<owner>` replaced with `goyal-chintan` and the `sha256` / version updated after the first DMG build. Placeholders are fine for now.

**Step 3: Add a minimal README**

```bash
cat > README.md << 'EOF'
# homebrew-focusflow

[Homebrew](https://brew.sh) tap for [FocusFlow](https://github.com/goyal-chintan/focus-flow) — a native macOS menu bar Pomodoro focus timer.

## Install

```sh
brew tap goyal-chintan/focusflow
brew install --cask focusflow
```

## Requirements

macOS 26 (Tahoe) or later.
EOF
```

**Step 4: Commit and push**

```bash
git add Casks/focusflow.rb README.md
git commit -m "feat: initial Homebrew tap for FocusFlow

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
git push -u origin main
```

**Step 5: Verify tap works**

```bash
brew tap goyal-chintan/focusflow
brew info --cask focusflow
```
Expected: shows cask info (will error on sha256 mismatch until real DMG is built — that's fine for now)

---

### Task 7: Build first release DMG and publish

> Do this after Tasks 1–6 are all merged to `main`.

**Step 1: Tag the release**

```bash
cd /path/to/focus-flow
git checkout main && git pull
git tag v1.0.0
git push origin v1.0.0
```

**Step 2: Build the DMG locally**

```bash
VERSION=1.0.0 ./Scripts/build-dmg.sh
```
Expected: `DMG ready: Artifacts/FocusFlow-1.0.0.dmg` + SHA-256 printed.

**Step 3: Create GitHub Release and upload DMG**

```bash
gh release create v1.0.0 \
  Artifacts/FocusFlow-1.0.0.dmg \
  --title "FocusFlow 1.0.0" \
  --notes "## Install

\`\`\`sh
brew tap goyal-chintan/focusflow
brew install --cask focusflow
\`\`\`

Or download the DMG below and drag to Applications.
First launch: right-click → Open to bypass Gatekeeper.

> Requires macOS 26 (Tahoe) or later."
```

**Step 4: Update Homebrew cask with real SHA-256**

Take the SHA printed by `build-dmg.sh` and update `Casks/focusflow.rb` in the `homebrew-focusflow` repo:

```ruby
sha256 "PASTE_REAL_SHA_HERE"
url "https://github.com/goyal-chintan/focus-flow/releases/download/v1.0.0/FocusFlow-1.0.0.dmg"
```

Also replace `<owner>` with `goyal-chintan`.

```bash
cd homebrew-focusflow
git add Casks/focusflow.rb
git commit -m "chore: update cask to v1.0.0

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
git push
```

**Step 5: Verify end-to-end install**

```bash
brew untap goyal-chintan/focusflow 2>/dev/null || true
brew tap goyal-chintan/focusflow
brew install --cask focusflow
open -a FocusFlow
```
Expected: FocusFlow appears in menu bar. macOS prompts for permissions on first use.

---

## Future: CI Builds (when macOS 26 runners available)

Update `.github/workflows/release.yml` line:
```yaml
runs-on: macos-15   # change to macos-26 when available
```

This will automate Steps 2–3 of Task 7 on every tag push.
