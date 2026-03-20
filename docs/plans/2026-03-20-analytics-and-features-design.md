# FocusFlow Analytics, Integrations & Anti-Procrastination Design

**Date:** 2026-03-20
**Branch:** `feature/analytics-and-insights`

## Overview

Six features expanding FocusFlow from a timer into an intelligent productivity companion:

1. **Rich Weekly View** — interactive day drill-down, heatmap, enhanced stats
2. **Insights Tab** — productive hours, focus patterns, science-based tips
3. **Calendar Integration** — auto-create Apple Calendar events for completed sessions
4. **Reminders Integration** — read/write Apple Reminders, link tasks to sessions
5. **Enhanced App Blocking** — block until daily focus target met
6. **Anti-Procrastination** — app usage tracking, gentle nudges when dwelling in FocusFlow

## Data Model Changes

### AppSettings (extend existing)
```swift
var dailyFocusGoal: TimeInterval = 7200       // 120 min default, user-configurable
var calendarIntegrationEnabled: Bool = false
var calendarName: String = "FocusFlow"         // calendar to write events to
var antiProcrastinationEnabled: Bool = true
var antiProcrastinationThresholdMinutes: Int = 5
```

### FocusSession (extend existing)
```swift
var calendarEventId: String?                   // EventKit event identifier
```

### New: AppUsageRecord
```swift
@Model class AppUsageRecord {
    var date: Date              // day this record belongs to
    var focusFlowOpenSeconds: Int  // time app was open/foreground
    var totalFocusSeconds: Int     // time actually in focus sessions
}
```

## Feature Designs

### 1. Weekly View Overhaul

**Current:** Bar chart + 3 summary cards.

**New layout:**
- Period toggle (7/30 days) — kept
- Enhanced bar chart with day-tap selection
- **Day Detail Panel** (on selection): session timeline, projects, mood, achievements
- **Heatmap row** — colored intensity squares (GitHub-style)
- Enhanced summary cards: + "Peak Hour", "Top Project", "Completion Rate"

### 2. Insights Tab (new 5th tab)

Added to CompanionWindowView sidebar.

**Sections:**
1. **Productive Hours** — radial/bar chart, sessions bucketed by hour-of-day
2. **Focus Duration Distribution** — histogram, highlight "sweet spot"
3. **Break Behavior** — avg break duration vs planned, overtime %
4. **30-Day Trend** — line chart with trend line
5. **Science-Based Tips** — 3-5 contextual tips derived from user data patterns
6. **Focus Efficiency** — ratio of focus time to total FocusFlow open time

**Computation:** All analytics computed from FocusSession query over configurable period. No external dependencies.

### 3. Calendar Integration (EventKit)

**Service:** `CalendarService` singleton.
- On session complete (in `saveReflection`): create EKEvent with title, duration, project, achievements
- Store `event.eventIdentifier` in `FocusSession.calendarEventId`
- Request calendar access via `EKEventStore.requestFullAccessToEvents()`
- Create/reuse a "FocusFlow" calendar (colored blue)
- Settings toggle to enable/disable

### 4. Reminders Integration (EventKit)

**Service:** `RemindersService` singleton.
- Read incomplete reminders from user's default list
- Display in session complete window: "Link completed tasks"
- On link: mark reminder as completed via `EKReminder.isCompleted = true`
- Show linked reminders in session timeline
- Request access via `EKEventStore.requestFullAccessToReminders()`

### 5. Enhanced App Blocking

**Extend BlockingService:**
- New mode: "Block until daily goal met"
- Check `todayFocusTime >= dailyFocusGoal` before allowing deactivation
- Show progress toward goal in blocking status

### 6. Anti-Procrastination

**AppUsageTracker service:**
- Track time FocusFlow is in foreground (NSWorkspace.shared.frontmostApplication)
- Compare to active focus session time
- After threshold (default 5 min) of foreground without session: send nudge notification
- Record daily usage in AppUsageRecord for Insights display

## Implementation Priority

1. Data model changes + Settings UI (foundation)
2. Insights Tab + Weekly View overhaul (highest user value)
3. Calendar integration (EventKit)
4. Reminders integration (EventKit)
5. Enhanced blocking
6. Anti-procrastination tracking

## Quality Gates

Each feature must pass:
1. `swift build` clean (zero errors)
2. Stable commit on feature branch
3. UI matches Liquid Glass design system
4. Data persists correctly across app restart
5. Accessibility labels on all interactive elements
