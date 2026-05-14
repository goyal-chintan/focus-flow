# Energy Hot Paths Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce FocusFlow's background energy use by cutting the browser-tracking hot path and backing off the always-on app-usage polling loop outside active focus sessions.

**Architecture:** Keep the existing polling-based tracking design, but make it adaptive. `AppUsageTracker` will own cadence selection and browser-context refresh gating, while `TimerViewModel` will drop unnecessary main-actor task hops from timers that already fire on the main run loop.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, XCTest

---

### Task 1: Add failing tracker hot-path tests

**Files:**
- Modify: `Tests/FocusFlowTests/AppUsageTrackerTests.swift`

**Step 1: Write the failing test**

Add focused tests for:
- adaptive tracker interval selection during focus vs idle
- browser refresh gating so browser context does not refresh on every idle/background polling tick

**Step 2: Run test to verify it fails**

Run: `swift test --filter AppUsageTrackerTests`
Expected: tests fail because the helper APIs and cadence logic do not exist yet, or the suite is blocked by the current baseline SwiftData macro/plugin issue.

**Step 3: Write minimal implementation**

Add the smallest test-only accessors needed to verify cadence and browser refresh decisions without introducing production-only test hooks beyond narrow internal helpers.

**Step 4: Run test to verify it passes**

Run: `swift test --filter AppUsageTrackerTests`
Expected: new tests pass if the environment allows the suite to run; otherwise capture the same baseline blocker with the new test code present.

**Step 5: Commit**

```bash
git add Tests/FocusFlowTests/AppUsageTrackerTests.swift
git commit -m "test: cover app usage energy hot paths"
```

### Task 2: Implement adaptive tracking cadence

**Files:**
- Modify: `Sources/FocusFlow/Services/AppUsageTracker.swift`
- Test: `Tests/FocusFlowTests/AppUsageTrackerTests.swift`

**Step 1: Write the failing test**

If Task 1 did not already isolate cadence behavior cleanly, add a smaller failing test for the exact interval chosen while focusing vs idle.

**Step 2: Run test to verify it fails**

Run: `swift test --filter AppUsageTrackerTests/test...`
Expected: failure shows the tracker still uses one fixed interval.

**Step 3: Write minimal implementation**

Implement:
- a cadence selector in `AppUsageTracker`
- timer rescheduling only when cadence class changes
- preservation of 1-second precision while actively focusing

**Step 4: Run test to verify it passes**

Run: `swift test --filter AppUsageTrackerTests`
Expected: cadence tests pass or the known baseline blocker remains unchanged.

**Step 5: Commit**

```bash
git add Sources/FocusFlow/Services/AppUsageTracker.swift Tests/FocusFlowTests/AppUsageTrackerTests.swift
git commit -m "perf: back off idle app usage polling"
```

### Task 3: Tighten browser context refresh gating

**Files:**
- Modify: `Sources/FocusFlow/Services/AppUsageTracker.swift`
- Test: `Tests/FocusFlowTests/AppUsageTrackerTests.swift`

**Step 1: Write the failing test**

Add a failing test proving browser context refresh is skipped when the tracker is in a low-frequency idle mode and nothing material changed.

**Step 2: Run test to verify it fails**

Run: `swift test --filter AppUsageTrackerTests`
Expected: failure shows current refresh logic remains too eager.

**Step 3: Write minimal implementation**

Implement browser-refresh gating that:
- preserves refresh on app switch
- preserves refresh during active focus precision mode
- reduces refreshes while idle/background tracking is backed off

**Step 4: Run test to verify it passes**

Run: `swift test --filter AppUsageTrackerTests`
Expected: new gating tests pass or the baseline blocker remains unchanged.

**Step 5: Commit**

```bash
git add Sources/FocusFlow/Services/AppUsageTracker.swift Tests/FocusFlowTests/AppUsageTrackerTests.swift
git commit -m "perf: reduce browser tracking refresh pressure"
```

### Task 4: Remove unnecessary timer task hops

**Files:**
- Modify: `Sources/FocusFlow/Services/AppUsageTracker.swift`
- Modify: `Sources/FocusFlow/ViewModels/TimerViewModel.swift`

**Step 1: Write the failing test**

No new dedicated test is required if existing behavior tests already cover the timer state logic. Document why this is a behavior-preserving internal change.

**Step 2: Run targeted test coverage before change**

Run: `swift test --filter AppUsageTrackerTests`
Expected: same result as previous steps.

**Step 3: Write minimal implementation**

Replace `Task { @MainActor in ... }` wrappers inside main-runloop timer callbacks with direct method calls.

**Step 4: Run verification after change**

Run: `swift test --filter AppUsageTrackerTests`
Expected: no new failures beyond the baseline blocker.

**Step 5: Commit**

```bash
git add Sources/FocusFlow/Services/AppUsageTracker.swift Sources/FocusFlow/ViewModels/TimerViewModel.swift
git commit -m "perf: remove redundant timer task hops"
```

### Task 5: Verify, document, and ship

**Files:**
- Modify: `docs/plans/2026-05-15-energy-hotpaths-design.md`
- Modify: `docs/plans/2026-05-15-energy-hotpaths-implementation-plan.md`
- Create or update: GitHub issue
- Create: PR description

**Step 1: Run verification**

Run:
- `swift test --filter AppUsageTrackerTests`
- `swift build`
- `bash Scripts/run.sh`

Expected: capture pass/fail evidence, including the known baseline SwiftData macro/plugin blocker if still present in this environment.

**Step 2: Open issue**

Document root cause, file references, and why recent persistence batching was insufficient.

**Step 3: Create final commit**

```bash
git add Sources/FocusFlow/Services/AppUsageTracker.swift Sources/FocusFlow/ViewModels/TimerViewModel.swift Tests/FocusFlowTests/AppUsageTrackerTests.swift docs/plans/2026-05-15-energy-hotpaths-design.md docs/plans/2026-05-15-energy-hotpaths-implementation-plan.md
git commit -m "perf: reduce app usage tracking energy hot paths"
```

**Step 4: Create PR**

Create a PR that includes:
- root cause summary
- targeted fix description
- verification evidence
- explicit note about the unrelated baseline build/test blocker seen in this CLI environment
