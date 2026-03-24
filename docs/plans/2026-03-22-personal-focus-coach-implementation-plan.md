# Personal Focus Coach v1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an on-device, real-time, low-friction Focus Coach that reduces intention-to-action delay with personalized scoring, adaptive interventions, anomaly reason chips, and weekly coach insights.

**Architecture:** Keep telemetry local by extending existing `TimerViewModel` + `AppUsageTracker` into a new `FocusCoachEngine` pipeline (signals -> risk -> intervention decision -> outcome logging). Persist coach context in SwiftData models and keep core logic testable through pure service structs (`RiskScorer`, `InterventionPolicy`, `InsightsBuilder`). Integrate UI in canonical surfaces only: menu bar popover for live coaching, session/break flows for anomaly chips, settings for configuration, and Insights for weekly interpretation.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, XCTest, AppKit (`NSWorkspace`), UserNotifications, existing Liquid Glass design tokens/components.

---

## Implementation Rules (apply to every task)

- Use **@test-driven-development** for every non-trivial logic change.
- Keep prompts low-friction: max 1-3 taps, anomaly-only reason capture.
- Keep defaults privacy-safe and on-device.
- Use **@verification-before-completion** before claiming the feature complete.
- Use **@apple-grade-ui-system** for all UI work and validation.
- Enforce premium UI bar: refined hierarchy, nuanced depth, micro-interactions, and purposeful motion on all coach surfaces.

---

### Task 1: Add Focus Coach settings + migration defaults

**Files:**
- Modify: `Sources/FocusFlow/Models/AppSettings.swift`
- Modify: `Sources/FocusFlow/Persistence/StoreMigrator.swift`
- Test: `Tests/FocusFlowTests/StoreMigratorTests.swift`

**Step 1: Write the failing migration test for new coach settings columns**

Add a new test in `StoreMigratorTests.swift`:

```swift
func testMigrateAddsFocusCoachSettingsColumnsWithDefaults() throws {
    // Arrange existing legacy ZAPPSETTINGS table (same setup pattern as existing tests)
    // Act: try StoreMigrator.migrateStoreIfNeeded(at: url)
    // Assert columns + defaults:
    // ZCOACHREALTIMEENABLED = 1
    // ZCOACHPROMPTBUDGETPERSESSION = 4
    // ZCOACHREASONPROMPTSENABLED = 1
    // ZCOACHDEFAULTSNOOZEMINUTES = 10
    // ZCOACHCOLLECTRAWDOMAINS = 0
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter StoreMigratorTests/testMigrateAddsFocusCoachSettingsColumnsWithDefaults
```

Expected: FAIL (missing columns/defaults).

**Step 3: Implement minimal settings + migration columns**

Add to `AppSettings.swift`:

```swift
var coachRealtimeEnabled: Bool = true
var coachPromptBudgetPerSession: Int = 4
var coachReasonPromptsEnabled: Bool = true
var coachDefaultSnoozeMinutes: Int = 10
var coachCollectRawDomains: Bool = false
```

Add corresponding `ColumnMigration` entries to `StoreMigrator.requiredColumnMigrations`:

```swift
("ZCOACHREALTIMEENABLED", "INTEGER", "1")
("ZCOACHPROMPTBUDGETPERSESSION", "INTEGER", "4")
("ZCOACHREASONPROMPTSENABLED", "INTEGER", "1")
("ZCOACHDEFAULTSNOOZEMINUTES", "INTEGER", "10")
("ZCOACHCOLLECTRAWDOMAINS", "INTEGER", "0")
```

**Step 4: Run test to verify it passes**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter StoreMigratorTests/testMigrateAddsFocusCoachSettingsColumnsWithDefaults
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/Models/AppSettings.swift Sources/FocusFlow/Persistence/StoreMigrator.swift Tests/FocusFlowTests/StoreMigratorTests.swift && git commit -m "feat: add focus coach settings defaults and migration" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Create Focus Coach domain models and register schema

**Files:**
- Create: `Sources/FocusFlow/Models/FocusCoachEnums.swift`
- Create: `Sources/FocusFlow/Models/TaskIntent.swift`
- Create: `Sources/FocusFlow/Models/CoachInterruption.swift`
- Create: `Sources/FocusFlow/Models/InterventionAttempt.swift`
- Modify: `Sources/FocusFlow/FocusFlowApp.swift`
- Test: `Tests/FocusFlowTests/FocusCoachModelDefaultsTests.swift`

**Step 1: Write failing defaults test for new models**

Create `FocusCoachModelDefaultsTests.swift`:

```swift
import XCTest
@testable import FocusFlow

final class FocusCoachModelDefaultsTests: XCTestCase {
    func testTaskIntentDefaults() {
        let intent = TaskIntent(title: "Write failing test")
        XCTAssertEqual(intent.expectedResistance, 3)
        XCTAssertEqual(intent.taskType, .deepWork)
    }

    func testInterventionAttemptDefaults() {
        let attempt = InterventionAttempt(kind: .softNudge, riskScore: 0.4)
        XCTAssertFalse(attempt.dismissed)
        XCTAssertNil(attempt.outcomeRawValue)
    }
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachModelDefaultsTests
```

Expected: FAIL (`TaskIntent` / `InterventionAttempt` not found).

**Step 3: Add model implementations**

Implement minimal models/enums:

```swift
enum FocusCoachTaskType: String, Codable { case deepWork, admin, learning, creative }
enum FocusCoachReason: String, Codable { case urgentMeeting, familyPersonal, stressSpike, fatigue, legitDistraction, resistanceAvoidance, other }
enum FocusCoachInterruptionKind: String, Codable { case missedStart, fakeStart, drift, breakOverrun, midSessionStop }
enum FocusCoachInterventionKind: String, Codable { case softNudge, quickPrompt, strongPrompt }
enum FocusCoachOutcome: String, Codable { case improved, ignored, snoozed, dismissed }
```

```swift
@Model final class TaskIntent { ... }
@Model final class CoachInterruption { ... }
@Model final class InterventionAttempt { ... }
```

Then register in `FocusFlowApp` schema:

```swift
Schema([
  Project.self, FocusSession.self, AppSettings.self, TimeSplit.self,
  BlockProfile.self, AppUsageRecord.self, AppUsageEntry.self,
  TaskIntent.self, CoachInterruption.self, InterventionAttempt.self
])
```

**Step 4: Run tests to verify pass**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachModelDefaultsTests && swift build
```

Expected: PASS + build succeeds.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/Models/FocusCoachEnums.swift Sources/FocusFlow/Models/TaskIntent.swift Sources/FocusFlow/Models/CoachInterruption.swift Sources/FocusFlow/Models/InterventionAttempt.swift Sources/FocusFlow/FocusFlowApp.swift Tests/FocusFlowTests/FocusCoachModelDefaultsTests.swift && git commit -m "feat: add focus coach data models and schema wiring" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Implement real-time risk scoring service

**Files:**
- Create: `Sources/FocusFlow/Services/FocusCoachRiskScorer.swift`
- Test: `Tests/FocusFlowTests/FocusCoachRiskScorerTests.swift`

**Step 1: Write failing tests for risk logic**

Create `FocusCoachRiskScorerTests.swift`:

```swift
import XCTest
@testable import FocusFlow

final class FocusCoachRiskScorerTests: XCTestCase {
    func testHighDelayAndSwitchingYieldHighRisk() {
        let scorer = FocusCoachRiskScorer()
        let signals = FocusCoachSignals(
            startDelaySeconds: 480,
            appSwitchesPerMinute: 14,
            nonWorkForegroundRatio: 0.75,
            inactivityBurstSeconds: 120,
            blockedAppAttempts: 2,
            pauseCount: 2,
            breakOverrunSeconds: 0,
            recentLegitimateReason: false
        )
        let result = scorer.score(signals)
        XCTAssertEqual(result.level, .highRisk)
        XCTAssertGreaterThan(result.score, 0.75)
    }

    func testLegitimateReasonReducesFalsePositiveRisk() {
        let scorer = FocusCoachRiskScorer()
        var signals = FocusCoachSignals.sampleHighRisk
        signals.recentLegitimateReason = true
        let result = scorer.score(signals)
        XCTAssertLessThan(result.score, 0.75)
    }
}
```

**Step 2: Run tests to verify failure**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachRiskScorerTests
```

Expected: FAIL (missing scorer/types).

**Step 3: Implement minimal scorer**

Implement:

```swift
struct FocusCoachSignals { ... }
enum FocusCoachRiskLevel { case stable, driftRisk, highRisk }
struct FocusCoachRiskResult { let score: Double; let confidence: Double; let level: FocusCoachRiskLevel }

struct FocusCoachRiskScorer {
    func score(_ signals: FocusCoachSignals) -> FocusCoachRiskResult {
        // weighted formula with clamp(0...1)
        // apply false-positive dampener when recentLegitimateReason == true
    }
}
```

**Step 4: Run tests and keep them green**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachRiskScorerTests
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/Services/FocusCoachRiskScorer.swift Tests/FocusFlowTests/FocusCoachRiskScorerTests.swift && git commit -m "feat: add focus coach risk scoring service" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Implement intervention policy (budget, snooze, escalation)

**Files:**
- Create: `Sources/FocusFlow/Services/FocusCoachInterventionPolicy.swift`
- Test: `Tests/FocusFlowTests/FocusCoachInterventionPolicyTests.swift`

**Step 1: Write failing policy tests**

```swift
import XCTest
@testable import FocusFlow

final class FocusCoachInterventionPolicyTests: XCTestCase {
    func testSnoozeSuppressesIntervention() {
        let policy = FocusCoachInterventionPolicy()
        let now = Date()
        let state = FocusCoachPromptState(
            promptCountThisSession: 1,
            consecutiveHighRiskWindows: 2,
            snoozedUntil: now.addingTimeInterval(300)
        )
        let decision = policy.decide(now: now, risk: .highRisk, state: state, promptBudget: 4)
        XCTAssertEqual(decision.kind, .none)
    }

    func testEscalatesToStrongAfterRepeatedHighRisk() {
        let policy = FocusCoachInterventionPolicy()
        let state = FocusCoachPromptState(promptCountThisSession: 2, consecutiveHighRiskWindows: 3, snoozedUntil: nil)
        let decision = policy.decide(now: Date(), risk: .highRisk, state: state, promptBudget: 4)
        XCTAssertEqual(decision.kind, .strongPrompt)
    }
}
```

**Step 2: Run tests to verify failure**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachInterventionPolicyTests
```

Expected: FAIL.

**Step 3: Implement policy service**

```swift
enum FocusCoachDecisionKind { case none, softStrip, quickPrompt, strongPrompt }
enum FocusCoachQuickAction: String { case returnNow, cleanRestart5m, snooze10m }
struct FocusCoachDecision { ... }
struct FocusCoachPromptState { ... }

struct FocusCoachInterventionPolicy {
    func decide(now: Date, risk: FocusCoachRiskLevel, state: FocusCoachPromptState, promptBudget: Int) -> FocusCoachDecision {
        // honor snooze and budget first
        // driftRisk -> quickPrompt
        // repeated highRisk -> strongPrompt
    }
}
```

**Step 4: Run tests to verify pass**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachInterventionPolicyTests
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/Services/FocusCoachInterventionPolicy.swift Tests/FocusFlowTests/FocusCoachInterventionPolicyTests.swift && git commit -m "feat: add focus coach intervention policy with snooze and escalation" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: Add FocusCoachEngine and wire telemetry ingestion

**Files:**
- Create: `Sources/FocusFlow/Services/FocusCoachEngine.swift`
- Modify: `Sources/FocusFlow/Services/AppUsageTracker.swift`
- Modify: `Sources/FocusFlow/ViewModels/TimerViewModel.swift`
- Test: `Tests/FocusFlowTests/FocusCoachEngineTests.swift`

**Step 1: Write failing engine tests**

```swift
import XCTest
@testable import FocusFlow

final class FocusCoachEngineTests: XCTestCase {
    func testTickProducesQuickPromptWhenRiskCrossesThreshold() {
        let store = InMemoryCoachStore()
        let engine = FocusCoachEngine(store: store)
        engine.recordBehaviorSample(.highDriftSample)
        let decision = engine.tick(now: Date())
        XCTAssertEqual(decision?.kind, .quickPrompt)
    }

    func testLegitimateReasonCreatesInterruptionMarkedLegitimate() {
        let store = InMemoryCoachStore()
        let engine = FocusCoachEngine(store: store)
        engine.recordAnomaly(kind: .midSessionStop, reason: .urgentMeeting, sessionId: UUID())
        XCTAssertTrue(store.interruptions.last?.isLegitimate == true)
    }
}
```

**Step 2: Run tests to verify failure**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachEngineTests
```

Expected: FAIL.

**Step 3: Implement engine + store protocol**

Add protocol + orchestrator:

```swift
protocol FocusCoachPersisting {
    func saveInterruption(_ interruption: CoachInterruption)
    func saveInterventionAttempt(_ attempt: InterventionAttempt)
}

final class FocusCoachEngine {
    // holds scorer + policy + prompt state
    // recordTimelineEvent(...)
    // recordBehaviorSample(...)
    // tick(now:) -> FocusCoachDecision?
    // recordInterventionOutcome(...)
}
```

Wire:
- In `TimerViewModel.configure`: initialize engine.
- On start/pause/resume/break/stop paths: call timeline event logging.
- In `AppUsageTracker`: compute app-switch/minute + inactivity burst and call `timerVM.recordCoachBehaviorSample(...)`.

**Step 4: Run focused tests and existing regressions**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachEngineTests && swift test --filter NotificationServiceTests
```

Expected: PASS for both.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/Services/FocusCoachEngine.swift Sources/FocusFlow/Services/AppUsageTracker.swift Sources/FocusFlow/ViewModels/TimerViewModel.swift Tests/FocusFlowTests/FocusCoachEngineTests.swift && git commit -m "feat: wire realtime coach engine into timer and app usage telemetry" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: Build menu bar real-time coach UI (pre-session + live strip)

**Files:**
- Create: `Sources/FocusFlow/Views/Components/FocusCoachStripView.swift`
- Create: `Sources/FocusFlow/Views/Components/FocusCoachQuickPromptView.swift`
- Create: `Sources/FocusFlow/Views/Components/FocusCoachPreSessionCard.swift`
- Modify: `Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift`
- Test: `Tests/FocusFlowTests/FocusCoachPresentationMapperTests.swift`
- Create: `Sources/FocusFlow/Services/FocusCoachPresentationMapper.swift`

**Step 1: Write failing presentation tests (text/color/action mapping)**

```swift
import XCTest
@testable import FocusFlow

final class FocusCoachPresentationMapperTests: XCTestCase {
    func testHighRiskMapsToRedStripAndStrongCopy() {
        let model = FocusCoachPresentationMapper.map(level: .highRisk, score: 0.9)
        XCTAssertEqual(model.tone, .red)
        XCTAssertTrue(model.title.contains("Drift"))
    }
}
```

**Step 2: Run tests to verify failure**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachPresentationMapperTests
```

Expected: FAIL.

**Step 3: Implement mapper + components and integrate in popover**

Add:

```swift
struct FocusCoachStripView: View { ... } // green/amber/red strip
struct FocusCoachQuickPromptView: View { ... } // Return now / Clean restart / Snooze
struct FocusCoachPreSessionCard: View { ... } // task, resistance, suggested duration, success criteria
```

In `MenuBarPopoverView`:
- Idle state: render `FocusCoachPreSessionCard` above duration selector.
- Focusing/paused/break state: render `FocusCoachStripView`.
- Show `FocusCoachQuickPromptView` only when engine decision requests it.

Add premium interaction details:
- hover + pressed states for all coach CTAs and chips,
- risk strip tint interpolation animation (green/amber/red),
- compact sheet spring transitions,
- subtle CTA pulse only for urgency windows,
- clear selected-state treatment for quick actions.

**Step 4: Run tests and build**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachPresentationMapperTests && swift build
```

Expected: PASS + build succeeds.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/Services/FocusCoachPresentationMapper.swift Sources/FocusFlow/Views/Components/FocusCoachStripView.swift Sources/FocusFlow/Views/Components/FocusCoachQuickPromptView.swift Sources/FocusFlow/Views/Components/FocusCoachPreSessionCard.swift Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift Tests/FocusFlowTests/FocusCoachPresentationMapperTests.swift && git commit -m "feat: add realtime focus coach strip and pre-session card in popover" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 7: Add anomaly reason chips + snooze (low-friction)

**Files:**
- Create: `Sources/FocusFlow/Services/FocusCoachAnomalyClassifier.swift`
- Create: `Sources/FocusFlow/Views/Components/FocusCoachReasonChipSheet.swift`
- Modify: `Sources/FocusFlow/ViewModels/TimerViewModel.swift`
- Modify: `Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift`
- Modify: `Sources/FocusFlow/Views/SessionCompleteWindow.swift`
- Test: `Tests/FocusFlowTests/FocusCoachAnomalyClassifierTests.swift`

**Step 1: Write failing tests for anomaly classification**

```swift
import XCTest
@testable import FocusFlow

final class FocusCoachAnomalyClassifierTests: XCTestCase {
    func testBreakOverrunTriggersReasonPrompt() {
        let classifier = FocusCoachAnomalyClassifier()
        XCTAssertTrue(classifier.shouldPromptReason(event: .breakOverrun(seconds: 180)))
    }

    func testShortPauseDoesNotTriggerReasonPrompt() {
        let classifier = FocusCoachAnomalyClassifier()
        XCTAssertFalse(classifier.shouldPromptReason(event: .pause(seconds: 30)))
    }
}
```

**Step 2: Run tests to verify failure**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachAnomalyClassifierTests
```

Expected: FAIL.

**Step 3: Implement classifier + reason chip UI**

Implement classifier service and reason sheet with chips:

```swift
["Urgent Meeting", "Family / Personal", "Stress Spike", "Fatigue", "Legit Distraction", "Resistance / Avoidance", "Other"]
```

Integrate:
- Show only on anomaly events (break overrun, mid-session stop, repeated drift).
- Save selected reason via `timerVM.recordCoachReason(...)`.
- Include `Snooze` action in same sheet (1 tap).

**Step 4: Run tests and build**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachAnomalyClassifierTests && swift build
```

Expected: PASS + build succeeds.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/Services/FocusCoachAnomalyClassifier.swift Sources/FocusFlow/Views/Components/FocusCoachReasonChipSheet.swift Sources/FocusFlow/ViewModels/TimerViewModel.swift Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift Sources/FocusFlow/Views/SessionCompleteWindow.swift Tests/FocusFlowTests/FocusCoachAnomalyClassifierTests.swift && git commit -m "feat: add anomaly reason chips and snooze flow for low-friction recovery" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 8: Build personalized coach insights algorithms + UI section

**Files:**
- Create: `Sources/FocusFlow/Services/FocusCoachInsightsBuilder.swift`
- Modify: `Sources/FocusFlow/Views/Companion/InsightsView.swift`
- Test: `Tests/FocusFlowTests/FocusCoachInsightsBuilderTests.swift`

**Step 1: Write failing insights-builder tests**

```swift
import XCTest
@testable import FocusFlow

final class FocusCoachInsightsBuilderTests: XCTestCase {
    func testBuildsStartLatencyTrend() {
        let report = FocusCoachInsightsBuilder().build(
            sessions: SampleCoachData.sessions,
            interruptions: SampleCoachData.interruptions,
            attempts: SampleCoachData.attempts,
            appUsage: SampleCoachData.appUsage
        )
        XCTAssertGreaterThan(report.avgStartLatencySeconds, 0)
    }

    func testRanksTopTriggerAndInterventionWinRate() {
        let report = FocusCoachInsightsBuilder().build(...)
        XCTAssertEqual(report.topTriggers.first?.label, "Rapid app switching")
        XCTAssertGreaterThan(report.interventionWinRate, 0.0)
    }
}
```

**Step 2: Run tests to verify failure**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachInsightsBuilderTests
```

Expected: FAIL.

**Step 3: Implement builder + render in `InsightsView`**

Add builder output DTO:

```swift
struct FocusCoachWeeklyReport {
    let avgStartLatencySeconds: Int
    let interventionWinRate: Double
    let topTriggers: [TriggerMetric]
    let bestSessionLengthByTaskType: [FocusCoachTaskType: Int]
}
```

Then add an Insights section:
- Start Latency card
- Recovery Speed card
- Top Trigger list
- Intervention Effectiveness list

Premium Insights visual requirements:
- richer hierarchy (hero metric + supporting context),
- polished card depth and spacing alignment with Liquid tokens,
- meaningful motion on data updates (no noisy chart spam),
- actionable emphasis (what to do next) over decorative data.

**Step 4: Run tests and compile**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachInsightsBuilderTests && swift build
```

Expected: PASS + build succeeds.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/Services/FocusCoachInsightsBuilder.swift Sources/FocusFlow/Views/Companion/InsightsView.swift Tests/FocusFlowTests/FocusCoachInsightsBuilderTests.swift && git commit -m "feat: add personalized weekly focus coach insights report" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 9: Expand Settings for coach controls and privacy

**Files:**
- Modify: `Sources/FocusFlow/Views/Companion/SettingsView.swift`
- Modify: `Sources/FocusFlow/ViewModels/TimerViewModel.swift`
- Test: `Tests/FocusFlowTests/FocusCoachSettingsNormalizationTests.swift`
- Create: `Sources/FocusFlow/Services/FocusCoachSettingsNormalizer.swift`

**Step 1: Write failing normalization tests**

```swift
import XCTest
@testable import FocusFlow

final class FocusCoachSettingsNormalizationTests: XCTestCase {
    func testPromptBudgetIsClamped() {
        var settings = AppSettings()
        settings.coachPromptBudgetPerSession = 99
        FocusCoachSettingsNormalizer.normalize(&settings)
        XCTAssertEqual(settings.coachPromptBudgetPerSession, 8)
    }
}
```

**Step 2: Run tests to verify failure**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachSettingsNormalizationTests
```

Expected: FAIL.

**Step 3: Implement normalizer + settings UI controls**

Add normalizer:

```swift
enum FocusCoachSettingsNormalizer {
    static func normalize(_ settings: inout AppSettings) {
        settings.coachPromptBudgetPerSession = min(max(settings.coachPromptBudgetPerSession, 1), 8)
        settings.coachDefaultSnoozeMinutes = min(max(settings.coachDefaultSnoozeMinutes, 5), 30)
    }
}
```

Update `SettingsView.focusCoachSection` with:
- Realtime coaching toggle
- Prompt budget stepper
- Reason chips toggle
- Default snooze stepper
- Raw domain collection toggle (default OFF)

Call normalizer before `save()`.

**Step 4: Run tests and build**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachSettingsNormalizationTests && swift build
```

Expected: PASS + build succeeds.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/Services/FocusCoachSettingsNormalizer.swift Sources/FocusFlow/Views/Companion/SettingsView.swift Sources/FocusFlow/ViewModels/TimerViewModel.swift Tests/FocusFlowTests/FocusCoachSettingsNormalizationTests.swift && git commit -m "feat: add focus coach controls in settings with safe normalization" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 10: End-to-end validation + docs

**Files:**
- Modify: `README.md`
- Modify: `docs/plans/2026-03-22-personal-focus-coach-design.md` (only if implementation decisions changed)

**Step 1: Add README feature notes**

Add concise bullets:
- Real-time coach strip
- Anomaly reason chips
- Weekly intervention effectiveness report
- On-device privacy-first personalization

**Step 2: Run full automated checks**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && swift test && swift build
```

Expected: PASS (all tests, clean build).

**Step 3: Manual critical-flow validation**

Run app:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && bash Scripts/run.sh
```

Validate manually:
1. Miss planned start -> soft coach nudge appears.
2. Start + fake-start behavior -> quick prompt appears.
3. Long break overrun -> reason chips + snooze appears.
4. Mid-session end -> reason capture flow appears.
5. Insights tab shows personalized coach report.
6. Settings changes immediately affect coach behavior.

Expected: each flow works without crash and with visible feedback.

**Step 4: Final regression pass**

Re-check adjacent flows:
- existing pause warnings
- session completion flow
- calendar/reminders toggles
- blocking controls

Expected: no regressions.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add README.md docs/plans/2026-03-22-personal-focus-coach-design.md && git commit -m "docs: document personalized on-device focus coach flows" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 11: Apple-grade Gatekeeper review package (mandatory before PASS)

**Files:**
- Create: `docs/plans/2026-03-22-personal-focus-coach-gatekeeper-review.md`
- Capture: screenshots/recordings for critical flows (store references in review file)

**Step 1: Collect required rendered + functional evidence**

Capture for each critical flow:
1. Pre-session missed-start coach cue
2. Fake-start detection prompt
3. Break overrun reason-chip sheet + snooze
4. Mid-session stop reason capture path
5. Weekly personalized coach insights section
6. Settings changes reflected in coach behavior
7. Premium interaction evidence: hover/pressed/selected states
8. Motion evidence: risk transitions, sheet transitions, CTA urgency pulse
9. Visual hierarchy evidence: first-glance clarity and primary action dominance

Also collect:
- console/runtime logs (no crashes, no uncaught errors),
- regression checks for pause warnings, completion flow, integrations, and blocking.
- side-by-side screenshots or clips showing premium polish vs baseline where relevant.

**Step 2: Run Gatekeeper review using required output contract**

Create `docs/plans/2026-03-22-personal-focus-coach-gatekeeper-review.md` with exactly:
1. Executive Verdict (`PASS`, `PASS_WITH_RISKS`, or `BLOCKED`)
2. Critical Blockers
3. Screen-By-Screen Click Walkthrough
4. Placement And Discoverability Map
5. Top 5 Prioritized Fixes
6. Re-Review Checklist
7. Functional Validation Evidence
8. Explicit Assumptions
9. Product Integration Artifacts Check
10. UI Spec Matrix Completeness
11. PM Integration Verdict

If any required evidence is missing, verdict must be `BLOCKED`.

**Step 3: Clear blockers (if any), then re-run review**

If verdict is `BLOCKED`:
- fix blockers,
- re-run tests/manual flows,
- regenerate review file with updated evidence,
- keep iterating until no auto-block trigger remains.

**Step 4: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add docs/plans/2026-03-22-personal-focus-coach-gatekeeper-review.md && git commit -m "docs: add apple-grade gatekeeper evidence and verdict" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Final Verification Checklist (must be complete before merge)

- [ ] `swift test` passes.
- [ ] `swift build` passes.
- [ ] Critical manual flows validated.
- [ ] Rendered evidence exists for all critical flows.
- [ ] Functional validation evidence recorded (logs + pass/fail per flow).
- [ ] Gatekeeper review contract file created and complete.
- [ ] Final gatekeeper verdict is not `BLOCKED`.
- [ ] Premium UI quality validated: depth, hierarchy, and attention to detail.
- [ ] Motion quality validated: smooth purposeful transitions + micro-interaction feedback.
- [ ] No configuration UI leaked into transient popover surfaces.
- [ ] Reason prompts remain anomaly-only and 1-3 taps.
- [ ] On-device only behavior preserved (no cloud calls).
- [ ] Existing timer, break, completion, and settings flows remain intact.

---

## Suggested Commit Sequence

1. `feat: add focus coach settings defaults and migration`
2. `feat: add focus coach data models and schema wiring`
3. `feat: add focus coach risk scoring service`
4. `feat: add focus coach intervention policy with snooze and escalation`
5. `feat: wire realtime coach engine into timer and app usage telemetry`
6. `feat: add realtime focus coach strip and pre-session card in popover`
7. `feat: add anomaly reason chips and snooze flow for low-friction recovery`
8. `feat: add personalized weekly focus coach insights report`
9. `feat: add focus coach controls in settings with safe normalization`
10. `docs: document personalized on-device focus coach flows`
11. `docs: add apple-grade gatekeeper evidence and verdict`
