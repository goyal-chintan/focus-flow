# Coach v3: the start engine

Date: 2026-10-19 · Status: building · Extends `2026-10-17-coach-v2-learning-motivation-design.md` and `2026-10-17-coach-rescue-loop-design.md`

## The problem in the user's words
> "I'm not getting any prompts or anything from coach, can't see any insights, machine learning and science based advice in the app. The goal was that this app should be able to get me to the focus session, but that didn't happen… the motivation quotes are also missing in challenger."

## 1. What actually happened (two days of live data after the v2 build)
Read from the live store (`InterventionAttempt`, `FocusSession`), `/tmp/focusflow_debug.log` and a CPU sample of the running build.

| # | Finding | Evidence | Code |
|---|---|---|---|
| R1 | The daily cap (3) was spent within 20 minutes around midday. Nothing could show all evening and night, which is the user's main personal-work time. | Three panel attempts within 20 minutes. The log shows the idle path re-checked about every 15 minutes through the evening and night, and stopped at the guardrail each time. | `CoachGuardrails.verdict` `dailyCapReached` |
| R2 | Double fire: an ignored L1 rescue raises the level to L2. A level rise bypasses the 20-minute repeat, so a second panel showed 30 s later. | Two attempts 30 s apart, `lvl:1` then `lvl:2` | `CoachRescueCadence.shouldDecide` (`level > last.level`), `DriftMonitor.level(base:ignoredRescues:)` |
| R3 | The panel is a 356×120 card in the top-right corner. It is silent, hides itself after 20 s and logs "ignored". 4 of the 5 prompts since the build "timed out" after about 21 s. A user looking at another display, or away from the desk, never sees it. The bandit then learns "ignored" and drifts toward silence. | `ZRESOLVEDAT − ZDELIVEREDAT` = 20.8–21.4 s | `CoachPanelPresentation.autoHideSeconds`, `coachPanelTimedOut` |
| R4 | The coach is only reactive. It waits for drift (≥ 10 min of a derailer, or ≥ 20 min of pseudo-work under pacing pressure) or for a learned window while behind pace. It never asks *when* the user will work, and never cues that moment. | 5 sessions in 30 days. Intent text is empty on every session. | `DriftMonitor.isActive`, `evaluateIdleStarterIntervention` |
| R5 | The day rollover is late by hours. The midnight `Timer` does not advance while the Mac sleeps, so "today" stayed on the previous day until mid-morning. Pacing and "today" facts were wrong all morning. | Log: rollover detected about 10 and 11 hours after midnight on two consecutive days | `scheduleMidnightRefresh` |
| R6 | Quotes are effectively unreachable. The composer puts a fact or the fixed "1%" line in the single detail slot first. L2 and L3 always show the 1% line. Start nudges almost always show the goal fact. The start nudge also logs a quote as "shown" even when a fact displaced it, which burns the 3-day no-repeat pool. | Explore trace | `CoachMessageComposer.detail`, `deliverStartNudge` |
| R7 | The user picked Challenger, but the bandit still explores Gentle and Data. | Attempt 1524 is `gentle` | `CoachBanditPolicy.choose` |
| R8 | Nothing the coach learns is visible: windows, pacing, bandit, plan adherence. The only advice strings come from a different model than the one the coach uses. No science is cited anywhere in the app. | Explore trace | `InsightsView`, `TodayView`, `CoachSettingsTab` (debug only) |
| R10 | Found during live verification: a recurring 14-hour, evening-to-morning "busy" calendar block (an off-work or out-of-office marker) counted as a meeting. The calendar guardrail silenced every prompt on those evenings, and the plan card had no free time to offer. | A logged busy interval of 840 minutes; the debug log shows `busyNow=true` all evening | `CalendarService.availability`, `CalendarAvailability.compute` |
| R11 | Found during live verification: the coach panel window was stuck at 120 pt, which clipped the header and the action buttons. The slide-in `animator().setFrame` finished after the content reported its real height and reset the frame. | Panel window frame `356×120` while the content measured 225 pt | `CoachPanelController.showPanel`, `contentSizeChanged` |
| R9 | The app uses about 30% CPU at rest. The menu-bar `symbolEffect(.pulse, .repeating)` runs until the popover is next opened, which can be days, and it relayouts the status item every frame. | `sample`: constant `NSDisplayCycleFlush` / `RepeatAnimation` | `FocusFlowApp` label |

## 2. What the research says gets people to start
1. **Decide when and where in advance (implementation intentions).** "When it is 22:00 at my desk, I will open the draft." A meta-analysis of 94 studies found a medium-to-large effect on goal attainment, d = 0.65 (Gollwitzer & Sheeran, 2006, *Adv. Exp. Soc. Psychol.* 38). Planning prompts raised follow-through in field studies (Milkman et al., 2011, *PNAS* 108(26)). This is Clear's first law, "make it obvious" (*Atomic Habits*, 2018).
2. **A cue at the moment, not a reminder you can swipe away.** Behaviour happens when motivation, ability and a prompt meet (Fogg, *Tiny Habits*, 2019). Just-in-time adaptive interventions deliver support at the moment of need and receptivity (Nahum-Shani et al., 2018, *Ann. Behav. Med.* 52(6)). A cue should arrive at the planned moment and stay until it is answered.
3. **Make the first step tiny (the two-minute rule).** Starting is the bottleneck. Procrastination grows with task aversiveness and delay (Steel, 2007, *Psychol. Bull.* 133(1)). So the cue always offers a 5-minute starter that needs no setup.
4. **Never miss twice.** In habit formation, automaticity rose along a curve, median 66 days. Missing a single day did not materially affect it (Lally et al., 2010, *Eur. J. Soc. Psychol.* 40(6)). The rule is to protect the next day, not the streak.
5. **Same time, same context, every day.** Habits are cued by stable contexts (Wood & Neal, 2007, *Psychol. Rev.* 114(4)). The coach suggests the user's own strongest learned hour so the habit gets a stable anchor.
6. **Fresh starts.** Temporal landmarks such as Mondays and the start of a month raise goal pursuit (Dai, Milkman & Riis, 2014, *Manage. Sci.* 60(10)).
7. **Progress you can see.** Effort rises as the goal gets closer (goal gradient: Kivetz, Urminsky & Zheng, 2006, *J. Mark. Res.* 43(1)). Small visible wins drive motivation (Amabile & Kramer, 2011).
8. **Forgive the miss.** Self-forgiveness for procrastinating reduced later procrastination (Wohl, Pychyl & Bennett, 2010, *Pers. Individ. Differ.* 48(7)). The Challenger voice is direct, never shaming.
9. **Interrupt at breakpoints.** Interruptions at task breakpoints cost less than mid-task ones (Iqbal & Bailey, 2008, CHI). The daily plan card waits for a breakpoint: the first activity after waking, or the end of a meeting.

## 3. Design

### 3.1 Daily plan (make it obvious)
- **New model `PlannedBlock`:** `day`, `startAt`, `minutes`, optional `title`, `status` (planned, started, skipped, missed), `cueCount`, `createdAt` and `sessionID`.
- **Plan card (on screen, stays until answered):** once a day, at the first coach tick that meets all of these:
  - outside quiet hours
  - no session running
  - calendar free
  - the user is active
  - no plan exists for today
  - the goal is not yet met
- **Plan card content:** "When is today's 2h?" followed by up to three time chips: the next learned good windows that are free in the calendar, then sensible fallbacks. Each chip is one click.
- **Plan card buttons:** "Not today" releases the day. ✕ asks again in 2 hours (at most twice a day).
- **Popover, idle:** a "Today" row shows the next planned block ("22:00 · 50m"), or offers the same time chips when nothing is planned.

### 3.2 The cue at the planned time
- **When:** at `startAt`, an on-screen panel appears: "22:00. Your planned block." It never auto-hides and floats on the display with the pointer.
- **Primary:** "Start 25m on {priority}".
- **Secondary:** "Just 5 minutes" (two-minute rule), "Push 15 min", "Push 1 hour", "Skip today".
- **✕ or Esc:** pushes the block 15 minutes. After three pushes it becomes "missed".
- **Starting any block** between 30 minutes before and 90 minutes after `startAt` marks the plan started.
- **Calendar busy at `startAt`:** the cue waits until the meeting ends, up to 60 minutes, and that end is a natural breakpoint.
- **Limits:** planned cues ignore quiet hours and the daily cap, because the user asked for them. Screen share still blocks them.

### 3.3 Rescue fixes
- **R1 cap:** the daily cap counts only rescue and nudge panels that were actually seen (panel, pause screen, notification), and planned cues and the plan card don't count. The default cap stays at 3.
- **R2 double fire:** a level rise bypasses the 20-minute repeat only when usage raised the base level, and only after at least 5 minutes. Ignored rescues raise the level of the *next* decision.
- **R3 unseen panels:** start and rescue panels stay for 3 minutes, and hovering pauses the timer. If the user had no input for the panel's whole life, it was unseen: the outcome is not "ignored", and the bandit, the level and the cap don't count it. The panel appears on the display with the pointer.

### 3.4 Quotes (R6)
- `CoachComposedMessage` gains a separate `motivation` line, so a quote no longer competes with the fact. Challenger panels (start, rescue at every level, planned cue, pseudo-work) always carry a quote or a house line under the fact.
- A quote is logged as shown only when it was displayed.
- The popover's idle state shows **Today's line**: one quote per day for the chosen style. A click shows another.

### 3.5 Style (R7)
The chosen style is the only style the bandit uses. It still learns the surface: silent, panel or pause screen.

### 3.6 Coach insights (R8)
- **Today → "Your coach":**
  - Today's plan and its status.
  - The best windows left today, from the coach's own availability model, with how much likelier a start is than in the average hour.
  - Pacing: minutes left and window time left.
  - A 14-day "never miss twice" chain.
  - Up to three advice cards, each from the user's data and each with its citation.
- **Insights → "What the coach learned":**
  - A heatmap of start probability by hour of week from the posterior.
  - Plan adherence (planned → started).
  - Start rate on planned days versus unplanned days.
  - Prompts that led to a start.

### 3.7 Reliability
- **R5:** rollover is checked on wake, on `NSCalendarDayChanged` and on every coach tick.
- **R9:** the menu-bar pulse plays three times, then settles to a static dot. The running app went from about 30% to about 1% CPU.
- **R10:** busy blocks of four hours or more, and out-of-office events, are availability markers, not meetings, so the coach ignores them.
- **R11:** the panel measures its content before it slides in, and any resize goes through the animator, so the full panel is visible.
