# Design Patterns

Recurring design patterns and conventions established across FocusFlow development.

## UI Patterns

### Liquid Glass Components

**Where:** MenuBarPopoverView, ProjectFormView, settings areas  
**Pattern:** Use `.glassEffect()` and `.buttonStyle(.glass)` for interactive controls  
**Rules:**
- Never stack glass on glass (causes muddiness)
- Use `GlassEffectContainer` when grouping multiple glass elements
- Popover background opacity: 0.45-0.55 (higher kills translucency)
- Icon-only buttons: use `.buttonStyle(.plain)` NOT `.glass` (prevents gray rectangles)
- Reference design images are source of truth (see Stitch folder)

### Button Styling

**Pattern:** Conditional glass styling requires if/else (not ternary - causes SwiftUI type errors)

```swift
if isSelected {
    button.buttonStyle(.glassProminent).tint(.blue)
} else {
    button.buttonStyle(.glass)
}
```

### List Row Styling  

**Pattern:** Use `Color.white.opacity(0.04)` fills for rows, NOT `LiquidGlassPanel` (prevents wireframe effect)

## Architecture Patterns

### Timer State Machine

```
IDLE → startFocus() → FOCUSING → timerCompleted() → OVERTIME
                         ↓
                      pause()
                         ↓
                      PAUSED
                         ↓
                      resume() → FOCUSING
```

**Key property:** `isOvertime=true` when in overtime, keeps timer running and counting up

### MVVM + Scene-Based Architecture

**Pattern:** Single `@Observable TimerViewModel` shared across MenuBarExtra and Window scenes via `.environment()`

**Data flow:**
1. `FocusFlowApp` creates ModelContainer and TimerViewModel
2. Both scenes inject them via `.environment()`
3. Views access via `@Environment(TimerViewModel.self)`

### Session Completion Flow

**Pattern:** Completion opens standalone `SessionCompleteWindowView`, not inline in popover

**Overtime display:** Menu bar shows orange `+M:SS` counter

## Data Patterns

### Day Boundary Handling

**Pattern:** Cross-midnight sessions attributed to both days using overlap calculation

```
overlap = [max(sessionStart, dayStart), min(sessionEnd, dayEnd)]
```

**Applied in:** `loadTodayStats()`, `TodayStatsView`, `WeeklyStatsView`

### Session Cleanup

**Rules:**
- Sessions under 1 minute are auto-deleted
- Minimum session duration: 5 minutes (300 seconds)
- Orphaned sessions (app quit mid-focus) cleaned on next launch

## Testing & Quality Patterns

### Pre-Delivery Review Gates

**3-Gate review before any visual change:**

1. **Pixel match** ≥80% against reference images
2. **Apple HIG checklist** (layout, typography, spacing)
3. **Apple UX checklist** (interaction model, accessibility)

**Rule:** If any gate fails, fix before showing user

### Type-Check Timeouts

**Pattern:** Complex view bodies cause "unable to type-check this expression" errors

**Fix:** Extract sections into `private var someName: some View` computed properties

---

*For pattern examples and evolution, see [TIMELINE.md](../evolution/TIMELINE.md)*
