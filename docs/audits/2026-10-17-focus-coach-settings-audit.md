# Focus Coach, Settings UX & Bug Audit — 2026-10-17

Scope: Focus Coach (engine → policy → planner → UI → back to `TimerViewModel`), coach copy/prompts, Settings screen UX, and general bugs.
Method: three Haiku 5.5 agents collected call graphs, UI inventory and diff/docs; Opus 5.5 verified the high-severity items against source and wrote the analysis.
Build: `swift build` passes with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the default `xcode-select` points at CommandLineTools, which lacks `actool`).
Tests: 51 swift-testing tests pass. XCTest has **1 failure** and the process **crashes** (see B10, B11).

Paths are relative to `Sources/FocusFlow/` unless noted. ✅ = verified by reading the source directly.

---

## 1. How the coach works today (call graph)

### 1.1 In-session drift (Chain A)

```
Timer 1s tick ─ TimerViewModel.tick()                        ViewModels/TimerViewModel.swift:1840
  └ every 30 ticks while .focusing                           TimerViewModel.swift:1863-1875
     └ FocusCoachEngine.tick()                               Services/FocusCoachEngine.swift:244
        ├ FocusCoachRiskScorer.score(signals, profile)       Services/FocusCoachRiskScorer.swift:87
        │    signals fed by AppUsageTracker.feedCoachSignals Services/AppUsageTracker.swift:688 → Engine:224
        ├ FocusCoachInterventionPolicy.decide(...)           Services/FocusCoachInterventionPolicy.swift:86
        │    gates: snooze :93 · budget :99 · 90s cooldown :111 · risk ladder :124-148
        └ returns FocusCoachDecision
  └ routeCoachDecision(_:)                                   TimerViewModel.swift:2590
     ├ suppress: release window / screen share              TimerViewModel.swift:2592-2597, 2521
     ├ FocusCoachInterventionPlanner.routeActiveDecision     Services/FocusCoachInterventionPlanner.swift:130
     ├ quick  → currentCoachQuickPromptDecision → MenuBarPopoverView:262 FocusCoachQuickPromptView
     └ strong → openCoachInterventionWindow()                TimerViewModel.swift:2672 → FocusFlowApp.swift:196
                 → CoachInterventionWindowView               Views/CoachInterventionWindowView.swift:3
                    → FocusCoachMessageBuilder.build         Services/FocusCoachMessageBuilder.swift:74
  user action ─ handleCoachAction(_:skipReason:)             TimerViewModel.swift:2244
```

### 1.2 Idle starter, the "get them to start" path (Chain B)

```
AppUsageTracker.tick() idle branch                           Services/AppUsageTracker.swift:505-525
  └ evaluateIdleStarterIntervention(...)                     TimerViewModel.swift:2683
     ├ guards: idle, release, screen share, settings, cooldown   :2689-2722
     ├ FocusCoachOpportunityModel.idleStarterContext         Services/FocusCoachOpportunityModel.swift:98
     ├ WorkIntentWindowDetector.evaluate                     Services/FocusCoachInterventionPlanner.swift:35
     ├ OutsideSessionSignalScorer.scoreWorkIntent/scoreDrift Services/OutsideSessionSignalScorer.swift:59, 86
     ├ FocusCoachGuardianAdvisor.guardianState               Services/FocusCoachGuardianAdvisor.swift:102
     ├ Planner.routeIdleStarter                              Services/FocusCoachInterventionPlanner.swift:214
     └ surface (pick one):
         strong window   TimerViewModel.swift:2897-2928
         notification    TimerViewModel.swift:2931-2946 → NotificationService.swift:216  (no tap handler)
         popover card    TimerViewModel.swift:2948-2959
  user action ─ .startFocusNow → startFocus()                TimerViewModel.swift:2269-2277 → :751
```

### 1.3 Every path that starts a session from a coach prompt

| # | Surface | Path | Notes |
|---|---|---|---|
| S1 | Window primary "Start Focus Now" | `CoachInterventionWindowView.swift:200-208` → `TimerViewModel.swift:2269` → `startFocus()` | Idle starter only |
| S2 | Window primary "Start 5m rescue block" | `TimerViewModel.swift:2252-2259` → `abandonSession()` → `startFocus()` | **Destroys the running session (B1)** |
| S3 | Popover quick prompt buttons | `FocusCoachQuickPromptView.swift:80-116` → `MenuBarPopoverView.swift:265` → `:2244` | Same actions as S1/S2 |
| S4 | macOS notification "Focus check-in" | `TimerViewModel.swift:2933` | **No path. Tapping does nothing (B4)** |

---

## 2. Bugs, ranked

### P0: data loss or broken core loop

**B1 ✅ The in-session "rescue block" deletes the user's real session.**
In-session strong and high-risk prompts offer `[.returnNow, .cleanRestart5m, .snooze10m]` (`FocusCoachInterventionPolicy.swift:139, 145`). The window has no "Return now" button (`CoachInterventionWindowView.swift:197-271`), so its primary button becomes `.cleanRestart5m` (`:42-45`). That calls `abandonSession()` (`TimerViewModel.swift:2256`), which runs `modelContext?.delete(session)` (`:1589`). Example: 22 minutes of logged focus are erased when the user clicks the button the coach pushes most. It also leaves `selectedMinutes = 5` in place for all later sessions (`:2257`).
*Fix:* rescue should `stop()` (save as incomplete) or pause and resume, never abandon. Add a "Back to work" (`.returnNow`) primary button in the window. Restore `selectedMinutes` afterwards.

**B2 ✅ Snooze duration is overwritten.**
`snooze(minutes:)` sets `snoozedUntil` (`FocusCoachEngine.swift:351-353`), then calls `recordInterventionOutcome(.snoozed)`. That call resets it to 10 or 20 minutes whenever any attempt exists (`:337-341`). "2 hours", "Off for today" (90 min, `TimerViewModel.swift:2294`) and the user's Default snooze setting all become 10 minutes. Users get re-nagged after saying "leave me alone."
*Fix:* remove the reassignment in `recordInterventionOutcome`. Let `snooze()` own the duration. Add a test asserting `snoozedUntil ≈ now + requested`.

**B3 ✅ Outcomes are written to the oldest record.**
`SwiftDataCoachStore.attempts` sorts newest-first (`Services/SwiftDataCoachStore.swift:40-43`), but the engine writes to `store.attempts.last` (`FocusCoachEngine.swift:330`). In production every outcome and skip reason lands on the oldest attempt. The in-memory test store appends, so tests pass and hide this. The calibration (`CoachPersonalProfile`) and Insights effectiveness learn from corrupted data.
*Fix:* use `.first`, or better, have `recordDeliveredIntervention` return the attempt id and resolve by id.

**B4 ✅ Coach notifications are dead ends.**
`sendGenericNotification(title: "Focus check-in")` (`TimerViewModel.swift:2933`) has no `UNUserNotificationCenterDelegate` anywhere in `Sources/` (grep is empty), so there is no action button and no tap routing. It is the main outside-app start nudge, and it cannot start a session.
*Fix:* register a `UNNotificationCategory` with "Start 25m" and "Snooze" actions, and add a delegate in `NotificationService` that calls `handleCoachAction`.

**B5 ✅ Start failures are invisible.**
`handleCoachAction` calls `startFocus()` and then `closePopover()` unconditionally (`TimerViewModel.swift:2258-2259, 2276-2277`). The only place `startError` is shown is the popover banner (`MenuBarPopoverView.swift:44`), which was just closed. If a start fails (overtime, not idle), the user clicked "Start" and nothing happened.
*Fix:* make `startFocus()` return `Bool`, keep the surface open on failure, and show the error in the window.

### P1: wrong behaviour

| # | Bug | Evidence |
|---|---|---|
| B6 ✅ | Pre-session "Mental effort" copy is the opposite of what the code does. It says higher effort means a gentler ramp-up, but higher resistance raises the multiplier and **lowers** the thresholds (more nagging). | `FocusCoachPreSessionCard.swift:140` vs `CoachPersonalProfile.swift:26-31, 107-112` |
| B7 ✅ | Undo of "planned" classification can never match: it records the bare key and removes a `domain:`/`app:`-prefixed key. | `TimerViewModel.swift:2200-2203` vs `:2218-2226`; `IdleDistractionCatalog.swift:23-31` |
| B8 | `switchProject` creates a new session but never calls `coachEngine.startSession`, so coach stats attach to the old session id. | `TimerViewModel.swift:839-900`; Engine `startSession` called only at `:639, :814` |
| B9 | The in-session drift reason sheet has no host. The flag is set mid-session (`TimerViewModel.swift:1877-1881`) but only `SessionCompleteWindow` renders it (`:186, 700`). | — |
| B10 ✅ | New uncommitted test `testCheckDayRolloverResetsStatsOnNewDay` fails. It never moves `currentDay` back to yesterday, so the function correctly does nothing. This is a test bug; the production change looks right. | `Tests/FocusFlowTests/TimerCompletionFlowTests.swift:1191-1193` |
| B11 ✅ | The XCTest process crashes with `ModelContext.save() called after its ModelContainer has been deallocated` (signal 5). Suites after `TimerCompletionFlowTests` do not run. A test (or a leftover timer) outlives its container. | `swift test` output |
| B12 | Dismissing the window with X records no outcome; popover dismiss does. This skews effectiveness stats. | `CoachInterventionWindowView.swift:486-489` → `TimerViewModel.swift:2337` vs `:2320` |
| B13 | "Mark off-duty for now" button is permanently disabled: no policy or planner ever emits `.markOffDuty`. | `CoachInterventionWindowView.swift:248-257`; `FocusCoachInterventionPolicy.swift:131-145`; `FocusCoachInterventionPlanner.swift:256-259` |
| B14 | The "Snooze Coach" chip in the reason sheet only hides the sheet; the engine is not snoozed. | `FocusCoachReasonChipSheet.swift:93-95` → `SessionCompleteWindow.swift:521, 860` |
| B15 | `.startFocusNow` silently overwrites the user's chosen duration with the recommended minutes. | `TimerViewModel.swift:2273-2275` |
| B16 | Over-planning detection treats any bundle id containing "openai" or "anthropic" as drift. That penalises legitimate AI-assisted work. | `TimerViewModel.swift:2769-2774` |

### P2: dead code and drift from design

- Six `coach*PromptSeconds` / `coach*EscalationSeconds` settings are only clamped, never read (`Models/AppSettings.swift:45-50`, `FocusCoachSettingsNormalizer.swift:10-20`).
- `autoStartBreak`, `autoStartNextSession`: no readers. The Settings banner apologises for them (`SettingsView.swift:190`).
- `pendingBlockingRecommendation` is written and never read (`FocusCoachEngine.swift:55, 428`). The whole `FocusCoachBlockingRecommendationEngine` copy (`:215-222`) is never surfaced.
- Policy `softStrip` messages are dropped by the planner (`FocusCoachInterventionPolicy.swift:101-118` → `FocusCoachInterventionPlanner.swift:89`).
- Strip `onTap` is not wired (`MenuBarPopoverView.swift:253`).
- 20 motivational quotes are built on every window open and never shown (`FocusCoachMessageBuilder.swift:78`, `CoachInterventionWindowView.swift:112`).
- Unused APIs: `GuardianAdvisor.releaseDuration`, `AnomalyClassifier.interruptionKind`, `BRE.allowRecommendation/recordBreakOverrunCorrelation/hasRisk/projectScopedRisk`, `DriftMemoryStore.sessionScopedAllowance/removeAvoidant/pruneOldEntries` (the drift memory is never pruned), `Engine.updateStartDelay`.
- `startFocus` 300 s guard is unreachable (`TimerViewModel.swift:764` vs `:154-156`).
- Empty `else {}` at `TimerViewModel.swift:2927-2928`.
- Design doc `2026-03-25-notification-first-coach-escalation-design.md:50` lists three settings that do not exist in code.

---

## 3. Prompts & copy

Problems:
1. **Five voices for one coach.** Titles come from four layers that override each other: `FocusCoachMessageBuilder` headlines, `FocusCoachPresentationMapper` ("Guardrail Check", "Planned or Drift?"), `CoachInterventionWindowView` fallbacks ("Off-plan right now?", "Let's start focus now"), policy messages ("Sustained mismatch detected…"), and `TimerViewModel.contextualMessage` (`:2480-2496`). The user sees inconsistent tone across surfaces.
2. **Jargon and blame.** "Guardrail Check", "Sustained off-plan behavior detected. Choose a corrective action.", "Restart friction increases with idle drift…recover trajectory", "Drift Alert". This is clinical and accusatory, which raises the abandon rate (people dismiss shame-based nudges).
3. **Too many choices.** The strong window shows up to 6 actions plus a 5-option snooze panel plus 9 skip reasons. A start nudge should have **one** obvious action.
4. **False specifics.** "One 25-minute block changes the whole day" (`FocusCoachMessageBuilder.swift:214`) is hardcoded even when the recommended block is 10 minutes.
5. **"ChatGPT loop… looks like over-planning"** (`:244`) is a judgement based only on the app name.

Proposed voice: calm, specific, one verb. Use the project name and the real duration. Examples:

| Situation | Title | Body | Primary | Secondary |
|---|---|---|---|---|
| Idle, project known | Ready for {Project}? | {N} minutes now keeps today on track ({pct}% of goal). | **Start {N}m** | Not now ▾ |
| Idle, no project | Start a focus block? | Pick what you're working on; I'll keep it short ({N}m). | **Choose & start** | Not now ▾ |
| In-session drift (quick) | Still on {Project}? | You've been in {App} for {M}m. | **Back to it** | It's part of the work |
| In-session drift (strong) | Let's get back to {Project} | {M}m in {App} this block. Your {elapsed}m so far is saved. | **Back to it** | Pause · End block |
| Break overrun | Break's {M}m over | Your progress is saved. | **Start next block** | 5 more min · Done for today |

"Not now ▾" expands to: 15 min · 1 hour · Done for today. Skip reasons stay optional, in a single row of chips after dismissal, not before.

Single source: move all copy into `FocusCoachMessageBuilder` and delete the fallbacks in `PresentationMapper`, `CoachInterventionWindowView` and `TimerViewModel.contextualMessage`.

---

## 4. How the coach should work: "start-first" loop

The goal is a started session, not a classified distraction. Proposed state machine:

```
          ┌──────────── release (Done for today / meeting / screen share) ─────────┐
          ▼                                                                         │
 IDLE ──(work-intent + idle ≥ X min)──▶ NUDGE ──Start──▶ FOCUSING ──drift──▶ CHECK-IN
  ▲         ▲                            │ Not now                 ▲  Back to it │
  │         └─── snooze (honoured) ◀─────┘                         └─────────────┘
  └──────── session end / done for today ◀── FOCUSING ──End──▶ REFLECT (reason chips, optional)
```

Rules:
1. **One nudge, one tap to start.** Each nudge carries a concrete `StartPlan {project, minutes}`. The primary action calls `startFocus(plan)` and returns success or failure. The window stays open on failure.
2. **Notifications are actionable.** `UNNotificationAction` "Start {N}m" works from Notification Center without opening the app (B4).
3. **Escalation ladder is time-boxed and honours snooze.** Popover badge, then notification, then window (max 1 per hour). Idle path must read the same `snoozedUntil` as the session path (today the idle path uses a separate 300 s cooldown, `TimerViewModel.swift:2356-2394`).
4. **Never destroy work.** In-session recovery = resume/refocus, with "End block" saving the session as incomplete. Remove `.cleanRestart5m` from in-session surfaces (B1).
5. **Learn only from clean data.** Fix B3 and B12 first, otherwise calibration in `CoachPersonalProfile` trains on wrong outcomes.
6. **Release beats everything.** "Done for today" sets a release window until next work-hours start, visible in the popover footer with an "Undo" link.

---

## 5. Settings screen UX

Current state (`Views/Companion/SettingsView.swift`, 1839 lines): **9 flat sections, 37 control sites**, ordered Durations · Behavior · Sound & Notifications · Goals · Blocking · Integrations · Focus Coach · About · Permission Health.

Problems:
1. **The Focus Coach section alone has 14 controls**, nested 8 levels deep (`:1229-1660`). Most are implementation knobs ("Strong prompts per session", "Bring app to front on strong prompt", "Open popover with strong prompt", "Allow Skip this check").
2. **A debug panel ships to users**: "Outside-session signal debug" (`:1455-1481`).
3. **Overlapping toggles.** "Idle nudge notifications" (`antiProcrastinationEnabled`) actually gates the whole idle starter path (`TimerViewModel.swift:2709`), not just notifications. "Idle starter intervention card" is a child of it.
4. **Permissions are spread across 3 places.** Notifications: banner `:346` plus health row `:513`. Calendar and Reminders: badge, inline button and health row. Automation and Screen Recording: domain block plus health row. The URL literals are duplicated (`:838/1687`, `:997/1693`).
5. **About sits above Permission Health**, so the most actionable section is last.
6. **Walls of text.** Eleven captions run 99 to 302 characters (`:1241, 1532, 1548, 1774-1780`).
7. **Apology banner** for hidden auto-start controls (`:190`).
8. **Two sleep steppers** whose difference users can't tell ("Resume if asleep less than" vs "Wake recovery threshold", `:245, :281`).
9. `launchAtLogin` is stored, never read back from `SMAppService`, so it can drift from reality.

Proposed structure (5 groups, about 14 controls visible by default):

| Group | Controls |
|---|---|
| **Timer** | Focus / Short break / Long break / Sessions before long break · Daily goal · Completion sound |
| **Focus Coach** | Coach on/off · **Style:** Gentle / Balanced / Strict (maps to mode, budgets, auto-open, bring-to-front, snooze) · Remind me to start after [5] min idle · Ask why sessions end early |
| **Blocking** | Manage profiles… |
| **Integrations & Permissions** | One row per item (Notifications, Calendar, Reminders, Browser domains, Screen Recording): status dot + one action. Calendar/Reminders pickers appear inline only when connected |
| **General** | Launch at login (read from `SMAppService.mainApp.status`) · Sleep: "Pause on sleep; auto-resume if back within [N] min" (one control) · About |

Hidden behind an "Advanced" disclosure (or ⌥-click): prompt budgets, strong-prompt caps, skip action, collect raw domains. The debug panel moves behind `#if DEBUG`.

Implementation: split `SettingsView.swift` into `Settings/TimerSection.swift`, `CoachSection.swift`, `PermissionsSection.swift`, etc. (also fixes type-check slowness). Add a `CoachStyle` enum that writes the underlying fields so existing logic keeps working.

---

## 6. Suggested fix order

1. **P0 data integrity:** B1, B2, B3 (+ tests that use a SwiftData-backed store, not `InMemoryCoachStore`).
2. **Start path:** B4 (actionable notifications), B5 (visible failure), B15.
3. **Test health:** B10, B11, so the suite runs end to end.
4. **Copy consolidation** (section 3) and remove dead actions (B13, B14).
5. **Settings restructure** (section 5).
6. **Dead code sweep** (P2 list).

---

## 7. Addendum: coach effectiveness on real data

The local store (`~/Library/Application Support/FocusFlow/FocusFlow.store`, read from a copy) shows **1,513 strong prompts and 9 starts within 10 minutes (0.6%)**, mostly fired 09:00–18:59 while sessions start 11–12 and 22–00. Work tools (Slack, Claude, Atlassian, GitHub) are flagged as distractions. Root causes W1–W6, T1–T4, L1–L4 and the redesign are in `docs/plans/2026-10-17-coach-v2-learning-motivation-design.md`.
