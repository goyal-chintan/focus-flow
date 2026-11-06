# Coach v8: from focus timer to life coach

Date: 2026-11-06 · Status: phases 1–2 built, phases 3–5 proposed · Builds on v6 (adapt and speak) and v7 (land and return)

> "The Insights section should have strong recommendations… what are the patterns, what are the
> strongest recommendations, and whether the behaviour is improving or not… If I'm putting more time
> in office calls and not doing anything on the laptop, it should figure it out… is personal time
> planned, or did I just waste the whole weekend where there was no plan… the central place to
> manage my life." Also: "the goal view and the live dashboards should be cleaner", and "Slack is
> important for work but a distraction when I'm on my personal projects."

## 1. Where it stands (live store, 6 Nov 2026)

### What the app can't see

| Need | Today | Evidence |
|---|---|---|
| **What kind of day it is** | No notion of day type anywhere. Out-of-office and all-day calendar events are thrown away. "Weekend" means Mon–Fri targets in one place and Sunday only (en_IN) in another. | `CalendarService.swift:187-239`; `Project.swift:55-59` vs `TimerViewModel.swift:3581` |
| **Leave** | The signal exists but is unused. Office apps (Slack, Zoom, Atlassian, Meet) run 2.5–5 h on normal weekdays and **0 h on 4–6 Nov**, while learning apps (scaler.com, Obsidian) rise to 1–3.2 h | `AppUsageEntry` daily rows |
| **Where the hours went** | App usage is **one row per day per app**: no hour, no project, no idle subtraction. Browser time is counted twice (once for the app, once for the domain). Lock and sleep time used to go to `loginwindow` (151 h in a month until 17 Oct). | `AppUsageEntry.swift:5-11`; `AppUsageTracker.swift:467-478, 675-708` |
| **Switching** | Kept 2 minutes in memory, then lost. Tab switches are not counted at all. | `AppUsageTracker.swift:641-648` |
| **Planned vs unplanned time** | Only 2 `PlannedBlock` rows have ever been made. Two whole weekends (18–19 Oct and 24–25 Oct) have no blocks and no plan. | `ZPLANNEDBLOCK`; sessions |
| **Context-aware distraction** | Slack, Obsidian, Zoom, Arc, Ghostty and others are hard-coded as "never a distraction", and this list **beats your own rules**. Distraction rules have no project. A per-project memory (`projectId\|workMode\|app`) is written but never read. | `DerailerAnalytics.swift:24-30, 72`; `IdleDistractionItem.swift:27-36`; `ContextIntelligenceModels.swift:158-168` |

### What the screens get wrong
- **Insights describes but never advises.** It has 5 sections and more than 25 numbers. Nothing compares this period with the last except derailers, nothing says "do this next", and the "set windows" cards are settings.
- **Coach effectiveness is hidden.** Prompt→start, the coach's advice cards and the coach log are under a collapsed row in Settings → Coach. The advice cards are generic research rules ("Never miss twice"), not drawn from your data.
- **The live surfaces repeat each other.** The popover, the notch and Today each show the goal ring, the lever, the quote, the size ladder and a task counter. The notch alone has about 11 elements. The Today hero shows the daily goal 3 ways.
- **Goals is busy.** A 4-number goal has about 12 controls, pace is said 3 times, and the Daily goal (a setting) sits between the goal cards.
- **There is dead analytics code.** A weekly report (`FocusCoachInsightsBuilder`), `AppUsageRecord` (0 rows) and `TaskIntent` are all written or defined but never read.

## 2. What the research says, and what it means here

| Finding | Evidence | Design consequence |
|---|---|---|
| **Monitoring progress improves goal attainment**, more so when progress is recorded and reported | Harkin et al., 2016, *Psychol. Bull.* 142(2): 138 studies, N = 19,951 | Every week ends with a recorded verdict. "Am I improving?" is the first thing on the page, not a chart to decode. |
| **Reflection makes experience count.** Fifteen minutes of reflection at the end of the day raised performance by about 20 % in a field study. | Di Stefano, Gino, Pisano & Staats, "Learning by Thinking" (HBS WP 14-093; summaries report 21–23 %) | A 5-minute **weekly review** ritual: what happened, one change for next week |
| **Personal-informatics tools fail at reflection and action**, not at collection | Li, Dey & Forlizzi, 2010, CHI: the stage model (preparation, collection, integration, reflection, action) | The page must close the loop. Each recommendation has an **Apply** button, and next week it reports whether it worked. |
| **How free time is managed predicts quality of life; how much of it there is does not** | Wang, Kao, Huan & Wu, 2011, *J. Happiness Stud.* 12(4), N = 403 | Weekends and leave days are judged on *planned vs not*, not on hours. "Unplanned and lost" is the pattern to fix. |
| **Consistency builds habits.** One missed day barely matters; repeated misses add up. | Lally et al., 2010, *Eur. J. Soc. Psychol.* (median ≈ 66 days to automaticity) | Show consistency (days with a block), not streaks that reset. Coach "never miss twice". |
| **An active goal suppresses competing goals** | Shah, Friedman & Kruglanski, 2002, *JPSP* 83(6) | Whether an app is a distraction depends on **which goal is active**. Slack competes with Learning but *is* the Office goal. |
| **People draw work–home boundaries differently, and violations hurt** | Kreiner, Hollensbe & Sheep, 2009, *AMJ* 52(4) | Work tools during your own time are boundary violations. The coach names them per context instead of banning apps. |
| **App categories only work per person.** Fixed productive/distracting labels misfire. | RescueTime's own docs (Slack can be a tool for one person and a distraction for another); no peer-reviewed validation of global scores | Labels are per person *and* per context, start from editable defaults, and are learned from your blocks |
| **Fast switching goes with stress and lower productivity** (observational) | Mark et al.: median time on one screen ≈ 40 s in recent datasets | Show switches per hour inside blocks as a focus-quality trend. Never use it as a score to shame. |

## 3. Design

### 3.1 The Day Ledger (the foundation)
One row per day, rebuilt every night and on demand.

| Field | Source |
|---|---|
| `dayType` | **workday · leave · weekend · holiday**. Inferred, and you can override it (below). |
| `planned` | A plan existed before the day began: planned blocks, today's tasks with a time, or a weekly plan for the day |
| `ownMinutes`, `officeMinutes`, `awayMinutes`, `derailMinutes` | The hourly rollup (3.2) plus sessions |
| `targetMinutes` | Your own-work target **for that day type** (3.5) |
| `switchesPerHourInBlocks`, `stretchRate`, `returnMedian` | Rollup, sessions, v7 cycle stats |
| `verdict` | The **plan × outcome 2×2**: *Planned & done* · *Planned, missed* · *Unplanned but did* · *Unplanned & lost* |

**Day-type inference** is rules first, then learned from your labels:
1. If the calendar has an out-of-office or all-day "leave", "holiday" or "OOO" event, the day is leave or a holiday. These events are now *kept* for this; they still don't make you look busy.
2. Saturday and Sunday are weekend. A single `DayType.isWeekend` replaces the three inconsistent rules.
3. A weekday with less than 30 min of office apps by 13:00, with you present, is **leave** with medium confidence. On your data this catches 4–6 Nov and 20 and 29 Oct.
4. Confidence below high gets one quick question (v6): *"No Slack or calls today. On leave?"* The answers are *Leave · Holiday · Working (just quiet) · Sick*. Each answer is a label, and with about 20 labels a naive-Bayes model replaces rule 3.

### 3.2 Activity rollup v2 (what the hours really were)
- Store one **hourly row per (hour, app or domain, context)**, where the context is the running block's project, or none. Each row has seconds in a block and outside, plus **switches** (app *and* domain changes).
- **Away is its own bucket.** No keyboard or mouse input for 5 min or more, a locked screen or sleep go to `away`, not the frontmost app. Elapsed time per tick is capped.
- A domain row replaces its browser's row for that time, so browser time is no longer counted twice.
- **Call time** is camera/mic in use (`AVCaptureDevice` in-use flags, read only; no recording), or a call app frontmost, or a calendar event with a link. The coach can then tell **"in calls"** from **"at the laptop doing nothing"** from **"away"**.
- **Retention:** hourly rows for 90 days, then folded into today's daily rows. Everything stays local. No window titles; domains only with the existing setting.

### 3.3 Apps mean different things in different contexts
Replace the global distraction list with **app roles per context**:

| Context | Slack | Obsidian | scaler.com | YouTube |
|---|---|---|---|---|
| Office block / office hours on a workday | **Tool** | neutral | neutral | Pull |
| Learning block / own-work window | **Pull** | Tool | **Tool** | Pull (a tutorial can be marked as a tool for one block) |
| Leave or weekend, no block | neutral | neutral | neutral | Pull, counted only past your limit |

- **Contexts.** The running block's project. Outside a block, the day type and window: office hours on a workday, an own-work window, or free time.
- **Defaults.** Today's hard-coded needles become **editable default rules**, and your rules always win (this fixes "Ghostty · Strong" being ignored).
- **Three ways it learns, strongest first:**
  1. **You say so.** "Distraction / It's work" now asks *"For which project?"*, defaulting to the block's project, with "everywhere" as an option.
  2. **Your blocks show it.** Minutes in completed, real-work blocks of project P are evidence that the app is a tool for P. Minutes in drift episodes are evidence that it pulls you away. Each (app, context) has a Beta posterior, and an app becomes "Tool for Learning" once P(tool) > 0.8 with 60+ min of evidence. scaler.com already qualifies, with 12.4 h inside Learning blocks.
  3. **The coach asks when it is unsure** (v6 quick question): *"Slack was open in 3 Learning blocks this week. Part of the work, or a pull?"*
- **The per-project memory that already exists** (`projectScopedAllowance`) is read for the first time, and it seeds these posteriors.
- **Settings → Distractions** becomes a table of app × context with the learned role, its evidence ("12 h in Learning blocks"), and an override.

### 3.4 Insights becomes "Your week"
One page answers four questions, in this order:

```
┌ YOUR WEEK · 31 Oct – 6 Nov ············· [This week ▾] ┐
│ Better than your last 4 weeks.                             │
│ 7h 40m own work (avg 5h 10m) · goal met 4 of 7 days        │
├ TREND (this week vs 4-week avg; ▲ better, ▼ worse) ─────────┤
│ Own work ▲+48%  Consistency 6/7 days ▲  Unplanned & lost 1 ▼│
│ Switches/h in blocks 31 ▲  Stretch rate 48% ▼  Return 15m ▲ │
├ DAYS ───────────────────────────────────────────────────────┤
│ Sa ● Su ● Mo ◐ Tu ◐ We ●L Th ●L Fr ●L                      │
│ ● planned & done  ◐ unplanned but did  ○ planned, missed    │
│ ✕ unplanned & lost   L leave   (click a day: its timeline)  │
├ DO THIS NEXT (ranked) ──────────────────────────────────────┤
│ 1 Plan your weekend. 18–19 and 24–25 Oct: 0 blocks.         │
│   31 Oct–1 Nov: 3h 44m. Decide it now.  [Plan Sat + Sun]    │
│ 2 Leave days: aim higher. 4–6 Nov averaged 1h 50m own work  │
│   with no office load. Set a leave target of 3h?  [Set 3h]  │
│ 3 Land on time. 48% of blocks ran 5+ min over; the next one │
│   came 86 min later.  [Try 35-min blocks]                   │
├ IS THE COACH HELPING? ──────────────────────────────────────┤
│ Prompt → start 31% (no prompt: 12%) · Back-from-break panel │
│ +22 pts · Last week's pick "Plan weekend": worked ✓         │
├ PATTERNS (details) ▸   QUESTIONS (2) ▸                      │
└─────────────────────────────────────────────────────────────┘
```

The recommendations quote the live store. The trend values and the "coach helping" line are
illustrative.

- **Headline.** A plain verdict against your own last 4 weeks, by day type (a leave day is compared with leave days).
- **Trend strip.** Six measures, each this week against the 4-week average with a direction. "Better" is defined per measure: fewer switches is better, more consistency is better.
- **Days strip.** The plan × outcome 2×2, with day-type marks. Clicking a day opens its timeline, where the hourly rollup shows calls, own work, away and derailers.
- **Do this next.** At most 3 recommendations from a rule library over the ledger. Each has your evidence, an expected impact, one **Apply** action, and follow-up: the next week reports *worked / didn't / not tried*. They are ranked by impact × confidence × not recently shown. The library at launch:
  - weekend plan
  - leave target
  - stretch → length
  - break overrun → landing
  - windows mismatch
  - app pull in context (for example "Slack in Learning blocks")
  - derailer hour (for example "X after 22:00")
  - never miss twice
  - day-type target miss
- **Is the coach helping?** The prompt lift (v5), the back-from-break lift (v7) and recommendation outcomes, moved here from Settings.
- **Patterns and Questions** are collapsed. The current pattern sentences and every pending quick question live in one inbox, not mixed into the analysis.

### 3.5 Targets per day type, and the weekly review
- **Own-work targets per day type:** workday, leave, weekend. They are set once from your history (median of good days) and changed with "Set 3h" style recommendations. Goals keep their numbers; the *time* target lives here.
- **Weekly review.** Sunday at 19:00 (or the first breakpoint after it) a full-window, 5-minute ritual:
  1. **Last week:** the verdict, the days strip and what worked.
  2. **One pick:** choose one recommendation for the coming week.
  3. **Plan:** put the coming week's own-work blocks on leave and weekend days, plus 2 workday anchors.
  4. **One line:** what's in the way?
  Each step is a recorded answer: this is the monitoring (Harkin) and the reflection (Di Stefano). After a week with no plan, Saturday morning brings one quick "Plan today?" card.

### 3.6 Cleaner live surfaces: one job each
- **Popover:** start and control only. Project, what, size, and Start; while running, the timer and controls. No quote, no ring, no lever row, no footer stats.
- **Notch:** timer plus one next action, and one ring idle. Show the lever *or* the task, never both.
- **Today:** one sentence ("1h 43m of 2h · on pace · leave day"), the next block, tasks, and the day timeline (the hourly rollup) merged with the block list. Distractions move to Insights.
- **The quote:** once a day, on one surface (Today).
- **Goals:**
  - Each card is one sentence, one bar and "today: 3 LeetCode". Numbers and ± sit behind a disclosure.
  - Pace is said once.
  - The Daily goal moves to Settings → Focus, as targets per day type.

## 4. Learning, briefly

| Learner | Method | Data it needs |
|---|---|---|
| Day type | Rules, then naive Bayes on your labels (features: weekday, calendar flags, office minutes by 13:00, first active hour) | About 20 labels; one question on uncertain days |
| App role per context | Beta posterior per (app, context) from block evidence, plus your labels as strong pseudo-counts | Hourly rollup with context |
| Recommendations | A rule library plus outcome tracking. Later, a Thompson-sampling choice among eligible recommendations by measured "worked" rate | 1–3 recommendations a week, follow-ups |
| Existing | v5 prompt bandit, v7 return hazard and experiment | No change |

No deep learning: about 100 blocks and 20 weeks of data are far too few, and every recommendation has to explain itself.

## 5. Plan, in phases (each ships alone and is installed and checked)

| Phase | Scope | Done when |
|---|---|---|
| **1. See the day** | Hourly rollup v2 with the away bucket, switches, call time and no double counting. Day Ledger plus day-type inference plus the leave quick question. One weekend helper. Backfill the ledger from daily rows (113 days). | Ledger says leave for 4–6 Nov. Office, own, away and calls add up to the active hours. Tests on fixtures. |
| **2. Apps in context** | App roles per context: editable defaults, project-scoped rules, the "for which project?" buttons, block-evidence posteriors, the role question, and the Distractions table. | Slack is a pull in a Learning block and a tool in an Office block. scaler.com is learned as a tool for Learning. |
| **3. Your week** | The new Insights: verdict, trend strip, days strip with day timelines, ranked recommendations with Apply and follow-up, "Is the coach helping?", and the inbox. The coach section leaves Settings. | Every recommendation shows evidence and one action. Week-over-week deltas are right on fixtures. |
| **4. Weekly review** | The Sunday ritual, targets per day type, the "Plan today?" card on unplanned weekends, and recommendation outcomes. | The review writes a plan and a pick. Next week reports the pick's result. |
| **5. Calm surfaces** | The popover, notch, Today and Goals cleanup in §3.6. | Element counts roughly halved. No number shown twice on one surface. |

Recommended order: 1 → 2 → 3 → 4 → 5. Phases 3 and 5 can swap if the clutter bothers you more than the missing advice. Phase 1 starts collecting the data that 2–4 need, so it goes first either way.

## 6. Decisions for you
1. **Day-type targets.** Proposed from your history: workday 1h 30m, leave 3h, weekend 2h own work.
2. **Weekend days.** Saturday and Sunday? (en_IN treats only Sunday as the weekend.)
3. **Weekly review time.** Sunday 19:00?
4. **Recording.** An hourly per-app rollup and camera/mic in-use flags, kept locally, with no window titles. Is that OK?

## 7. Phase 1, as built (6 Nov 2026)
- **Ledger on the live store** (`DayLedgerStoreTests/testLedgerOnALiveStoreCopy`, 17 Oct – 6 Nov):
  - Leave on 20 Oct, 4 Nov, 5 Nov and 6 Nov (no office apps).
  - Weekends 18 Oct, 24 Oct and 25 Oct were *unplanned & lost*.
  - Summary: "11 workdays, 3 leave days, 6 weekend days. Of 9 days off, 1 had a plan and 4 went
    unplanned with little own work."
- **Office minutes come from the daily rows**, so past days work from day one. The hourly rollup
  only adds call and away minutes, from the install onward. Hourly office time by 13:00 is a
  phase-2 refinement.
- **Inferred leave stays at confidence 0.6 until you answer.** The coach asks "On leave?" once,
  first among its quick questions. Calendar out-of-office events skip the question.
- **No new screen yet** beyond the "Your days" line in Insights. The Your week page is phase 3.

## 8. Phase 2, as built (6 Nov 2026)
- **Learning is a threshold, not the Beta posterior from §3.3.** An app is a learned tool for a
  project at 60+ min inside that project's blocks over 3+ days, or 2+ "planned" marks from block
  reviews. It is shown with its evidence ("12h 24m in its blocks on 9 days").
- **Learning never overrides a default pull.** Time in a block is not proof: Slack in a Learning
  block is asked about instead (the `.appRole` question). Browsers are never learned; their sites
  are.
- **History before the hourly rollup:** a day's in-block app time is lent to its project only
  when all that day's blocks were one project.
- **Outside a block, "work" means a workday from 09:00 to 19:00.** Learned office hours are left
  for later.
- **Live store:** your global "allowed" rules make scaler.com and Obsidian tools everywhere.
  Nothing else had enough single-project evidence yet. Slack had too little block time for the
  question to fire.

## 9. Phase 3, as built (6 Nov 2026)
- **The verdict compares like days.** Each finished day of the week is compared with the
  baseline mean of its own day type (a type with fewer than 2 baseline days uses the overall
  mean). Today counts only once it is no longer open. Under 7 days of history there is no
  baseline, and the page says so.
- **"Days on track" uses the verdict's rule**: at least half the day's target, and 25 min.
  Otherwise "7/7 days with own work" would sit next to "3 unplanned & lost".
- **Targets per day type came forward from phase 4**, because the ledger, the verdict and the
  leave recommendation all need them. A type you have not set follows the daily goal, so
  nothing changed on install. Only a settled day type changes today's goal: your answer, the
  calendar or a weekend. An inferred leave waits for "On leave?".
- **The library has 9 rules.** A rule fires only when it has an action. For example, "Land on
  time" needs a natural length to offer, and "Plan your weekend" needs an unplanned weekend
  ahead. A workday target miss opens Goals, because the workday target is the Goals tab's daily
  goal.
- **Follow-up.** Apply stores the measure over the previous 28 days. A week later, "Is the coach
  helping?" shows the change ("25% → 67%"). Windows, app roles and derailer hours have no
  measure, so they show as applied.
- **Live store (6 Nov):** "Better than your last 4 weeks", with 11h own work against an average
  of 2h 34m. The ranked recommendations:
  1. Plan your weekend: 7 of 10 days off were lost.
  2. Leave days: aim higher. The average was 1h 51m, so set the leave target to 3h.
  3. Workdays: a target you can hit. You met 2h 30m on 0 of 15 workdays.
  4. Use the hours you actually start in: your windows caught 17 of 47 starts.

## 10. Phase 4, as built (6 Nov 2026)
- **When the review is offered.** The review window runs from Sunday 19:00 to Monday 12:00, at a
  breakpoint (no block, no panel, someone present, no share or quiet hours). "Later" asks again
  after 3 h.
- **How it runs.** The review is a sheet over the companion window. Nothing is written until
  Finish. The plan step proposes days off at your usual hour, plus Tuesday and Thursday anchors
  at your evening window.
- **Records.** Reviews, recommendation records and targets live in defaults. Plans are
  `PlannedBlock` rows, as before. No model changed in phases 3 or 4.
- **"Plan today?"** asks on a settled day off, between 08:00 and 13:00, when there is no plan,
  no own work yet, and no planned day in the last week.
- **Data safety.** `FocusFlowSchema` is the one model list. `StoreUpgradeTests` opens a pre-v8
  store with it. The real pre-v8 backup also opened with identical row counts in all 12 tables.
