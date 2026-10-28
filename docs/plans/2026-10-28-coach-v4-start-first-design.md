# Coach v4: start first

Date: 2026-10-28 · Status: building · Extends `2026-10-19-coach-v3-start-engine-design.md`

## The problem in the user's words
> "I'm still not seeing the coach prompt… the primary ask and the primary goal of the focus coach should be whether it is able to push me to start focus or not. … it asks for a 2 hour focus block, but … even a 5 minute, or 25 minute, or even 15 minute — if I could start with that then I can get more sessions. … if something is not working, then maybe get a reason and then act better next time."

**North-star metric:** the share of coach prompts the user *saw* that were followed by a focus start within 10 minutes. Everything else is secondary.

## 1. What happened in the nine days after v3 (19–28 Oct, live store)

| Trigger | Shown | Unseen (away) | Start ≤ 10 min after | Credited as a start |
|---|---|---|---|---|
| Plan card ("When is today's 2h?") | 14 | 0 | **4 (29%)** | **0** |
| Rescue ladder (L1–L3) | 17 | 2 | 0 | 0 |
| Idle start nudge (panel) | 8 | **7** | 0 | 0 |
| Menu-bar badge | 28 | n/a | 0 | 0 |

There were 14 focus blocks in the period. 4 of them followed a coach card within 3 minutes.

| # | Finding | Evidence | Code |
|---|---|---|---|
| F1 | **The only working prompt is logged as a failure.** After the plan card the user started a block from the popover 1–7 minutes later. That start was never credited: the plan card does not set `pendingCoachAttemptID`, and a start is credited only through that one ID. Every reward in the period is 0, so the bandit, the insights ("Prompts → starts") and every learner downstream see a coach that never works. | 20 Oct 14:08 card → 14:09 start; 21 Oct 07:11 → 07:11; 22 Oct 08:06 → 08:09; 27 Oct 08:05 → 08:12. All logged `ignored`/`snoozed`, reward 0. | `evaluateDailyPlanInvite`, `creditCoachPromptForStart`, `CoachRewardLedger.creditStart` |
| F2 | **The plan card asks for the wrong thing.** It says "When is today's 2h? Decide now." and offers only future times, with no way to start now. The user answers it by starting *now*, from the popover. | Card copy; `hasPrimary == false` for `.dailyPlan`. | `CoachMessageComposer.dailyPlanHook`, `CoachPanelPresentation.hasPrimary` |
| F3 | **Start nudges fire at an empty desk.** The idle path counts time since the last session. It never checks whether anyone is at the Mac. 7 of 8 start panels (22:00–00:30) were unseen. | `idle:90+`, outcome `unseen`, 556–1032 s | `AppUsageTracker.tick` → `evaluateIdleStarterIntervention` |
| F4 | **One unseen panel silences the evening.** The 2-hour panel spacing counts unseen panels. After one, the bandit can only pick a badge. It did, every 15 minutes, until 00:30 (10–12 badges a day). | 24 Oct: 3 unseen panels, 12 badges | `CoachGuardrails.verdict` `panelTooSoon` |
| F5 | **Rescues fire in the user's day job.** All 17 rescues were at `avail:low/medium` between 08:30 and 18:40, with 0 starts. | context keys | `evaluateRescueLoop` |
| F6 | **"Not now" teaches nothing.** A decline records `snoozed` and nothing else. The coach never asks why, so it repeats the same ask at the same size. | `skipReasonRaw` is empty on every row | `performCoachPanelSecondary` |
| F7 | **The coach is a black box in the installed app.** The release build logs nothing, and `/tmp/focusflow_debug.log` holds only test-run noise. Nobody can see why the coach stayed quiet. | 725 kB of test output, no live entries | `TimerViewModel.log` (`#if DEBUG`) |

## 2. What the research says about *starting*

1. **Small, near goals beat big, far ones.** Proximal subgoals raised self-efficacy, persistence and performance more than one distal goal (Bandura & Schunk, 1981, *JPSP* 41(3), 586–598). A 5-, 15- or 25-minute block is a proximal goal. "2 hours today" is a distal one.
2. **Starting is the bottleneck. Lower the cost of the first minute.** Procrastination grows with task aversiveness and with delay (Steel, 2007, *Psychol. Bull.* 133(1)). When motivation is low, behaviour happens only if the step is easy and the prompt arrives at that moment (Fogg, *Tiny Habits*, 2019).
3. **Once started, people tend to continue.** A 2025 meta-analysis found no reliable memory advantage for unfinished tasks (Zeigarnik). It did find a robust tendency to *resume* them (Ovsiankina), about 67% against a 50% baseline (Ghibellini & Meier, 2025, *Humanit. Soc. Sci. Commun.* 12, 962). So a short block ends with an offer to keep going, not a stop.
4. **Prompt when the person is there and receptive.** Prompts at moments of receptivity, learned per person, raised engagement by up to about 40% over random timing (Mishra et al., 2021, *Proc. ACM IMWUT* 5(2), 74). Interruptions at breakpoints cost less (Iqbal & Bailey, 2008). Coming back to the desk is a breakpoint.
5. **Decide when (implementation intentions).** d = 0.65 across 94 studies (Gollwitzer & Sheeran, 2006). Keep the plan, but make it the second option, not the only one.
6. **Name the obstacle, then plan for it (MCII / WOOP).** Mental contrasting with implementation intentions: g = 0.34 across 21 studies and 15,907 participants (Wang, Wang & Gai, 2021, *Front. Psychol.* 12:565202). The coach asks *why not*, then changes its next ask ("if it feels too big, then 5 minutes").
7. **Urgent-feeling beats important.** People pick urgent, lower-payoff tasks over important ones even when they know the payoff is lower: the mere urgency effect (Zhu, Yang & Hsee, 2018, *J. Consum. Res.* 45(3), 673–690). This is the user's pseudo-productivity pattern, for example building productivity tools instead of doing the work. The coach names the priority at the moment of choice.

## 3. Design

### 3.1 Measure the one thing (F1, F7)
- **Honest attribution.** Any focus start credits the most recent *seen* coach prompt delivered in the last 10 minutes, whatever surface started it: popover, panel, shortcut or companion. The prompt's own button stays the first choice. Badges are ambient, so they are never credited.
- **The start card's starts count.** They count in "Prompts → starts", in the size ladder and in the journal. The card stays out of the bandit, because the card is shown once a day by rule; the bandit does not choose it.
- **Coach journal.** Every coach decision is appended to `~/Library/Application Support/FocusFlow/coach-journal.jsonl` in release builds, capped at 2,000 lines. A decision is shown (trigger, surface, size) or suppressed (with the reason), and an outcome follows (started, declined with a reason, unseen). Insights shows today's entries, so "why was the coach quiet?" has an answer.

### 3.2 Only when someone is there (F3, F4)
- **Presence gate.** Idle start prompts need keyboard or mouse input in the last 90 s. While the user is away, the coach waits.
- **Arrival breakpoint.** When the user comes back after 10 minutes or more away, and no block is running, the coach evaluates a start prompt at once. This counts as a breakpoint, so it skips the learned-window gate. All hard guardrails still apply: quiet hours, calendar, screen share, cap and snooze.
- **Unseen panels don't block.** A panel nobody saw does not start the 2-hour panel spacing. It already did not count toward the daily cap.

### 3.3 Start first, small first (F2)
- **The start card replaces the plan card.** Same moment: the first breakpoint of the day, with the user present. Its question is "start now?":
  - Hook: "First block. Start small." Later in the day: "Next block. Small is fine."
  - **Three one-click sizes, 5 · 15 · 25**, with the learned size highlighted. Return starts the highlighted size.
  - "Later today": the learned time chips from v3, smaller, under the sizes. A chip still creates a `PlannedBlock` and its cue.
  - The copy never mentions the 2-hour goal. Progress toward it stays in the popover and the companion.
- **Start nudges** show the same three sizes.
- **Adaptive size ladder** (`CoachBlockSizeLadder`, a pure fold over the last 21 days of prompts and blocks; nothing extra is stored):
  - Sizes 5 → 15 → 25 → 50.
  - Two seen prompts in a row with no start: one size down.
  - "Feels too big" as the reason: straight to 5.
  - A start from a prompt sets the size to the size started.
  - Three completed blocks in a row at the current size or longer: one size up, at most 50.
  - The panel shows why: "5m: the last two asks didn't land".
- **Popover.** The idle popover leads with "Start small, now" and one button for the suggested size. The Duration picker below it already offers every size, so the popover has no second row of sizes. "Plan it for later" chips sit under it.
- **Keep going (Ovsiankina): deferred.** The session-complete window already offers "continue focusing". A short-block "+10 min" ramp is the next step after live data.

### 3.4 Ask why, then act on it (F6)
- **"Not now ▾" on start prompts** gains a reason section:

  | Reason | What the coach does next |
  |---|---|
  | Busy with work | Quiet for 60 minutes. The next ask comes at the next breakpoint. |
  | Too tired | Quiet until tomorrow if it is after 20:00. Otherwise quiet for 60 minutes and offer 5 minutes next time. |
  | Feels too big | The next ask is 5 minutes. |
  | Don't know the next step | The next ask is "5 minutes to find the next step". |

- **Storage.** The reason is stored on the attempt (`skipReasonRaw`). It is never a penalty: a reasoned decline is a snooze with information.
- **Insights → "What stops you"** shows the top reasons for the last 14 days and what the coach changed because of them.

### 3.5 Rescues respect the day job (F5)
The rescue ladder's on-screen asks (L1 and L2 panels, L3 pause screen) run only in learned windows (`avail:high`). Elsewhere a rescue drops to the menu-bar counter. Pseudo-work and derailer facts are still tracked.

## 4. Code map
- **Pure logic:** `Services/Coach/CoachStartFirst.swift` (`CoachPresence`, `CoachBlockSizeLadder`, `CoachDeclineResponse`, `CoachPromptAttribution`, `CoachRescueWindowPolicy`), plus `Services/Coach/CoachJournal.swift`.
- **Wiring:** `TimerViewModel`:
  - Coach-v4 section: `startLadderRecommendation`, `handleArrival`, `performCoachPanelStart`, `performCoachPanelDecline`, `startNextBlock`.
  - Existing paths: `creditCoachPromptForStart`, the presence gate in `evaluateIdleStarterIntervention`, the arrival check in `coachIdleTick`, and the start card in `evaluateDailyPlanInvite`.
- **Guardrails:** `CoachGuardrails.Delivery.wasSeen`.
- **Ledger:** `CoachRewardLedger.creditLatestSeen`.
- **UI:** size pills and the reason menu section in `CoachPanelView`; the popover chooser in `PopoverPlanCard`; Insights in `CoachInsightsSections` (`CoachStartFirstBlock`).
- **Tests:** `CoachV4StartFirstTests`.

## 5. Success criteria
- Prompts seen → starts ≤ 10 min, 14 days: from 4/72 (6%; 0 credited) to ≥ 25%. Badges are excluded from the denominator.
- Unseen start panels: from 7/8 to ≤ 10%.
- Focus blocks per week: from about 10 to ≥ 15, at any size.
- Every decline with a reason changes the next ask. This is unit-tested.
