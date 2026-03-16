# FocusFlow

A native macOS Pomodoro focus timer built with SwiftUI and Apple's Liquid Glass design language.

![FocusFlow Logo](Brand/LogoConcepts/focusflow-logo-final.svg)

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

**Menu Bar Timer**
- Lives in the menu bar — always visible, never in the way
- Animated timer ring with live countdown
- Start, pause, resume, and stop focus sessions
- Pick from saved projects or type a custom label
- Session cycle tracking with automatic short and long breaks

**Companion Window**
- Today: focus time, session count, per-project breakdown, session timeline
- Week: bar chart of daily focus time with 7-day and 30-day views
- Projects: create, edit, and archive projects with colors and icons
- Settings: customize durations, sounds, auto-start behavior, launch at login

**Built with Apple's Liquid Glass**
- Native `.glassEffect()` materials with refraction and specular highlights
- `.buttonStyle(.glass)` and `.glassProminent` controls
- `GlassEffectContainer` for grouped glass elements
- Designed exclusively for macOS 26 (Tahoe) and Apple Silicon

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
├── FocusFlowApp.swift          # App entry — MenuBarExtra + Window scenes
├── Models/                     # SwiftData models
│   ├── Project.swift           # Projects with color, icon, sessions
│   ├── FocusSession.swift      # Focus/break session records
│   ├── AppSettings.swift       # User preferences
│   └── SessionType.swift       # Focus, short break, long break
├── ViewModels/
│   └── TimerViewModel.swift    # Timer state machine + SwiftData persistence
├── Services/
│   └── NotificationService.swift  # macOS notifications + sounds
└── Views/
    ├── MenuBar/
    │   └── MenuBarPopoverView.swift   # Timer popover
    ├── Companion/
    │   ├── CompanionWindowView.swift  # Sidebar navigation
    │   ├── TodayStatsView.swift       # Daily stats dashboard
    │   ├── WeeklyStatsView.swift      # Weekly/monthly charts
    │   ├── ProjectsListView.swift     # Project management
    │   ├── ProjectFormView.swift      # Add/edit project
    │   └── SettingsView.swift         # App preferences
    └── Components/
        ├── TimerRingView.swift        # Animated progress ring
        ├── ControlButton.swift        # Liquid Glass buttons
        ├── SessionDotsView.swift      # Session cycle dots
        ├── ProjectPickerView.swift    # Project selector
        ├── StatCard.swift             # Stats display card
        ├── BarChartView.swift         # Weekly bar chart
        ├── ProjectTimeBar.swift       # Per-project progress bar
        ├── SessionTimelineView.swift  # Daily session timeline
        └── TimeFormatting.swift       # Shared time formatting
```

## Tech Stack

- **SwiftUI** — declarative UI framework
- **SwiftData** — local persistence (no cloud, no accounts)
- **Liquid Glass** — Apple's native material system (macOS 26+)
- **UNUserNotificationCenter** — session completion notifications
- **SMAppService** — launch at login

## License

MIT
