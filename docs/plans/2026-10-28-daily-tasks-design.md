# Daily tasks: plan the day, tick it off, feed the goal

Date: 2026-10-28. Branch: `feature/daily-tasks` (stacked on `feature/onboarding`).

## 1. Problem

You can plan *time* (daily target, planned start) and *outcomes* (goals, key results). You cannot plan the *day's to-dos* and see "3 of 5 done". The end-of-block window logs wins as free text ("one per line"). Nothing counts that text, so it never reaches a goal, the coach or the reports.

Existing pieces, and why each one is not enough on its own:

| Piece | What it is | Gap |
|---|---|---|
| `WeeklyPriority` | Up to 3 per week, in Settings | Weekly, not daily; few |
| `PlannedBlock` | A start time for the daily plan | Time, not tasks |
| Session intent | One line per block | Not a list; nothing to tick |
| Carry-forward note | Free text after a block | Not counted |
| Reminders link | Apple Reminders, optional | Needs Reminders, no daily count |

## 2. Design

A **daily task** is one to-do for one day. It can be linked to a project and to a goal's key result.

- **Ticking a linked task logs goal progress.** It adds a `GoalProgressEntry` of the task's amount. Unticking deletes that entry. The goal pace and today's lever stay true.
- **Add today's lever as a task.** The levers ("3 LeetCode questions") are offered as one-tap suggestions with the link and the amount set, so the plan and the goal stay in step.
- **Carry over.** Unfinished tasks from the last planned day (within 7 days) are offered as "Bring 2 over". They are copied, not moved, so yesterday's count stays honest.
- **Pick a task for a block.** The popover's "Goal for this block" offers today's open tasks. Picking one fills the intent. The block remembers the task. When the block ends, that task is shown ticked in the end-of-block window, ready to confirm.
- **The end-of-block window logs against the plan.** A "Tasks" section lists today's open tasks. Tick the ones you finished in this block, or add one you did. Ticks are credited to the session. The free-text note stays, for anything else.
- **Everywhere it matters:**

| Surface | What it shows |
|---|---|
| Today tab | The full list: add, tick, link, reorder by drag, delete. Lever suggestions, carry-over, and 7 days of planned against done. |
| Popover | "Tasks 2 of 5", the next open task, and one tick. |
| Notch, idle | "2 of 5 tasks · Next: …" with a tick. |
| Notch, in a block | The block's task with a tick. |
| Insights → drift | The week's task completion ("12 planned, 7 done · 58%"). |

## 3. Model

`DailyTask` is a new SwiftData model, so the lightweight migration adds the table. Fields:

- `id`, `title`, `day` (start of day), `order`
- `isDone`, `doneAt`
- `projectID?`, `keyResultID?`, `amount?` (progress to log; nil = 1)
- `progressEntryID?` (the entry made on tick, removed on untick)
- `sessionID?` (the block it was ticked in)
- `carriedFromID?`
- `createdAt`

The session remembers its task through `FocusSession.taskID?`, an optional column.

## 4. Code

- `Services/Goals/DailyTasks.swift`: pure.
  - `DailyTaskPlanner`: stats, history, carry-over candidates, next task, lever suggestions.
  - `DailyTaskStats`: the counts for one day.
- `TimerViewModel`: the store operations.
  - `addDailyTask`, `setDailyTask(_:done:)`, `deleteDailyTask`, `carryOverDailyTasks`, `moveDailyTasks`
  - `todayTasks()` and `dailyTaskStats()`
- Views:
  - `Views/Goals/DailyTasksSection.swift`: the Today tab section and the row.
  - `Views/Goals/SessionTasksSection.swift`: the end-of-block section.
  - The popover strip and the notch lines reuse the VM helpers.
- Tests: `DailyTaskTests` covers the planner, ticking and unticking with goal entries, carry-over, and lever suggestions. Captures go through `UIEvidenceCaptureTests`.
