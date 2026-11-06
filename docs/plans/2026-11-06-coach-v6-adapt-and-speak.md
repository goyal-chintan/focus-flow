# Coach v6: adapt, ask, and say what it sees

Date: 2026-11-06 · Status: building · Extends v4 (start first) and v5 (learning engine)

> "Why does the coach feel very silent? … I wanted it to adapt, to understand, and to have
> interactions with the user so that it adapts to them better while not being restrictive. If it
> doesn't understand anything, it could quickly collect the input."

## 1. What happened, 28 Oct – 6 Nov (live store and coach journal)

589 journal lines in 10 days. **4 start prompts were shown.** Every other decision point ended
quiet, or never became a decision point at all.

| # | Finding | Evidence | Code |
|---|---|---|---|
| S1 | **The declared windows miss the real work.** Since 5 Nov the coach decides only inside 07:00–09:00 and 20:00–22:00. In the last 30 days 17 own-work blocks started between 22:00 and 03:00, about 6 in 07–09 and **none** in 20–22. Outside a declared window nothing is evaluated. | 32 `outside_own_window` lines | `evaluateIdleStarterIntervention`, `evaluateRescueLoop` |
| S2 | **The drift ladder takes the turn, then cannot speak.** While a drift is active, idle prompts give way to the rescue ladder. The rescue is then held by the calendar, the cap or a "screen share". On 3 Nov both paths stayed quiet every 15 min for 6.5 h. | 68 `drift_active` lines, plus about 150 rescue holds | idle path `currentDrift` check |
| S3 | **The day job counts as drift.** Pacing pressure ≥ 0.5 switches the monitor on all day, and any work app counts as pseudo-work. One morning rescue that was ignored keeps the level at L2 until midnight. | Nov 3: L1/L2 08:19–14:49Z | `CoachDriftMonitor.isActive`, `classify` |
| S4 | **Being in a call counts as screen sharing.** The guard matches app names ("teams", "meet", "call"). The rule is: hide only while the screen is actually shared. | 58 `screen_share` lines | `ScreenShareGuard` |
| S5 | **The cap is used up before your hours.** Start cards (up to 2 a day, one right after midnight) and rescues use the 3 slots. | Nov 2: 42 `daily_cap` lines | `CoachDailyPlanInvite.maxPerDay`, guardrails |
| S6 | **The prompt learner never leaves warm-up.** 4 resolved decisions against a warm-up of 40. | `ZINTERVENTIONATTEMPT` | `CoachPromptPolicy.warmUpDecisions` |
| S7 | **The size learner is not true Thompson sampling.** It draws again for every comparison. The display uses the mean, the rule bonus keeps 25 ahead, and so it always says 25. | 18 size observations, all reward ≤ 0.33 | `CoachSizePolicy.choose` |
| S8 | **Nothing about your patterns reaches you.** Break data is never analysed. Your breaks run 21 min against 7.7 suggested, and 21 of 31 ran over. The advice cards sit in a collapsed Settings section. "Best windows" merges 8 hours into one. | `ZBREAKLEARNINGEVENT` | Insights, `CoachInsightsSections` |
| S9 | **The coach never asks when it is unsure.** It does not ask about wrong windows, or about breaks that run long. | none | — |
| S10 | **The pseudo-work check names a counter, not your work.** "Is this Problems Solved: 4 today…" | journal | `pseudoProductivityFocusName` |
| S11 | **The block-end window offered "Start 5m" right above "Break 5m".** A click meant for the break started a 5-minute focus block 6 times. | sessions 116 · 135 · 147 · 153 · 161 · 167 | `SessionCompleteWindow.footerBar` |

## 2. Principles

1. **Declared windows are a starting belief, not a fence.** The coach learns from when you
   actually start. When the two disagree, it asks you once instead of going silent.
2. **A gate that silences must be able to deliver.** A path may defer to another only when the
   other one can speak.
3. **Hard limits stay hard**: quiet hours, real screen sharing, presence, calendar, the daily cap.
4. **When unsure, ask one short question with one-tap answers.** The answer changes behaviour
   now. At most one question a day, never during a block or a share.
5. **Say what you see.** Patterns are plain sentences with numbers, shown where decisions happen.

## 3. Design

### 3.1 Windows that follow you (S1)
- `CoachWindowFit` (pure) reads the last 28 days of own-work block starts. It finds the hours
  where they cluster (at most 3 windows of 1–3 h, at least 3 starts each) and how many starts
  the declared windows cover.
- **The mismatch** is when declared windows cover under 40 % of at least 8 own-work starts.
- **Effective windows** are the declared ones plus the observed ones, until you answer the
  question. All gating uses them: idle prompts, rescues, drift activation. The cap's held slots
  count declared windows only.
- **The question (3.4).** "Your own work starts around 22:00–00:00 and 12:00–14:00, not your
  set windows. Use these?" The answers are: Use these · Add them to mine · Keep mine. "Keep mine"
  turns the observed windows off for 14 days.

### 3.2 Gates that can deliver (S2–S5)
- **Idle vs drift.** The idle path waits for the rescue ladder only when a rescue was shown in
  the last 30 min. Otherwise it decides normally.
- **Drift monitor.** With windows declared, pacing pressure never turns work apps into
  pseudo-work outside an effective window. Real derailers (YouTube, X) still count, so the menu bar
  counter stays honest.
- **Screen share.** It holds the coach only on a real capture or "Private now".
- **Start card.** Never before quiet hours end (it fired at 00:00 and used a cap slot). A closed card still means "later", so up to 2 a day.
- **Planned cue.** An unanswered planned cue stops blocking other prompts after 15 min.

### 3.3 Learners that move (S6, S7, S10)
- Prompt warm-up: 40 → 15 resolved decisions.
- Size: one posterior draw per arm (true Thompson sampling).
- Pseudo-work check: names the goal or project, never a "N today" lever line.
- Break length: an overrun you answer "needed the rest" counts toward a longer suggestion. "Got
  pulled away" or "lost track" counts toward keeping it short.

### 3.4 Quick questions (S9)
- A new coach panel kind, `.question`, with up to 3 one-tap choices and "Not now".
- At most one a day. It is logged in the journal (`question`), and every answer is stored and
  acted on.
- **Window fit**: see 3.1.
- **Break overrun**: when a break ends ≥ 5 min over, in the break-over moment: "Your break ran
  12 min over. What happened?" The answers are: Needed the rest · Got pulled into something ·
  Lost track. The answer is stored on the break's `BreakLearningEvent` (`overrunReasonRaw`).

### 3.5 What the coach noticed (S8)
`CoachPatterns` (pure) produces sentences with numbers, shown first in Insights:
- **Your hours**: the top own-work start hours (28 days).
- **Windows fit**: "Your set windows caught 6 of 47 starts."
- **Breaks**: "Breaks run about 21 min against 8 planned; 21 of 31 ran over; you came back to
  focus 22 times."
- **Block length**: the completion rate by size (5 · 15 · 25 · 50).
- The coach's start prompts may use "You usually start around HH:00" in every style.

### 3.6 Block-end footer (S11)
After a block there is no smaller start: Start 25m · Break Nm on one row, and Done for today
below it. After a break, the coach's learned smaller ask shows only when it is below your usual
length.

## 4. Success criteria (14 days after install)
- Start prompts shown: from 4 in 10 days to ≥ 1 per own-work day.
- `drift_active` and `screen_share` quiet lines: −80 %.
- No 5-minute focus blocks starting within 2 s of a block end.
- Insights shows at least 3 pattern sentences for this store.
- Every question asked has a stored answer or a "Not now".
