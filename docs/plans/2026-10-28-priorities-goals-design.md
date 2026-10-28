# Priorities, goals and the honest breakdown

Date: 2026-10-28 · Status: building · Builds on Coach v4/v5 (`2026-10-28-coach-v4-start-first-design.md`, `2026-10-28-coach-v5-learning-engine-design.md`)

## The ask, in the user's words
> "If I even see that I was in focus for 10 hours, but in my actual project learning … the breakdown should clearly state that I just spent around 1 hour in the actual personal focus session. It keeps me honest."
>
> "My goal could be … the deadline to apply for a job is one month from now. So I have to complete 60 questions in LeetCode, 10 questions in SQL. Then reach out for referral, apply for job … it tracks that I am on timelines or I am not."
>
> "Most of the time I am deciding the goals but there's no way for me to track them and visually see what I should have been doing and what I am doing."

## 1. Build or reuse?

| Option | What it does well | Why not for this |
|---|---|---|
| Super Productivity (MIT, Electron) | Projects, tasks, time tracking, Pomodoro, work log | A second app. It is not native, and it has no link to FocusFlow's sessions or coach. Its goals are task lists with no deadline pacing. |
| solidtime / Kimai (AGPL, self-hosted web) | Team timesheets and invoicing | Server-based and team-oriented. They have no goals and no focus coaching. |
| ActivityWatch | App usage | FocusFlow already has an app-usage tracker. |

**Decision: build it natively.** The value is having one place where a focus block, the project's priority, and the goal's progress are the same data. No open-source tool does that, and bolting one on would split the data. We reuse their ideas: Super Productivity's work log, and OKR-style key results with deadline pacing.

## 2. What the research says

- **Monitoring progress works, especially when it is recorded.** A meta-analysis of 138 RCTs (N = 19,951) found that prompting progress monitoring improved goal attainment, d = 0.40. The effect was larger when progress was physically recorded or made visible (Harkin et al., 2016, *Psychol. Bull.* 142(2)). So progress is logged as data (+1 entries), and the gap between "should be" and "is" is drawn, not just stated.
- **A clear hierarchy beats many equal goals.** Dan Koe's "How to fix your entire life in 1 day" (2026) uses a hierarchy:
  1. **anti-vision**: the life you refuse to live
  2. **vision**
  3. **1-year goal**: the one mission
  4. **1-month project**: the "boss fight" with a deliverable
  5. **daily levers**: 2–3 actions tomorrow
  6. **constraints**: the rules

  It also asks: "If the last two hours were recorded, what would they say you want?" The honest breakdown is that recording.
- **Proximal subgoals and adaptive goals** (from v4/v5): a 30-day goal becomes a per-day rate ("2 LeetCode a day"), recomputed from the remaining work and the days left.
- **Implementation intentions** (from v3): daily levers become the coach's start target.

## 3. Design

### 3.1 Projects get a priority, a kind and a time target
New optional fields on `Project`. They are nullable columns, so they need no migration.
- **`priorityRank`**: 1 is the top. Unranked projects come after the ranked ones.
- **`areaRaw`**: Personal, Learning, Work or Other. Personal and Learning are your own work; Work is the job.
- **`dailyTargetMinutes`** and **`targetWeekdaysOnly`**: for example Learning 4 h every day, Office 3 h on weekdays.
- **`purpose`**: one line on why it matters.

### 3.2 Goals with key results and deadline pacing
- **`ProjectGoal`**: title, project, start, deadline, status (active, done, dropped), and "boss fight" (the month's main goal).
- **`GoalKeyResult`**: a count ("60 LeetCode questions") or a checkbox ("Ask for 3 referrals" can be a count of 3; "Apply" is a checkbox).
- **`GoalProgressEntry`**: amount, time, optional session. A key result's progress is the sum of its entries, so progress has a history and the pace chart can be drawn.
- **Pace** (`GoalPacing`, pure):
  - `expected = target × elapsed / duration`
  - status from done vs expected: **ahead**, **on track** (≥ 90% of expected), **behind** or **overdue**
  - `needed per day = remaining / days left`
  - the projected finish from the rate so far
- A goal's progress is the mean progress of its key results. Its status comes from the same comparison.

### 3.3 The honest breakdown (`PriorityAllocation`, pure)
- **Each day:** time per project (splits included) against each project's target, in priority order.
- **A one-line verdict:** "6h 40m tracked · 55m on Learning, your #1 (target 4h) · 14% your own work".
- **"Your own work"** is the Personal + Learning share of the day.

### 3.4 Drift report: said vs did (`DriftReport`, pure)
- **Over 7 days:** each project's average per day against its target.
- **Lines:** the biggest gap, and a "your #1 got N% of its time" line.
- **Chart:** your own work as a share of each day.

### 3.5 Direction and daily levers (Dan Koe)
- **Direction card:**
  - **Fields:** anti-vision, vision, 1-year goal and constraints. They are stored on `AppSettings` as optional text.
  - **Boss fight:** the active goal flagged as this month's boss fight is shown with them.
- **Today's levers** (`DailyLevers`, pure): up to 3 actions taken from the key results furthest behind pace, for example "2 LeetCode questions (need 2.1/day)". The coach uses the first lever's project as its start target when you haven't set weekly priorities.

### 3.6 Surfaces
- **Projects form:** redesigned in sections:
  - Identity
  - Priority and time: kind, rank, daily target
  - Why
  - Goal: deadline and key results
  - Focus protection: blocking and coach settings, collapsed
- **Projects list:** sorted by rank, with a rank badge and today-vs-target bars. The detail adds the goal card.
- **Goals tab (new):** the direction card, today's levers, and active goal cards. Each card shows the progress bar with an ideal marker, the key results with +1 and checkboxes, and a pace chart of actual vs ideal.
- **Today:** "Where today went" breakdown and the honesty line.
- **Insights:** the drift report.
- **Session complete:** "Progress on your goal": +1 on the session project's key results, linked to the session.

## 4. Not in this change
- Calendar meeting import into Office time. The user asked to skip it for now.
- Recurring and weekly goals.
- Sync.
