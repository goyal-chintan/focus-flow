# FocusFlow Liquid Glass High-Fidelity Redesign Implementation Plan

> **For Claude:** Use /executing-plans to implement this plan task-by-task.

**Goal:** Deliver a complete high-fidelity UI redesign (popover states, session complete, companion analytics/management surfaces) using reusable Liquid Glass primitives while preserving all current timer/data behavior.
**Architecture:** Keep `TimerViewModel` + SwiftData logic unchanged. Rebuild UI as composable state-specific views and shared visual primitives (`Views/Components/*`) so future features plug into a consistent design system. Use incremental migration: primitives first, then surfaces.
**Tech Stack:** SwiftUI, SwiftData, macOS 26 Liquid Glass APIs (`.glassEffect`, `.buttonStyle(.glass/.glassProminent)`, `GlassEffectContainer`)

---

### Task 1: Baseline verification + implementation guardrails

**Files:**
- Modify: `docs/plans/2026-03-19-liquid-glass-high-fidelity-redesign.md` (append progress notes while implementing)
- Verify: `Scripts/run.sh`
- Verify: `Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift`
- Verify: `Sources/FocusFlow/Views/SessionCompleteWindow.swift`
- Verify: `Sources/FocusFlow/Views/Companion/TodayStatsView.swift`
- Verify: `Sources/FocusFlow/Views/Companion/WeeklyStatsView.swift`

**Step 1: Run baseline build**
Run: `swift build`
Expected: `Build complete!` (or equivalent success), no compile errors.

**Step 2: Run baseline app bundle launch**
Run: `bash Scripts/run.sh`
Expected: FocusFlow app bundle created/launched without crash.

**Step 3: Capture baseline state checklist (known fail vs new design)**
Checklist (manual): idle/focusing/paused/break popover, focus-complete, break-complete, today, week.
Expected: Existing UI is functional but does **not** match stitch high-fidelity target (intentional baseline fail against new spec).

**Step 4: Commit checkpoint**
```bash
git add docs/plans/2026-03-19-liquid-glass-high-fidelity-redesign.md
git commit -m "chore: record baseline for liquid glass redesign"
```

---

### Task 2: Build shared Liquid Glass primitives

**Files:**
- Create: `Sources/FocusFlow/Views/Components/LiquidDesignTokens.swift`
- Create: `Sources/FocusFlow/Views/Components/LiquidGlassPanel.swift`
- Create: `Sources/FocusFlow/Views/Components/LiquidActionButton.swift`
- Create: `Sources/FocusFlow/Views/Components/LiquidSectionHeader.swift`
- Create: `Sources/FocusFlow/Views/Components/LiquidMetricCard.swift`
- Modify: `Sources/FocusFlow/Views/Components/ControlButton.swift`
- Modify: `Sources/FocusFlow/Views/Components/StatCard.swift`

**Step 1: Add design tokens file**
```swift
import SwiftUI

enum LiquidSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum LiquidRadius {
    static let control: CGFloat = 12
    static let card: CGFloat = 16
    static let hero: CGFloat = 24
}
```

**Step 2: Add `LiquidGlassPanel`**
```swift
struct LiquidGlassPanel<Content: View>: View {
    let prominence: Prominence
    @ViewBuilder var content: Content

    enum Prominence { case low, regular, high }

    var body: some View {
        content
            .padding(LiquidSpacing.md)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidRadius.card))
    }
}
```

**Step 3: Add `LiquidActionButton` + `LiquidSectionHeader` + `LiquidMetricCard`**
Implement typed variants (`primary`, `secondary`, `destructive`) with explicit style branches (`.glassProminent` vs `.glass`) and consistent typography/spacing.

**Step 4: Refactor `ControlButton` and `StatCard` to tokens**
Replace hardcoded spacing/radius/font values with shared tokens and new components.

**Step 5: Verify build**
Run: `swift build`
Expected: success; no type-check timeout.

**Step 6: Commit**
```bash
git add Sources/FocusFlow/Views/Components/LiquidDesignTokens.swift Sources/FocusFlow/Views/Components/LiquidGlassPanel.swift Sources/FocusFlow/Views/Components/LiquidActionButton.swift Sources/FocusFlow/Views/Components/LiquidSectionHeader.swift Sources/FocusFlow/Views/Components/LiquidMetricCard.swift Sources/FocusFlow/Views/Components/ControlButton.swift Sources/FocusFlow/Views/Components/StatCard.swift
git commit -m "feat: add shared liquid glass UI primitives"
```

---

### Task 3: Rewrite popover shell and state-specific content

**Files:**
- Modify: `Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift`
- Modify: `Sources/FocusFlow/Views/Components/TimerRingView.swift`
- Modify: `Sources/FocusFlow/Views/Components/SessionDotsView.swift`
- Modify: `Sources/FocusFlow/Views/Components/ProjectPickerView.swift`
- Modify: `Sources/FocusFlow/FocusFlowApp.swift`

**Step 1: Extract per-state content views inside `MenuBarPopoverView`**
Create internal `private struct` sections:
- `IdlePopoverContent`
- `FocusingPopoverContent`
- `PausedPopoverContent`
- `BreakPopoverContent`

**Step 2: Recompose layout as hero/context/actions/footer decks**
Use shared panel/button primitives; widen popover (`~320-340`) for stitch-like spacing.

**Step 3: Upgrade `TimerRingView`**
Adjust ring track/progress visual depth, typography rhythm, and state caption hierarchy.

**Step 4: Upgrade `SessionDotsView` + `ProjectPickerView`**
Match spacing/shape and avoid tiny control affordances.

**Step 5: Update menu bar label density in `FocusFlowApp.swift`**
Keep semantics but improve scanability for running/paused/overtime indicators.

**Step 6: Verify build + run**
Run: `swift build && bash Scripts/run.sh`
Expected: app launches; popover states render correctly (idle/focusing/paused/break).

**Step 7: Commit**
```bash
git add Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift Sources/FocusFlow/Views/Components/TimerRingView.swift Sources/FocusFlow/Views/Components/SessionDotsView.swift Sources/FocusFlow/Views/Components/ProjectPickerView.swift Sources/FocusFlow/FocusFlowApp.swift
git commit -m "feat: implement high-fidelity liquid popover states"
```

---

### Task 4: Rewrite session completion flows

**Files:**
- Modify: `Sources/FocusFlow/Views/SessionCompleteWindow.swift`
- Modify: `Sources/FocusFlow/Views/MenuBar/TimeSplitView.swift`
- Modify: `Sources/FocusFlow/Views/MenuBar/SessionCompleteView.swift` (if referenced elsewhere)

**Step 1: Refactor focus-complete layout**
Use `LiquidGlassPanel` + `LiquidSectionHeader` for:
- success header
- mood selector row
- reflection input
- split section
- primary/secondary action grouping

**Step 2: Refactor break-complete layout**
Keep `continueAfterCompletion` behavior unchanged; redesign visual hierarchy only.

**Step 3: Restyle `TimeSplitView`**
Align field chrome/buttons/rows with shared primitives.

**Step 4: Preserve and verify window-front behavior**
Keep current bring-to-front flow (`bringWindowToFront`) unless broken by layout changes.

**Step 5: Verify build + run**
Run: `swift build && bash Scripts/run.sh`
Expected: completion windows open and actions still trigger expected state transitions.

**Step 6: Commit**
```bash
git add Sources/FocusFlow/Views/SessionCompleteWindow.swift Sources/FocusFlow/Views/MenuBar/TimeSplitView.swift Sources/FocusFlow/Views/MenuBar/SessionCompleteView.swift
git commit -m "feat: redesign session completion experience"
```

---

### Task 5: Rewrite companion analytics surfaces (Today + Week)

**Files:**
- Modify: `Sources/FocusFlow/Views/Companion/TodayStatsView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/WeeklyStatsView.swift`
- Modify: `Sources/FocusFlow/Views/Components/BarChartView.swift`
- Modify: `Sources/FocusFlow/Views/Components/ProjectTimeBar.swift`
- Modify: `Sources/FocusFlow/Views/Components/SessionTimelineView.swift`

**Step 1: Refactor Today summary block to shared cards**
Replace direct `StatCard` usage where needed with `LiquidMetricCard` wrappers and consistent spacing.

**Step 2: Refactor project/timeline/reflections containers**
Use consistent panel treatment; preserve current query and overlap calculation logic.

**Step 3: Refactor Weekly chart + summary**
Upgrade hierarchy/spacing and panel composition while preserving chart data computation.

**Step 4: Polish `BarChartView`, `ProjectTimeBar`, `SessionTimelineView`**
Align with high-fidelity style and stronger row readability/edit affordance.

**Step 5: Verify build + run**
Run: `swift build && bash Scripts/run.sh`
Expected: Today + Week render with no regressions in totals, labels, or day attribution.

**Step 6: Commit**
```bash
git add Sources/FocusFlow/Views/Companion/TodayStatsView.swift Sources/FocusFlow/Views/Companion/WeeklyStatsView.swift Sources/FocusFlow/Views/Components/BarChartView.swift Sources/FocusFlow/Views/Components/ProjectTimeBar.swift Sources/FocusFlow/Views/Components/SessionTimelineView.swift
git commit -m "feat: redesign companion today and weekly analytics"
```

---

### Task 6: Rewrite companion management surfaces (projects, blocking, settings, forms)

**Files:**
- Modify: `Sources/FocusFlow/Views/Companion/CompanionWindowView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/ProjectsListView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/ProjectFormView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/ManualSessionView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/SessionEditView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/BlockingSettingsView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/BlockProfileFormView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/SettingsView.swift`

**Step 1: Refactor `CompanionWindowView` shell**
Improve sidebar/detail framing using consistent spacing/material and clearer selection state.

**Step 2: Refactor projects list + project form**
Adopt shared section/panel/button primitives; maintain current CRUD behavior.

**Step 3: Refactor manual log + session edit forms**
Keep form logic intact; improve information hierarchy and action layout.

**Step 4: Refactor blocking + settings surfaces**
Replace stock-feeling grouping with panelized composition and consistent control rhythm.

**Step 5: Verify build + run**
Run: `swift build && bash Scripts/run.sh`
Expected: all companion tabs open/operate with no behavior regressions.

**Step 6: Commit**
```bash
git add Sources/FocusFlow/Views/Companion/CompanionWindowView.swift Sources/FocusFlow/Views/Companion/ProjectsListView.swift Sources/FocusFlow/Views/Companion/ProjectFormView.swift Sources/FocusFlow/Views/Companion/ManualSessionView.swift Sources/FocusFlow/Views/Companion/SessionEditView.swift Sources/FocusFlow/Views/Companion/BlockingSettingsView.swift Sources/FocusFlow/Views/Companion/BlockProfileFormView.swift Sources/FocusFlow/Views/Companion/SettingsView.swift
git commit -m "feat: redesign companion management and settings surfaces"
```

---

### Task 7: Full verification and documentation alignment

**Files:**
- Modify: `README.md` (only if UI description/screenshots materially changed)
- Modify: `docs/plans/2026-03-19-liquid-glass-high-fidelity-redesign.md` (mark verification completion)

**Step 1: Run final clean build**
Run: `swift build`
Expected: success.

**Step 2: Run final app launch verification**
Run: `bash Scripts/run.sh`
Expected: app runs.

**Step 3: Execute full manual checklist**
Verify:
- popover: idle/focusing/paused/break
- session complete: focus + break flows
- companion: today/week/projects/blocking/settings
- forms: manual session + session edit + project/block profile forms

**Step 4: Update README if needed**
Adjust only UI-facing description if implementation changed visible product positioning.

**Step 5: Final commit**
```bash
git add README.md docs/plans/2026-03-19-liquid-glass-high-fidelity-redesign.md
git commit -m "chore: finalize liquid glass redesign verification notes"
```

