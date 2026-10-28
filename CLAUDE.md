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

Coach v2 design: `docs/plans/2026-10-17-coach-v2-learning-motivation-design.md`. Companion/Settings design: `docs/plans/2026-10-17-companion-window-redesign.md`. Debug hooks (DEBUG builds, env vars): `FOCUSFLOW_DEBUG_COACH_PANEL=1` shows the on-screen coach panel 5s after launch; add `FOCUSFLOW_DEBUG_DRIFT_LEVEL=<1|2|3>` to show the rescue-ladder panel at that level; `FOCUSFLOW_DEBUG_PAUSE_SCREEN=1` shows the rescue pause screen 5s after launch (rescue loop: `docs/plans/2026-10-17-coach-rescue-loop-design.md`; starter blocks are sessions with `customLabel == "Starter"` and no project); `FOCUSFLOW_DEBUG_CAPTURE_DIR=<dir>` captures every companion tab from inside the app. Coach v3 (start engine: daily plan, planned-start cue, coach insights; `docs/plans/2026-10-19-coach-v3-start-engine-design.md`): `FOCUSFLOW_DEBUG_PLAN=card|cue` shows the plan card or a planned-start cue 5s after launch without saving anything, and with `FOCUSFLOW_DEBUG_CAPTURE_DIR` also writes `panel_plan_<mode>.png`. Launch an installed build with env vars via `open -n ~/Applications/FocusFlow.app --env KEY=value`. Coach v4 (start first: presence gate, arrival breakpoint, 5·15·25 size ladder, "Not now, because…" reasons, honest prompt→start attribution, coach journal; `docs/plans/2026-10-28-coach-v4-start-first-design.md`): the journal is `~/Library/Application Support/FocusFlow/coach-journal.jsonl` (release builds too) and shows under Insights → "Today's coach log". Coach tests that evaluate idle prompts must set `vm.systemIdleSecondsProvider` (nil reads the real machine's idle time). Coach v5 learning engine (`docs/plans/2026-10-28-coach-v5-learning-engine-design.md`): idle start prompts are decided by an action-centred Bayesian contextual bandit (`CoachPromptPolicy`, HeartSteps-style, every decision point logged with features and propensity, quiet ones too), and block size by Thompson sampling (`CoachSizePolicy`, v4 rules as the prior). Rewards are resolved from the sessions table an hour after each decision. Tests that need a fixed size set `vm.coachExploreSizes = false`; `coachArmOverride` forces the prompt decision (propensity nil, excluded from learning). Priorities and goals (`docs/plans/2026-10-28-priorities-goals-design.md`): projects have optional `priorityRank`, `areaRaw` (personal/learning/work/other), `dailyTargetMinutes`, `targetWeekdaysOnly` (Mon–Fri explicitly; en_IN's weekend is Sunday only) and `purpose`; goals are `ProjectGoal` → `GoalKeyResult` → `GoalProgressEntry` (progress = sum of entries). Pure logic lives in `Services/Goals/GoalTracking.swift` (pacing, `PriorityAllocation`, `DriftReport`, `DailyLevers`), fed by `GoalDataBuilder`. Once any project is marked Work, the daily goal and coach pacing count own work only (`goalProgressSeconds`). The companion has a Goals tab; capture its screens with `FOCUSFLOW_CAPTURE_OUTPUT_DIR=<dir> swift test --filter UIEvidenceCaptureTests/testCapturePrioritiesAndGoals`. Notch companion (`docs/plans/2026-10-28-notch-companion-design.md`): `NotchController` hosts `NotchView` in a non-activating panel at `mainMenu + 3` around the hardware notch (`NotchGeometry`; a virtual notch on screens without one), resized to the island so it never blocks the menu bar; toggle in Settings → General (`AppSettings.notchCompanionEnabled`, nil = on). Render every state with `FOCUSFLOW_CAPTURE_OUTPUT_DIR=<dir> swift test --filter NotchTests/testCaptureNotchStates`. Welcome tour (`docs/plans/2026-10-28-onboarding-design.md`, user guide `docs/GETTING_STARTED.md`): five steps in `Views/Onboarding/OnboardingView.swift` (`Window(id: "onboarding")`), pure logic in `Services/Onboarding/OnboardingPlan.swift` (`OnboardingDraft.commit` writes through `ProjectDraft`/`GoalDraft`; `OnboardingLaunch.decide` shows it only for a store with no sessions and nil `AppSettings.onboardingCompletedAt`). Reopen from Settings → General → Getting started (`timerVM.openOnboarding`). Captures: `FOCUSFLOW_CAPTURE_OUTPUT_DIR=<dir> swift test --filter OnboardingTests/testCaptureOnboardingSteps`. Tests that hold a `ModelContext` must also keep its `ModelContainer` alive, or SwiftData traps. Daily tasks (`docs/plans/2026-10-28-daily-tasks-design.md`): `DailyTask` model (one to-do per day; linked to a key result, ticking logs a `GoalProgressEntry` of its amount and unticking deletes exactly that entry), pure logic in `Services/Goals/DailyTasks.swift`, store ops on the VM (`addDailyTask`, `setDailyTask(_:done:sessionID:)`, `carryOverDailyTasks`); `FocusSession.taskID` remembers the task a block was started for. Screen audit (`docs/plans/2026-10-28-screen-audit.md`) is the contract for every surface: own-work goal everywhere, weekly priorities retired (data kept, `TimerViewModel.weeklyPrioritiesRetired`), levers shown once per screen, 5·15·25 with the learned size preselected, one vocabulary (Finish / Keep going / Break 5 min / Done for today / Log this block), block-end window is one stage that logs against tasks and goals (no mood, no free-text note). Capture the new surfaces with `PopoverCaptureTests` and `DailyTaskTests/testCaptureDailyTaskSurfaces`; review flows are filtered with `FOCUSFLOW_REVIEW_FLOW_FILTER`.

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
