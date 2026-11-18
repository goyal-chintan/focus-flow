# Coach v7: land the block, return from the break

Date: 2026-11-06 · Status: built (branch `fix/coach-adapts-and-speaks`) · Extends v6 (`2026-11-06-coach-v6-adapt-and-speak.md`)

> "I'm stretching a particular session and then taking a longer break, and then taking some time
> to get back to the session. That was the primary challenge."

## 1. The cycle in your data (1 Sep – 6 Nov 2026, live store)

| Measure | Value |
|---|---|
| Focus blocks | 64 |
| Ran more than 5 min past the planned length | **31 (48 %)**. Median +3 min, p75 +12, p90 +19 |
| Block end → next block start, same sitting (< 4 h), n = 38 | Median **15 min**, p75 **86 min**, p90 132 min. The distribution has two peaks: 14 restarts within 2 min, and 11 that took 1–4 h |
| Next start after a block that **ended on time** (≤ 5 min over) | Median **24 min**; over 30 min in 44 % (n = 9) |
| Next start after a block **stretched 5–15 min** | Median **86 min**; over 30 min in **82 %** (n = 11) |
| Spearman correlation, overtime vs. gap | 0.34 (n = 24) |
| Recorded breaks | Median 10.5 min against 8 suggested; 12 of 31 more than twice the suggestion; 11 ran over by more than 10 min |
| The 16 gaps longer than 30 min | 9 began with a break you started in the app that then ran 30–90 min. 7 had no break: you ended the block and left |

**How much to trust this.** The sample is small and the data is correlational. Stretching may be a
*symptom* rather than a cause: you may stretch the last block of a sitting because you are about to
stop anyway. The design therefore treats "stretching causes long returns" as a hypothesis, and
§4 measures it with randomisation instead of assuming it.

**What the app does today.**
- At the planned end, the block switches to an open-ended count-up. Overtime counts as focus, and
  the notch's "Keep going" never ends.
- At the end of a break you get one notification and the break-over window, then nothing. No
  surface shows what you were in the middle of.
- The break warnings fire at 2 and 5 minutes *elapsed*, not before the break ends
  (`TimerViewModel.tick`).

## 2. What the research says

| # | Finding | Evidence | Lever |
|---|---|---|---|
| R1 | **Self-regulated breaks lead to longer work stretches and longer breaks, with more fatigue.** Fixed breaks gave better mood with the same task completion. | Biwer, de Bruin & Persky, 2023, *Br. J. Educ. Psychol.*: self-regulated breaks vs 24/6 and 12/3 schedules. A follow-up comparing Flowtime and Pomodoro found mixed effects on fatigue and motivation and no difference in outcomes. Both read from abstracts. | Hold the planned end and the break end. Make "keep going" a bounded choice, not an open-ended count-up. |
| R2 | **Attention declines with time on task**, typically within the first 20–35 min, with half of the decline in the first 15. | Vigilance-decrement literature (Warm et al., 2008; Teichner, 1974, as cited in later reviews) | Minutes 26–45 of a stretched 25-min block are low-yield time that still costs recovery |
| R3 | **Breaks help, and recovery scales with demand.** Micro-breaks raised vigour (d = .36) and lowered fatigue (d = .35). Longer breaks gave larger performance gains, and highly depleting tasks may need more than 10 min. | Albulescu et al., 2022, *PLOS ONE* 17(8): e0272460, a meta-analysis of 22 samples, N = 2,335 | Size the break to the minutes *actually worked*, so a stretched block earns a longer break up front instead of an unplanned one |
| R4 | **A suspended goal decays. A cue to the next step, set before the interruption, shortens the resumption lag.** | Altmann & Trafton's memory-for-goals model; Trafton et al., 2003, *IJHCS*; Hodgetts & Jones, 2006 | Before the break, write one line about the next step. At the end of the break, show that line and offer a start |
| R5 | **Stopping where you know the next step makes resuming easier.** | The Ovsiankina resumption tendency is robust (Ghibellini & Meier, 2025 meta-analysis, already used in v4). The "Hemingway effect" itself rests on thin evidence and is only used as a framing | Land the block with a known next step; don't run until you are empty |
| R6 | **Implementation intentions** ("when X, I will Y") work, with d = .65. | Gollwitzer & Sheeran, 2006 | "When the break ends, I start: <next step>." On a walk-away, "Back at 16:30?" |
| R7 | **Autonomy over breaks matters for recovery.** Chosen, relaxing breaks lowered fatigue; imposed ones did not. | Trougakos, Hideg, Cheng & Beal, 2014, *Acad. Manag. J.* | Never lock the screen or forbid anything. The coach holds the boundary by default; you can always override it, and it asks why |
| R8 | **Mentally reattaching before starting predicts engagement.** | Sonnentag & Kühnel, 2016 (morning reattachment) | The return cue *is* the reattachment: the next step, your goal line, and one tap to start |
| R9 | **Just-in-time adaptive interventions**: decision points, tailoring variables, decision rules and a proximal outcome, tested with micro-randomised trials. | Nahum-Shani et al., 2018, *Ann. Behav. Med.*; Klasnja et al., 2015 | The structure of §4 |

## 3. Design: three moments

### 3.1 Landing: the last 2 minutes and the planned end
- **At T − 2 min, a landing cue.** It is a quiet notch line, not a panel: "2 min left. Next step?" with
  a one-line field and the block's task preselected. The text is stored on the session as
  `FocusSession.nextStepText`, an optional attribute. (R4, R5)
- **At the planned end, Finish is the default**, and the break pill is sized to the minutes actually
  worked (R3).
- **Keep going becomes "+10 min"**, a bounded lap that ends with the same window. A second lap asks
  one reason chip (*In flow · Finishing a thought · Lost track*). An open-ended count-up stays
  available, but only by choice. (R1, R7)
- **During a stretch, one fact at +5 min**, from your own data and shown only once there are ≥ 8
  samples: "Blocks you run 5+ min over are followed by a 86-min gap; blocks that end on time, 24 min."
- **Natural length.** When at least 60 % of the last 15 blocks ran 8+ min over *while focused* (no
  pauses), the coach asks one quick question (v6 §3.4): "Your blocks run about 35 min. Make 35 your
  usual?" A block that ends where you planned beats a 25 you always break. The boundary then holds
  at 35.

### 3.2 Return: when the break ends
A return ladder, keyed on time since the break should have ended:

| When | Surface | Content |
|---|---|---|
| End − 1 min | Notch line (it replaces the 2- and 5-min "elapsed" warnings) | "1 min. Next: <next step>" |
| End | Panel; it stays until answered | "Back to: <next step>" · Start 25m · Start 10m |
| +3 min | Notch turns amber, and the panel stays | Overrun counter |
| +10 min | Panel | The v6 "What happened?" chips, plus "Start 5m on <next step>". A smaller re-entry after a long break uses the proximal-goal / foot-in-the-door logic from v4 |
| +30 min | — | The break is closed as ended. The next arrival breakpoint (v4) shows the next step |

### 3.3 Walk-away: a block ended with no break
- **"Done for today" before 19:00 with the goal not met** asks, without blocking you: "Back at…?"
  with chips for +30 min, +1 h, +2 h, the next own-work window, or *Really done*. A chip creates a
  `PlannedBlock` with its own cue (R6).
- **The arrival prompt** (you come back after 10+ min away) leads with the stored next step.

## 4. Learning: what the coach learns, and how

**Proximal outcome.** The return latency *R*: minutes from the block's end to the next block's start.
It is censored at 4 h or the end of the day. Its secondary forms are a start within 10 min of the
break's end, and minutes stretched past the plan.

| Learner | Method | Why this one |
|---|---|---|
| **A. Return hazard** | A discrete-time hazard model: Bayesian logistic regression on person-minute rows. Features: overtime, active minutes, whether a break was taken and its ratio to the suggestion, next step captured, hour, inside an own-work window, prompt shown. | Built for time-to-event data with censoring (an evening with no return is information, not missing data). It works with ~40 cycles a month when it starts from priors, as v5 does. It predicts *when* the return probability collapses, so the ladder steps can move to just before that point for you. |
| **B. Does the lever work?** | Micro-randomisation at three decision points: T − 2 landing cue, break-end panel vs notification only, and the +10 min re-entry offer. The probability is clipped to [0.2, 0.8], with fixed 0.5 for the first 30 decisions, and effects are estimated action-centred (the same estimator as v5 Learner A). | The only honest way to learn whether the coach *causes* faster returns, given that stretching may be a symptom (§1). It is the HeartSteps / micro-randomised-trial method. |
| **C. Break length** | Thompson sampling over 5 · 10 · 15 min, conditioned on active minutes. The reward is a return within 5 min of the break's end *and* the next block ending within 5 min of plan. | Optimises the whole cycle, not the break alone. Its prior is the current effort-based table (`EarnedBreakSuggestionEngine`). |
| **D. Natural length** | A plain rule plus a question (§3.1), not a model. | One number, asked once, with your answer as the label |

**Rejected.** Deep learning or RL: there are about 64 blocks in two months, far too few. A supervised
"will you return" classifier: it would predict who returns anyway, not what helps you return (the
same argument as v5 §2.2).

**What you'll see.** Insights → "What the coach noticed" gains a **Cycle** line: "Block end →
next start: median 15 min (was 86 after stretched blocks)." It also shows each lever's measured
effect once there are 20+ randomised decisions.

## 5. Success criteria (4 weeks after install)
- Blocks stretched by more than 5 min without choosing "+10": from 48 % to ≤ 20 %.
- Block end → next start (same sitting), p75: from 86 min to ≤ 40 min.
- Breaks more than 10 min over: from 11 of 31 to ≤ 15 %.
- Own-work blocks per day: up. This is the north star; the cycle exists to serve it.

## 6. As built (6 Nov 2026), and where it differs from the proposal
- **The landing cue is a floating coach card, not a notch line.** The notch panel can't take
  keyboard focus, and the coach card can. The card hides itself after 150 s. The block-end window
  has the same "Next step" field.
- **The return panel's probability is 0.7, not a 50/50 split**, so most breaks get help while 30 %
  stay as the control. The treated arm gets the whole ladder (the panel at the end, re-entry at
  the learned minute). The control arm gets the notification and the break-over window only.
  Decisions are kept in `CoachCycleLog` (UserDefaults), not `InterventionAttempt`.
- **Learner C (break-length Thompson sampling) is deferred.** It needs the outcomes learner B is
  now collecting. Breaks keep `BreakAdaptation` (v6).
- **The landing cue and the +10 re-entry are not separately randomised yet.** Only the break-end
  panel is.
- **Learner A on the live store (22 breaks in 60 days):** back within 5 min of a break's end 28 %
  of the time. The per-minute hazard falls from 0.073 (0–3 min) to 0.014 (6–10 min), so the
  re-entry offer comes at +6 min.
- **"Keep going" now means a 10-min lap on every surface:** the notch, the popover and the
  block-end window. The popover used to start a new block.

## 7. Code map
- **Pure logic:** `Services/Coach/CoachCycle.swift` (`CoachLanding`, `CoachReturnLadder`,
  `CoachCycleStats`), `Services/Coach/CoachReturnHazard.swift` (discrete-time hazard on the existing
  `BayesianLinearModel`).
- **Model:** `FocusSession.nextStepText` (optional). Decision points are logged as
  `InterventionAttempt` with new context keys (`cycle:landing`, `cycle:return`, `cycle:reentry`).
- **Wiring:** `TimerViewModel.tick` (T − 2, break end − 1, ladder steps), `timerCompleted`,
  `continueAfterCompletion(.continueOvertime)` → a +10 lap, `.endSession` → "Back at…?".
- **UI:** a landing field in `NotchView`, the return panel kind in `CoachPanelPresentation`, the lap
  button in the block-end footer, and a Cycle line in `CoachPatterns`.
- **Tests:** `CoachCycleTests`: the ladder timings, lap bounds, a hazard-model fit on synthetic
  data with a planted effect, and the stats on fixed data.
