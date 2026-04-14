# Dynamic Activation Policy Design

**Date:** 2026-04-14  
**Issue:** #38  
**Branch:** feat/dynamic-activation-policy

## Problem

`LSUIElement=true` in Info.plist marks FocusFlow as a macOS accessory process. This hides it from the Dock, Cmd+Tab switcher, and Activity Monitor when windows like Settings, Stats, Coach, or Session Complete are open — making it hard to track or switch to.

## Approach

**Dynamic activation policy** — the standard pattern used by 1Password, Alfred, CleanMyMac, etc.

- Keep `LSUIElement=true` so the app stays menu-bar-first when idle (no Dock clutter)
- Call `NSApp.setActivationPolicy(.regular)` when any real window becomes visible
- Revert to `NSApp.setActivationPolicy(.accessory)` when all real windows close

## Architecture

### `WindowPolicyManager.swift` (new)

`@MainActor` singleton. Responsibilities:

1. Subscribe to `NSWindow.didBecomeVisibleNotification` and `NSWindow.willCloseNotification` via `NotificationCenter`
2. On each notification, count windows matching: `isVisible && !isMiniaturized && level == .normal`
   - `.normal` level excludes the MenuBarExtra popup (which runs at `.statusBar` level) and other system overlays
3. If count > 0 → `NSApp.setActivationPolicy(.regular)` + `NSApp.activate()`
4. If count == 0 → `NSApp.setActivationPolicy(.accessory)` (debounced 150ms to avoid flicker during window transitions)

### `FocusFlowApp.swift` (1-line change)

Start `WindowPolicyManager.shared` from `AppLaunchBridge.task`.

## Files Changed

| File | Change |
|------|--------|
| `Sources/FocusFlow/WindowPolicyManager.swift` | New file |
| `Sources/FocusFlow/FocusFlowApp.swift` | 1-line addition in `AppLaunchBridge` |

`Info.plist` and `Scripts/run.sh` are **unchanged**.

## Acceptance Criteria

- Opening Stats/Settings/Coach/Session Complete shows FocusFlow in Dock and Cmd+Tab
- Closing all windows removes FocusFlow from the Dock
- MenuBarExtra popup does NOT trigger the Dock icon
- Activity Monitor shows FocusFlow as a named app when windows are open
