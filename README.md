# FocusFlow

A native macOS Pomodoro focus timer built with SwiftUI and Apple's Liquid Glass design language.

![FocusFlow Logo](Brand/LogoConcepts/focusflow-logo-final.svg)

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### Menu Bar Timer
- Lives in the menu bar — always visible, never in the way
- Shows live countdown during focus + total daily focus time
- Animated timer ring with smooth progress
- Preset durations (15 / 25 / 45 / 60 min) or custom minute input
- Minimum 5-minute sessions enforced
- Session cycle tracking with automatic short and long breaks
- Pause indicator with elapsed time in menu bar

### Focus Sessions
- **Start / Pause / Resume / Stop** with Liquid Glass controls
- **Pause counter** with color-coded warnings — orange at 2 min, red at 5 min, with notification sounds
- **Abandon session** — stop and choose to save as incomplete or discard entirely
- **Session completion flow** — when a timer finishes:
  - Rate your focus (Distracted / Neutral / Focused / Deep Focus)
  - Record what you achieved
  - Split time across multiple projects (e.g., 15 min coding + 10 min review)
  - Choose: Take a Break, Continue Focusing, or End Session

### Smart Project Management
- Inline search-and-create — type to find existing projects or create new ones on the fly
- Projects with custom colors (10 options) and SF Symbol icons (16 options)
- Archive projects (soft delete, data preserved)
- No confusing split between "labels" and "projects" — unified system

### Stats & Analytics
- **Today tab** — focus time, session count, streak, per-project time bars, session timeline with mood icons, reflections summary (mood distribution + achievements)
- **Week tab** — bar chart with 7-day / 30-day toggle, daily average, best day, total
- **Edit past sessions** — click any session in the timeline to change project, mood, or achievement
- **Cross-midnight handling** — sessions spanning midnight are correctly attributed to each day
- **Time splits in stats** — split sessions show per-project breakdown accurately

### Settings
- Customize focus / short break / long break durations
- Sessions before long break (2–8)
- Auto-start breaks and next session toggles
- Completion sound picker (13 macOS system sounds with preview)
- Launch at login (SMAppService)

### Day Boundary Handling
- Automatic stats refresh at midnight
- Cross-midnight sessions split attribution between days
- Session counter resets at day change

### Notifications
- Focus session complete — sound + macOS notification
- Break complete — sound + notification
- Pause too long — warning at 2 min, critical at 5 min

### Personal Focus Coach (On-Device AI)
- **Real-time risk scoring** — detects drift, app switching, and procrastination patterns every 30 seconds
- **Adaptive intervention policy** — 3-level escalation (soft nudge → quick prompt → strong prompt) with budget, cooldown, and snooze safeguards
- **Pre-session intention card** — set task type, expected resistance, and success criteria (MCII-based)
- **Live coach strip** — green/amber/red risk status bar during active sessions
- **Anomaly reason chips** — 1-tap reason capture (meeting, fatigue, stress, avoidance) for false-positive control
- **Personalized weekly insights** — completion rate, recovery rate, top distractions, science-backed coaching tips
- **Privacy-first** — all data stays on-device, no cloud dependency
- **Science-informed** — based on Steel 2007 (procrastination), Rozental 2018 (CBT), Albulescu 2022 (micro-breaks)

### Built with Apple's Liquid Glass
- Native `.glassEffect()` materials with refraction and specular highlights
- `.buttonStyle(.glass)` and `.glassProminent` controls
- `GlassEffectContainer` for grouped glass elements
- Designed exclusively for macOS 26 (Tahoe)

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26 or Swift 6.2+
- Apple Silicon or Intel Mac (2020+)

## Build & Run

```bash
# Clone
git clone https://github.com/goyal-chintan/focus-flow.git
cd focus-flow

# Build and launch as .app bundle
bash Scripts/run.sh
```

Or open `Package.swift` in Xcode and press ⌘R.

## Install to Applications

```bash
bash Scripts/run.sh
cp -R .build/debug/FocusFlow.app /Applications/
```

Then launch from Spotlight (⌘+Space → "FocusFlow") or Launchpad.

## Architecture

```
Sources/FocusFlow/
├── FocusFlowApp.swift              # App entry — MenuBarExtra + Window scenes
├── Models/
│   ├── Project.swift               # Projects with color, icon, sessions
│   ├── FocusSession.swift          # Focus/break session records + mood/achievement
│   ├── TimeSplit.swift             # Time splits across projects
│   ├── SessionReflection.swift    # FocusMood enum
│   ├── AppSettings.swift           # User preferences
│   └── SessionType.swift           # Focus, short break, long break
├── ViewModels/
│   └── TimerViewModel.swift        # Timer state machine, pause tracking, day boundary
├── Services/
│   └── NotificationService.swift   # Notifications + sounds + pause warnings
└── Views/
    ├── MenuBar/
    │   ├── MenuBarPopoverView.swift    # Timer popover with controls
    │   └── TimeSplitView.swift         # Split time across projects UI
    ├── Companion/
    │   ├── CompanionWindowView.swift   # Sidebar navigation
    │   ├── TodayStatsView.swift        # Daily dashboard with reflections
    │   ├── WeeklyStatsView.swift       # Weekly/monthly charts
    │   ├── ProjectsListView.swift      # Project management
    │   ├── ProjectFormView.swift       # Add/edit project
    │   ├── SessionEditView.swift       # Edit past sessions
    │   └── SettingsView.swift          # App preferences
    └── Components/
        ├── TimerRingView.swift         # Animated progress ring
        ├── ControlButton.swift         # Liquid Glass buttons
        ├── SessionDotsView.swift       # Session cycle dots
        ├── ProjectPickerView.swift     # Search + create project picker
        ├── StatCard.swift              # Glass stat card
        ├── BarChartView.swift          # Weekly bar chart
        ├── ProjectTimeBar.swift        # Per-project progress bar
        ├── SessionTimelineView.swift   # Clickable session timeline
        └── TimeFormatting.swift        # Shared time formatting
```

## Tech Stack

- **SwiftUI** — declarative UI framework
- **SwiftData** — local persistence (no cloud, no accounts)
- **Liquid Glass** — Apple's native material system (macOS 26+)
- **UNUserNotificationCenter** — session and pause notifications
- **SMAppService** — launch at login

## License

MIT
