# Adaptive Earned Breaks Implementation Plan

> **For Claude:** Use /executing-plans to implement this plan task-by-task.

**Goal:** Add adaptive earned-break suggestions, break-aware controls, and green/amber/red ring escalation parity for break overrun + pause while preserving FocusFlow’s lightweight flow.

**Architecture:** Keep policy deterministic and explainable. Compute break suggestions in a pure engine, persist break outcomes in SwiftData, and wire usage through `TimerViewModel` so both `SessionCompleteWindowView` and menu-bar break states share one source of truth. Encapsulate visual severity in a small pure helper consumed by `TimerRingView` to keep UI logic testable.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, XCTest, existing FocusFlow review/fixture pipeline (`UIEvidenceCaptureTests`, `capture-ui-evidence.sh`).

---

## Scope and constraints

- Implement only the approved feature scope from `docs/plans/2026-03-25-adaptive-earned-breaks-design.md`.
- Keep chip-first and lightweight interaction style.
- Do not add heavy planning/task-management UX.
- Keep behavior deterministic (no ML model in this pass).
- Keep validation targeted (pre-existing unrelated failures remain out of scope).

---

### Task 1: Add earned-break suggestion engine (pure logic)

**Files:**
- Create: `Sources/FocusFlow/Services/EarnedBreakSuggestionEngine.swift`
- Create: `Tests/FocusFlowTests/EarnedBreakSuggestionEngineTests.swift`

**Step 1: Write the failing tests**
```swift
import XCTest
@testable import FocusFlow

final class EarnedBreakSuggestionEngineTests: XCTestCase {
    func test55MinuteEffortSuggests15Minutes() {
        let engine = EarnedBreakSuggestionEngine()
        let input = EarnedBreakSuggestionInput(
            effectiveEffortSeconds: 55 * 60,
            overtimeSeconds: 0,
            runCreditSeconds: 55 * 60,
            adaptationMinutes: 0
        )
        XCTAssertEqual(engine.suggest(input).suggestedMinutes, 15)
    }

    func testOvertimeBonusCapsAt20Minutes() {
        let engine = EarnedBreakSuggestionEngine()
        let input = EarnedBreakSuggestionInput(
            effectiveEffortSeconds: 90 * 60,
            overtimeSeconds: 15 * 60,
            runCreditSeconds: 90 * 60,
            adaptationMinutes: 0
        )
        XCTAssertEqual(engine.suggest(input).suggestedMinutes, 20)
    }

    func testAdaptationIsClampedBetweenMinus3AndPlus3() {
        let engine = EarnedBreakSuggestionEngine()
        let input = EarnedBreakSuggestionInput(
            effectiveEffortSeconds: 40 * 60,
            overtimeSeconds: 0,
            runCreditSeconds: 40 * 60,
            adaptationMinutes: 9
        )
        XCTAssertEqual(engine.suggest(input).adaptationAppliedMinutes, 3)
    }
}
```

**Step 2: Run test to verify it fails**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && swift test --filter EarnedBreakSuggestionEngineTests
```
Expected: FAIL (`EarnedBreakSuggestionEngine` / input types not found).

**Step 3: Write minimal implementation**
```swift
struct EarnedBreakSuggestionInput {
    let effectiveEffortSeconds: Int
    let overtimeSeconds: Int
    let runCreditSeconds: Int
    let adaptationMinutes: Int
}

struct EarnedBreakSuggestion {
    let suggestedMinutes: Int
    let adaptationAppliedMinutes: Int
}

struct EarnedBreakSuggestionEngine {
    func suggest(_ input: EarnedBreakSuggestionInput) -> EarnedBreakSuggestion {
        let effortMinutes = max(0, input.effectiveEffortSeconds / 60)
        let baseline: Int
        switch effortMinutes {
        case ..<25: baseline = 5
        case 25..<40: baseline = 8
        case 40..<55: baseline = 12
        case 55..<75: baseline = 15
        default: baseline = 20
        }
        let overtimeBonus = input.overtimeSeconds > 0 ? 2 : 0
        let clampedAdaptation = min(3, max(-3, input.adaptationMinutes))
        let raw = baseline + overtimeBonus + clampedAdaptation
        return EarnedBreakSuggestion(
            suggestedMinutes: min(20, max(5, raw)),
            adaptationAppliedMinutes: clampedAdaptation
        )
    }
}
```

**Step 4: Run test to verify it passes**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && swift test --filter EarnedBreakSuggestionEngineTests
```
Expected: PASS.

**Step 5: Commit**
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && git add Sources/FocusFlow/Services/EarnedBreakSuggestionEngine.swift Tests/FocusFlowTests/EarnedBreakSuggestionEngineTests.swift && git commit -m "feat: add deterministic earned break suggestion engine" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Persist break learning outcomes for adaptation

**Files:**
- Create: `Sources/FocusFlow/Models/BreakLearningEvent.swift`
- Create: `Sources/FocusFlow/Services/BreakLearningStore.swift`
- Modify: `Sources/FocusFlow/FocusFlowApp.swift`
- Test: `Tests/FocusFlowTests/BreakLearningStoreTests.swift`

**Step 1: Write the failing persistence tests**
```swift
@MainActor
final class BreakLearningStoreTests: XCTestCase {
    func testRecordAndFetchRecentProjectScopedBreakEvents() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let store = BreakLearningStore(modelContext: context)
        let project = Project(name: "Interview Prep")
        context.insert(project)

        store.record(
            projectId: project.id,
            workMode: .deepWork,
            suggestedMinutes: 15,
            choseSuggested: true,
            actualBreakSeconds: 14 * 60,
            returnedToFocus: true,
            endedEarly: false,
            overrunSeconds: 0
        )

        let events = store.recentEvents(projectId: project.id, workMode: .deepWork, limit: 10)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].returnedToFocus)
    }
}
```

**Step 2: Run test to verify it fails**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && swift test --filter BreakLearningStoreTests
```
Expected: FAIL (`BreakLearningEvent` / `BreakLearningStore` not found).

**Step 3: Write minimal model + store + schema wiring**
```swift
@Model
final class BreakLearningEvent {
    var id: UUID
    var createdAt: Date
    var projectId: UUID?
    var workModeRawValue: String
    var suggestedMinutes: Int
    var choseSuggested: Bool
    var actualBreakSeconds: Int
    var returnedToFocus: Bool
    var endedEarly: Bool
    var overrunSeconds: Int
    // init(...)
}
```

```swift
@MainActor
struct BreakLearningStore {
    let modelContext: ModelContext
    func record(...) { /* insert + save */ }
    func recentEvents(projectId: UUID?, workMode: WorkMode, limit: Int) -> [BreakLearningEvent] { /* fetch */ }
}
```

Add `BreakLearningEvent.self` to the `Schema([...])` list in `FocusFlowApp.swift`.

**Step 4: Run test to verify it passes**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && swift test --filter BreakLearningStoreTests && swift build
```
Expected: PASS + build succeeds.

**Step 5: Commit**
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && git add Sources/FocusFlow/Models/BreakLearningEvent.swift Sources/FocusFlow/Services/BreakLearningStore.swift Sources/FocusFlow/FocusFlowApp.swift Tests/FocusFlowTests/BreakLearningStoreTests.swift && git commit -m "feat: persist break learning outcomes for adaptive suggestions" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Wire adaptive suggestion and break outcome lifecycle into TimerViewModel

**Files:**
- Modify: `Sources/FocusFlow/ViewModels/TimerViewModel.swift`
- Test: `Tests/FocusFlowTests/TimerCompletionFlowTests.swift`

**Step 1: Write failing lifecycle tests**
```swift
func testSuggestedEarnedBreakIsCalculatedAfterMeaningfulFocusCompletion() throws {
    // complete a ~55m focus block
    // assert vm.suggestedEarnedBreakMinutes == 15 (or adapted value)
}

func testChoosingSuggestedBreakStartsBreakWithSuggestedDuration() throws {
    // set vm.suggestedEarnedBreakMinutes = 12
    // vm.continueAfterCompletion(action: .takeBreak(duration: vm.suggestedEarnedBreakSeconds))
    // assert break session duration == 12m
}

func testBreakOutcomeRecordedWhenReturningToFocus() throws {
    // start break -> end break via continue focusing
    // assert one BreakLearningEvent with returnedToFocus == true
}
```

**Step 2: Run test to verify it fails**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && swift test --filter TimerCompletionFlowTests/testSuggestedEarnedBreakIsCalculatedAfterMeaningfulFocusCompletion
```
Expected: FAIL (new adaptive properties/events missing).

**Step 3: Implement minimal TimerViewModel wiring**
```swift
var suggestedEarnedBreakMinutes: Int = 5
var suggestedEarnedBreakSeconds: TimeInterval { TimeInterval(suggestedEarnedBreakMinutes * 60) }
private var choseSuggestedBreakForCurrentEpisode = false
private var breakLearningStore: BreakLearningStore? { modelContext.map(BreakLearningStore.init(modelContext:)) }

private func refreshEarnedBreakSuggestion() { /* use EarnedBreakSuggestionEngine + recent events */ }
private func recordBreakLearning(returnedToFocus: Bool, endedEarly: Bool) { /* insert BreakLearningEvent */ }
```

Update completion/break transitions:
- Recompute suggestion when focus completes.
- Mark whether selected break was planned vs suggested.
- Record outcome on “start focusing” and “end session” break exits.
- Keep existing `completedBlockContext` semantics intact.

**Step 4: Run tests to verify they pass**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && swift test --filter TimerCompletionFlowTests/testSuggestedEarnedBreakIsCalculatedAfterMeaningfulFocusCompletion && swift test --filter TimerCompletionFlowTests/testChoosingSuggestedBreakStartsBreakWithSuggestedDuration && swift test --filter TimerCompletionFlowTests/testBreakOutcomeRecordedWhenReturningToFocus
```
Expected: PASS.

**Step 5: Commit**
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && git add Sources/FocusFlow/ViewModels/TimerViewModel.swift Tests/FocusFlowTests/TimerCompletionFlowTests.swift && git commit -m "feat: wire adaptive break suggestion and learning into timer lifecycle" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Update Session Complete window actions (Planned 5m + Suggested earned break)

**Files:**
- Modify: `Sources/FocusFlow/Views/SessionCompleteWindow.swift`
- Modify: `Tests/FocusFlowTests/UIEvidenceCaptureTests.swift` (fixture assertions/cases as needed)

**Step 1: Write failing evidence expectation for suggested break CTA**
```swift
// In UIEvidenceCaptureTests flow coverage or render setup:
// Expect session-complete next-stage flow to include both:
// - "Planned 5m Break"
// - "Suggested Earned Break"
```

**Step 2: Run test to verify it fails**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && swift test --filter UIEvidenceCaptureTests/testCaptureReviewArtifactsForAllRequiredFlows
```
Expected: FAIL (new CTA copy/flow not represented yet).

**Step 3: Implement minimal UI updates**
Replace next-stage break actions with:
```swift
LiquidActionButton(title: "Planned 5m Break", ...) {
    saveAndDismiss(action: .takeBreak(duration: 300))
}

LiquidActionButton(
    title: "Suggested Earned Break (\(timerVM.suggestedEarnedBreakMinutes)m)",
    ...
) {
    saveAndDismiss(action: .takeBreak(duration: timerVM.suggestedEarnedBreakSeconds))
}
```

Update break-complete actions to match approved labels:
- `Start focusing`
- `End session`
- `Pause break` (wired where break is still active).

**Step 4: Run test to verify it passes**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && swift test --filter UIEvidenceCaptureTests/testCaptureReviewArtifactsForAllRequiredFlows
```
Expected: PASS.

**Step 5: Commit**
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && git add Sources/FocusFlow/Views/SessionCompleteWindow.swift Tests/FocusFlowTests/UIEvidenceCaptureTests.swift && git commit -m "feat: show planned and suggested break actions in completion flow" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: Add break-state controls in menu bar (Start focusing, End session, Pause break)

**Files:**
- Modify: `Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift`
- Modify: `Sources/FocusFlow/ViewModels/TimerViewModel.swift`
- Test: `Tests/FocusFlowTests/TimerCompletionFlowTests.swift`

**Step 1: Write failing break-control tests**
```swift
func testPauseBreakFreezesBreakCountdownUntilResume() throws {
    // start break, capture remaining
    // pause break, wait/tick, ensure remaining unchanged
    // resume break, ensure countdown continues
}

func testBreakStateStartFocusingTransitionsToFocusing() throws {
    // state .onBreak -> start focusing action
    // assert state == .focusing
}
```

**Step 2: Run test to verify it fails**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && swift test --filter TimerCompletionFlowTests/testPauseBreakFreezesBreakCountdownUntilResume
```
Expected: FAIL (`pauseBreak`/resume behavior missing).

**Step 3: Implement minimal control wiring**
Add in `TimerViewModel`:
```swift
func pauseBreak() { /* invalidate timer while onBreak; track paused state */ }
func resumeBreak() { /* restart timer for onBreak */ }
func startFocusingFromBreak() { deferBreakAndStartNextBlock() }
func endSessionFromBreak() { continueAfterCompletion(action: .endSession) }
```

Update `BreakPopoverContent` actions to:
- `Start focusing`
- `End session`
- `Pause break` / `Resume break` toggle

**Step 4: Run tests to verify they pass**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && swift test --filter TimerCompletionFlowTests/testPauseBreakFreezesBreakCountdownUntilResume && swift test --filter TimerCompletionFlowTests/testBreakStateStartFocusingTransitionsToFocusing
```
Expected: PASS.

**Step 5: Commit**
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && git add Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift Sources/FocusFlow/ViewModels/TimerViewModel.swift Tests/FocusFlowTests/TimerCompletionFlowTests.swift && git commit -m "feat: add break-state controls and pause-break behavior" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: Implement green/amber/red escalation parity for pause + break overrun ring

**Files:**
- Create: `Sources/FocusFlow/Views/Components/RingEscalationSeverity.swift`
- Modify: `Sources/FocusFlow/Views/Components/TimerRingView.swift`
- Test: `Tests/FocusFlowTests/RingEscalationSeverityTests.swift`

**Step 1: Write failing severity tests**
```swift
final class RingEscalationSeverityTests: XCTestCase {
    func testPauseSeverityTransitionsGreenAmberRed() {
        XCTAssertEqual(RingEscalationSeverity.pause(seconds: 30), .normal)
        XCTAssertEqual(RingEscalationSeverity.pause(seconds: 120), .warning)
        XCTAssertEqual(RingEscalationSeverity.pause(seconds: 301), .critical)
    }

    func testBreakOverrunSeverityTransitionsGreenAmberRed() {
        XCTAssertEqual(RingEscalationSeverity.breakOverrun(seconds: 30), .normal)
        XCTAssertEqual(RingEscalationSeverity.breakOverrun(seconds: 121), .warning)
        XCTAssertEqual(RingEscalationSeverity.breakOverrun(seconds: 301), .critical)
    }
}
```

**Step 2: Run test to verify it fails**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && swift test --filter RingEscalationSeverityTests
```
Expected: FAIL (`RingEscalationSeverity` missing).

**Step 3: Implement helper + hook into TimerRingView**
```swift
enum RingEscalationBand { case normal, warning, critical }

enum RingEscalationSeverity {
    static func pause(seconds: TimeInterval) -> RingEscalationBand { ... }
    static func breakOverrun(seconds: TimeInterval) -> RingEscalationBand { ... }
}
```

Then update `TimerRingView` color/stroke selection for pause and break overtime to map:
- `.normal` -> mint/green
- `.warning` -> amber
- `.critical` -> red/salmon

**Step 4: Run tests to verify they pass**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && swift test --filter RingEscalationSeverityTests && swift test --filter UIEvidenceCaptureTests/testCaptureReviewArtifactsForAllRequiredFlows
```
Expected: PASS.

**Step 5: Commit**
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && git add Sources/FocusFlow/Views/Components/RingEscalationSeverity.swift Sources/FocusFlow/Views/Components/TimerRingView.swift Tests/FocusFlowTests/RingEscalationSeverityTests.swift && git commit -m "fix: align pause and break overrun ring escalation tiers" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 7: Update review contracts/fixtures for new break flows and rerun Apple-grade evidence

**Files:**
- Modify: `Sources/FocusFlow/Review/ReviewArtifactContract.swift`
- Modify: `Tests/FocusFlowTests/ReviewContractsTests.swift`
- Modify: `Tests/FocusFlowTests/UIEvidenceCaptureTests.swift`
- Modify (if needed): `Sources/FocusFlow/Review/FlowFixtureSeedContract.swift`

**Step 1: Write failing contract expectations for new flows**
```swift
// In ReviewContractsTests expectedFlowIDs include:
// - menu_bar_break_paused
// - session_complete_next_stage_break_choices
// - session_complete_break_controls
```

**Step 2: Run test to verify it fails**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && swift test --filter ReviewContractsTests/testReviewArtifactContractCoversAllCriticalFlows
```
Expected: FAIL (required flow IDs mismatch).

**Step 3: Implement contract + fixture updates**
- Add required flow IDs in `ReviewArtifactContract.requiredFlowIDs`.
- Add corresponding capture cases + fixture setup in `UIEvidenceCaptureTests.captureFlow`.
- Add/update purpose mapping in `flowPurpose(for:)`.
- Keep all existing required flows intact.

**Step 4: Run tests and regenerate artifacts**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && swift test --filter ReviewContractsTests && swift test --filter UIEvidenceCaptureTests/testCaptureReviewArtifactsForAllRequiredFlows && RUNNER=swift ./Scripts/capture-ui-evidence.sh
```
Expected: PASS and new artifact bundle under `Artifacts/review/<run-id>/`.

**Step 5: Commit**
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && git add Sources/FocusFlow/Review/ReviewArtifactContract.swift Tests/FocusFlowTests/ReviewContractsTests.swift Tests/FocusFlowTests/UIEvidenceCaptureTests.swift Sources/FocusFlow/Review/FlowFixtureSeedContract.swift Artifacts/review && git commit -m "test: update review contracts and fixtures for adaptive break flows" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 8: Final verification sweep (targeted + build)

**Files:**
- No new files expected (verification only)

**Step 1: Run targeted feature test matrix**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && swift test --filter EarnedBreakSuggestionEngineTests && swift test --filter BreakLearningStoreTests && swift test --filter RingEscalationSeverityTests && swift test --filter TimerCompletionFlowTests && swift test --filter UIEvidenceCaptureTests/testCaptureReviewArtifactsForAllRequiredFlows
```
Expected: PASS.

**Step 2: Run build verification**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && swift build
```
Expected: Build succeeds.

**Step 3: Re-run Apple-grade evidence capture**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && RUNNER=swift ./Scripts/capture-ui-evidence.sh
```
Expected: Artifact manifest + journey generated in `Artifacts/review/<run-id>/`.

**Step 4: Sanity-check git status**
Run:
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && git --no-pager status --short
```
Expected: Only intended files changed.

**Step 5: Final commit (or PR-ready state)**
```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/feature/idle-first-guardian-intelligence && git add -A && git commit -m "feat: ship adaptive earned breaks and break-state awareness" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Notes for execution

- Use `RUNNER=swift` for fixture capture in this worktree (avoids Xcode workspace-path issue).
- Keep `completedBlockContext` durable behavior unchanged.
- Keep outside-session guardian logic untouched in this feature pass.
- If any broad test failures appear outside these areas, treat as baseline unless directly caused by this feature.

