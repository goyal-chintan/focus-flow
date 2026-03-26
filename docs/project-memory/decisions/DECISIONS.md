# Design Decisions

This document records all significant design decisions made during FocusFlow development. Each decision includes the problem statement, alternatives considered, the chosen approach, and the outcome.

## Format

Each decision follows this structure:

```
## [Decision Title]

**Category:** Timer/UI/Data/Architecture/Notifications
**Date:** YYYY-MM-DD  
**Status:** Active | Deprecated | Evolving
**Session(s):** Session IDs where this was decided

### Problem
[What problem or question prompted this decision?]

### Alternatives Considered
- [Option A: ...] - Pros/Cons
- [Option B: ...] - Pros/Cons  
- [Option C: ...] - Pros/Cons

### Decision
[The chosen approach]

### Rationale
[Why this approach was chosen]

### Outcomes
[What resulted from this decision]

### Related Decisions
- [Link to other related decisions]

### Learnings
[What did we learn from this?]
```

---

## Decision Records

### Session 1: Apple Liquid Glass UI Redesign (2026-03-24)

**Session ID:** 491f35aa-8366-4f7b-83ca-04f133f8b943

This was a major visual overhaul session that established core design patterns and quality gates for the entire project.

#### D1.1: 3-Gate Visual Review Process

**Category:** UI/Process  
**Status:** Active

**Problem**
UI iterations had 30-50% visual match to reference images. Designers needed a way to prevent false "done" states.

**Decision**
Establish three mandatory gates before showing ANY visual work to the user:
1. **Gate 1 - Pixel Perfection:** ≥80% visual match vs reference images
2. **Gate 2 - Apple Design Compliance:** HIG layout, typography, spacing, click targets (≥30pt)
3. **Gate 3 - Apple UX Compliance:** Interaction patterns, accessibility, color semantics

**Outcomes**
- Visual quality improved from ~45% to 92%+ reference match
- Prevented 5+ false "done" presentations
- Reduced revision cycles by catching issues early

**Key Learning**
Never present work scoring <80% on Gate 1. Strict gates feel slow initially but save cycles overall.

---

#### D1.2: Native Glass for Labeled Controls, Plain Style for Icon Buttons

**Category:** UI  
**Status:** Active

**Problem**
- `.buttonStyle(.glass)` on icon-only buttons rendered as ugly gray/red rectangles
- Icon buttons were too small for accessibility (< 30pt hit targets)

**Decision**
- Labeled buttons: use `.buttonStyle(.glass)` or `.buttonStyle(.glassProminent)`
- Icon buttons: use `.buttonStyle(.plain)` with `.frame(width: 30, height: 30)` + `.contentShape(Rectangle())`

**Example**
```swift
// ✅ Correct: Icon button with plain style
Button(action: { close() }) {
    Image(systemName: "xmark")
}
.buttonStyle(.plain)
.frame(width: 30, height: 30)
.contentShape(Rectangle())

// ✅ Correct: Labeled button with glass style  
Button("Start Focus") { startFocus() }
    .buttonStyle(.glassProminent)
    .tint(.blue)
```

**Outcomes**
- All buttons render cleanly without gray rectangles
- Click targets expanded to 30pt minimum
- Accessibility improved; VoiceOver can reach all controls

---

#### D1.3: Never Stack Glass on Glass; Use GlassEffectContainer

**Category:** UI  
**Status:** Active

**Problem**
Stacking multiple `.glassEffect()` or glass-styled components created visual muddiness and broke translucency.

**Decision**
- Never directly nest multiple glass effects
- When grouping glass elements, wrap in `GlassEffectContainer { ... }`
- This ensures proper compositing and preserves translucency

**Outcomes**
- UI appears cleaner and more premium
- Glass translucency consistently preserved
- No more "muddy" layered glass appearance

---

#### D1.4: Remove LiquidGlassPanel from List Rows

**Category:** UI  
**Status:** Active

**Problem**
`LiquidGlassPanel` wrappers on list rows created visible bordered wireframes—looked like a prototype, not a finished app.

**Decision**
Use subtle background fills for rows instead:
```swift
// ✅ Use this instead of LiquidGlassPanel
Color.white.opacity(0.04)
```

**Outcomes**
- Projects/Blocking rows no longer look like wireframes
- Appearance is more polished and native-feeling
- Still maintains visual hierarchy

---

#### D1.5: Design Reference Images are Source of Truth

**Category:** UI/Process  
**Status:** Active

**Problem**
Code convenience and developer preferences led to visual divergence. No single source of truth.

**Decision**
- PNG reference images in `Stitch/` folder are the source of truth
- All UI decisions must be driven by reference match, not developer preference
- Maintain ≥80% pixel fidelity with references before any work is shown

**Important Files**
- Reference folder: `FocusFlow/Stitch/stitch_popover_break_light 2/` (13 subfolders, one per screen)
- See [QUICK_START.md](../reference/QUICK_START.md) for how to view and use

**Outcomes**
- All screens now consistently match reference images
- Removed subjective design debates ("looks better to me")
- Visual coherence across all surfaces

---

#### D1.6: Extract Complex View Bodies into Computed Properties

**Category:** Architecture  
**Status:** Active

**Problem**
Complex view bodies in `MenuBarPopoverView`, `ProjectFormView`, and `ManualSessionView` triggered SwiftUI type-checker errors: "unable to type-check this expression in reasonable time."

**Decision**
Split complex views into `private var` computed properties or separate structs:

```swift
// ✅ Extract into computed property
private var focusContent: some View {
    VStack {
        // Complex layout here
    }
}

// Then use in body
var body: some View {
    ZStack {
        focusContent
    }
}
```

**Outcomes**
- Type-checking completes in reasonable time
- Code is more maintainable and testable
- No performance degradation

---

### By Category Summary

- **UI Decisions** (5): Glass styling, button patterns, list rows, reference-driven design, 3-gate review
- **Architecture Decisions** (1): Complex view extraction
- **Data Decisions** (0): *Added in future sessions*
- **Timer Decisions** (0): *Added in future sessions*
- **Notifications** (0): *Added in future sessions*

---

## Query the Database

Use SQLite to query decisions:

```bash
# View all decisions (newest first)
sqlite3 docs/project-memory/DECISION_LOG.db \
  "SELECT decision_date, category, title FROM decisions ORDER BY decision_date DESC;"

# Find all UI decisions
sqlite3 docs/project-memory/DECISION_LOG.db \
  "SELECT title, outcome FROM decisions WHERE category='UI';"

# Find decisions from a specific session
sqlite3 docs/project-memory/DECISION_LOG.db \
  "SELECT title FROM decisions WHERE session_id='491f35aa-8366-4f7b-83ca-04f133f8b943';"

# Find active decisions only
sqlite3 docs/project-memory/DECISION_LOG.db \
  "SELECT title, category FROM decisions WHERE status='active';"
```

---

**Next:** Add sessions covering Timer Logic, Data Models, and Notifications. See [TIMELINE.md](../evolution/TIMELINE.md) for session-by-session evolution.
