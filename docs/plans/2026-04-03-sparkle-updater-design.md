# Sparkle Updater Design

## Problem

FocusFlow currently ships through GitHub Releases and DMG/Homebrew install flows, but the app itself has no way to discover or apply updates. The goal is to let users update FocusFlow from inside the app without sending them to a browser or asking them to manually drag a new app bundle into place.

## Approved approach

Use Sparkle as the app's updater framework.

1. Add Sparkle to the app target and initialize it from the main app lifecycle.
2. Enable automatic background update checks.
3. Add a manual **Check for Updates...** action to the existing **Settings > About** section.
4. Update the release pipeline so published artifacts are compatible with Sparkle, including signed update metadata and a feed the app can consume.

## Why this fits the requirement

- It provides real in-app update discovery and installation instead of a browser handoff.
- It keeps update controls in the canonical configuration surface: **Settings > About**, reached from the menu bar gear button.
- It avoids building and maintaining a custom updater with fragile download, replacement, relaunch, and rollback behavior.

## Product integration

### Entry and discoverability

- **Primary discovery:** automatic background checks after launch
- **Explicit re-entry:** menu bar gear -> companion window Settings -> About -> **Check for Updates...**
- **No direct popover action:** the popover stays focused on active-session controls, matching FocusFlow's surface hierarchy rules

### Journey blueprint

1. User launches FocusFlow.
2. Sparkle checks for updates in the background.
3. If an update is available, Sparkle presents its updater flow.
4. User can also open Settings > About and manually trigger **Check for Updates...**
5. FocusFlow downloads and applies the update through Sparkle, then relaunches into the updated app.

### Failure and recovery

- If the feed is unavailable or invalid, the About section must still expose a manual retry path.
- If automatic checks are unable to run because release metadata is incomplete, the app must surface a meaningful updater state instead of failing silently.
- Release tooling must fail loudly when required Sparkle artifacts are missing.

## Architecture

### App-side changes

- Add a small updater integration layer that owns Sparkle setup and exposes:
  - current app version
  - update-check status
  - manual check trigger
- Inject that updater state into the Settings experience without turning the updater into a TimerViewModel concern.
- Keep the About UI thin: it should render updater state and invoke the manual check action, not implement release logic itself.

### Release-side changes

- Package Sparkle-compatible release artifacts in the DMG/build scripts.
- Publish a Sparkle feed alongside releases.
- Ensure signing and update metadata are stable enough for Sparkle to trust and apply updates.

## Alternatives considered

### 1. Open the GitHub Releases page from Settings

Pros:
- Minimal implementation effort

Cons:
- Fails the requirement for true in-app update
- Keeps installation manual

Decision: rejected because the user explicitly wants update application from inside the app.

### 2. Add a direct update action in the menu bar popover

Pros:
- Faster access

Cons:
- Breaks FocusFlow's surface placement rules
- Adds configuration behavior to a transient active-session surface

Decision: rejected in favor of Settings > About.

### 3. Build a custom updater

Pros:
- No external dependency

Cons:
- Higher implementation risk
- More release-pipeline complexity owned entirely by FocusFlow
- More likely to regress install and relaunch behavior

Decision: rejected in favor of Sparkle.

## Implementation boundaries

In scope:
- Sparkle dependency and app integration
- Settings > About update UI
- automatic and manual update checks
- release pipeline changes required for Sparkle
- documentation updates for the new update flow

Out of scope:
- App Store distribution
- a direct update control in the menu bar popover
- fixing unrelated baseline warnings
- fixing the pre-existing `TimerCompletionFlowTests` failures discovered on the clean feature branch

## Baseline notes

- Clean worktree branch: `feature/sparkle-updater`
- Baseline `swift build`: passes
- Baseline `swift test`: fails in `TimerCompletionFlowTests.testIdleEscalationFiringOutsideWorkHoursWhenNotificationWasIgnored` before updater changes
