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

---

## Session: Domain Analytics Integrity Rollout (2026-04-06)

**Session ID:** 71def331-9ad6-4d58-87ad-bdd1e0782d57

Browser-domain capture, companion analytics windows, and recovery messaging were tightened so Today, Week, Insights, and Settings all describe the same data pipeline.

---

#### D3.1: Shared Windowed Domain Analytics With Privacy-Safe Browser Context

**Category:** Data/UI/Architecture
**Date:** 2026-04-06
**Status:** Active
**Session(s):** 71def331-9ad6-4d58-87ad-bdd1e0782d57

### Problem

- Browser-domain history contained malformed `domain:` rows and no reliable contract for what counted as a valid website.
- Insights mixed incompatible time windows, which made domain guidance feel stale even when fresh activity existed.
- Turning off detailed domains in Settings did not fully stop browser-title-derived coaching context.
- Browser app rows and resolved domain rows could distort live ratios and hide unresolved browser time.

### Alternatives Considered

- **Keep per-surface analytics logic** — faster in the short term, but guaranteed more drift between Today, Week, Insights, and Settings recovery states.
- **Persist only domain rows for browser time** — simpler analytics, but risked losing generic browser visibility when a site could not be resolved.
- **Treat Screen Recording as universally required** — easier messaging, but false for supported browsers that expose active-tab URLs directly.

### Decision

- Keep `AppUsageEntry` as the persisted primitive, but centralize domain validation and windowing in a shared `CompanionAnalyticsBuilder`.
- Treat Today, trailing 7 days, and trailing 30 days as the canonical windows for all companion domain surfaces.
- Preserve app-level browser tracking as the authoritative total, use valid `domain:` rows to refine site-level analytics, and keep residual unresolved browser time visible instead of dropping it.
- When detailed domains are off, sanitize browser coaching context back to app-level labels and titles.
- Treat Screen Recording as a title-fallback aid only, not a blanket prerequisite for all browser-domain capture.

### Rationale

This keeps the product honest in both directions: precise site-level insight when valid domains exist, and accurate generic browser/app tracking when they do not. One shared analytics contract also prevents Today, Week, Insights, and Settings from drifting into conflicting explanations.

### Outcomes

- Browser-domain capture is validated before persistence and malformed legacy `domain:` rows are ignored in analytics and recovery messaging.
- Today and Week gained always-visible domain sections backed by the same analytics source as Insights.
- Insights now uses explicit today and trailing-window inputs instead of mixed all-time data, while Today and Week keep owning the today / 7-day / 30-day domain surfaces.
- Settings copy and recovery states now match the real capture pipeline, including the Screen Recording fallback nuance.

### Related Decisions

- D1.1: 3-Gate Visual Review Process
- D2.1: `domain:` Prefix Convention for Browser-Domain AppUsageEntries

### Learnings

Privacy toggles are not complete until labels, coaching, persistence, and recovery messaging all agree. For browser analytics, "supported browser", "title fallback", and "valid domain history" are distinct concepts and must not be collapsed into one state.

---

#### D3.2: Settings Needs a Unified Permission Health Surface

**Category:** UI/Architecture/Notifications
**Date:** 2026-04-07
**Status:** Active
**Session(s):** 71def331-9ad6-4d58-87ad-bdd1e0782d57

### Problem

- FocusFlow depended on multiple macOS permission surfaces, but the recovery path was fragmented across Settings.
- Browser-domain capture relies on Automation first and Screen Recording only as fallback, which made the old "permission help" copy too easy to misread.
- Users had no single place to see whether Notifications, Calendar, Reminders, Browser Automation, and Screen Recording were actually ready.

### Alternatives Considered

- **Keep recovery in each local section only** — less UI surface area, but users still have to hunt across Settings to understand what is broken.
- **Add a summary without actions** — visually lighter, but still forces a second navigation step for recovery.
- **Collapse all setup into one new panel** — centralizes status, but weakens the existing organization of Calendar, Reminders, and coach settings.

### Decision

- Keep the existing Calendar, Reminders, and domain-tracking controls where they belong.
- Add a final `Permission & Integration Health` section in Settings with five live rows: Notifications, Calendar, Reminders, Browser Automation, and Screen Recording.
- Give every row a direct recovery action, and compute Browser Automation status per supported installed browser with Apple Events permission probing instead of a blanket assumption.

### Rationale

This keeps setup discoverable while adding a single trustworthy health check. It also makes the browser capture pipeline honest: Automation is primary, Screen Recording is fallback, and both should be visible without forcing the user to infer internal implementation details.

### Outcomes

- Settings now ends with one canonical permission health surface for the app’s core integrations.
- Each permission row has an explicit status and an actionable recovery button.
- Browser-domain recovery no longer warns supported browsers indiscriminately; approved browsers stay in the normal "waiting for first capture" state.

### Related Decisions

- D1.1: 3-Gate Visual Review Process
- D3.1: Shared Windowed Domain Analytics With Privacy-Safe Browser Context

### Learnings

Permission UX should describe the real pipeline, not the easiest simplification. For FocusFlow, "feature enabled", "OS permission granted", and "integration configured" are separate states and deserve separate feedback.

---

## Session: Guardian Recommendations & Idle Escalation (2026-03-26)

**Session ID:** a78f68d5-ee86-4127-b11d-18d71d7a35b8

Three bugs fixed across AppUsageTracker, InsightsView confidence scoring, and idle prompt escalation routing.

---

#### D2.1: `domain:` Prefix Convention for Browser-Domain AppUsageEntries

**Category:** Data/Architecture
**Status:** Active

**Problem**
`AppUsageTracker` tracked the frontmost browser app (e.g. Arc) but never wrote a separate entry for the active website. Guardian Recommendations therefore showed only app names — YouTube, Reddit, GitHub never appeared as distinct items even when they were the true source of distraction.

**Alternatives Considered**
- Store domain as a nullable field on the browser `AppUsageEntry` — requires schema migration, complicates queries
- Separate SwiftData model for domains — over-engineered for current scale
- `domain:<host>` keyed `AppUsageEntry` reusing the existing model — zero schema change, filtered cleanly by prefix

**Decision**
Write a parallel `AppUsageEntry(bundleIdentifier: "domain:<host>")` every second the browser is frontmost. `recommendedBlockTarget()` strips the prefix to return the bare host. `recommendationDisplayLabel()` returns the app name stored in the entry (already sanitised at write time).

**Outcomes**
- Websites now appear in Guardian Recommendations within 30 s of browsing
- Coach message personalisation receives a real-time `currentFrontmostDomainLabel` (e.g. "YouTube")
- Zero schema migration required

**Key Learning**
Encoding semantics in the `bundleIdentifier` string is pragmatic for a single-model store; use `hasPrefix("domain:")` guards consistently everywhere this field is read.

---

#### D2.2: Confidence Formula Recalibration (Saturation Fix)

**Category:** Data
**Status:** Active

**Problem**
`guardianRecommendations` in `InsightsView` used `0.62 + min(0.25, weightedSeconds / 7_200)`. Any app with ≥30 min of weighted usage saturated at 0.87, so Claude, Codex, and Slack all showed identical 87% scores regardless of actual exposure.

**Alternatives Considered**
- Logarithmic scale — harder to reason about, non-linear jumps feel arbitrary
- Longer denominator with same additive structure — simple, predictable, preserves existing formula shape

**Decision**
Change to `0.50 + min(0.40, weightedSeconds / 36_000)`. Saturation now occurs at ~10 hours of 7-day weighted usage. Typical spread: heavy app ~80%, medium ~65%, light ~52%.

**Outcomes**
- Scores now differentiate between apps proportionally to actual usage
- `min(0.97, ...)` cap still prevents false certainty

**Key Learning**
Denominator should represent "maximum realistic 7-day exposure" not "session length". Match the window of data being queried.

---

#### D2.3: `prettifyToken` Preserve-Case Guard

**Category:** Data/UI
**Status:** Active

**Problem**
`prettifyToken("YouTube")` returned `"Youtube"` because it split on nothing and lowercased all-but-first characters. This broke `FocusCoachBlockingRecommendationEngine` copy text matching (`"YouTube"` ≠ `"Youtube"`).

**Decision**
In `recommendationDisplayLabel()`, if the stored `appName` contains no technical separator characters (`. : / - _`) and starts uppercase, return it as-is rather than running through `prettifyToken`.

**Outcomes**
- "YouTube", "ChatGPT", "GitHub" render correctly without downstream match failures
- `prettifyToken` still normalises bundle-ID-derived names

---

#### D2.4: Idle Hard Prompt — Bypass Work-Intent Gate for Ignored Notifications

**Category:** Architecture/Notifications
**Status:** Active

**Problem**
After 20 min idle, `routeIdleStarter` gates the strong prompt behind `WorkIntentSignal.isWorkIntentWindow`. Outside 9 am–6 pm (or when the user hasn't opened FocusFlow recently), `isWorkIntentWindow = false`, so the gate blocks the strong prompt even though a notification was already sent and ignored — exactly the case where the hard prompt *should* appear.

**Alternatives Considered**
- Remove the `isWorkIntentWindow` gate entirely — too aggressive, would interrupt users outside working hours with no prior signal
- Widen `withinTypicalWorkHours` range — arbitrary, doesn't solve the core issue
- Pass `workIntentSignal: nil` when `outsideSessionAwaitingStartFocus = true` — surgical, only bypasses the gate after the system has already sent a notification the user ignored

**Decision**
In `evaluateIdleStarterIntervention`, call `routeIdleStarter(workIntentSignal: outsideSessionAwaitingStartFocus ? nil : workIntentSignal)`. When the signal is `nil`, the `if let signal = workIntentSignal` guard skips the gate naturally; `shouldPresent` is then driven only by the guardian state (`.challenge` → true).

**Outcomes**
- Strong prompt fires correctly at hour=22 in tests (previously blocked)
- No change to behaviour during first two escalation nudges (gate still applies)
- 206/206 tests pass

**Key Learning**
Escalation design rule: once a notification has been sent and ignored (`outsideSessionAwaitingStartFocus = true`), the system has already established user context. A follow-up hard prompt is justified at any hour.

---

#### D2.5: Agent Workflow Constitution (AGENT_INSTRUCTIONS.md)

**Category:** Process/Architecture
**Status:** Active

**Problem**
Multiple AI agent sessions each re-investigated the same codebase from scratch, duplicated debugging effort, and occasionally made changes that conflicted with prior decisions.

**Decision**
Create `docs/AGENT_INSTRUCTIONS.md` — a 6-phase workflow guide (Orient → Understand → Branch → Implement → Audit → Ship) that every agent must follow. Key mandates: read checkpoints + decision log before touching code; use systematic-debugging before proposing fixes; use apple-grade-ui-system for any UI work; raise a PR, never push directly to main.

**Outcomes**
- Guardian Recommendations and idle prompt bugs investigated and fixed without redundant exploration
- UI changes gated by apple-grade-ui-system Gatekeeper review
- PR-first workflow enforced consistently

---

---

## Stats Window Minimum Frame Constraint

**Category:** Architecture
**Date:** 2026-04-11
**Status:** Active
**Session(s):** fix/stats-window-layout-loop (fixes #33)

### Problem
On macOS 26 Tahoe the Stats/Companion window deadlocked the main thread on every open attempt. `sample` showed 100% of samples stuck in an infinite `NSPerformVisuallyAtomicChange` → `NSView._layoutSubtreeWithOldSize` recursion triggered from `CompanionWindowView`'s `NavigationSplitView(.balanced)`. The app had been frozen for 3+ days.

### Alternatives Considered
- **Add `.windowResizability(.contentSize)`** — too restrictive; user should be able to resize a full companion window freely.
- **Add `.frame(minWidth:minHeight:)` to `CompanionWindowView`** — gives AppKit a concrete lower bound without restricting resize behaviour. ✅ Chosen.
- **Switch `NavigationSplitView` style to `.prominentDetail`** — would change UX; not the minimal surgical fix.

### Decision
Add `.frame(minWidth: 600, minHeight: 400)` to `CompanionWindowView` inside the `"stats"` Window scene in `FocusFlowApp.swift`.

### Rationale
The `NavigationSplitView(.balanced)` style negotiates equal column widths, requiring the window to have a concrete total-width bound during the first-responder layout pass (`layoutIfNeeded`). Without `.frame(minWidth:)`, AppKit on macOS 26 Tahoe re-enters `NSPerformVisuallyAtomicChange` from within itself, producing an infinite loop. A 600pt minimum (180pt sidebar + 420pt detail) matches `navigationSplitViewColumnWidth(min: 180)` already declared in `CompanionWindowView`, so layout can always settle.

### Outcomes
- Stats/Companion window opens without hanging.
- `swift build` zero new warnings; all 40 non-screenshot test suites pass.

### Learnings
- Every `Window` scene containing a `NavigationSplitView` on macOS 26 Tahoe **must** carry either `.windowResizability(.contentSize)` or an explicit `.frame(minWidth:minHeight:)` to avoid the layout-loop regression.
- The other two windows (`"session-complete"`, `"coach-intervention"`) already had `.windowResizability(.contentSize)` and were unaffected — this asymmetry was the distinguishing clue.

---

## App Usage Tracking and Companion Analytics Batching

**Category:** Data/Architecture/Performance
**Date:** 2026-04-14
**Status:** Active
**Session(s):** fix/power-usage-reduction

### Problem
`AppUsageTracker` was mutating `AppUsageEntry` every second, and companion analytics views were recomputing expensive aggregates from live query data too frequently. This created unnecessary UI invalidation and elevated power usage.

### Alternatives Considered
- Keep per-second persistence and optimize only rendering paths — reduces some overhead but leaves write churn as the primary trigger.
- Batch writes in memory and flush on cadence while preserving forced flush semantics — minimizes churn without changing persisted model shape. ✅
- Move analytics computation off-view entirely with broader architecture changes — potentially cleaner long term, but too large for a focused reliability/performance fix.

### Decision
- Introduce in-memory usage delta batching in `AppUsageTracker` and flush deltas on persist cadence plus forced flush paths (stop/day rollover).
- Ensure pending deltas are cleared only after successful save; preserve/retry deltas on save failure.
- Add a debounced, coordinator-backed analytics report cache for `TodayStatsView` to avoid repeated `CompanionAnalyticsBuilder` recomputation during rapid updates.

### Rationale
The highest-value fix is reducing model mutation frequency while preserving behavioral correctness. A small coordinator for analytics keeps rendering stable and minimizes expensive recomputation without changing the existing report builder contract.

### Outcomes
- Significantly lower model write frequency from per-second mutations to batched persistence.
- Companion analytics rendering now coalesces rapid updates instead of rebuilding full reports on each transient change.
- Added focused regression coverage for batching, save-failure retry behavior, and analytics debounce/coalescing.

### Learnings
For telemetry-style counters in SwiftData-backed UI, write batching and save-failure-safe buffering are required to keep power usage predictable. View-level caching/debouncing is an effective complement when aggregate computation is non-trivial.

---

**By Category Summary (updated)**

- **UI Decisions** (6): Glass styling, button patterns, list rows, reference-driven design, 3-gate review, prettifyToken preserve-case
- **Architecture Decisions** (5): Complex view extraction, domain-prefix convention, work-intent gate bypass, stats-window minimum frame constraint, app usage + analytics batching
- **Data Decisions** (3): `domain:` AppUsageEntry, confidence formula recalibration, batched usage delta persistence
- **Performance Decisions** (1): Companion analytics debounce/caching + save-failure-safe buffering
- **Process Decisions** (1): AGENT_INSTRUCTIONS workflow constitution
- **Notifications** (0): *Added in future sessions*
