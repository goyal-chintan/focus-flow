# FocusFlow Apple Design Language Findings (Liquid Glass)

**Date:** 2026-03-16  
**Scope:** What we learned from Apple WWDC25 design guidance, plus current FocusFlow UI/UX observations on branch `codex/premium-ui-redesign`.

## 1) Official Sources Reviewed

- [Meet Liquid Glass (WWDC25, 219)](https://developer.apple.com/videos/play/wwdc2025/219/)
- [Build a SwiftUI app with the new design (WWDC25, 323)](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Get to know the new design system (WWDC25, 279)](https://developer.apple.com/videos/play/wwdc2025/279/)
- [Liquid Glass Technology Overview](https://developer.apple.com/documentation/technologyoverviews/liquid-glass)
- [Adopting Liquid Glass in SwiftUI](https://developer.apple.com/documentation/swiftui/adopting-liquid-glass)

## 2) Apple Design Language Facts (from sources)

1. Apple positions the new design system as a cross-platform visual language built around a shared material and geometry model, not isolated one-off effects.
2. Liquid Glass is described as dynamic material behavior, where translucency, refraction, and contrast adapt to content and context.
3. Motion is structural: controls should feel anchored to their origin, with pop-open and morph transitions between related states.
4. The design system emphasizes concentric geometry and updated control sizing, with larger/cleaner shape rhythms to improve visual coherence.
5. SwiftUI is intended to be the primary implementation path; Apple highlights dedicated APIs and styling updates instead of custom rendering hacks.
6. Glass-style containers and transitions are expected to preserve hierarchy and clarity, not overwhelm content with heavy effects.

## 3) Inferred Implementation Principles for FocusFlow

These are inferences from the above sources, not direct quotes:

1. Liquid Glass quality depends more on interaction choreography than static blur.
2. If controls and panels do not animate as one system, the interface reads as "styled components" rather than native material behavior.
3. Compactness and premium feel are linked: too much narrative copy and too many stacked cards reduce perceived quality in high-frequency surfaces like menu bar popovers.
4. Consistent motion timing tokens are necessary to avoid each surface feeling like a different product.

## 4) FocusFlow UI/UX Observations (current branch)

### What is now aligned

1. Menu bar popover has been compacted and constrained to a tighter shell (`.frame(width: 340)`), reducing the previously oversized feel.
2. Popover now has entry and state transitions (`FFMotion.popover`, `FFMotion.section`) and staged content morphs.
3. Timer stage includes animated numeric transitions and focus-state breathing behavior.
4. Interaction feedback has been added for duration presets, status chips, project selection, and session progress dots.
5. A shared motion token set exists (`FFMotion`) for timing consistency.

### Remaining gaps to Apple-grade Liquid Glass

1. We are using spring/content transitions, but not yet using shared `glassEffectID` transition choreography across related controls/surfaces.
2. Companion window still leans on standard `NavigationSplitView`/plain-button patterns in several areas, so shell identity is weaker than the menu experience.
3. Motion grammar is strongest in menu flows; companion pages are less animated and less materially expressive.
4. Some control/icon sizing in companion forms/lists remains conservative for a premium "native instrument" feel.

## 5) Concrete Code Facts Backing the Observations

- Menu popover and motion wiring: `Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift`
- Timer stage motion behavior: `Sources/FocusFlow/Views/Components/TimerRingView.swift`
- Project picker interaction feedback: `Sources/FocusFlow/Views/Components/ProjectPickerView.swift`
- Session dot micro-motion: `Sources/FocusFlow/Views/Components/SessionDotsView.swift`
- Shared motion tokens: `Sources/FocusFlow/Views/Components/DesignSystem.swift`
- Companion shell baseline structure (still mostly standard split-view shell): `Sources/FocusFlow/Views/Companion/CompanionWindowView.swift`

## 6) Recommended Next UX/UI Pass (if continued)

1. Add `glassEffectID`-based source-to-destination transitions for key menu interactions (project selection, action deck state changes).
2. Apply the same motion tokens and transition grammar to companion window navigation and card updates.
3. Tighten companion component sizing/spacing and icon rhythm to match menu bar polish.
4. Add one cohesive "material hierarchy" map (hero/card/inset/interactive) and enforce it across all screens.

