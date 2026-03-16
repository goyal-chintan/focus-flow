# FocusFlow Premium UI/UX Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild FocusFlow's visual system and primary surfaces so the app feels like a premium native macOS product with consistent sizing, spacing, hierarchy, and liquid-glass-style depth.

**Architecture:** Introduce a shared design-system layer first, then migrate the menu bar popover, session completion flow, companion window shell, dashboard panels, lists, and forms onto those primitives. Keep the data model and timer state machine intact while changing layout, materials, hierarchy, and interaction polish.

**Tech Stack:** SwiftUI, SwiftData, AppKit-backed macOS app bundle via `Scripts/run.sh`, native materials/glass APIs on macOS 26

---

### Task 1: Add design-system tokens and surface primitives

**Files:**
- Create: `Sources/FocusFlow/Views/Components/DesignSystem.swift`
- Create: `Sources/FocusFlow/Views/Components/PremiumSurface.swift`
- Create: `Sources/FocusFlow/Views/Components/PremiumSectionHeader.swift`
- Modify: `Sources/FocusFlow/Views/Components/ControlButton.swift`
- Modify: `Sources/FocusFlow/Views/Components/StatCard.swift`

**Step 1: Create shared design tokens**

Add `DesignSystem.swift` with:

```swift
import SwiftUI

enum FFSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum FFRadius {
    static let control: CGFloat = 12
    static let card: CGFloat = 18
    static let hero: CGFloat = 28
}

enum FFType {
    static let heroTimer = Font.system(size: 52, weight: .ultraLight, design: .rounded)
    static let heroLabel = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let sectionTitle = Font.system(.title3, weight: .semibold)
    static let cardValue = Font.system(.title2, weight: .semibold)
    static let body = Font.system(.body)
    static let callout = Font.system(.callout, weight: .medium)
    static let meta = Font.system(.footnote, weight: .medium)
}

enum FFColor {
    static let focus = Color.blue
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let deepFocus = Color.indigo
}
```

**Step 2: Create premium container primitives**

Add `PremiumSurface.swift` and `PremiumSectionHeader.swift` to wrap:

- hero surfaces
- standard cards
- inset trays
- section headers with title/subtitle/actions

These components should own consistent padding, corner radius, material, overlay stroke, and shadow depth.

**Step 3: Refactor `ControlButton` to consume the design system**

Update `ControlButton.swift` so it uses shared typography, larger vertical padding, and a stronger role-based layout. Keep the same public API if possible.

**Step 4: Refactor `StatCard` to consume shared tokens**

Replace hard-coded type/radius values with design tokens and improve internal hierarchy.

**Step 5: Run build verification**

Run:

```bash
swift build
```

Expected: build succeeds with no new compiler errors.

**Step 6: Commit**

```bash
git add Sources/FocusFlow/Views/Components/DesignSystem.swift Sources/FocusFlow/Views/Components/PremiumSurface.swift Sources/FocusFlow/Views/Components/PremiumSectionHeader.swift Sources/FocusFlow/Views/Components/ControlButton.swift Sources/FocusFlow/Views/Components/StatCard.swift
git commit -m "feat: add shared premium design system primitives"
```

---

### Task 2: Rebuild the timer hero and menu bar popover shell

**Files:**
- Modify: `Sources/FocusFlow/Views/Components/TimerRingView.swift`
- Modify: `Sources/FocusFlow/Views/Components/ProjectPickerView.swift`
- Modify: `Sources/FocusFlow/Views/Components/SessionDotsView.swift`
- Modify: `Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift`
- Modify: `Sources/FocusFlow/FocusFlowApp.swift`

**Step 1: Upgrade the timer stage**

Refactor `TimerRingView.swift` to:

- enlarge the stage
- improve ring depth and stroke layering
- use shared typography tokens
- strengthen the supporting label
- preserve numeric transitions

**Step 2: Redesign the project picker surface**

Update `ProjectPickerView.swift` so the closed state reads like a premium field/tray rather than a small menu trigger. Increase icon size, padding, and affordance clarity. Keep `Menu` if needed initially, but restyle the field and popover entry sheet to match the new system.

**Step 3: Upgrade session dots to match the hero**

Adjust `SessionDotsView.swift` to use the new spacing and visual rhythm so it belongs to the timer stage instead of floating beneath it.

**Step 4: Recompose the menu bar popover layout**

Refactor `MenuBarPopoverView.swift` to:

- widen the popover
- group content into hero, context, and action decks
- remove arbitrary spacing values
- improve footer hierarchy
- make paused/focusing states feel distinct
- keep the stop confirmation visually integrated with the new shell

Target outcome:

- idle state feels staged and premium
- action buttons are larger and easier to scan
- the footer no longer competes with primary actions

**Step 5: Refresh the menu bar label density**

Update `FocusFlowApp.swift` so the menu bar extra label uses improved spacing, clearer icon hierarchy, and slightly better density without becoming noisy.

**Step 6: Run build verification**

Run:

```bash
swift build
```

Expected: build succeeds.

**Step 7: Run app verification**

Run:

```bash
bash Scripts/run.sh
```

Expected: app launches. Manually verify idle, focusing, paused, and break states in the menu bar popover.

**Step 8: Commit**

```bash
git add Sources/FocusFlow/Views/Components/TimerRingView.swift Sources/FocusFlow/Views/Components/ProjectPickerView.swift Sources/FocusFlow/Views/Components/SessionDotsView.swift Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift Sources/FocusFlow/FocusFlowApp.swift
git commit -m "feat: redesign menu bar popover and timer hero"
```

---

### Task 3: Redesign the completion, manual-log, and session-edit flows

**Files:**
- Modify: `Sources/FocusFlow/Views/MenuBar/SessionCompleteView.swift`
- Modify: `Sources/FocusFlow/Views/MenuBar/TimeSplitView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/ManualSessionView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/SessionEditView.swift`

**Step 1: Rebuild the completion shell**

Refactor `SessionCompleteView.swift` to create:

- a stronger success header
- better spacing and width
- more expressive mood selection
- clearer hierarchy for reflection text
- a single obvious primary action with subordinate alternatives

**Step 2: Restyle split-time editing**

Update `TimeSplitView.swift` so expanded split configuration visually belongs to the completion flow and uses the same field chrome, spacing, and hierarchy as the new surfaces.

**Step 3: Bring manual session logging onto the new system**

Refactor `ManualSessionView.swift` to use:

- shared field styling
- larger presets and mood controls
- stronger section grouping
- a more polished action row

**Step 4: Bring session editing onto the new system**

Refactor `SessionEditView.swift` to align with the same shell and control language as manual session logging and completion.

**Step 5: Run build verification**

Run:

```bash
swift build
```

Expected: build succeeds.

**Step 6: Run app verification**

Run:

```bash
bash Scripts/run.sh
```

Expected: app launches. Manually verify:

- completion flow after finishing a session
- manual log sheet
- session edit sheet from timeline

**Step 7: Commit**

```bash
git add Sources/FocusFlow/Views/MenuBar/SessionCompleteView.swift Sources/FocusFlow/Views/MenuBar/TimeSplitView.swift Sources/FocusFlow/Views/Companion/ManualSessionView.swift Sources/FocusFlow/Views/Companion/SessionEditView.swift
git commit -m "feat: redesign completion and editing flows"
```

---

### Task 4: Rebuild the companion app shell

**Files:**
- Modify: `Sources/FocusFlow/Views/Companion/CompanionWindowView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/TodayStatsView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/WeeklyStatsView.swift`
- Modify: `Sources/FocusFlow/Views/Components/BarChartView.swift`
- Modify: `Sources/FocusFlow/Views/Components/ProjectTimeBar.swift`
- Modify: `Sources/FocusFlow/Views/Components/SessionTimelineView.swift`

**Step 1: Replace the stock-feeling shell treatment**

Refactor `CompanionWindowView.swift` so the sidebar and detail region feel branded and deliberate. Preserve the same tab model, but improve the selection treatment, spacing, toolbar feel, and overall framing.

**Step 2: Rebuild the Today dashboard**

Update `TodayStatsView.swift` to:

- add a stronger top section/header
- place cards and sections into premium panels
- reduce visual fragmentation
- improve mood/reflection presentation

**Step 3: Rebuild the Week dashboard**

Update `WeeklyStatsView.swift`, `BarChartView.swift`, and `ProjectTimeBar.swift` so charting and summary panels match the premium surface language and carry stronger hierarchy.

**Step 4: Redesign the timeline rows**

Update `SessionTimelineView.swift` so rows have better spacing, state signaling, and edit affordance while preserving the existing behavior.

**Step 5: Run build verification**

Run:

```bash
swift build
```

Expected: build succeeds.

**Step 6: Run app verification**

Run:

```bash
bash Scripts/run.sh
```

Expected: app launches. Manually verify Today and Week views for layout, readability, and consistent material usage.

**Step 7: Commit**

```bash
git add Sources/FocusFlow/Views/Companion/CompanionWindowView.swift Sources/FocusFlow/Views/Companion/TodayStatsView.swift Sources/FocusFlow/Views/Companion/WeeklyStatsView.swift Sources/FocusFlow/Views/Components/BarChartView.swift Sources/FocusFlow/Views/Components/ProjectTimeBar.swift Sources/FocusFlow/Views/Components/SessionTimelineView.swift
git commit -m "feat: redesign companion shell and dashboards"
```

---

### Task 5: Redesign projects, blocking, and settings surfaces

**Files:**
- Modify: `Sources/FocusFlow/Views/Companion/ProjectsListView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/ProjectFormView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/BlockingSettingsView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/BlockProfileFormView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/SettingsView.swift`

**Step 1: Upgrade projects list presentation**

Refactor `ProjectsListView.swift` to use larger, richer rows with better project identity, spacing, and actions. Empty states should use the new premium shell.

**Step 2: Upgrade project editing**

Refactor `ProjectFormView.swift` so project name, color, icon, and block-profile selection feel like one composed, premium editing surface.

**Step 3: Upgrade blocking management**

Refactor `BlockingSettingsView.swift` and `BlockProfileFormView.swift` to align with the same shell, field chrome, row styling, and empty-state language as the rest of the app.

**Step 4: Replace `GroupBox`-style settings presentation**

Refactor `SettingsView.swift` to use premium grouped panels with consistent headers, supporting descriptions, and better control alignment.

**Step 5: Run build verification**

Run:

```bash
swift build
```

Expected: build succeeds.

**Step 6: Run app verification**

Run:

```bash
bash Scripts/run.sh
```

Expected: app launches. Manually verify Projects, Blocking, and Settings surfaces including add/edit flows.

**Step 7: Commit**

```bash
git add Sources/FocusFlow/Views/Companion/ProjectsListView.swift Sources/FocusFlow/Views/Companion/ProjectFormView.swift Sources/FocusFlow/Views/Companion/BlockingSettingsView.swift Sources/FocusFlow/Views/Companion/BlockProfileFormView.swift Sources/FocusFlow/Views/Companion/SettingsView.swift
git commit -m "feat: redesign management and settings surfaces"
```

---

### Task 6: Add brand integration and final polish pass

**Files:**
- Modify: `Sources/FocusFlow/Views/Companion/CompanionWindowView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/SettingsView.swift`
- Modify: `Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift`
- Modify: `README.md`
- Optional asset touch: `Sources/FocusFlow/Assets.xcassets/*` if app imagery needs adjustment

**Step 1: Integrate the FocusFlow brand subtly**

Add restrained brand moments using the existing FocusFlow identity:

- header/sidebar brand treatment
- improved About section
- refined empty states or hero accents

Use restraint. Do not let branding overpower information density.

**Step 2: Perform consistency sweep**

Remove leftover ad hoc values:

- stray tiny fonts
- mismatched radii
- inconsistent card padding
- generic sheet chrome that no longer matches the system

**Step 3: Update README if needed**

If the new shell materially changes the product presentation, update `README.md` to reflect the new visual language and any screenshots/description changes.

**Step 4: Run full verification**

Run:

```bash
swift build
```

Then run:

```bash
bash Scripts/run.sh
```

Expected:

- build succeeds
- app launches
- all major views render
- no obvious layout regressions in menu bar or companion window

**Step 5: Manual checklist verification**

Verify each of these states in the running app:

- idle timer
- running focus session
- paused session with warning progression
- break state
- completion flow with and without splits
- today dashboard
- weekly dashboard
- projects list and project form
- manual log flow
- session edit flow
- blocking profiles
- settings

**Step 6: Commit**

```bash
git add Sources/FocusFlow/Views/Companion/CompanionWindowView.swift Sources/FocusFlow/Views/Companion/SettingsView.swift Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift README.md
git commit -m "feat: complete premium FocusFlow redesign"
```
