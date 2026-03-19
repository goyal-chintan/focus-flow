# FocusFlow High-Fidelity Liquid Glass UI Redesign — Design Document

**Date:** 2026-03-19  
**Status:** Approved

---

## Problem Statement

FocusFlow is functionally strong, but its visual language is fragmented across menu bar, completion flow, and companion surfaces. We need a complete high-fidelity UI redesign that uses consistent Liquid Glass patterns, remains maintainable for future features, and preserves all existing timer/session behavior.

---

## Scope

In scope:

- Full menu bar popover redesign across all states: idle, focusing, paused, and break
- Session completion window redesign for focus-complete and break-complete states
- Companion redesign for high-impact analytics surfaces (Today and Weekly)
- Shared UI primitives to ensure consistency and future extensibility

Out of scope:

- Timer state machine logic changes
- SwiftData schema/model changes
- Feature expansion unrelated to UI composition

---

## Approved Approach

Selected approach: **C — High-fidelity rewrite**.

To reduce risk while achieving a full redesign, implementation follows a structured rewrite:

1. Build reusable visual primitives first
2. Refactor per-surface composition to use those primitives
3. Preserve business/data logic and only replace presentation structure

This yields a high visual match to design references while keeping engineering boundaries clear.

---

## Architecture

- Keep `TimerViewModel` as the single source of truth for timer/session state.
- Keep existing scene model (`MenuBarExtra`, companion `Window`, session-complete window).
- Refactor `MenuBarPopoverView` into a shell plus state-specific subviews:
  - `IdlePopoverContent`
  - `FocusingPopoverContent`
  - `PausedPopoverContent`
  - `BreakPopoverContent`
- Keep `SessionCompleteWindowView` behavior intact, but rebuild layout with shared primitives.
- Keep companion query/calculation logic in place; rewrite only surface composition.

This architecture isolates visual change from domain logic.

---

## Component Strategy

Create reusable primitives under `Views/Components/`:

- `LiquidGlassPanel`: refractive container with optional specular edge treatment
- `LiquidSectionHeader`: consistent micro-label + title hierarchy
- `LiquidActionButton`: primary/secondary/destructive visual variants
- `LiquidMetricCard`: reusable stat panel for companion summary cards

Design rules:

- Glass on controls/navigation/panels only; avoid glass-on-glass stacking
- Use `GlassEffectContainer` for grouped controls
- Prefer consistent spacing/radius tokens over one-off values
- Keep accessibility labels and semantic structure intact

---

## Data Flow and State Boundaries

- New components are presentational; they accept values and callbacks.
- No timer/session persistence logic is moved into UI primitives.
- `MenuBarPopoverView` state subviews receive explicit props to reduce coupling.
- Completion flow remains:
  - `saveReflection(...)`
  - `continueAfterCompletion(...)`
- Companion views keep current SwiftData queries and day-overlap attribution logic.

---

## Error Handling and Reliability

- Preserve existing explicit behavior paths; no broad catches or silent fallbacks.
- Keep existing stop/abandon/continue semantics unchanged.
- Keep session-complete window activation logic intact unless clearly broken by UI refactor.
- Any regressions introduced by layout extraction are fixed in the same implementation pass.

---

## Verification Plan

Because the repository has no test target, verification combines build checks and manual state coverage.

Baseline:

- `swift build` before UI rewrite

Post-change:

- `swift build`
- `bash Scripts/run.sh` to validate app bundle path and runtime wiring

Manual state coverage checklist:

- Popover idle
- Popover focusing
- Popover paused (including pause warning color progression)
- Popover break
- Session complete (focus)
- Session complete (break)
- Companion Today
- Companion Weekly

---

## Trade-offs

Benefits:

- High-fidelity redesign aligned with stitch references
- Strong visual consistency via shared primitives
- Better maintainability for future features

Costs/Risks:

- Larger UI delta and higher regression risk than incremental polish
- Potential SwiftUI type-check pressure if view extraction is insufficient
- Additional manual verification burden due no automated UI tests

Mitigation:

- Extract complex subviews early
- Keep data logic untouched
- Verify every major state explicitly after rewrite


---

## Final Verification Notes

Automated verification commands run (success):

- `swift build`
- `bash Scripts/run.sh`

Manual UX validation checklist:

- [ ] Popover: idle
- [ ] Popover: focusing
- [ ] Popover: paused
- [ ] Popover: break
- [ ] Session complete: focus
- [ ] Session complete: break
- [ ] Companion: Today
- [ ] Companion: Weekly
- [ ] Companion: Projects
- [ ] Companion: Blocking
- [ ] Companion: Settings
- [ ] Forms/flows: manual session log
- [ ] Forms/flows: session edit
- [ ] Forms/flows: project form
- [ ] Forms/flows: block profile form
