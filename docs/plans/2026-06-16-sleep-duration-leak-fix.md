# Lid-Close Focus Session Leak Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prevent focus sessions from continuing to run and accumulating fake overtime/focus minutes during Mac sleep, and intelligently prompt the user on wake to either crop the session to the sleep start time, keep the full overtime, or discard it.

**Architecture:**
1. **Model (AppSettings)**: Add `autoStopOnSleepThresholdMinutes: Int = 60` to represent the configurable threshold.
2. **ViewModel (TimerViewModel)**:
   - Always pause active focus sessions on sleep (in `pauseForSystemSleep()`), recording sleep start time.
   - On wake (in `resumeAfterSystemWake()`), check if sleep duration > threshold. If so:
     - Terminate active timers and clear active session state.
     - Save the session with `endedAt = Date()` (provisional wake time).
     - Transition to an idle state with `showWakeRecoveryPrompt = true`, `wakeRecoverySleepStartTime = systemSleepStartTime`, `wakeRecoveryWakeTime = Date()`, and `wakeRecoverySession = currentSession`.
     - Open the `SessionCompleteWindow` to show the recovery options.
   - Add `resolveWakeRecovery(choice:)` to handle user selection:
     - `.saveToSleepStart`: Set `session.endedAt = wakeRecoverySleepStartTime`, update duration, and transition to normal session complete reflection.
     - `.keepOvertime`: Set `session.endedAt = wakeRecoveryWakeTime`, and transition to normal session complete reflection.
     - `.discard`: Delete the session from database and close completion window.
3. **Database Migration (StoreMigrator)**: Register a column migration `ZAUTOSTOPONSLEEPTHRESHOLDMINUTES` for `ZAPPSETTINGS` to avoid crash on launch.
4. **Settings UI (SettingsView)**: Expose a stepper for "Wake recovery threshold" under General / App Behavior.
5. **Completion Window UI (SessionCompleteWindow)**: Detect `timerVM.isWakeRecoveryActive` and show a clean Obsidian-Glass recovery panel offering the three choices.

---

### Task 1: AppSettings Model & Database Migration

**Files:**
- Modify: [AppSettings.swift](file:///Users/chintan/Personal/repos/FocusFlow/Sources/FocusFlow/Models/AppSettings.swift)
- Modify: [StoreMigrator.swift](file:///Users/chintan/Personal/repos/FocusFlow/Sources/FocusFlow/Persistence/StoreMigrator.swift)

**Step 1: Write model property and migration**
Modify [AppSettings.swift](file:///Users/chintan/Personal/repos/FocusFlow/Sources/FocusFlow/Models/AppSettings.swift) to add the property and default initialization:
```swift
    // Focus Coach v2 - Realtime coaching / General Sleep settings
    var autoStopOnSleepThresholdMinutes: Int = 60
```
Update `init()` to set `self.autoStopOnSleepThresholdMinutes = 60`.

Modify [StoreMigrator.swift](file:///Users/chintan/Personal/repos/FocusFlow/Sources/FocusFlow/Persistence/StoreMigrator.swift) to add `ZAUTOSTOPONSLEEPTHRESHOLDMINUTES` to `requiredColumnMigrations`:
```swift
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZAUTOSTOPONSLEEPTHRESHOLDMINUTES",
            sqlType: "INTEGER",
            defaultSQLValue: "60"
        ),
```

**Step 2: Run build to verify**
Run: `swift build`
Expected: SUCCESS

**Step 3: Commit**
```bash
git add Sources/FocusFlow/Models/AppSettings.swift Sources/FocusFlow/Persistence/StoreMigrator.swift
git commit -m "model: add autoStopOnSleepThresholdMinutes and register store migration"
```

---

### Task 2: Expose Stepper in SettingsView

**Files:**
- Modify: [SettingsView.swift](file:///Users/chintan/Personal/repos/FocusFlow/Sources/FocusFlow/Views/Companion/SettingsView.swift)

**Step 1: Expose wake recovery threshold setting**
Modify [SettingsView.swift](file:///Users/chintan/Personal/repos/FocusFlow/Sources/FocusFlow/Views/Companion/SettingsView.swift) right below the `autoResumeOnWake` block (around line 256):
```swift
                    if settings.autoResumeOnWake {
                        // ... existing autoResumeThresholdSeconds ...
                    }

                    Divider()

                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "bed.double.fill")
                                .foregroundStyle(.indigo)
                                .font(.system(size: 13, weight: .semibold))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Wake recovery threshold")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Auto-stops and prompts on wake if asleep longer than this")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        Stepper(
                            "\(settings.autoStopOnSleepThresholdMinutes) min",
                            value: Binding(
                                get: { settings.autoStopOnSleepThresholdMinutes },
                                set: { settings.autoStopOnSleepThresholdMinutes = $0; save() }
                            ),
                            in: 5...240,
                            step: 5
                        )
                        .frame(width: 145)
                        .font(.subheadline)
                    }
```

**Step 2: Run build**
Run: `swift build`
Expected: SUCCESS

**Step 3: Commit**
```bash
git add Sources/FocusFlow/Views/Companion/SettingsView.swift
git commit -m "ui: add wake recovery threshold stepper to SettingsView"
```

---

### Task 3: Implement Wake Recovery State and Handler in TimerViewModel

**Files:**
- Modify: [TimerViewModel.swift](file:///Users/chintan/Personal/repos/FocusFlow/Sources/FocusFlow/ViewModels/TimerViewModel.swift)

**Step 1: Add wake recovery state variables**
Add the following properties to `TimerViewModel` (near line 245):
```swift
    // MARK: - Wake Recovery (Issue #32)
    var showWakeRecoveryPrompt: Bool = false
    var wakeRecoverySleepStartTime: Date? = nil
    var wakeRecoveryWakeTime: Date? = nil
    var wakeRecoverySession: FocusSession? = nil
    var wakeRecoveryWasOvertime: Bool = false

    var isWakeRecoveryActive: Bool {
        showWakeRecoveryPrompt && wakeRecoverySession != nil
    }
```

**Step 2: Update pauseForSystemSleep()**
Modify `pauseForSystemSleep()` to always pause active focus sessions, even if `isOvertime` is true (to ensure the sleep start time is cleanly captured and timer ticking is suspended):
```swift
        case .focusing:
            if !isOvertime {
                pause()
            }
```
Change to:
```swift
        case .focusing:
            if !isOvertime {
                pause()
            } else {
                // For overtime, invalidate the timer immediately to freeze ticking
                timer?.invalidate()
                timer = nil
            }
```

**Step 3: Update resumeAfterSystemWake()**
Modify `resumeAfterSystemWake()` to check if sleep duration > threshold:
```swift
    func resumeAfterSystemWake() {
        guard let sleepStart = systemSleepStartTime else { return }
        defer {
            systemSleepStartTime = nil
            stateBeforeSleep = nil
        }

        // Check if auto-resume is enabled
        guard settings?.autoResumeOnWake == true else { return }

        let sleepDuration = Date().timeIntervalSince(sleepStart)
        let threshold = TimeInterval(settings?.autoResumeThresholdSeconds ?? 120)

        // Only auto-resume if sleep was within threshold
        guard sleepDuration <= threshold else { return }
```
Replace the above check with:
```swift
    func resumeAfterSystemWake() {
        guard let sleepStart = systemSleepStartTime else { return }
        defer {
            systemSleepStartTime = nil
            stateBeforeSleep = nil
        }

        let sleepDuration = Date().timeIntervalSince(sleepStart)
        let autoStopThreshold = TimeInterval((settings?.autoStopOnSleepThresholdMinutes ?? 60) * 60)

        if sleepDuration > autoStopThreshold {
            log("resumeAfterSystemWake: long sleep detected (\(sleepDuration)s > \(autoStopThreshold)s) - triggering wake recovery")
            
            // Invalidate any active timers
            timer?.invalidate()
            timer = nil
            pauseTimer?.invalidate()
            pauseTimer = nil
            pauseStartTime = nil
            pauseElapsed = 0

            // Capture wake recovery state
            wakeRecoverySession = currentSession
            wakeRecoverySleepStartTime = sleepStart
            wakeRecoveryWakeTime = Date()
            wakeRecoveryWasOvertime = isOvertime

            // Provisionally save the session endedAt to wake time (can be overridden by user)
            if let session = currentSession {
                session.endedAt = Date()
                saveContext()
            }

            // Reset state machine to idle
            state = .idle
            isOvertime = false
            overtimeSeconds = 0
            remainingSeconds = 0
            totalSeconds = 0
            currentSession = nil
            clearCrashRecoveryState()

            // Trigger recovery window
            showWakeRecoveryPrompt = true
            showSessionComplete = true
            closePopover()

            DispatchQueue.main.async { [weak self] in
                self?.openCompletionWindow?()
                self?.requestAppActivation?()
            }
            return
        }

        // Check if auto-resume is enabled
        guard settings?.autoResumeOnWake == true else { return }

        let threshold = TimeInterval(settings?.autoResumeThresholdSeconds ?? 120)

        // Only auto-resume if sleep was within threshold
        guard sleepDuration <= threshold else { return }
```

**Step 4: Implement resolveWakeRecovery(choice:)**
Add the resolver method to `TimerViewModel`:
```swift
    enum WakeRecoveryChoice {
        case saveToSleepStart
        case keepOvertime
        case discard
    }

    func resolveWakeRecovery(choice: WakeRecoveryChoice) {
        guard isWakeRecoveryActive, let session = wakeRecoverySession else { return }
        
        switch choice {
        case .saveToSleepStart:
            let sleepStart = wakeRecoverySleepStartTime ?? Date()
            session.endedAt = sleepStart
            
            if !wakeRecoveryWasOvertime {
                let elapsed = sleepStart.timeIntervalSince(session.startedAt)
                session.completed = elapsed >= session.duration
            } else {
                session.completed = true
            }
            saveContext()

            // Set up contexts so normal reflection displays correct session stats
            lastCompletedDuration = session.duration
            lastCompletedLabel = session.label
            lastCompletedSession = session
            lastCompletedFocusSession = session
            lastCompletionWasBreak = (session.type != .focus)
            completedBlockContext = CompletedBlockContext(
                sessionId: session.id,
                projectName: session.project?.name ?? "Focus",
                projectId: session.project?.id,
                durationMinutes: Int(session.actualDuration / 60),
                workMode: session.project?.workMode ?? .deepWork,
                earnedAt: Date()
            )
            refreshEarnedBreakSuggestion()
            showWakeRecoveryPrompt = false

        case .keepOvertime:
            let wakeTime = wakeRecoveryWakeTime ?? Date()
            session.endedAt = wakeTime
            session.completed = true
            saveContext()

            lastCompletedDuration = session.duration
            lastCompletedLabel = session.label
            lastCompletedSession = session
            lastCompletedFocusSession = session
            lastCompletionWasBreak = (session.type != .focus)
            completedBlockContext = CompletedBlockContext(
                sessionId: session.id,
                projectName: session.project?.name ?? "Focus",
                projectId: session.project?.id,
                durationMinutes: Int(session.actualDuration / 60),
                workMode: session.project?.workMode ?? .deepWork,
                earnedAt: Date()
            )
            refreshEarnedBreakSuggestion()
            showWakeRecoveryPrompt = false

        case .discard:
            modelContext?.delete(session)
            saveContext()
            
            showWakeRecoveryPrompt = false
            showSessionComplete = false
            clearWakeRecoveryState()
        }
    }

    func clearWakeRecoveryState() {
        showWakeRecoveryPrompt = false
        wakeRecoverySleepStartTime = nil
        wakeRecoveryWakeTime = nil
        wakeRecoverySession = nil
        wakeRecoveryWasOvertime = false
    }
```

**Step 5: Run tests and verify**
Run: `swift test`
Expected: PASS

**Step 6: Commit**
```bash
git add Sources/FocusFlow/ViewModels/TimerViewModel.swift
git commit -m "core: implement wake recovery state and resolver in TimerViewModel"
```

---

### Task 4: Implement Wake Recovery UI in SessionCompleteWindow

**Files:**
- Modify: [SessionCompleteWindow.swift](file:///Users/chintan/Personal/repos/FocusFlow/Sources/FocusFlow/Views/SessionCompleteWindow.swift)

**Step 1: Add Wake Recovery Screen**
Modify `SessionCompleteWindowView` in [SessionCompleteWindow.swift](file:///Users/chintan/Personal/repos/FocusFlow/Sources/FocusFlow/Views/SessionCompleteWindow.swift). 
Around line 50, update `body` to render the wake recovery prompt when active:
```swift
    var body: some View {
        Group {
            if timerVM.isWakeRecoveryActive {
                wakeRecoveryContent
            } else if isBreakCompletion {
                breakContent
            } else {
                focusContent
            }
        }
        // ... rest of body ...
```

Add `wakeRecoveryContent` view layout at the end of the file:
```swift
    // MARK: - Wake Recovery Screen (Issue #32)

    private var wakeRecoveryContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // Badge/Icon
                    ZStack {
                        Circle()
                            .fill(LiquidDesignTokens.Spectral.indigo.opacity(0.15))
                            .frame(width: 80, height: 80)
                        Image(systemName: "bed.double.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(LiquidDesignTokens.Spectral.indigo)
                    }
                    .padding(.top, 16)

                    // Headline
                    VStack(spacing: 6) {
                        Text("Wake Recovery")
                            .font(LiquidDesignTokens.Typography.labelSmall)
                            .tracking(1.2)
                            .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                        Text("Resolve Interrupted Session")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                    }

                    // Description text
                    Text("FocusFlow detected your computer slept for a long duration while a focus session was active. How would you like to log this session?")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)

                    // Choices
                    VStack(spacing: 10) {
                        Button {
                            timerVM.resolveWakeRecovery(choice: .saveToSleepStart)
                        } label: {
                            HStack {
                                Image(systemName: "clock.badge.checkmark.fill")
                                    .foregroundStyle(LiquidDesignTokens.Spectral.mint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Save up to sleep start")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                                    if let sleepStart = timerVM.wakeRecoverySleepStartTime,
                                       let session = timerVM.wakeRecoverySession {
                                        let elapsed = sleepStart.timeIntervalSince(session.startedAt)
                                        Text("Logs \(Int(elapsed / 60)) min (excludes sleep duration)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.5))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        Button {
                            timerVM.resolveWakeRecovery(choice: .keepOvertime)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(LiquidDesignTokens.Spectral.amber)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Keep full overtime")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                                    if let wakeTime = timerVM.wakeRecoveryWakeTime,
                                       let session = timerVM.wakeRecoverySession {
                                        let elapsed = wakeTime.timeIntervalSince(session.startedAt)
                                        Text("Logs \(Int(elapsed / 60)) min (includes sleep duration)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.5))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        Button {
                            timerVM.resolveWakeRecovery(choice: .discard)
                            dismissWindow(id: "session-complete")
                        } label: {
                            HStack {
                                Image(systemName: "trash.fill")
                                    .foregroundStyle(LiquidDesignTokens.Spectral.salmon)
                                Text("Discard session entirely")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                }
                .padding(24)
            }
        }
        .frame(width: 480, height: 440)
    }
```

**Step 2: Run build**
Run: `swift build`
Expected: SUCCESS

**Step 3: Commit**
```bash
git add Sources/FocusFlow/Views/SessionCompleteWindow.swift
git commit -m "ui: implement Wake Recovery Screen in SessionCompleteWindow"
```

---

### Task 5: Write Integration Unit Tests for Wake Recovery

**Files:**
- Create: [Tests/FocusFlowTests/WakeRecoveryTests.swift](file:///Users/chintan/Personal/repos/FocusFlow/Tests/FocusFlowTests/WakeRecoveryTests.swift)

**Step 1: Write wake recovery unit tests**
Create a new file [Tests/FocusFlowTests/WakeRecoveryTests.swift](file:///Users/chintan/Personal/repos/FocusFlow/Tests/FocusFlowTests/WakeRecoveryTests.swift) with test scenarios verifying:
1. Session pauses on sleep.
2. Short sleep triggers auto-resume.
3. Long sleep (> threshold) stops session and activates wake recovery mode.
4. Resolving as `.saveToSleepStart` crops duration and proceeds to completion.
5. Resolving as `.keepOvertime` retains wake-time duration.
6. Resolving as `.discard` deletes session.

```swift
import XCTest
import SwiftData
@testable import FocusFlow

@MainActor
final class WakeRecoveryTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var timerVM: TimerViewModel!
    private var settings: AppSettings!

    override func setUp() async throws {
        let schema = Schema([Project.self, FocusSession.self, AppSettings.self, TimeSplit.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: config)
        modelContext = modelContainer.mainContext
        
        settings = AppSettings()
        settings.autoStopOnSleepThresholdMinutes = 10
        modelContext.insert(settings)
        
        timerVM = TimerViewModel()
        timerVM.configureForEvidence(modelContext: modelContext, settings: settings)
    }

    override func tearDown() {
        timerVM = nil
        settings = nil
        modelContext = nil
        modelContainer = nil
    }

    func testPauseOnSleepAndWakeAutoResumeShortSleep() {
        // Start a session
        timerVM.startFocus()
        XCTAssertEqual(timerVM.state, .focusing)
        
        // Sleep system (brief)
        timerVM.pauseForSystemSleep()
        XCTAssertEqual(timerVM.state, .paused)
        XCTAssertNotNil(timerVM.systemSleepStartTime)
        
        // Wake system after 30 seconds (within threshold)
        timerVM.resumeAfterSystemWake()
        XCTAssertEqual(timerVM.state, .focusing)
        XCTAssertNil(timerVM.systemSleepStartTime)
    }

    func testLongSleepTriggersWakeRecovery() {
        // Start a session
        timerVM.startFocus()
        XCTAssertEqual(timerVM.state, .focusing)
        let session = timerVM.currentSession
        XCTAssertNotNil(session)
        
        // Sleep system
        timerVM.pauseForSystemSleep()
        XCTAssertEqual(timerVM.state, .paused)
        
        // Manually adjust sleep start time to be 15 minutes ago
        timerVM.systemSleepStartTime = Date().addingTimeInterval(-900)
        
        // Wake system (long sleep > 10 min threshold)
        timerVM.resumeAfterSystemWake()
        
        XCTAssertEqual(timerVM.state, .idle)
        XCTAssertTrue(timerVM.showWakeRecoveryPrompt)
        XCTAssertTrue(timerVM.isWakeRecoveryActive)
        XCTAssertEqual(timerVM.wakeRecoverySession?.id, session?.id)
    }

    func testResolveSaveToSleepStart() {
        timerVM.startFocus()
        let session = timerVM.currentSession!
        timerVM.pauseForSystemSleep()
        
        let sleepStart = Date().addingTimeInterval(-600)
        timerVM.systemSleepStartTime = sleepStart
        timerVM.resumeAfterSystemWake()
        
        timerVM.resolveWakeRecovery(choice: .saveToSleepStart)
        
        XCTAssertFalse(timerVM.showWakeRecoveryPrompt)
        XCTAssertEqual(session.endedAt, sleepStart)
        XCTAssertNotNil(timerVM.lastCompletedSession)
    }

    func testResolveKeepOvertime() {
        timerVM.startFocus()
        let session = timerVM.currentSession!
        timerVM.pauseForSystemSleep()
        
        let sleepStart = Date().addingTimeInterval(-600)
        timerVM.systemSleepStartTime = sleepStart
        timerVM.resumeAfterSystemWake()
        
        let wakeTime = timerVM.wakeRecoveryWakeTime!
        timerVM.resolveWakeRecovery(choice: .keepOvertime)
        
        XCTAssertFalse(timerVM.showWakeRecoveryPrompt)
        XCTAssertEqual(session.endedAt, wakeTime)
        XCTAssertNotNil(timerVM.lastCompletedSession)
    }

    func testResolveDiscard() {
        timerVM.startFocus()
        timerVM.pauseForSystemSleep()
        
        timerVM.systemSleepStartTime = Date().addingTimeInterval(-600)
        timerVM.resumeAfterSystemWake()
        
        timerVM.resolveWakeRecovery(choice: .discard)
        
        XCTAssertFalse(timerVM.showWakeRecoveryPrompt)
        XCTAssertFalse(timerVM.showSessionComplete)
        XCTAssertNil(timerVM.wakeRecoverySession)
    }
}
```

**Step 2: Run tests**
Run: `swift test`
Expected: PASS

**Step 3: Commit**
```bash
git add Tests/FocusFlowTests/WakeRecoveryTests.swift
git commit -m "test: add WakeRecoveryTests unit tests"
```

---

### Task 6: Walkthrough & Evidence Generation

**Files:**
- Create: [docs/project-memory/evolution/YYYY-MM-DD-sleep-recovery-walkthrough.md](file:///Users/chintan/Personal/repos/FocusFlow/docs/project-memory/evolution/2026-06-16-sleep-recovery-walkthrough.md)

**Step 1: Document accomplishments and tests**
Write a walkthrough of the changes made, the new settings page rendering, and the mock wake prompt dialog rendering.

**Step 2: Commit**
```bash
git add docs/project-memory/evolution/2026-06-16-sleep-recovery-walkthrough.md
git commit -m "docs: add sleep recovery feature walkthrough"
```
