# Calendar + Reminders Instability Audit (2026-03-21)

## Context
Branch: `fix/apple-grade-ui-audit-fixes`
Base signal: app repeatedly crashes/behaves unstably around Calendar + Reminders integrations.

## What I found
1. EventKit operations were overlapping on one shared `EKEventStore` (fetch + save + request access + list loads), which is a known instability vector.
2. Reminder mutation/list APIs were sync at several call sites, creating race-prone UI interactions under stress.
3. Calendar tab triggered excessive reminder reloads (date changes + multiple change hooks + EventKit change bursts), causing task storms.
4. Permission flow had inconsistent post-grant behavior: app could still show denied state despite access being allowed at OS level.
5. Companion window could disappear during permission flow.
6. Calendar day summary had unsafe numeric conversion path (`Int(Double)`) vulnerable to NaN/Infinity from bad session duration data.

## What I changed (implemented)
1. Added global EventKit exclusivity gate in `EventStoreManager`.
2. Moved Reminders operations (`requestAccess`, fetch, complete, update, create, lists) to async + serialized access.
3. Moved Calendar operations (`requestAccess`, available calendars, create/update event) to async + serialized access.
4. Migrated all impacted UI/view-model call sites to async/await:
   - `SettingsView`
   - `CalendarTabView`
   - `TodayStatsView`
   - `TimerViewModel`
   - `SessionCompleteWindow`
5. Reduced reload storms in Calendar tab:
   - removed unnecessary reminder reload hooks
   - coalesced noisy `EKEventStoreChanged` reload bursts
6. Removed forced app re-activation after permission dialogs (to avoid hide/reappear flicker).
7. Added companion window continuity fallback (reopen `stats` if it disappears unexpectedly after permission flow).
8. Hardened calendar focus-time math and formatting against non-finite values.
9. Changed integration toggles to trust post-request authorization state (`authStatus`) as source of truth.
10. Treated reminders `.writeOnly` as authorized for consistency.

## Verification performed
- Build: `swift build` (pass)
- Tests: `swift test` (pass)
- Runtime launch path verified: `.build/arm64-apple-macosx/debug/FocusFlow.app/Contents/MacOS/FocusFlow`
- Live logging enabled during reproduction attempts (`log stream` + app stdout capture)

## What is still not working (per latest user repro)
1. Both primary bugs still reproducible:
   - integration flow still unstable
   - calendar interaction still fails in user run
2. New regression observed by user:
   - companion window closes right after granting access
3. Intermittent mismatch remains between OS-granted permission and in-app integration state.

## Why unresolved
- The remaining failure appears runtime-sequence-specific and not fully reproduced in the attached terminal session.
- No deterministic macOS crash report was produced in `~/Library/Logs/DiagnosticReports` during observed runs.
- Final failure likely depends on UI lifecycle timing around permission dialogs / window scene restoration.

## Suggested next debug step
Instrument app lifecycle and window scene events around permission requests (active/inactive/scene phase/window visibility transitions) and capture exact timestamped logs from a failing run to isolate the closing-window trigger path.
