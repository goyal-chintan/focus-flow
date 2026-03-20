# Premium UI Overhaul — Spacious, Fun, Interesting

> **For Claude:** Use /executing-plans to implement this plan task-by-task.

**Goal:** Make the popover larger and more spacious, the timer ring more visually interesting and premium, add missing reference features, and polish everything to Apple-grade quality.
**Architecture:** Surgical edits across existing view files — no new files needed. Popover widens from 300→340pt, ring grows from 160→190pt with decorative elements, missing features added.
**Tech Stack:** SwiftUI, macOS 26 Liquid Glass APIs, SwiftData

---

## Key Visual Changes (from reference analysis)

### Ring Enhancement
- **Size**: 160pt → 190pt (reference shows a generous, dominant ring)
- **Outer halo**: Subtle concentric ring 8pt outside main ring (like a watch bezel)
- **Tick marks**: 60 subtle tick marks around perimeter (watch-face aesthetic)
- **Richer gradient**: 3-stop angular gradient with luminance variation
- **Inner shadow**: Subtle inset shadow on the dark disc for depth
- **Breathing glow**: Wider, softer ambient glow pulse when active

### Popover Spaciousness
- **Width**: 300pt → 340pt
- **More vertical padding**: Ring section gets 24pt top/bottom (was 10-18pt)
- **Controls breathe**: 16pt gaps between sections (was 14pt)
- **Footer upgrade**: Add "FOCUSFLOW TAHOE EDITION" tracked text below footer

### Missing Reference Features
- **+5m Extension button**: Glass button in focusing state (between controls and footer)
- **Blocking Profile card**: Glass card with toggle in idle state (between presets and CTA)
- **Next Up card**: Glass card showing next project in focusing state

### Session Complete Polish
- **Title**: 32pt bold italic serif-feel (reference shows editorial weight)
- **Mood buttons**: Taller (44pt min), more prominent
- **Stat cards**: Slightly larger with more padding

### Companion Today
- **Title**: 42pt light weight "Today, March 24" (reference is huge display text)
- **Goal subtitle**: Move to below title, not in card
- **Timeline cards**: Richer with descriptions, icon badges, time ranges

### Quick Fixes
- **9pt → 10pt** in SessionEditView and ManualSessionView mood labels

---

## Tasks

### Task 1: Timer Ring Premium Enhancement
**Files:** `Sources/FocusFlow/Views/Components/TimerRingView.swift`

### Task 2: Popover Layout — Wider, Spacious, Missing Features
**Files:** `Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift`

### Task 3: Session Complete Polish
**Files:** `Sources/FocusFlow/Views/SessionCompleteWindow.swift`

### Task 4: Companion Today Enhancement
**Files:** `Sources/FocusFlow/Views/Companion/TodayStatsView.swift`, `Sources/FocusFlow/Views/Components/SessionTimelineView.swift`

### Task 5: Fix 9pt Violations + Final Polish
**Files:** `Sources/FocusFlow/Views/Companion/SessionEditView.swift`, `Sources/FocusFlow/Views/Companion/ManualSessionView.swift`

### Task 6: Build Verification
Run `swift build` and verify no compiler errors.

### Task 7: Commit
