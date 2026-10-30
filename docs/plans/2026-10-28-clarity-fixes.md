# Clarity fixes: a coach that speaks, a line you see, ticks that say what they did

Date: 2026-10-28. Branch: `fix/coach-clarity`.

Three reports from a day of real use (2026-10-28):

1. The coach never asked for a start.
2. The motivating line was nowhere to be seen.
3. A task showed as done, and the goal had moved, without the user knowing why.

## 1. Why the coach stayed silent

Evidence comes from `coach-journal.jsonl` and the calendar for the day. From 10:54 to 17:48 IST the coach was quiet 28 times and showed one start card. It gave three reasons:

| Reason | Count | Cause |
|---|---|---|
| Calendar shows a busy event | 15 | The recurring "Deep work" Focus Time blocks (11:00–13:00, 15:15–16:00) and "Placeholder: Deep Work" counted as meetings. Google Focus Time reaches EventKit as a plain busy event. |
| Screen-share guard | 7 | `ScreenShareGuard` treated any frontmost Slack window as a call. Slack was in front for 34 minutes that day. |
| Outside learned focus windows | 2 | Working as designed. |

Two crashes (15:10 and 15:58, fixed in #60) also left the app down for part of the afternoon.

**Fixes**

- `CalendarAvailability.isFocusBlock(title:)` recognises "deep work", "focus time", "focus block", "heads down", "maker time", "no meetings" and "focus". Those events are not busy. While one covers now and no real meeting overlaps it, `isFocusBlockNow` opens a coach window, even outside the learned hours.
- Slack is no longer a call app. Zoom, Teams and Webex still are.

## 2. The daily reminder line

The quote library (`CoachQuoteLibrary`) was only shown inside coach prompts. Because the coach was silent, it was never seen. "My why", vision and anti-vision were empty.

- `DailyReminder` is pure logic. It picks one line a day, and the line is the same all day and changes tomorrow. A click shows another.
- The pool is built to ground, not decorate. The user asked for "majorly Dan Koe", challenging lines and his questions:
  - **Dan Koe's interrupt questions** (12), for example "What am I avoiding right now by doing what I'm doing?". They alternate day by day with:
  - **challenging lines**:
    - Koe's statements (6)
    - the quotes the user chose on 2026-10-17 (Seneca, Karen Lamb, Rita Emmett, the house lines)
    - the hardest discipline lines (Willink, Gregorek, Clear on trajectory and never missing twice)
    - "1% better daily = 37× in a year"

  Generic advice such as "Clarity about what matters…" is left out. About 58% of the pool is Dan Koe.
- Your own lines (My why, then the first sentence of anti-vision and vision) take every other day once you write some.
- Challenger house lines are for Challenger only.
- Source for the Dan Koe text: "How to fix your entire life in 1 day", Dan Koe's newsletter (letters.thedankoe.com), 23 Dec 2025. It was checked word for word against the post on 2026-10-28. The lines are also in `CoachQuoteLibrary`, so the coach's prompts and the pause screen use them too. The questions are tagged for drift, spiral and comeback.
- It appears on the popover in every state, at the top of the notch's idle view, and as a card at the top of Today. The card has **Write your own** (it saves to My why, up to five lines).
- `TimerViewModel.dailyReminder(now:offset:)` only reads, so it is safe to call while drawing (see CLAUDE.md, "Never write observed state while drawing").

## 3. Tasks and goals that say what they do

What happened: the tour created a task titled "3 problems solved", linked to the goal with amount 3. Sixteen seconds later a click on its bare circle logged +3 to the goal and marked the task done. A later "−1" on the goal tried to undo it.

Problems:

- The title read as a finished state, not a to-do.
- One unlabelled circle logged everything at once, with no feedback and no undo.
- You could not log 1 of 3.
- In the popover, the task picked for the next block had a blue ✓, which looked like "done".
- "Today's goal is done" in the hero meant the time target, but read like the tasks.

**Design**

- A **counted task** is linked to a key result and has an amount above 1. It shows a ring with a plus and "1 of 3". Each click logs one `GoalProgressEntry` (tagged with `taskID`). The task is done when the count reaches its amount. Right-click offers **Take back 1** and **Mark all N done**.
- A **one-off task** keeps the round tick. Its caption says what ticking does ("Counts 1 toward SQL"). Once done, it says what it did ("Logged 3 to SQL").
- Every tick or +1 shows a **receipt** for 6 seconds, with **Undo**. Example: "+1 Problems solved · today 1 of 3 · goal 4 of 40". The receipt shows on Today, the popover, the end-of-block window and the notch.
- Counted tasks are named for what you count ("Problems solved", "LeetCode questions"). `DailyLever.taskTitle` and the tour both use this name.
- The end-of-block window asks "How many did you do?" with − and + for a counted block task.
- The popover marks the next block's task with a **Next block** tag, never a check mark.
- The hero says "Own-work time target reached", not "Today's goal is done".

**Data**

The model has two new optional columns, so the change uses a lightweight migration:

- `DailyTask.loggedAmount`
- `GoalProgressEntry.taskID`

A task ticked by an older build has one entry, found through `progressEntryID`. The first change to that task adopts the entry: it sets `taskID` and fills `loggedAmount`. A −1 then reduces that entry.

## Code

- `Services/CalendarService.swift`: focus blocks.
- `Services/ScreenShareGuard.swift`: Slack removed.
- `Services/Coach/DailyReminder.swift`, `Views/Components/DailyReminderView.swift`.
- `Services/Goals/DailyTasks.swift`: `DailyTaskReceipt`.
- `TimerViewModel`: `stepDailyTask`, `advanceDailyTask`, `undoDailyTaskReceipt`, `dailyReminder`, `setReminderLines`.
- `Views/Goals/DailyTasksSection.swift`: `DailyTaskControl`, `DailyTaskCounterButton`, `DailyTaskCountText`, `DailyTaskReceiptBanner`.
- Tests: `ClarityFixesTests`, plus `CoachV2FlowTests.testCalendarFocusBlockOpensAWindowInsteadOfSilencingTheCoach` and `ScreenShareGuardTests.testSlackIsNotTreatedAsAScreenShare`.

## 4. One thing tracked, one truth per goal (evening review)

A popover screenshot from the same evening showed four numbers that disagreed:

| Surface | Showed | Counted |
|---|---|---|
| Ring | "Focus today 26m of 2h 3…" | Every block. No project was marked Work, so the Office block counted. |
| Footer | "26m tracked · 0m on your #1 · 0% own work" | Learning (#1) only. |
| Lever | "Problems Solved: 2 today" | Goal entries today (+3, −1) against a pace that had risen to 4. |
| Tasks | "Done", full green bar | The one accidental tick, 3 of 3. |

**Decisions**

- **The goal tracks your ★ #1 project.** `GoalDataBuilder.goalScope` returns the #1 project once one is ranked, else own work once a project is marked Work, else every block. The ring, the notch, the coach's pace, Today's hero, the streaks and History all use it.
  - The ring is labelled "★ Learning".
  - Time on other projects shows as its own line ("26m on other projects today"), so the honest total in the footer never contradicts the ring.
- **A task for a key result is today's commitment.** `DailyTaskPlanner.reconcile` applies to every lever surface:
  - A done task removes the lever, even if the pace has since risen.
  - An open counted task replaces the lever text with its counter ("Problems solved: 1 of 3 today").
  - The popover's goal field picks that task, so the block's end asks "How many did you do?".
- **The hero states where you stand, not what to do next.** It shows "YOUR #1 TODAY · 2h 30m to go" and the pace. The next step lives once, in "Goal for this block". The ring says "of 2h30", so it is no longer cut off.
- **No bare "Done".** A one-task day reads "1 of 1 done".
- **No "Plan for later" in the idle popover.** Opening it is a moment to start. Planning a time stays in the coach's plan card, where it is asked for.
