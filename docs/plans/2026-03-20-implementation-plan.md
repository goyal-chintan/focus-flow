# FocusFlow Analytics & Features Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add 6 features — rich weekly analytics, insights tab, calendar integration, reminders integration, enhanced blocking, and anti-procrastination tracking.

**Architecture:** Extend existing SwiftData models, add 3 new services (CalendarService, RemindersService, AppUsageTracker), add 1 new companion tab (Insights), enhance Weekly view. All data-driven from existing FocusSession records.

**Tech Stack:** SwiftUI, SwiftData, EventKit (Calendar + Reminders), AppKit (NSWorkspace for app tracking)

---

## Phase 1: Data Layer Foundation

### Task 1: Extend AppSettings

**Files:**
- Modify: `Sources/FocusFlow/Models/AppSettings.swift`

**Step 1: Add new properties to AppSettings**

```swift
@Model
final class AppSettings {
    var focusDuration: TimeInterval
    var shortBreakDuration: TimeInterval
    var longBreakDuration: TimeInterval
    var sessionsBeforeLongBreak: Int
    var autoStartBreak: Bool
    var autoStartNextSession: Bool
    var launchAtLogin: Bool
    var completionSound: String
    // New settings
    var dailyFocusGoal: TimeInterval
    var calendarIntegrationEnabled: Bool
    var calendarName: String
    var antiProcrastinationEnabled: Bool
    var antiProcrastinationThresholdMinutes: Int

    init() {
        self.focusDuration = 25 * 60
        self.shortBreakDuration = 5 * 60
        self.longBreakDuration = 15 * 60
        self.sessionsBeforeLongBreak = 4
        self.autoStartBreak = true
        self.autoStartNextSession = false
        self.launchAtLogin = false
        self.completionSound = "Glass"
        self.dailyFocusGoal = 7200  // 120 min default
        self.calendarIntegrationEnabled = false
        self.calendarName = "FocusFlow"
        self.antiProcrastinationEnabled = true
        self.antiProcrastinationThresholdMinutes = 5
    }
}
```

**Step 2: Add calendarEventId to FocusSession**

File: `Sources/FocusFlow/Models/FocusSession.swift`

Add property: `var calendarEventId: String?`
Add to init: `self.calendarEventId = nil`

**Step 3: Create AppUsageRecord model**

File: `Sources/FocusFlow/Models/AppUsageRecord.swift`

```swift
import Foundation
import SwiftData

@Model
final class AppUsageRecord {
    var date: Date
    var focusFlowOpenSeconds: Int
    var totalFocusSeconds: Int

    init(date: Date = Calendar.current.startOfDay(for: Date())) {
        self.date = date
        self.focusFlowOpenSeconds = 0
        self.totalFocusSeconds = 0
    }

    var efficiencyRatio: Double {
        guard focusFlowOpenSeconds > 0 else { return 0 }
        return Double(totalFocusSeconds) / Double(focusFlowOpenSeconds)
    }
}
```

**Step 4: Update schema in FocusFlowApp.swift**

File: `Sources/FocusFlow/FocusFlowApp.swift`

Change schema line to include `AppUsageRecord`:
```swift
let schema = Schema([Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self])
```

**Step 5: Build and commit**

```bash
swift build
git add -A && git commit -m "feat: extend data models for analytics and integrations"
```

---

## Phase 2: Settings UI

### Task 2: Add new settings to SettingsView

**Files:**
- Modify: `Sources/FocusFlow/Views/Companion/SettingsView.swift`

**Step 1: Add daily goal, calendar, and anti-procrastination settings sections**

After the existing "Sound" section, add:

```swift
// MARK: - Goals
LiquidGlassPanel {
    VStack(alignment: .leading, spacing: 12) {
        LiquidSectionHeader("Goals")
        settingRow(title: "Daily Focus Goal", value: "\(Int(settings.dailyFocusGoal / 60)) min") {
            Slider(value: Binding(
                get: { settings.dailyFocusGoal / 60 },
                set: { settings.dailyFocusGoal = $0 * 60; save() }
            ), in: 30...480, step: 15)
            .tint(LiquidDesignTokens.Spectral.primaryContainer)
        }
    }
    .padding(16)
}

// MARK: - Integrations
LiquidGlassPanel {
    VStack(alignment: .leading, spacing: 12) {
        LiquidSectionHeader("Integrations")
        Toggle("Record sessions to Calendar", isOn: Binding(
            get: { settings.calendarIntegrationEnabled },
            set: { settings.calendarIntegrationEnabled = $0; save() }
        ))
    }
    .padding(16)
}

// MARK: - Focus Coach
LiquidGlassPanel {
    VStack(alignment: .leading, spacing: 12) {
        LiquidSectionHeader("Focus Coach")
        Toggle("Anti-procrastination nudges", isOn: Binding(
            get: { settings.antiProcrastinationEnabled },
            set: { settings.antiProcrastinationEnabled = $0; save() }
        ))
    }
    .padding(16)
}
```

**Step 2: Build and commit**

```bash
swift build
git add -A && git commit -m "feat: add goal, calendar, and focus coach settings"
```

---

## Phase 3: Weekly View Enhancement

### Task 3: Add heatmap and enhanced day detail

**Files:**
- Create: `Sources/FocusFlow/Views/Components/HeatmapView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/WeeklyStatsView.swift`

**Step 1: Create HeatmapView component**

```swift
import SwiftUI

struct HeatmapView: View {
    let data: [(label: String, value: Double)]
    let maxValue: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(data.indices, id: \.self) { index in
                let intensity = maxValue > 0 ? data[index].value / maxValue : 0
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(heatColor(intensity: intensity))
                    .frame(height: 18)
                    .overlay {
                        if data.count <= 7 {
                            Text(data[index].label)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(intensity > 0.3 ? 0.8 : 0.3))
                        }
                    }
            }
        }
    }

    private func heatColor(intensity: Double) -> Color {
        if intensity <= 0 { return Color.white.opacity(0.04) }
        if intensity < 0.25 { return Color(hex: 0x3DA86A).opacity(0.25) }
        if intensity < 0.50 { return Color(hex: 0x3DA86A).opacity(0.45) }
        if intensity < 0.75 { return Color(hex: 0x3DA86A).opacity(0.65) }
        return Color(hex: 0x3DA86A).opacity(0.85)
    }
}
```

**Step 2: Add heatmap to WeeklyStatsView**

In WeeklyStatsView, add between chartSection and summarySection:

```swift
private var heatmapSection: some View {
    LiquidGlassPanel {
        VStack(alignment: .leading, spacing: 10) {
            LiquidSectionHeader(
                "Focus Intensity",
                subtitle: "Darker = more focus time"
            )
            HeatmapView(
                data: chartData,
                maxValue: chartData.map(\.value).max() ?? 1
            )
        }
        .padding(16)
    }
}
```

**Step 3: Add session timeline to day detail**

Add a timeline section inside the dayDetailCard that shows sessions for the selected day.

**Step 4: Add "Peak Hour" and "Completion Rate" stat cards**

```swift
private var peakHour: String {
    let calendar = Calendar.current
    let focusSessions = allSessions.filter { $0.type == .focus }
    var hourCounts = [Int: TimeInterval]()
    for session in focusSessions {
        let hour = calendar.component(.hour, from: session.startedAt)
        hourCounts[hour, default: 0] += session.actualDuration
    }
    guard let bestHour = hourCounts.max(by: { $0.value < $1.value })?.key else { return "—" }
    let formatter = DateFormatter()
    formatter.dateFormat = "ha"
    let date = calendar.date(from: DateComponents(hour: bestHour))!
    return formatter.string(from: date).lowercased()
}

private var completionRate: String {
    let focusSessions = allSessions.filter { $0.type == .focus }
    let total = focusSessions.count
    guard total > 0 else { return "—" }
    let completed = focusSessions.filter(\.completed).count
    return "\(Int(Double(completed) / Double(total) * 100))%"
}
```

**Step 5: Build and commit**

```bash
swift build
git add -A && git commit -m "feat: weekly view heatmap, peak hour, completion rate"
```

---

## Phase 4: Insights Tab

### Task 4: Create Insights Tab

**Files:**
- Create: `Sources/FocusFlow/Views/Companion/InsightsView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/CompanionWindowView.swift`

**Step 1: Add insights case to CompanionTab**

```swift
enum CompanionTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case weekly = "Week"
    case insights = "Insights"  // NEW
    case projects = "Projects"
    case settings = "Settings"
    // ... add icon, subtitle, tint for insights
}
```

Insights tab:
- icon: "brain.head.profile"
- subtitle: "Patterns and tips"
- tint: .indigo

**Step 2: Create InsightsView**

Core sections:
1. **Productive Hours** — horizontal bar chart showing focus time per hour (0-23)
2. **Session Duration Distribution** — histogram of session lengths
3. **Break Behavior** — avg break vs planned, streak of on-time breaks
4. **30-Day Trend** — simple sparkline
5. **Science Tips** — contextual cards based on data analysis
6. **Focus Efficiency** — ratio card (focus time / app open time)

Each section is a `LiquidGlassPanel` with `LiquidSectionHeader`.

**Step 3: Wire into CompanionWindowView**

```swift
case .insights:
    InsightsView()
```

**Step 4: Build and commit**

```bash
swift build
git add -A && git commit -m "feat: insights tab with productive hours, patterns, tips"
```

---

## Phase 5: Calendar Integration

### Task 5: CalendarService

**Files:**
- Create: `Sources/FocusFlow/Services/CalendarService.swift`
- Modify: `Sources/FocusFlow/ViewModels/TimerViewModel.swift` (call on session save)
- Modify: `Sources/FocusFlow/Info.plist` (add NSCalendarsUsageDescription)

**Step 1: Create CalendarService**

```swift
import EventKit

@MainActor
final class CalendarService {
    static let shared = CalendarService()
    private let store = EKEventStore()
    private init() {}

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch { return false }
    }

    func createEvent(for session: FocusSession, calendarName: String) -> String? {
        // Find or create FocusFlow calendar
        // Create EKEvent with session data
        // Return event.eventIdentifier
    }
}
```

**Step 2: Call from saveReflection in TimerViewModel**

After saving reflection, if calendarIntegrationEnabled, call CalendarService.

**Step 3: Add Info.plist calendar usage description**

**Step 4: Build and commit**

```bash
swift build
git add -A && git commit -m "feat: calendar integration — auto-create events for sessions"
```

---

## Phase 6: Reminders Integration

### Task 6: RemindersService

**Files:**
- Create: `Sources/FocusFlow/Services/RemindersService.swift`
- Modify: `Sources/FocusFlow/Views/SessionCompleteWindow.swift` (add reminders linking)
- Modify: `Sources/FocusFlow/Info.plist` (add NSRemindersUsageDescription)

**Step 1: Create RemindersService**

```swift
import EventKit

@MainActor
final class RemindersService {
    static let shared = RemindersService()
    private let store = EKEventStore()
    private init() {}

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch { return false }
    }

    func fetchIncompleteReminders() async -> [EKReminder] { ... }
    func completeReminder(_ reminder: EKReminder) { ... }
}
```

**Step 2: Add reminder linking UI to SessionCompleteWindowView**

Show incomplete reminders as checkable list in session completion flow.

**Step 3: Build and commit**

```bash
swift build
git add -A && git commit -m "feat: reminders integration — link and complete tasks from sessions"
```

---

## Phase 7: Anti-Procrastination

### Task 7: AppUsageTracker

**Files:**
- Create: `Sources/FocusFlow/Services/AppUsageTracker.swift`
- Modify: `Sources/FocusFlow/FocusFlowApp.swift` (start tracker)

**Step 1: Create AppUsageTracker**

Tracks time FocusFlow is frontmost app. Compares to active session time. Sends nudge notification via NotificationService after threshold.

**Step 2: Record usage in AppUsageRecord model**

**Step 3: Wire into FocusFlowApp startup**

**Step 4: Build and commit**

```bash
swift build
git add -A && git commit -m "feat: anti-procrastination tracking and nudge notifications"
```

---

## Phase 8: Enhanced Blocking

### Task 8: Block Until Daily Goal

**Files:**
- Modify: `Sources/FocusFlow/Services/BlockingService.swift`
- Modify: `Sources/FocusFlow/Views/Companion/BlockingSettingsView.swift`

**Step 1: Add daily-goal-based blocking mode**

**Step 2: Build and commit**

```bash
swift build
git add -A && git commit -m "feat: enhanced blocking — block until daily focus goal met"
```
