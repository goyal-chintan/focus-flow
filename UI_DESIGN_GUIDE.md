# FocusFlow UI/UX Design Guide

> **For agents working on FocusFlow visual design:** Read this before touching any UI code. This captures hard-won lessons from the comprehensive Liquid Glass redesign. Follow the 3-gate review process — it prevents the mistakes documented here.

---

## Quick Start: The 3-Gate Review Process

**Never present visual work without passing all 3 gates:**

1. **Gate 1: Pixel Perfection (≥80% match)**
   - View every reference image in `stitch_popover_break_light 2/`
   - Compare element-by-element to code: sizes, fonts, colors, spacing, shapes
   - Score each screen 0-100%. Below 80% = needs fixes before showing user.

2. **Gate 2: Apple Expert Design Review**
   - `.glass`/`.glassProminent` for ALL interactive controls (never custom gradients)
   - Typography: SF Pro only, minimum 10pt, `.rounded` only for numbers
   - Click targets: 30pt minimum (use `.frame()` + `.contentShape()`)
   - No glass-on-glass stacking; use `GlassEffectContainer` for groups
   - Proper contrast, semantic colors, consistent corner radii

3. **Gate 3: Apple Expert UX Review**
   - Clear primary action per state
   - Destructive actions require confirmation
   - Input bounds validation (clamped ranges)
   - Consistent color language (blue=focus, amber=paused, green=break)
   - Accessibility labels on all interactive elements

**If any gate scores below passing, fix before showing user.** This is non-negotiable.

---

## 8 Critical Mistakes (With Fixes)

### 1. Custom matchedGeometryEffect Segmented Slider
**Problem:** Built a custom pill selector with `matchedGeometryEffect`. Rendered as visible gray rectangle, didn't blend.

**Fix:** Use individual buttons per segment — `.glassProminent` (selected) / `.glass` (unselected).
```swift
// BAD
ZStack {
    Capsule().fill(Color.blue.opacity(0.2))
        .matchedGeometryEffect(id: "pill", in: namespace)
    ...
}

// GOOD
ForEach(presets) { preset in
    Button { selectedMinutes = preset } label: { ... }
        .if(selectedMinutes == preset) { view in
            view.buttonStyle(.glassProminent)
                .tint(.blue)
        }
        .if(selectedMinutes != preset) { view in
            view.buttonStyle(.glass)
        }
        .buttonBorderShape(.capsule)
}
```

### 2. ultraThinMaterial for Ring Background
**Problem:** Used `.ultraThinMaterial` as timer ring disc fill. Created visible gray disc that didn't blend.

**Fix:** Use `Color.black.opacity(0.5)` — blends seamlessly with dark panel.
```swift
// BAD
Circle().fill(.ultraThinMaterial)

// GOOD
Circle().fill(Color.black.opacity(0.5))
```

### 3. Popover Background Too Opaque
**Problem:** Set `Color.black.opacity(0.72)` over `.ultraThinMaterial`. Killed glass translucency; wallpaper invisible.

**Fix:** Use `0.45-0.55` opacity to preserve the Liquid Glass depth cue.
```swift
// BAD
.fill(Color.black.opacity(0.72))

// GOOD
.fill(Color.black.opacity(0.52))
```

### 4. Menu + Custom Chevron = Double Chevron
**Problem:** Added `Image(systemName: "chevron.down")` inside Menu label. Native Menu already renders its own.

**Fix:** Don't add chevrons to Menu labels. Only add them to manual popover Buttons.
```swift
// BAD
} label: {
    HStack {
        Text("Project")
        Spacer()
        Image(systemName: "chevron.down")  // DOUBLE!
    }
}

// GOOD
} label: {
    HStack {
        Text("Project")
        Spacer()
    }
}
```

### 5. LiquidGlassPanel on Every Row
**Problem:** Wrapped every project/blocking row in `LiquidGlassPanel`. Screen looked like wireframe prototype with 4+ visible bordered rectangles.

**Fix:** Reserve glass panels for SECTION containers. Rows use subtle fills without borders.
```swift
// BAD
ForEach(projects) { project in
    LiquidGlassPanel {
        HStack { ... }
    }
}

// GOOD
ForEach(projects) { project in
    HStack { ... }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
}
```

### 6. .buttonStyle(.glass) on Icon-Only Buttons
**Problem:** Applied `.buttonStyle(.glass)` to small pencil/trash/star icons. Rendered as ugly gray/red rectangles.

**Fix:** Use `.buttonStyle(.plain)` with proper hit targets.
```swift
// BAD
Button { ... } label: {
    Image(systemName: "pencil")
        .frame(width: 28, height: 28)
}
.buttonStyle(.glass)
.tint(.secondary)

// GOOD
Button { ... } label: {
    Image(systemName: "pencil")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
}
.buttonStyle(.plain)
```

### 7. Partial Arc Ring for Idle State
**Problem:** Showed only 30% arc in idle. Looked half-baked.

**Fix:** Full circle track for ALL states. Idle gets subtle highlight arc (0.72→0.97) on top.
```swift
// BAD
Circle()
    .trim(from: 0, to: 0.3)
    .stroke(ringColor)

// GOOD
// Full track (all states)
Circle()
    .stroke(Color.white.opacity(0.08))

// Idle: highlight arc overlay
if state == .idle {
    Circle()
        .trim(from: 0.72, to: 0.97)
        .stroke(ringColor.opacity(0.55))
}
```

### 8. Unvalidated Custom Input
**Problem:** Custom minutes TextField accepted any integer: 0, -10, 99999.

**Fix:** Clamp to valid range with `.onChange()`.
```swift
TextField("Min", value: $selectedMinutes, format: .number)
    .onChange(of: selectedMinutes) { _, newValue in
        selectedMinutes = max(5, min(180, newValue))
    }
```

---

## Essential Design Tokens

### Colors
```swift
// Primary actions
LiquidDesignTokens.Spectral.primaryContainer  // #3E90FF
LiquidDesignTokens.Spectral.electricBlue      // #AAC7FF — accents

// State colors
LiquidDesignTokens.Spectral.amber             // #FFC07A — paused
LiquidDesignTokens.Spectral.mint              // #5ED4A0 — break
LiquidDesignTokens.Spectral.salmon            // #FFB4A8 — destructive

// Text
LiquidDesignTokens.Surface.onSurface          // #E5E2E1
LiquidDesignTokens.Surface.onSurfaceMuted     // @ 0.55 opacity
```

### Typography
- **36pt ultraLight rounded** — timer display (hero element)
- **28pt bold** — page titles
- **24pt bold** — window titles
- **18pt bold** — section headers
- **14-16pt** — body text/controls
- **10-11pt** — tracked labels (MINIMUM 10pt, never below)

### Spacing
- **24pt** — popover horizontal padding, section padding
- **14pt** — between elements
- **8pt** — between rows
- **6pt** — inline elements

### Animation
```swift
FFMotion.control   // 0.26s spring — button interactions
FFMotion.section   // 0.34s spring — state transitions
FFMotion.breathing // 1.8s easeInOut repeat — ambient glow
FFMotion.progress  // 0.75s easeInOut — ring updates
```

---

## Component Rules

### Buttons
```swift
// Primary CTAs (one per screen max)
.buttonStyle(.glassProminent)
.tint(LiquidDesignTokens.Spectral.primaryContainer)
.buttonBorderShape(.capsule)

// Secondary actions
.buttonStyle(.glass)
.buttonBorderShape(.capsule)  // or .roundedRectangle(radius: 14)

// Icon-only actions
.buttonStyle(.plain)
.frame(width: 30, height: 30)
.contentShape(Rectangle())
```

### Containers
```swift
// Passive containers (text fields)
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))

// Section panels
LiquidGlassPanel { ... }

// List rows (NO glass panel!)
HStack { ... }
    .padding(14)
    .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.04))
    )
```

### Accessibility
```swift
// Timer ring
.accessibilityElement(children: .ignore)
.accessibilityLabel("FOCUS SESSION, 25:00")
.accessibilityValue("50 percent complete")

// Buttons
.accessibilityLabel("Pause focus")

// State indicator
.accessibilityAddTraits(.isButton)
```

---

## File Map (Reference Images → Code)

| Screen | Code Files | Reference |
|--------|-----------|-----------|
| Idle popover | `MenuBarPopoverView` (IdlePopoverContent), `TimerRingView`, `ProjectPickerView` | `popover_idle_liquid_glass_refined/screen.png` |
| Focusing popover | `MenuBarPopoverView` (FocusingPopoverContent), `TimerRingView` | `popover_focusing_refined/screen.png` |
| Paused popover | `MenuBarPopoverView` (PausedPopoverContent), `TimerRingView` | `popover_paused_dark/screen.png` |
| Break popover | `MenuBarPopoverView` (BreakPopoverContent), `TimerRingView` | `popover_break_light/screen.png` |
| Session Complete | `SessionCompleteWindow.swift` | `session_complete_dark/screen.png` |
| Companion Today | `TodayStatsView`, `StatCard`, `SessionTimelineView` | `companion_today_refined/screen.png` |
| Companion Week | `WeeklyStatsView` | (pattern: stats + chart) |
| Companion Projects | `ProjectsListView` | (pattern: list + form) |
| Companion Blocking | `BlockingSettingsView` | (pattern: list + form) |
| Companion Settings | `SettingsView` | (pattern: sections + toggles) |
| Shared | `LiquidDesignTokens.swift`, `LiquidGlassPanel`, `StatCard`, `SessionTimelineView` | Reference: all screens |

---

## Workflow for Any UI Task

1. **VIEW the reference image** — `stitch_popover_break_light 2/` folder
2. **READ the current code** — understand existing structure
3. **COMPARE element-by-element** — make checklist of differences
4. **EDIT surgically** — change only what doesn't match
5. **BUILD** — `swift build` must pass
6. **SELF-AUDIT all 3 gates** — mentally verify before showing
7. **If score <80%, fix** — never show incomplete work

### Golden Rule
> Reference images are the source of truth. Apple HIG is the quality floor. Code is the implementation vehicle. Never let code convenience override visual fidelity.

---

## Common Patterns

### State-Aware Colors
```swift
private var ringColor: Color {
    switch state {
    case .focusing: Color(hex: 0x506392)      // blue
    case .paused: LiquidDesignTokens.Spectral.amberDark
    case .onBreak: LiquidDesignTokens.Spectral.mintDark
    case .idle: Color(hex: 0x4C5A80)
    }
}
```

### Conditional Styling
```swift
.if(isSelected) { view in
    view.buttonStyle(.glassProminent)
        .tint(.blue)
}
.if(!isSelected) { view in
    view.buttonStyle(.glass)
}
```

### Tracked Labels
```swift
TrackedLabel(
    text: "TODAY'S TOTAL",
    font: .system(size: 10, weight: .medium),
    color: LiquidDesignTokens.Surface.onSurfaceMuted,
    tracking: 2.2
)
```

---

## Testing & Validation

Before committing:
1. `swift build` passes cleanly
2. Menu bar popover renders correctly in all 4 states
3. Companion window renders all tabs
4. Session Complete window shows correctly
5. No console errors or warnings
6. Visual inspection against reference images

---

## References

- **Apple HIG (macOS):** https://developer.apple.com/design/human-interface-guidelines/macos
- **Liquid Glass APIs:** `.glassEffect()`, `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`
- **Stitch Designs:** `stitch_popover_break_light 2/` folder (source of truth)
