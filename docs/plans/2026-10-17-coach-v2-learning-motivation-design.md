# Focus Coach v2: Learning Coach + Challenger Motivation

Date: 2026-10-17 · Status: proposal · Companion to `docs/audits/2026-10-17-focus-coach-settings-audit.md`

## 0. The problem in one table (your real data, 2026-07-10 → 2026-10-16)

| Metric | Value | Source |
|---|---|---|
| Strong prompts delivered | **1,513** (~15/day) | `ZINTERVENTIONATTEMPT` |
| Prompts followed by a session start within 10 min | **9 (0.6%)** | join with `ZFOCUSSESSION` |
| Prompts with a recorded outcome | **1 of 1,513** | `ZOUTCOMERAWVALUE` (bug B3) |
| Prompt hours | 09–18 ≈ 130–160 each; 22–23 ≈ 24 total | delivery hour |
| Your session start hours | **11–12: 24**, **22–00: 32**, 09–10: 5 | start hour |
| Top real time sinks outside focus | Video streaming and social sites (YouTube, X, Netflix, a regional streaming service) dominate, at tens of hours each over the period | `ZAPPUSAGEENTRY` |
| Work tools in your top 25 | Arc, Cursor, Slack, Antigravity, Claude, Copilot, Atlassian, Zoom, IntelliJ, Obsidian, GitHub | same |
| Auto-suggested "distractions" | 63, including the company Jira (`*.atlassian.net`), `github.com`, `mail.google.com` and an internal SSO domain | `ZIDLEDISTRACTIONITEM` |

The coach fires during your day job, when you are not going to start a personal focus block. It calls work tools distractions and never learns from your responses. It is ~0.6% effective, which is noise.

---

## 1. Root causes (verified in code)

### Wrong app ("you're wasting time in X", where X is a work app)
- **W1. Block recommendation has top priority and accepts any amount of use.** `FocusCoachMessageBuilder.resolveSignal` checks `suggestedBlockTarget` second, before everything else (`Services/FocusCoachMessageBuilder.swift:88-89`). The advisor picks today's top entry that maps to a target, with **no minimum duration** (`Services/FocusCoachGuardianAdvisor.swift:43-50, 91`).
- **W2. The "derailer" fallback hardcodes your work tools.** `anthropic, claude, openai, chatgpt, slack, discord, telegram, whatsapp` become block targets (`Models/AppUsageEntry.swift:199-209`). Slack and Claude are two of your top-7 apps.
- **W3. AI tools are treated as over-planning.** Any bundle id containing `openai` or `anthropic` sets `overPlanningLoopDetected` (`ViewModels/TimerViewModel.swift:2769-2774`). The banner then says "ChatGPT loop… looks like over-planning" (`FocusCoachMessageBuilder.swift:244`).
- **W4. In-session default is "procrastinating".** An unknown app during focus gets disposition `.procrastinating`, and Slack or AI tools count as AI-chat (`Services/AppUsageTracker.swift` ~939, ~963-967).
- **W5. Context-aware classifier exists but is never called.** `AppUsageEntry.classifyForContext` has zero callers (`Models/AppUsageEntry.swift:55-86`). Classification ignores project and work mode.
- **W6. Distraction suggestions collect evidence from whatever was frontmost** when a notification was ignored (`TimerViewModel.swift:2862-2880`). That is how Atlassian, GitHub and Gmail got suggested.

### Wrong time
- **T1. Hardcoded day-job schedule.** Work-intent hours are `9...18` (`Services/FocusCoachInterventionPlanner.swift:41`), weekdays only (`TimerViewModel.swift:2724`). Opportunity scores are highest 07–17 and lowest after 22 (`Services/FocusCoachOpportunityModel.swift:52-61`). This is the **inverse of your real start pattern** (22–00 is your strongest window).
- **T2. Ten idle minutes is enough.** A neutral app at 10 minutes idle scores drift 0.58 against a 0.55 threshold, so the coach prompts. "Idle" means "no FocusFlow session", not "not working", so every non-session minute of your day job counts.
- **T3. Calendar is ignored.** `minutesUntilNextCalendarEvent: nil` and `preMeetingRunwayMinutes: nil` (`TimerViewModel.swift:2737, 2756`). You spent 20h in Zoom, and meetings are invisible to the coach.
- **T4. "since your last focused block" is wrong.** `dur` is the tracker's idle streak (reset on app launch or any state change, `AppUsageTracker.swift:322, 527-531`), not time since your last session.

### No learning
- **L1. Outcomes are written to the oldest row** (B3). Calibration (`CoachPersonalProfile`) reads garbage.
- **L2. Calibration only touches in-session thresholds** (`Services/FocusCoachEngine.swift:207, 248, 259`). The idle starter, where 100% of your prompts came from, has **no learned parameter at all**.
- **L3. Nobody learns hour-of-day.** Peak hour exists only as a chart subtitle (`Views/Companion/WeeklyStatsView.swift:415-430`).
- **L4. Quote choice is `dayOrdinal % count`** (`Services/FocusCoachMotivationalQuotes.swift:151-167`). No preference, and quotes are never rendered anyway.

---

## 2. Science basis

The design follows the **Just-in-Time Adaptive Intervention (JITAI)** framework (Nahum-Shani et al., *Annals of Behavioral Medicine*, 2018). A JITAI has decision points, tailoring variables, intervention options, decision rules and a proximal outcome. Mobile-health studies such as HeartSteps (Klasnja et al.) learned decision rules with on-device **Thompson-sampling contextual bandits**, which is the same approach used here.

| Principle | Evidence | How v2 applies it |
|---|---|---|
| Intervene only when the person is **available and receptive** | JITAI "state of receptivity" | Learned focus windows plus calendar plus work-context detection; no prompts outside them |
| Learn per person from outcomes | Contextual bandits (Thompson sampling) | Reward = session started within 10 min (+ completed) |
| If-then plans raise follow-through | Implementation intentions, Gollwitzer 1999; meta-analysis Gollwitzer & Sheeran 2006 (d ≈ 0.65) | You set "If it's 22:00 on a weeknight, I start a 25m block on {project}" and the coach reminds you of **your** plan |
| Identity framing beats outcome framing for habits | Clear, *Atomic Habits* 2018 (identity-based habits) | "Every block is a vote for who you're becoming" |
| Habits take weeks, not days | Lally et al. 2010, median ~66 days to automaticity | Streaks and consistency metrics measured over weeks; a missed day isn't failure (Lally: one miss didn't derail formation) |
| Style must match the person | Self-Determination Theory (Deci & Ryan): controlling language can backfire for many people | **You choose** Challenger; for you it's autonomous, not imposed. The bandit still verifies it works |
| Alert fatigue kills response | Notification-fatigue literature; your own 0.6% | Hard daily cap; bandit "no prompt" arm wins when nothing works |

---

## 3. Architecture

```
            ┌────────────── signals (every 30-60s, on-device) ──────────────┐
            │ hour-of-week · idle mins · frontmost app class · calendar busy │
            │ sessions today · goal % · streak · last prompt outcome        │
            └───────────────┬───────────────────────────────────────────────┘
                            ▼
  [1] Availability model ── "Is now a plausible focus window for this user?"
                            │ p_avail < τ  →  stay silent (no decision point)
                            ▼
  [2] App-context model ── "Is the frontmost thing work, neutral or a derailer?"
                            ▼
  [3] Decision policy (Thompson-sampling bandit)
        arms: silent · popover badge · notification(Start) · strong window
        × message style: Challenger · Data · Plan-reminder · Gentle
                            ▼
  [4] Message composer ── fills template with YOUR data + vetted quote
                            ▼
       user acts ─► reward (start ≤10 min = 1, +0.5 if completed) ─► update [1][2][3]
```

All of it runs on-device in Swift with SwiftData. There's no network and no ML framework; these are Beta/Gamma posteriors and logistic updates.

### [1] Availability model, learned focus windows

- 168 hour-of-week buckets. For each bucket, the posterior start rate is `Beta(α0 + starts, β0 + opportunities)`, where opportunities are minutes the Mac was awake and the user was not in a session.
- Prior: weak (α0 = 1, β0 = 20), smoothed ±1 hour so 11:00 informs 10:00 and 12:00.
- Decision point opens only if `P(start in bucket)` is in the user's top-k buckets for that day, **or** an explicit plan says so (implementation intention), **and** the calendar is not busy in the next 25 min.
- On your data this would allow 11–12 and 22–00, and suppress most of 09–18.
- Cold start uses the user's onboarding answer ("When do you usually do deep work?"). The bandit takes over after ~2 weeks.

### [2] App-context model, learned work vs derailer

The context-aware classifier (`classifyForContext`, currently unused) becomes the base, with three overlays in priority order:

1. **Explicit labels (strongest).** A one-tap "This is work" or "This is a distraction" on every coach surface. These are hard overrides scoped per project, using the existing `DriftMemoryStore` keys (`projectId|workMode|app`). Fix the undo key bug (B7).
2. **One-time review of top apps.** On first launch of v2, show your top 15 apps and domains by hours. You tag each as Work, Neutral or Derailer, which takes about 30 seconds. This gives far more signal than anything inferred.
3. **Prior lists** stay as the fallback, minus the work tools. Remove `slack, claude, anthropic, openai, chatgpt` from derailers (W2) and delete the bundle-substring over-planning rule (W3).

**Rejected: in-focus share as an implicit label.** On your data it fails. YouTube has 4.3% of its time inside focus sessions, Claude 3.6% and Cursor 1.1%, because most of your real work happens outside FocusFlow sessions. Inferring "work" from in-session time would rank YouTube above Cursor. At most it can serve as a weak tie-breaker for apps that are never labelled.

Block recommendations require: category = derailer (learned or user-confirmed) **and** ≥ 20 min today **and** not labelled work. That would surface YouTube, X, Netflix and zee5 for you, and never Slack or Claude.

### [3] Decision policy

- Arms: `silent`, `badge`, `notification` (with **Start {N}m** action, fixes B4), `strongWindow`.
- Message styles: `challenger`, `data`, `plan`, `gentle`.
- Context features (bucketed): availability tier (high/med), idle length (10–30 / 30–90 / 90+), frontmost class (work/neutral/derailer), sessions today (0 / ≥1).
- Each (context, arm, style) keeps a `Beta(1,1)` reward posterior. Sample, then take the argmax. `silent` has a small fixed reward prior (e.g. 0.05), so a prompt must beat 5% start probability to be worth showing. At your current 0.6% the coach would mostly go quiet until it finds what works.
- Guardrails, not learnable: ≤ 3 prompts/day, ≤ 1 strong window per 2 hours, none during calendar-busy or screen share, a "Done for today" release until the next learned window, and never during your configured quiet hours.
- Your stated preference sets the prior: if you pick **Challenger**, it starts at `Beta(3,1)` instead of `Beta(1,1)`, so it's tried first but can still lose to data.

### [4] Message composer

One builder replaces the five copy layers (audit §3). Every message has three parts:
1. **Hook**, one line chosen by style. The challenger hook uses your own numbers.
2. **Fact**, at most one, true, and only about confirmed derailers or your plan.
3. **Action**, one primary button: **Start {N}m on {Project}**.

No message may say something unverifiable ("since your last block" uses the real last session end time from `ZFOCUSSESSION`, never the idle streak).

---

## 4. Challenger motivation pack (your style)

Settings → Focus Coach → **Coaching style**: Gentle · Data · **Challenger** (default for you).

### 4.1 Message templates (data-driven, not generic)

| Trigger | Challenger copy |
|---|---|
| Learned window opens, 0 sessions today | **"Day {streakDay}. Show up."** 25 minutes on {Project}. The streak is built tonight, not tomorrow. |
| Learned window, derailer frontmost (confirmed) | **"YouTube has had 2h 10m of you this week."** Take 25 minutes back. |
| Your own if-then plan fires | **"You said: 22:00 → {Project}."** It's 22:00. Keep your word to yourself. |
| 1% framing (weekly) | **"1% better daily = 37× in a year."** (1.01³⁶⁵ ≈ 37.8.) Today's 1%: one block. |
| Missed yesterday | **"Never miss twice."** Yesterday is gone; today decides the trend. |
| Goal behind late in window | **"{pct}% of today's goal. {remaining}m left in your window."** Finish strong. |
| After a session ends | **"Vote cast."** {blocksThisWeek} blocks this week, {delta} vs last week. |

Rules: no shaming, no fake urgency, and every number comes from your data. Challenger means direct and demanding, not insulting.

### 4.2 Quote library: vetted and attributed, ≤ 1 per prompt

Store as `Quote {text, author, source, theme: discipline|consistency|identity|action|focus}`. **Only include quotes with a verifiable source.** Seed candidates (verify each source before shipping):

| Theme | Quote | Attribution / source |
|---|---|---|
| systems | "You do not rise to the level of your goals. You fall to the level of your systems." | James Clear, *Atomic Habits* (2018) |
| identity | "Every action you take is a vote for the type of person you wish to become." | James Clear, *Atomic Habits* |
| discipline | "Discipline equals freedom." | Jocko Willink, *Discipline Equals Freedom* (2017) |
| discipline | "Discipline is the bridge between goals and accomplishment." | Jim Rohn (widely attributed; secondary sources) |
| consistency | "We are what we repeatedly do. Excellence, then, is not an act, but a habit." | **Will Durant**, *The Story of Philosophy* (1926), paraphrasing Aristotle. Commonly misattributed to Aristotle; attribute correctly |
| focus | Deep-work idea, paraphrased in your own words | Cal Newport, *Deep Work* (2016) |

Also, **"My why" (user-authored)**: Settings lets you write up to 5 personal lines ("Ship the side project by Dec", "Be the engineer who…"). Challenger rotates them alongside quotes. The bandit learns whether quotes, your "why" lines, or raw data drive more starts.

Existing quotes: keep the 20 in `FocusCoachMotivationalQuotes.swift`, but add a `source` field and drop any you can't source. Actually render the quote (today it's built and discarded, audit P2).

### 4.3 "What's holding me back" weekly report

A weekly card in Insights, computed from your data:
- Top 3 confirmed derailers by hours, with the trend vs last week.
- Your best and worst focus windows (learned start rate).
- Prompt effectiveness per style (bandit posteriors, shown plainly: "Challenger messages led to a start 18% of the time; Gentle 4%").
- One concrete experiment for next week ("Block X.com 22:00–00:00 on weeknights?"). Accept → creates the block rule.

---

## 5. Phased rollout

| Phase | Scope | Effect for you |
|---|---|---|
| **0: Stop the bleeding** (small, ~1 day) | Fix B3 (outcome row) and B2 (snooze). Remove work tools from derailers (W2) and the over-planning rule (W3). Block recs need ≥20 min of a non-work target. Hard cap of 3 prompts/day. Pass calendar busy (T3). Fix the "since last block" text (T4). Purge the 63 auto-suggested items or mark them pending-review. | Prompts drop from ~15/day to ≤3; no more "Slack/Claude is distracting" |
| **1: Learn when** | Availability model (168 buckets, Beta posteriors); onboarding "when do you deep-work?"; implementation-intention plans | Prompts move to 11–12 and 22–00 |
| **2: Learn what** | Top-apps review + one-tap labels + `classifyForContext`; per-project scoping | The coach knows your work apps |
| **3: Learn how** | Thompson-sampling bandit over arm × style; actionable notifications (B4); reward logging | Silences itself when ineffective, escalates what works |
| **4: Challenger pack** | Style setting, data-driven templates, vetted quotes with sources, "My why", weekly "holding me back" report | Motivation in your style |

Each phase is independently shippable and testable. Phase 0 fixes ship first because every later phase depends on clean outcome data.

## 6. Measuring success

The primary metric (proximal outcome) is **prompt → session start within 10 min**. Today it's 0.6%; the target after phase 3 is ≥ 15%. Secondary metrics: prompts/day ≤ 3, focus minutes/week, and weekly consistency (days with ≥ 1 block). Show these in Insights so you can judge the coach yourself.

## 7. Decisions (2026-10-17, from the user)

1. **No hardcoded schedule.** Personal work can happen at night or in late morning at the office. The availability model (§3 [1]) learns windows from where you actually start sessions. Day-job hours are not hard-silenced; the calendar and the daily cap still apply.
2. **The north-star goal is 2–2.5 hours of personal deep work every day.** The coach optimises for this, not for "less idle time". See §8.
3. **The real enemy is pseudo-productivity, not apps.** Evening work that feels important but isn't (long Claude chats, building an ops dashboard nobody needs) does more damage than YouTube, because it doesn't look like a distraction. See §9.
4. Still open: quiet-hours cutoff, and whether to purge or review the 63 auto-suggested items.

---

## 8. Daily goal pacing (2–2.5h personal work)

- `dailyPersonalGoal` defaults to 120 min, stretch 150 min. Only sessions tagged to a **personal priority** count toward it (§9).
- **Pacing model:** `remaining = goal − done`. `windowsLeft` = expected focus minutes in the learned windows still ahead today (availability posteriors × window length). Pressure = `remaining / windowsLeft`:
  - < 0.5: on track. Stay quiet, at most one "vote cast" message after a session.
  - 0.5–1.0: nudge at the start of the next learned window.
  - > 1.0: today is at risk. Challenger message at the next window: **"90m still owed to {priority}. This window is the last good one today."**
- The coach suggests a block length that fits: `min(remaining, 50)`, at least 25.
- **Weekly view:** days with ≥ 120 min, plus a "never miss twice" streak (Lally et al. 2010: a single missed day did not derail habit formation; repeated misses did).

## 9. Important vs feels-important (pseudo-productivity guard)

Apps can't tell you whether you're doing real or busy work: the same Claude window can be either. The test has to be **intent alignment**, not the app.

**1. Weekly priorities.** On Sunday or Monday the coach asks for your **1–3 personal outcomes** for the week ("Ship X v1", "Finish Y chapter"). Each is concrete and finishable. Projects map to priorities. This draws on Eisenhower's important/urgent distinction and Newport's "do fewer things" (*Slow Productivity*, 2024).

**2. Intent before every session.** Starting a block asks one line: *"What will exist at the end of this block?"* (prefilled from last time), plus which priority it serves. This is an implementation intention at session scale.

**3. Outcome check after the session.** Three chips: **Shipped / Moved it forward / Busywork**, plus "Did this serve {priority}?" Yes/No. This is the reward label the learner was missing.

**4. Drift-into-busywork detector.** This is an evening guard. Inside a learned personal window, with no active session and pacing pressure ≥ 0.5, after ≥ 20 min in a neutral or work context (Claude, Cursor, Arc) the coach asks once:
   > **"Is this {priority}, or does it just feel productive?"**
   > [It's {priority}: start a block] · [Honestly, side quest: start {priority} instead] · [Planned, leave me]

   "It's {priority}" starts a tagged session, so the time counts. "Side quest" is logged as pseudo-work for that context. "Planned" is respected for 60 min.

**5. Learning which work is pseudo-work.** Per (project/context, hour-bucket), track the rate of `Busywork` and `side quest` answers. If an activity is repeatedly self-rated busywork (e.g. "ops dashboard" project, Claude chats after 22:00 without a session), the coach:
   - flags it in the weekly report: **"6h this week on Ops Dashboard; you rated 4 of 5 sessions as busywork. It's not one of your priorities."**
   - offers one experiment: archive the project for a week, or block it during your learned personal windows.

**6. Challenger copy for this case** (honest, not shaming):
   - "Feeling busy isn't progress. What will exist after the next 25 minutes?"
   - "Is this the work, or work about the work?"
   - "{priority} hasn't moved in 3 days. Everything else can wait 50 minutes."

Reward for the bandit becomes: `+1` start, `+0.5` completed, `+0.5` rated Shipped/Moved forward **and** aligned to a priority, `−0.5` rated Busywork. The coach learns which nudges lead to real progress, not just sessions.

**Phase mapping:** §8 pacing ships in Phase 1 with the availability model. §9 steps 1–3 (priorities, intent, outcome chips) ship in Phase 1 too, because they produce the training labels. Steps 4–6 ship in Phase 3 with the bandit.
