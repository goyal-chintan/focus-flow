# Energy Hot Paths Design

## Goal

Reduce FocusFlow's background energy usage without changing user-facing timer, coaching, or usage-tracking behavior.

## Confirmed Root Cause

Repository review and installed-app verification showed that the current shipping build already includes the recent persistence batching work from `092b291`, but the largest energy hot paths remain in foreground tracking:

1. `AppUsageTracker` runs a 1 Hz timer for the full app lifetime, even while idle.
2. Browser context refresh performs expensive cross-process work more often than necessary.
3. Timer callbacks create `Task { @MainActor in ... }` hops even though they already originate on the main run loop.

These costs are additive because the app also runs the focus countdown and pause timers on the main run loop.

## Constraints

- Preserve current tracking fidelity during active focus sessions.
- Keep browser/domain attribution behavior intact when domain capture is enabled.
- Avoid broad architectural changes such as fully event-driven tracking for this PR.
- Keep the fix minimal and safe enough for a targeted performance patch.

## Proposed Solution

### 1. Adaptive tracker cadence

Teach `AppUsageTracker` to use different polling intervals depending on app state:

- `1s` while the user is actively focusing.
- A slower cadence while idle or outside an active focus session.

This preserves current session precision while reducing unnecessary wakeups during background monitoring.

### 2. Reduce browser refresh pressure

Keep cached browser context longer and refresh it only when materially necessary instead of re-evaluating it at the current hot-path cadence.

The targeted PR will preserve existing domain classification behavior while reducing how often the expensive browser context path is exercised.

### 3. Remove unnecessary main-actor task hopping

Where timers already fire on `RunLoop.main`, invoke the timer tick methods directly instead of wrapping each callback in a new `Task`.

This removes steady-state task allocation overhead without changing behavior.

## Files In Scope

- `Sources/FocusFlow/Services/AppUsageTracker.swift`
- `Sources/FocusFlow/ViewModels/TimerViewModel.swift`
- `Tests/FocusFlowTests/AppUsageTrackerTests.swift`

## Verification Plan

- Add regression tests for adaptive tracker cadence and browser refresh gating.
- Run focused tests for `AppUsageTracker` where possible.
- Run available repo verification and document the pre-existing baseline SwiftData macro/plugin failure that blocks a full green build from this CLI environment.

## Non-Goals

- Replacing polling with full notification-driven tracking.
- Redesigning coaching logic.
- Changing user-visible timer behavior or tracked data semantics.
