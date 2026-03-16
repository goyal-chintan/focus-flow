# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Build, create .app bundle, and launch
bash Scripts/run.sh

# Build only (no bundle/launch)
swift build

# Install to Applications
cp -R .build/debug/FocusFlow.app /Applications/
```

The app cannot run via bare `swift run` — it needs a proper .app bundle for Liquid Glass compositing and UNUserNotificationCenter. `Scripts/run.sh` handles this by creating the bundle structure with Info.plist at `.build/debug/FocusFlow.app`.

**No test target exists.** No external dependencies — pure SwiftUI + SwiftData.

## Platform

- **macOS 26+ (Tahoe) only** — uses Liquid Glass APIs (`.glassEffect()`, `.buttonStyle(.glass)`, `GlassEffectContainer`)
- Swift 6.2, SwiftUI, SwiftData
- Swift tools version 6.2 in Package.swift
- LSUIElement=true (menu bar app, no dock icon)

## Architecture

**MVVM + Scene-based.** Two UI surfaces sharing one state:

1. **MenuBarExtra** (popover) — timer, controls, project picker, session completion flow
2. **Window** (companion) — stats, projects, settings

**Single source of truth:** `TimerViewModel` (`@Observable`) manages all timer/state logic and is injected via `.environment()` into both scenes. Views use `@Environment(TimerViewModel.self)`.

**SwiftData container:** One shared `ModelContainer` created in `FocusFlowApp` and attached to both scenes. Schema: `Project`, `FocusSession`, `AppSettings`, `TimeSplit`.

**Entry point:** `main.swift` calls `FocusFlowApp.main()` — the `@main` attribute is NOT on FocusFlowApp (SPM executable target requirement).

## Key Patterns

### Timer State Machine (TimerViewModel)
```
IDLE → startFocus() → FOCUSING → timerCompleted() → showSessionComplete (idle + completion view)
                         ↓                               ↓
                      pause()                    continueAfterCompletion(.takeBreak) → ON_BREAK
                         ↓                       continueAfterCompletion(.continueFocusing) → FOCUSING
                      PAUSED                     continueAfterCompletion(.endSession) → IDLE
                         ↓
                      resume() → FOCUSING
```

- Focus completion always shows `SessionCompleteView` (the `autoStartBreak` setting is intentionally unused)
- `stop()` saves session as incomplete; `abandonSession()` deletes it entirely
- Sessions under 1 minute are auto-deleted (in `stop()` and `cleanupOrphanedSessions()`)
- Minimum session duration: 5 minutes (300 seconds guard in `startFocus()`)

### Timers & RunLoop
- Main timer and pause timer run on `RunLoop.main` with `.common` mode (fires during menu tracking)
- Midnight refresh timer schedules 1 second past midnight to reload stats and reset session counter
- All timer callbacks dispatch to `@MainActor` via `Task { @MainActor in }`

### Day Boundary Handling
- Cross-midnight sessions are attributed to both days using overlap calculation: `max(sessionStart, dayStart)` to `min(sessionEnd, dayEnd)`
- Applied in `loadTodayStats()`, `TodayStatsView`, and `WeeklyStatsView`
- Orphaned sessions (app quit mid-focus) are cleaned up on next launch

### Liquid Glass Usage Rules
- Glass on controls/navigation only: buttons, picker backgrounds, floating panels
- Never stack glass on glass
- Use `GlassEffectContainer` when grouping multiple glass elements
- Conditional `.buttonStyle(.glass)` vs `.glassProminent` requires if/else branches (ternary causes type errors)

### SwiftUI Type-Check Timeout
Complex view bodies trigger "unable to type-check this expression in reasonable time." Fix by extracting sections into `private var someSection: some View` computed properties or separate structs. This has affected `MenuBarPopoverView`, `ProjectFormView`, and `ManualSessionView`.

## Data Models

- **Project** — name, color (String), icon (SF Symbol), archived (soft delete). One-to-many with FocusSession (nullify on delete).
- **FocusSession** — type (focus/shortBreak/longBreak), duration, startedAt, endedAt, completed, moodRawValue, achievement. One-to-many with TimeSplit (cascade delete).
- **TimeSplit** — splits a session's time across multiple projects with per-split duration.
- **AppSettings** — singleton for user preferences. Created on first launch by `TimerViewModel.loadSettings()`.
- **FocusMood** — enum stored as `moodRawValue` String on FocusSession, accessed via computed `mood` property.

## NotificationService

Singleton with `@MainActor`. Guards all `UNUserNotificationCenter` calls behind `Bundle.main.bundleIdentifier != nil` — prevents crashes when running without a proper app bundle. Sound playback uses `NSSound` directly.

## Git

- Author: Chintan Goyal <mail.chintan.goyal@gmail.com>
- Development happens on worktree at `.worktrees/feature/focusflow-build/`
- Main repo root: `/Users/chintan/Personal/repos/FocusFlow`
