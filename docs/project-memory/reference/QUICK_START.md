# Quick Reference for Contributors

A concise guide to FocusFlow's established architecture, patterns, and rules.

## Core Concepts

### App Architecture
- **Type:** Menu bar + companion window app (LSUIElement=true, no dock)
- **Platform:** macOS 26+ (Tahoe) only - uses Liquid Glass APIs
- **Frameworks:** SwiftUI, SwiftData, NotificationCenter
- **Build:** SPM with Swift 6.2

### State Management
- **Pattern:** MVVM with `@Observable TimerViewModel`
- **Data:** SwiftData with ModelContainer (Project, FocusSession, AppSettings, TimeSplit)
- **Sharing:** Scenes access ViewModel via `.environment()`

### Timer State Machine
```
IDLE ↔ FOCUSING ↔ PAUSED → OVERTIME → IDLE
```
- Overtime: timer keeps running, counts up, shows `+M:SS` in menu bar
- Sessions complete → `SessionCompleteWindowView` opens (not inline)
- Minimum session: 5 min; auto-delete if <1 min

## UI Rules (Don't Break These)

| Rule | Reason |
|------|--------|
| Icon-only buttons use `.buttonStyle(.plain)` not `.glass` | `.glass` renders as gray rectangles |
| Never stack glass on glass | Causes visual muddiness |
| Use `GlassEffectContainer` for grouped glass elements | Ensures proper compositing |
| Popover background opacity: 0.45-0.55 | >0.55 kills translucency |
| List rows use `Color.white.opacity(0.04)` | `LiquidGlassPanel` creates wireframe effect |
| Glass button styling needs if/else not ternary | Type-checking error with ternary |
| Conditional glass requires if/else branches | Type-checker limitation |
| Reference images are source of truth | Always match Stitch folder designs |
| 3-gate visual review (pixel, HIG, UX) | Before any visual change |

## Design Patterns to Use

### Liquid Glass Components
```swift
// For interactive controls
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
.buttonStyle(.glass)           // Secondary action
.buttonStyle(.glassProminent)  // Primary action
```

### List Row Styling
```swift
Color.white.opacity(0.04)      // Row background (not glass)
```

### Icon Buttons
```swift
Button(action: {}) {
    Image(systemName: "xmark")
}
.buttonStyle(.plain)
.frame(width: 30, height: 30)
.contentShape(Rectangle())
```

### Standalone Window  
```swift
.windowStyle(.hiddenTitleBar)  // Extends glass edge-to-edge
```

## Data Patterns to Follow

### Day Boundary Handling
Cross-midnight sessions split by overlap:
```
overlap = [max(start, dayStart), min(end, dayEnd)]
```

### Session Cleanup
- Auto-delete sessions <1 min
- Minimum session: 5 min (300 sec guard)
- Orphaned sessions: cleaned on next launch

### Timers  
- Run on `RunLoop.main` with `.common` mode
- Callbacks: dispatch to `@MainActor`
- Midnight refresh: schedules 1 sec past midnight

## Common Anti-Patterns (Don't Do These)

❌ Use `LiquidGlassPanel` on list rows  
❌ Stack glass on glass  
❌ Ternary operator for glass button styling  
❌ Icon buttons with `.glass` button style  
❌ Popover background opacity >0.55  
❌ Custom MatchedGeometryEffect pills for selection  
❌ Complex view bodies without extraction  
❌ Add chevrons to Menu labels (native Menu renders them)  
❌ Text smaller than 10pt  
❌ Click targets smaller than 30pt  

## When in Doubt

1. **Visual changes?** Check reference images in Stitch folder  
2. **Timer logic?** Review state machine - don't add new states without decision  
3. **UI styling?** Look up the pattern in [PATTERNS.md](../design-patterns/PATTERNS.md)  
4. **Data modeling?** Check existing models in FocusSession, Project, TimeSplit  
5. **Not sure?** Query the decision log:  
   ```bash
   sqlite3 docs/project-memory/DECISION_LOG.db "SELECT title FROM decisions WHERE category='YOUR_AREA' ORDER BY decision_date DESC LIMIT 5;"
   ```

## File Structure Reference

```
Sources/
├── main.swift              # Entry point
├── FocusFlowApp.swift      # @main app, scene setup
├── Views/
│   ├── MenuBarExtra/
│   │   ├── MenuBarPopoverView.swift
│   │   └── TimerRingView.swift
│   ├── Window/
│   │   ├── MainWindowView.swift
│   │   └── ProjectListView.swift
│   └── Common/
├── ViewModel/
│   └── TimerViewModel.swift    # @Observable singleton
├── Models/
│   ├── Project.swift
│   ├── FocusSession.swift
│   ├── AppSettings.swift
│   └── TimeSplit.swift
└── Services/
    └── NotificationService.swift
```

---

**For in-depth decisions, see [DECISIONS.md](../decisions/DECISIONS.md)**  
**For pattern evolution, see [TIMELINE.md](../evolution/TIMELINE.md)**
