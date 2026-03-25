# Idle-First Guardian Intelligence Implementation Plan

> **For Claude:** Use /executing-plans to implement this plan task-by-task.

**Goal:** Implement an idle-first, deterministic guardian that learns from chip inputs across all app/web/repo contexts, reacts quickly in all modes, and strictly suppresses all popups during screen sharing.
**Architecture:** Extend existing Focus Coach services (`AppUsageTracker`, `FocusCoachEngine`, `FocusCoachInterventionPlanner`, `FocusCoachGuardianAdvisor`) with a unified context key and deterministic confidence memory. Keep intervention routing centralized in `TimerViewModel` with strict suppression gates and mode-specific cadence. Reuse current Drift/Project risk stores for adaptation and recommendation generation.
**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, Foundation, AppKit, XCTest + Swift Testing.

---

## Global implementation constraints

- TDD for each logic change.
- Keep adaptation deterministic (no ML in this phase).
- Keep all memory project-scoped (`projectId|workMode|context`), no global one-shot allow/block.
- No popup UI during screen sharing; silent tracking only.
- Frequent commits after each task.

---

### Task 1: Add screen-share suppression and mode cadence settings

**Files:**
- Modify: `Sources/FocusFlow/Models/AppSettings.swift`
- Modify: `Sources/FocusFlow/Services/FocusCoachSettingsNormalizer.swift`
- Modify: `Tests/FocusFlowTests/FocusCoachSettingsNormalizationTests.swift`

**Step 1: Write failing settings-normalization tests**

Add tests:

```swift
func testScreenShareSuppressionDefaultsToEnabled() {
    let settings = AppSettings()
    XCTAssertTrue(settings.coachSuppressPopupsDuringScreenShare)
}

func testModeCadenceValuesAreClamped() {
    var settings = AppSettings()
    settings.coachStrictPromptSeconds = 5
    settings.coachStrictEscalationSeconds = 5000
    FocusCoachSettingsNormalizer.normalize(&settings)
    XCTAssertEqual(settings.coachStrictPromptSeconds, 15)
    XCTAssertEqual(settings.coachStrictEscalationSeconds, 300)
}
```

**Step 2: Run tests to verify failure**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachSettingsNormalizationTests`

Expected: FAIL (new properties missing).

**Step 3: Implement minimal settings + clamping**

Add to `AppSettings`:

```swift
var coachSuppressPopupsDuringScreenShare: Bool = true
var coachPassivePromptSeconds: Int = 120
var coachPassiveEscalationSeconds: Int = 240
var coachAdaptivePromptSeconds: Int = 90
var coachAdaptiveEscalationSeconds: Int = 180
var coachStrictPromptSeconds: Int = 60
var coachStrictEscalationSeconds: Int = 120
```

Add clamping in normalizer:

```swift
settings.coachStrictPromptSeconds = min(max(settings.coachStrictPromptSeconds, 15), 300)
settings.coachStrictEscalationSeconds = min(max(settings.coachStrictEscalationSeconds, 30), 300)
// same clamping shape for passive/adaptive
```

**Step 4: Run tests to verify pass**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachSettingsNormalizationTests`

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/Models/AppSettings.swift Sources/FocusFlow/Services/FocusCoachSettingsNormalizer.swift Tests/FocusFlowTests/FocusCoachSettingsNormalizationTests.swift && git commit -m "feat: add guardian cadence and screen-share settings" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Add screen-share detection guard and hard suppression policy

**Files:**
- Create: `Sources/FocusFlow/Services/ScreenShareGuard.swift`
- Modify: `Sources/FocusFlow/ViewModels/TimerViewModel.swift`
- Create: `Tests/FocusFlowTests/ScreenShareGuardTests.swift`

**Step 1: Write failing tests for suppression gate**

Create tests:

```swift
func testSuppressionActiveWhenScreenSharingAndSettingEnabled() {
    let guardService = ScreenShareGuard(isSharingProvider: { true })
    XCTAssertTrue(guardService.shouldSuppressGuardianPopups(enabled: true))
}

func testSuppressionInactiveWhenSettingDisabled() {
    let guardService = ScreenShareGuard(isSharingProvider: { true })
    XCTAssertFalse(guardService.shouldSuppressGuardianPopups(enabled: false))
}
```

**Step 2: Run tests to verify failure**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter ScreenShareGuardTests`

Expected: FAIL (service not found).

**Step 3: Implement service + VM gate**

Service API:

```swift
struct ScreenShareGuard {
    let isSharingProvider: () -> Bool
    init(isSharingProvider: @escaping () -> Bool = { false }) { ... }
    func shouldSuppressGuardianPopups(enabled: Bool) -> Bool { enabled && isSharingProvider() }
}
```

In `TimerViewModel`, before presenting any coach popup/window:

```swift
if screenShareGuard.shouldSuppressGuardianPopups(enabled: settings.coachSuppressPopupsDuringScreenShare) {
    currentCoachQuickPromptDecision = nil
    currentIdleStarterDecision = nil
    activeCoachInterventionDecision = nil
    showCoachInterventionWindow = false
    return
}
```

**Step 4: Run tests to verify pass**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter ScreenShareGuardTests`

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/Services/ScreenShareGuard.swift Sources/FocusFlow/ViewModels/TimerViewModel.swift Tests/FocusFlowTests/ScreenShareGuardTests.swift && git commit -m "feat: suppress guardian popups during screen sharing" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Unify release-window semantics (remove dual suppression paths)

**Files:**
- Modify: `Sources/FocusFlow/ViewModels/TimerViewModel.swift`
- Modify: `Tests/FocusFlowTests/InterventionSuppressionWindowTests.swift`
- Modify: `Tests/FocusFlowTests/WorkIntentWindowTests.swift`

**Step 1: Add failing tests for off-duty release behavior**

Add test:

```swift
@Test("markOffDuty enters release window instead of snooze-only path")
func markOffDutyEntersReleaseWindow() {
    let vm = TimerViewModel()
    vm.enterRelease(reason: .offDuty)
    #expect(vm.isInReleaseWindow == true)
}
```

**Step 2: Run tests to verify failure**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter InterventionSuppressionWindowTests`

Expected: FAIL (legacy guard path still referenced).

**Step 3: Implement release unification**

- Remove usage of `guardianReleaseUntil` in decision gates.
- Replace with `suppressionWindow`/`isInReleaseWindow` everywhere.
- In `handleCoachAction(.markOffDuty)`, call:

```swift
enterRelease(reason: .offDuty)
coachEngine.recordInterventionOutcome(.snoozed, skipReason: .doneForToday)
```

**Step 4: Run tests**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter InterventionSuppressionWindowTests && swift test --filter WorkIntentWindowTests`

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/ViewModels/TimerViewModel.swift Tests/FocusFlowTests/InterventionSuppressionWindowTests.swift Tests/FocusFlowTests/WorkIntentWindowTests.swift && git commit -m "fix: unify guardian release window semantics" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Normalize full context key and include Ghostty/terminal contexts

**Files:**
- Modify: `Sources/FocusFlow/Services/AppUsageTracker.swift`
- Modify: `Sources/FocusFlow/Models/AppUsageEntry.swift`
- Modify: `Sources/FocusFlow/Models/ContextIntelligenceModels.swift`
- Modify: `Tests/FocusFlowTests/AppUsageEntryClassificationTests.swift`

**Step 1: Add failing Ghostty/context tests**

```swift
func testGhosttyRecognizedAsTerminalEditorContext() {
    let category = AppUsageEntry.classify(bundleIdentifier: "com.mitchellh.ghostty", appName: "Ghostty")
    XCTAssertEqual(category, .productive)
}

func testRecommendedBlockTargetReturnsAppContextForNonWeb() {
    let target = AppUsageEntry.recommendedBlockTarget(bundleIdentifier: "com.mitchellh.ghostty", appName: "Ghostty")
    XCTAssertEqual(target, "app:com.mitchellh.ghostty")
}
```

**Step 2: Run tests to verify failure**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter AppUsageEntryClassificationTests`

Expected: FAIL (`app:` target unsupported).

**Step 3: Implement context normalization**

- Add helper to build deterministic context key:

```swift
static func normalizedContextKey(
  bundleIdentifier: String,
  appName: String,
  browserHost: String?,
  terminalWorkspace: String?,
  editorWorkspace: String?
) -> String
```

- Add Ghostty in terminal/editor detection list.
- Extend non-web fallback target: `app:<bundleId>` when domain unavailable.

**Step 4: Run tests**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter AppUsageEntryClassificationTests`

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/Services/AppUsageTracker.swift Sources/FocusFlow/Models/AppUsageEntry.swift Sources/FocusFlow/Models/ContextIntelligenceModels.swift Tests/FocusFlowTests/AppUsageEntryClassificationTests.swift && git commit -m "feat: add normalized context keys and ghostty coverage" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: Extend deterministic learning to idle/outside-session observations

**Files:**
- Modify: `Sources/FocusFlow/Services/FocusCoachEngine.swift`
- Modify: `Sources/FocusFlow/Services/DriftMemoryStore.swift`
- Modify: `Tests/FocusFlowTests/DriftMemoryIntegrationTests.swift`

**Step 1: Add failing idle-learning tests**

```swift
@Test("outside-session avoidant labels contribute to project-scoped risk")
func outsideSessionAvoidantContributesToRisk() {
    let store = makeStore()
    let p = UUID()
    store.recordAvoidant(projectId: p, workMode: .deepWork, appOrDomain: "app:com.mitchellh.ghostty")
    store.recordAvoidant(projectId: p, workMode: .deepWork, appOrDomain: "app:com.mitchellh.ghostty")
    #expect(store.projectScopedRisk(projectId: p, workMode: .deepWork, appOrDomain: "app:com.mitchellh.ghostty"))
}
```

**Step 2: Run tests to verify failure**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter DriftMemoryIntegrationTests`

Expected: FAIL (outside-session path not wired end-to-end).

**Step 3: Implement minimal idle-learning path**

In `FocusCoachEngine.handleNewObservation(_:)`, route both in-session and outside-session observations into memory when user chips later classify them; keep project-scoped keys only.

**Step 4: Run tests**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter DriftMemoryIntegrationTests`

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/Services/FocusCoachEngine.swift Sources/FocusFlow/Services/DriftMemoryStore.swift Tests/FocusFlowTests/DriftMemoryIntegrationTests.swift && git commit -m "feat: learn from idle and outside-session classifications" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: Implement repeated-pattern and historical missed-start work-intent signal

**Files:**
- Modify: `Sources/FocusFlow/Services/FocusCoachInterventionPlanner.swift`
- Modify: `Sources/FocusFlow/ViewModels/TimerViewModel.swift`
- Modify: `Tests/FocusFlowTests/WorkIntentWindowTests.swift`

**Step 1: Add failing tests for historical missed-start signal**

```swift
@Test("historical missed-start signal can satisfy work intent")
func historicalMissedStartCountsAsSignal() {
    let signal = WorkIntentSignal(
        openedAppRecently: false,
        selectedProjectRecently: false,
        recentlyAbandonedStart: false,
        withinTypicalWorkHours: true,
        matchesHistoricalMissedStart: true
    )
    #expect(signal.isWorkIntentWindow == true)
}
```

**Step 2: Run tests to verify failure**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter WorkIntentWindowTests`

Expected: FAIL (detector still hardcodes `false`).

**Step 3: Implement detector wiring**

Update `WorkIntentWindowDetector.evaluate(...)` signature:

```swift
func evaluate(..., matchesHistoricalMissedStart: Bool) -> WorkIntentSignal
```

In `TimerViewModel.evaluateIdleStarterIntervention`, compute repeated-pattern flag from drift/risk stores and pass it in.

**Step 4: Run tests**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter WorkIntentWindowTests`

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/Services/FocusCoachInterventionPlanner.swift Sources/FocusFlow/ViewModels/TimerViewModel.swift Tests/FocusFlowTests/WorkIntentWindowTests.swift && git commit -m "feat: wire historical missed-start into work-intent detection" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 7: Tighten outside-session challenge gates and mode-specific timing

**Files:**
- Modify: `Sources/FocusFlow/Services/FocusCoachGuardianAdvisor.swift`
- Modify: `Sources/FocusFlow/Services/FocusCoachInterventionPlanner.swift`
- Modify: `Sources/FocusFlow/ViewModels/TimerViewModel.swift`
- Modify: `Tests/FocusFlowTests/FocusCoachGuardianAdvisorTests.swift`
- Modify: `Tests/FocusFlowTests/FocusCoachInterventionPlannerTests.swift`

**Step 1: Add failing gate tests**

```swift
func testOutsideSessionChallengeRequiresHighConfidenceOrRepeatedPattern() {
    // expect false when challenge state exists but neither condition true
}

func testStrictModeUses60sPromptAnd120sEscalation() {
    // verify cadence-driven routing in idle evaluations
}
```

**Step 2: Run tests**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachGuardianAdvisorTests && swift test --filter FocusCoachInterventionPlannerTests`

Expected: FAIL.

**Step 3: Implement gate logic**

Add planner gate:

```swift
let confidenceGatePassed = hasHighConfidenceDrift || hasRepeatedProjectPattern
guard confidenceGatePassed else { return false }
```

Then enforce in idle route before any strong dialog.

Implement mode cadence map from `AppSettings` values (strict/adaptive/passive prompt/escalation seconds).

**Step 4: Run tests**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachGuardianAdvisorTests && swift test --filter FocusCoachInterventionPlannerTests`

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/Services/FocusCoachGuardianAdvisor.swift Sources/FocusFlow/Services/FocusCoachInterventionPlanner.swift Sources/FocusFlow/ViewModels/TimerViewModel.swift Tests/FocusFlowTests/FocusCoachGuardianAdvisorTests.swift Tests/FocusFlowTests/FocusCoachInterventionPlannerTests.swift && git commit -m "feat: tighten outside-session challenge gates and mode cadence" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 8: Surface non-web risk recommendations (Ghostty/app contexts)

**Files:**
- Modify: `Sources/FocusFlow/Services/FocusCoachBlockingRecommendationEngine.swift`
- Modify: `Sources/FocusFlow/Services/FocusCoachGuardianAdvisor.swift`
- Modify: `Sources/FocusFlow/Views/Companion/InsightsView.swift`
- Modify: `Tests/FocusFlowTests/BlockingRecommendationIntegrationTests.swift`

**Step 1: Add failing recommendation tests**

```swift
@Test("app-context recommendation can be emitted for ghostty") 
func appContextRecommendationForGhostty() {
    let engine = makeEngine()
    let p = UUID()
    let key = "app:com.mitchellh.ghostty"
    engine.recordAvoidant(projectId: p, workMode: .deepWork, contextKey: key, displayName: "Ghostty")
    engine.recordAvoidant(projectId: p, workMode: .deepWork, contextKey: key, displayName: "Ghostty")
    #expect(engine.blockRecommendation(for: key) != nil)
}
```

**Step 2: Run tests to verify failure**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter BlockingRecommendationIntegrationTests`

Expected: FAIL (domain-only assumptions).

**Step 3: Implement minimal app-context recommendation support**

- Keep domain recommendations.
- Add app-context branch for `app:` keys in recommendation copy.
- Update Insights section to include app-context candidates in guardian recommendation list.

**Step 4: Run tests**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter BlockingRecommendationIntegrationTests`

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/Services/FocusCoachBlockingRecommendationEngine.swift Sources/FocusFlow/Services/FocusCoachGuardianAdvisor.swift Sources/FocusFlow/Views/Companion/InsightsView.swift Tests/FocusFlowTests/BlockingRecommendationIntegrationTests.swift && git commit -m "feat: support non-web risk recommendations including ghostty contexts" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 9: Add idle chip micro-prompt feedback loop for uncertain contexts

**Files:**
- Modify: `Sources/FocusFlow/ViewModels/TimerViewModel.swift`
- Modify: `Sources/FocusFlow/Views/CoachInterventionWindowView.swift`
- Modify: `Sources/FocusFlow/Models/FocusCoachEnums.swift`
- Modify: `Tests/FocusFlowTests/FocusCoachEngineTests.swift`

**Step 1: Add failing tests for uncertain-context chip behavior**

```swift
func testIdleUncertainContextShowsClassificationChipPrompt() { ... }
func testChipSelectionUpdatesMemoryAndFutureCadence() { ... }
```

**Step 2: Run tests**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachEngineTests`

Expected: FAIL.

**Step 3: Implement minimal classification loop**

- Present compact chip prompt for low-confidence/new contexts.
- On chip selection, record planned/avoidant classification through existing engine memory path.
- Increase/decrease future prompt cadence based on repeated outcomes.

**Step 4: Run tests**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test --filter FocusCoachEngineTests`

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add Sources/FocusFlow/ViewModels/TimerViewModel.swift Sources/FocusFlow/Views/CoachInterventionWindowView.swift Sources/FocusFlow/Models/FocusCoachEnums.swift Tests/FocusFlowTests/FocusCoachEngineTests.swift && git commit -m "feat: add idle classification chip feedback loop" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 10: Full verification and docs alignment

**Files:**
- Modify: `README.md` (coach behavior summary if needed)
- Modify: `docs/plans/2026-03-24-idle-first-guardian-intelligence-design.md` (if implementation details changed)

**Step 1: Run targeted test suites**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow && \
swift test --filter FocusCoachSettingsNormalizationTests && \
swift test --filter ScreenShareGuardTests && \
swift test --filter WorkIntentWindowTests && \
swift test --filter FocusCoachInterventionPlannerTests && \
swift test --filter FocusCoachGuardianAdvisorTests && \
swift test --filter DriftMemoryIntegrationTests && \
swift test --filter BlockingRecommendationIntegrationTests && \
swift test --filter AppUsageEntryClassificationTests
```

Expected: PASS.

**Step 2: Run full test suite**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift test`

Expected: PASS.

**Step 3: Run build**

Run: `cd /Users/chintan/Personal/repos/FocusFlow && swift build`

Expected: Build succeeds.

**Step 4: Update docs with shipped behavior**

Add concise notes for:
- idle-first guardian
- screen-share suppression
- Ghostty/non-web recommendations

**Step 5: Final commit**

```bash
cd /Users/chintan/Personal/repos/FocusFlow && git add README.md docs/plans/2026-03-24-idle-first-guardian-intelligence-design.md && git commit -m "docs: align guardian behavior docs with idle-first deterministic model" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

