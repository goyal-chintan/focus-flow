# Settings Permission Health Design

## Problem

FocusFlow now depends on multiple macOS permission surfaces for core product behavior, but the recovery paths are fragmented across Settings. Users can toggle integrations or features on, yet still have to guess which permission is blocked, which integration is healthy, and where to fix it.

The immediate product gap is that there is no single trustworthy place at the end of Settings to answer:

- what core permissions FocusFlow needs
- whether each one is currently usable
- what action the user should take next

## Approved approach

Add a **Permission & Integration Health** section as the final section in Settings.

This panel will summarize the five core permission surfaces the app depends on:

1. Notifications
2. Calendar
3. Reminders
4. Browser Automation
5. Screen Recording

Each row will contain:

- a semantic icon
- a short title
- a visible status badge (`Ready`, `Needs action`, `Not requested`, `Unavailable`)
- a one-line explanation of why the permission matters
- a primary action button for that row

Existing controls stay in their current canonical locations:

- Calendar and Reminders toggles and pickers remain in **Integrations**
- detailed domain tracking remains in **Focus Coach**

The new panel becomes the canonical **health check + recovery** surface, not a replacement for existing setup controls.

## Why this approach

- It gives users one place to diagnose what is broken.
- It avoids moving existing configuration out of its correct Settings sub-sections.
- It matches the product reality that different permissions have different recovery actions.
- It supports the Apple-grade requirement that OS integrations expose actionable recovery, not just passive warnings.

## Alternatives considered

### 1. Keep all status inside existing sections

Pros:
- less code movement
- no new summary surface

Cons:
- users still need to hunt through Settings
- weak discoverability for blocked permissions
- no single “system health” checkpoint

Decision: rejected.

### 2. Add only a compact summary with no row-level actions

Pros:
- visually lighter
- smaller implementation

Cons:
- forces another navigation hop for recovery
- weaker fit for urgent permission failures

Decision: rejected.

## Status model

The panel should use truthful states, not optimistic guesses.

### Notifications

- `Ready` when `NotificationService.authorizationState == .authorized`
- `Not requested` when `.notDetermined`
- `Needs action` when `.denied`

Primary action:

- request permission when not determined
- open Notification settings when denied

### Calendar

- `Ready` when `CalendarService.shared.authStatus == .authorized`
- `Not requested` when `.notDetermined`
- `Needs action` when `.denied`

Primary action:

- request access when not determined
- open Calendars privacy settings when denied
- when already ready, offer a contextual button that scrolls to the integration controls

### Reminders

- `Ready` when `RemindersService.shared.authStatus == .authorized`
- `Not requested` when `.notDetermined`
- `Needs action` when `.denied`

Primary action:

- request access when not determined
- open Reminders privacy settings when denied
- when already ready, offer a contextual button that scrolls to the integration controls

### Browser Automation

This is the nuanced case. The app needs browser-specific Apple Events approval, not just a generic app-wide toggle.

The panel should evaluate installed supported browsers individually and derive a truthful aggregate state:

- `Ready` when all installed supported browsers are approved
- `Needs action` when one or more installed supported browsers are blocked
- `Unavailable` when no supported browsers are installed

The row should also show lightweight detail for installed browsers, calling out which are ready vs blocked.

Primary action:

- open the Automation privacy pane

### Screen Recording

- `Ready` when `CGPreflightScreenCaptureAccess()` is true
- `Needs action` otherwise

Primary action:

- open the Screen Recording privacy pane

## Implementation shape

Introduce a dedicated permission-health builder/service so SettingsView does not accumulate more permission branching inline.

Recommended structure:

- a small service or helper that builds row models for the five core permissions
- row models with title, icon, status, explanation, action label, action kind, and optional detail lines
- SettingsView renders the models with one shared row component

## UI behavior

- Place the section at the end of Settings, matching the user request.
- Use the existing glass panel + section header system.
- Keep rows non-glass inside the panel to avoid glass-on-glass noise.
- Make the full primary action a >=44pt capsule button.
- Use icon + label + badge, not color alone, for status communication.
- Keep status language terse and actionable.

## Error and recovery behavior

- The panel must refresh on appear.
- The panel must refresh after permission request flows complete.
- Calendar/Reminders/Notifications should restore the companion window after request flows, matching existing integration behavior.
- Automation and Screen Recording actions open System Settings and leave the app ready for a manual re-check on return.

## Testing strategy

Use TDD.

1. Add failing source-contract tests for:
   - new Settings section placement at the end
   - five required rows
   - accessible row CTAs
   - Automation row copy and per-browser detail support
2. Add focused unit tests for the permission-health builder:
   - each permission state mapping
   - Automation aggregate mapping across installed browsers
   - unsupported/no-browser case
3. Run targeted Settings/contract tests first, then full build/test/evidence validation.

## Out of scope

- moving existing Calendar/Reminders/domain toggles
- destructive cleanup of malformed stored domain history
- changing analytics logic beyond truthful permission reporting
