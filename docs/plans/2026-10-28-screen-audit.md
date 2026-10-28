# Screen audit: one loop, no layers

Date: 2026-10-28. Branch: `feature/daily-tasks`.

Four reviewers checked every screen in light and dark: the popover and notch; the companion window; the block-end window and coach screens; Settings and the tour. The screens were built in layers: coach v2, v3, v4 and v5, then goals, then tasks. Each layer kept the one before it. This document is the single set of decisions every surface follows.

## The loop every screen serves

**Plan → Start → Log → Reflect.**

- **Plan.** Three things plan the day:
  - ranked projects,
  - goals with key results and a deadline,
  - today's tasks.

  Today's lever comes from the goals. It is suggested as a task.
- **Start.** One way to start: 5 · 15 · 25 minutes. The size the coach suggests is preselected.
- **Log.** You log by ticking tasks and adding +1 to a key result. You rate the outcome when the block ends. Nothing is free text that the app then ignores.
- **Reflect.** Reflection shows own work against the goal, said vs did, and goal pace.

## Shared decisions

| Topic | Decision |
|---|---|
| Daily goal progress | **Own work everywhere.** Every streak, chain, "goal met" mark, popover ring and footer uses own-work time once any project is marked Work: `goalProgressSeconds` in the VM, own-work samples in the companion. |
| Honest total | Wherever a single "today" total appears, show the verdict instead ("3h 50m tracked · 50m on your #1 · 22% own work"). |
| Weekly priorities | **Retired** as a planning layer. They are kept in the store and no longer drive anything. Retired UI: the Settings section, the Insights section, the popover "Counts toward" menu, the coach target, the weekly invite, and the Today branch. |
| Levers | Shown in one place per screen. The Today tab shows them as task chips titled "Today's levers". The popover and notch show them as the hero. The Goals tab shows them as key-result captions only. |
| Block sizes | 5 · 15 · 25 (+ Custom in the popover). The coach's learned suggestion (`startLadderRecommendation`) is preselected on every surface. |
| Vocabulary | Use the same words on every surface: **Finish** (end a running block and log), **Keep going**, **Break 5 min**, **Done for today**, **Log this block**, **Not now, because…**. |
| What a start is about | The next task, else the lever, else the #1 project. `CoachStartTarget.taskTitle` carries it. |
| ⌃⌥Space | With a next step (task or lever), it starts that at the learned size. Otherwise it starts the starter block, which finds the step. |
| Block-end logging | Tasks and goal progress save as soon as you tap. Mood and the free-text note are removed. Ticked tasks become the session's achievement (history title, Calendar). "Next step" creates an open task. |
| Coach settings | Keep only what v5 does not learn: style, the limits (quiet hours, daily cap, notifications), the on/off switches, and the during-block options. Dead and conflicting knobs are removed. |

## Ownership while fixing

- **Popover and notch:** `Views/MenuBar/*`, `Views/Notch/*`.
- **Companion:**
  - `Views/Companion/{TodayView,ProjectsListView,HistoryView,InsightsView,CompanionComponents,CoachInsightsSections,CompanionWindowView}.swift`
  - `Views/Goals/{GoalsView,GoalComponents,GoalFormView,DriftReportSection,DailyTasksSection}.swift`
  - `ProjectFormView.swift`
- **Block-end and coach:**
  - `Views/SessionCompleteWindow.swift`, `Views/Goals/SessionTasksSection.swift`
  - `Views/CoachPanel/*`, `Views/PauseScreen/*`, `Views/Components/FocusCoachReasonChipSheet.swift`
  - `Services/Coach/{CoachMessageComposer,CoachPanelPresentation,CoachStartFirst}.swift`
- **Settings, tour, view model, shared logic:**
  - `Views/Companion/SettingsView.swift`, `Views/Settings/*`, `Views/Onboarding/*`, `Services/Onboarding/*`
  - `ViewModels/TimerViewModel.swift`, `Services/Goals/{GoalTracking,GoalDataBuilder,DailyTasks}.swift`
