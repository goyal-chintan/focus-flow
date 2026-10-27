# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Build, create .app bundle, and launch
bash Scripts/run.sh

# Build only (no bundle/launch)
swift build

# Install (release build → ~/Applications, registered for Spotlight, relaunched)
bash Scripts/install.sh
```

The app cannot run via bare `swift run` — it needs a proper .app bundle for Liquid Glass compositing and UNUserNotificationCenter. `Scripts/run.sh` handles this by creating the bundle structure with Info.plist at `.build/debug/FocusFlow.app`.

Tests: `swift test` (XCTest + Swift Testing in `Tests/FocusFlowTests`). If `xcode-select` points at CommandLineTools, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the build needs `actool`); the scripts in `Scripts/` do this themselves via `Scripts/lib/toolchain.sh`. No external dependencies — pure SwiftUI + SwiftData + Swift Charts.

Visual QA: off-screen renders (`UIEvidenceCaptureTests`, output dir via `FOCUSFLOW_CAPTURE_OUTPUT_DIR`) and in-app `cacheDisplay` captures draw AppKit controls and glass in the wrong appearance. Judge layout from them; judge colour only from real screenshots.

Coach v2 design: `docs/plans/2026-10-17-coach-v2-learning-motivation-design.md`. Companion/Settings design: `docs/plans/2026-10-17-companion-window-redesign.md`. Debug hooks (DEBUG builds, env vars): `FOCUSFLOW_DEBUG_COACH_PANEL=1` shows the on-screen coach panel 5s after launch; add `FOCUSFLOW_DEBUG_DRIFT_LEVEL=<1|2|3>` to show the rescue-ladder panel at that level; `FOCUSFLOW_DEBUG_PAUSE_SCREEN=1` shows the rescue pause screen 5s after launch (rescue loop: `docs/plans/2026-10-17-coach-rescue-loop-design.md`; starter blocks are sessions with `customLabel == "Starter"` and no project); `FOCUSFLOW_DEBUG_CAPTURE_DIR=<dir>` captures every companion tab from inside the app. Coach v3 (start engine: daily plan, planned-start cue, coach insights; `docs/plans/2026-10-19-coach-v3-start-engine-design.md`): `FOCUSFLOW_DEBUG_PLAN=card|cue` shows the plan card or a planned-start cue 5s after launch without saving anything, and with `FOCUSFLOW_DEBUG_CAPTURE_DIR` also writes `panel_plan_<mode>.png`. Launch an installed build with env vars via `open -n ~/Applications/FocusFlow.app --env KEY=value`.

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
IDLE → startFocus() → FOCUSING → timerCompleted() → OVERTIME (idle + completion window)
                         ↓                               ↓
                      pause()                    continueAfterCompletion(.takeBreak) → ON_BREAK
                         ↓                       continueAfterCompletion(.continueFocusing) → FOCUSING
                      PAUSED                     continueAfterCompletion(.endSession) → IDLE
                         ↓
                      resume() → FOCUSING
```

- On completion, timer keeps running in overtime mode (`isOvertime=true`), counting up
- `endedAt` is set at completion and updated every tick — overtime duration is included in `actualDuration`
- Completion opens a standalone `SessionCompleteWindowView` (not inline in popover)
- Menu bar shows orange `+M:SS` overtime counter
- Focus completion always shows `SessionCompleteWindowView` (the `autoStartBreak` setting is intentionally unused)
- `stop()` saves session as incomplete; `abandonSession()` deletes it entirely
- Sessions under 1 minute are auto-deleted (in `stop()` and `cleanupOrphanedSessions()`)
- Minimum session duration: 5 minutes (`focusDuration` clamps `selectedMinutes` to ≥5)

### Timers & RunLoop
- Main timer and pause timer run on `RunLoop.main` with `.common` mode (fires during menu tracking)
- Midnight refresh timer schedules 1 second past midnight to reload stats and reset session counter
- All timer callbacks dispatch to `@MainActor` via `Task { @MainActor in }`

### Day Boundary Handling
- Cross-midnight sessions are attributed to both days using overlap calculation: `max(sessionStart, dayStart)` to `min(sessionEnd, dayEnd)`
- Applied in `loadTodayStats()`, `TodayStatsView`, and `WeeklyStatsView`
- Orphaned sessions (app quit mid-focus) are cleaned up on next launch

### Liquid Glass Design Philosophy
FocusFlow embraces macOS Tahoe's Liquid Glass as a core design language, not just a styling option:

- **Glass on controls/navigation only:** buttons, picker backgrounds, floating panels. Content areas stay clear.
- **Never stack glass on glass** — leads to visual muddiness and breaks the translucency effect.
- **Use `GlassEffectContainer`** when grouping multiple glass elements (e.g., action button rows). This ensures proper compositing.
- **Conditional `.buttonStyle(.glass)` vs `.glassProminent`** requires if/else branches — ternary causes SwiftUI type errors.
- **`.glassProminent`** for primary/selected actions (with `.tint()` for color), **`.glass`** for secondary/unselected.
- **`.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))`** for text fields and passive containers — gives subtle depth without interactive affordance.
- **Standalone windows** (e.g., Session Complete) use `.windowStyle(.hiddenTitleBar)` to let glass compositing extend edge-to-edge.

### UI Design Rules (Hard-Won Lessons)
These rules were established through iterative visual review and must not be violated:

- **Reference images are source of truth** — Stitch folder (`stitch_popover_break_light 2/`) has PNG references for all screens. Match them before code convenience.
- **Never use `.buttonStyle(.glass)` on icon-only buttons** — renders as ugly gray rectangles. Use `.buttonStyle(.plain)` with `.frame(width: 28-30)` and `.contentShape(Rectangle())`.
- **Never use `LiquidGlassPanel` on list rows** — creates visible bordered wireframes. Use `Color.white.opacity(0.04)` fills for rows. Reserve glass panels for SECTION containers.
- **Popover background opacity: 0.45-0.55** — higher kills glass translucency. Don't exceed 0.55.
- **Timer ring: 160pt, 6pt stroke, 36pt text** — these are locked proportions for the 300pt popover.
- **Don't add chevrons to Menu labels** — native Menu renders its own. Double chevrons = broken.
- **Minimum text: 10pt** — Apple HIG floor. No exceptions.
- **Minimum click target: 30pt** — use `.frame()` + `.contentShape(Rectangle())` on icon buttons.
- **Custom matchedGeometryEffect pills look foreign** — use per-button `.glass`/`.glassProminent` + `.capsule` instead.
- **Floating panels: measure before animating.** An `animator().setFrame` slide-in overrides any plain `setFrame` made while it runs; measure the hosted content first and resize through the animator (the coach panel was stuck at 120 pt and clipped its buttons).
- **3-Gate review before presenting:** (1) Pixel match ≥80%, (2) Apple design checklist, (3) Apple UX checklist. If any gate fails, fix before showing user.

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
