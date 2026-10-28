# Coach v5: a learning engine for starting

Date: 2026-10-28 · Status: building · Extends `2026-10-28-coach-v4-start-first-design.md`

> "Have you considered the learning mechanism — machine learning, simple if-else rules, or a more sophisticated algorithm — to understand my behaviour and then act? That should be based on science as well."

## 1. What gets people started: the evidence, ranked

Strongest evidence first. Each item ends with the coach lever it maps to.

| # | Finding | Evidence | Coach lever |
|---|---|---|---|
| 1 | **Deciding when and where in advance.** "If it is X, I will do Y." | Meta-analysis, 94 studies, d = 0.65 (Gollwitzer & Sheeran, 2006) | Start card time chips; planned cue (v3) |
| 2 | **Change the situation, not the willpower.** Strategies that act before the impulse (remove the phone, block the site) beat resisting in the moment. | Review, Duckworth, Gendler & Gross, 2016, *Perspect. Psychol. Sci.* 11(1) | Offer site/app blocking at the start of a block (existing blocking profiles) |
| 3 | **CBT-style procrastination programmes work, and the effect lasts.** They combine planning, small steps, challenging thoughts and self-monitoring. | Meta-analysis, 24 studies, N = 1,173; CBT strongest (van Eerde & Klingsieck, 2018). Internet CBT RCT, N = 150, d ≈ 0.7–0.8 (Rozental et al., 2015) | The whole loop: monitor (journal), small steps (sizes), name the obstacle (reasons) |
| 4 | **Name the obstacle, then if-then plan around it** (mental contrasting, MCII). | Meta-analysis, 21 studies, g = 0.34 (Wang, Wang & Gai, 2021) | "Not now, because…" with an immediate counter-offer (v4) |
| 5 | **Small, near goals; ask small first.** | Proximal subgoals beat distal goals (Bandura & Schunk, 1981). Foot-in-the-door: a small yes raises a later bigger yes (Burger, 1999 review) | 5 · 15 · 25 sizes; the learned size |
| 6 | **Adaptive goals beat fixed goals over time.** | Percentile-shaped goals declined less over 4 months than a fixed 10,000-step goal (Adams et al., 2017, *BMC Public Health*) | Learn the size from your own response, not a fixed 2h |
| 7 | **Once started, people tend to continue.** | Ovsiankina resumption ≈ 67% against a 50% baseline (Ghibellini & Meier, 2025) | Reward includes minutes after the start; continue offers |
| 8 | **Pair the hard thing with a want.** | Temptation bundling: more gym visits, effect fades (Milkman, Minson & Volpp, 2014) | Later: "only during focus" rewards (not in v5) |
| 9 | **Prompt at receptive moments, and prompts wear out.** | Personalised receptivity models raised engagement by up to about 40% (Mishra et al., 2021). Responsiveness to repeated messages fell from 93% to 47% over 8 weeks (habituation). | Presence gate (v4); learned timing; a burden feature |
| 10 | **Self-compassion, not shame.** | Self-compassion is negatively associated with procrastination and mediates stress (Sirois, 2014; correlational) | Copy rules: no shaming |
| 11 | **Reward structure can correct the gap between now and later.** | Optimal gamification reduced procrastination (Lieder et al., 2019, *Nat. Hum. Behav.* 3) | Later: pseudo-rewards on priority work (not in v5) |

**What does not hold up.** Willpower or ego-depletion framing is weak evidence, so the coach never relies on it. The Zeigarnik memory effect did not replicate in the 2025 meta-analysis, so "unfinished tasks nag you" is not used; only the resumption tendency is.

## 2. Which learning mechanism, and why

### 2.1 What the coach learns today (audit)

| Learner | Method | What it learns | Problem |
|---|---|---|---|
| Availability | Beta-Binomial posterior per hour of the week (168 buckets, smoothed) | When you tend to start | Sound. Keep it. |
| Prompt bandit | Thompson sampling, Beta per (context cell × surface) | Whether and where to prompt | 61 scored prompts across 16 cells, 10 cells with one observation, 0 successes in the cells. Cells share nothing, so it can't generalise. It credits a prompt for starts that would have happened anyway: the prompt-plus-start reward measures correlation, not effect. |
| Quote picker | Thompson sampling, Beta per quote | Which line goes with starts | Fine. Minor. |
| v4 size ladder | Hand-written if-else rules | Size to ask | Not learning: the same rules for everyone, forever. |
| v4 reasons | Fixed if-then | What to do after "Not now" | Correct as an immediate response (MCII). It never checks whether the response worked. |

### 2.2 Options considered

| Option | Verdict |
|---|---|
| **If-else rules only** | Transparent, but they never adapt to you. This is v4's ladder. Kept only as *priors*. |
| **Supervised ML** (logistic regression, gradient boosting) predicting "will start" | Predicts *when* you start, not whether a prompt *causes* a start. Prompting when you would start anyway looks great and does nothing. It needs far more labels than 64 sessions. |
| **Deep RL / neural nets** | Far too data-hungry for one person's ~100 decisions a month. Unstable, and hard to explain. |
| **Tabular bandit** (the current one) | Learns, but every context cell starts from scratch, so with 16+ cells it never converges. |
| **Bayesian linear contextual bandit with action-centring and clipped randomisation** | ✅ Chosen. This is how HeartSteps decides whether to send a just-in-time suggestion (Liao, Greenewald, Klasnja & Murphy, 2020, *Proc. ACM IMWUT* 4(1); Greenewald et al., 2017, NeurIPS). It is data-efficient (shared linear weights), keeps uncertainty (it knows when it doesn't know), and estimates the *effect* of a prompt. It stays explainable: each weight is a sentence. RL-chosen messages also beat static policies in a 26-week diabetes trial (Yom-Tov et al., 2017, *JMIR* 19(10)) and in MyBehavior (Rabbi et al., 2015, UbiComp). |

### 2.3 Design principles
1. **Rules become priors; data overrides them.** Every learner starts from the science-based rule (the v4 behaviour) as its prior mean. With no data, v5 behaves like v4. Each observation moves it toward *your* behaviour.
2. **Learn the effect, not the correlation.** The coach models start(prompt) − start(no prompt) at the same moment. Starts you would have made anyway earn the prompt nothing.
3. **Keep a little randomness.** The prompt probability is clipped to [5%, 80%] (HeartSteps also clipped its randomisation probabilities). This keeps learning alive, lets the coach estimate its own lift honestly (inverse-propensity weighting), and avoids locking in an early wrong belief.
4. **Hard limits are never learned.** Quiet hours, calendar, screen share, presence, the daily cap and panel spacing stay rules. The learner only chooses inside them.
5. **Everything is explainable.** Insights shows each learned weight as a sentence, plus the measured lift of prompting.

## 3. The engine

### 3.1 Decision points and the reward
- **Decision point.** Every time the idle coach evaluates a start prompt and all hard limits allow one. That is the tracker's nudge schedule (5, 10, 25, then every 15 minutes idle) plus arrival breakpoints. Each decision is logged, *including the silent ones*, with features `x`, prompt probability `π`, action `a` (prompt or not) and the size asked.
- **Reward, resolved after 60 minutes from the sessions table:** `r = 1[a block started within 10 min] + 0.5 · min(focused minutes in the next 60 min, 50) / 50`. The start dominates (your stated goal), and momentum adds up to half as much again (Ovsiankina). No click is needed: a start from the popover counts.

### 3.2 Learner A: should I prompt now? (action-centred Thompson sampling)
- **Model:** `r = g(x) + (a − π) · xᵀθ + ε`. Only θ, the prompt *effect*, is estimated, by Bayesian linear regression on `z = (a − π)·x`. `E[a − π | x] = 0` cancels any baseline `g(x)`, however complex (Greenewald et al., 2017).
- **Variance reduction:** fit a linear baseline ĝ(x) first and regress `r − ĝ(x)` on `z`. That stays unbiased, because any function of x is uncorrelated with `a − π`. Without it, "would have started anyway" noise swamped the effect in simulation.
- **Policy:** effect `e = xᵀθ ~ N(xᵀμ, xᵀΣx)`. Then `π = clip(P(e > c), 0.05, 0.80)` with cost `c = 0.05`: a prompt must raise the start chance by about 5 points to be worth an interruption. The coach draws `a ~ Bernoulli(π)`.
- **Eligibility:** the v4 gate stays: a learned window, or an arrival. Otherwise off-hours decisions would spend the 3-a-day cap before evening (v3 R1).
- **Features (12):** bias; learned availability lift now; arrival breakpoint; hours since the last block; any block today; prompts seen in 24 h (burden or habituation); late night; frontmost is a derailer; frontmost is work; "too tired" said in the last 12 h; missed yesterday; weekend.
- **Prior (science → numbers, in start-probability units):**
  - **baseline effect 0, sd 0.03.** Average prompt effects in mHealth trials are small, so context weights must carry the signal.
  - **availability +0.05, arrival +0.05, sd 0.1** (receptive moments).
  - **burden −0.05, late night −0.03, tired −0.05, sd 0.05.** These have direct evidence, so their priors are tight. A vague prior means more exploration, and the coach should not explore at 1 a.m.
  - **everything else 0, sd 0.1.**
  - With no data the coach prompts about 10% of plain eligible moments, and about 60–70% at an arrival in a good hour.
- **Simulation** (`CoachLearningTests`, 800 decisions, about 1–2 months). The synthetic user starts 60% of the time at their usual hour, prompt or not, and responds to prompts only after coming back to the desk (+35 points).
  - The learner puts the effect on "coming back to the desk" (arrival weight about 0.16) and about 0 on the usual hour.
  - Arrival moments reach the 80% cap; usual-hour moments fall below 45%.
  - A correlational learner, like the v2 bandit, would have credited the usual hour.

### 3.3 Learner B: what size to ask? (linear Thompson sampling over 5 · 15 · 25)
- **Model:** one Bayesian linear model per size, predicting `r` from 6 features: bias; the v4 rule's suggestion as one-hot (5, 15, 25); late night; any block today.
- **Prior:** each arm's bias is 0.5. Its weight on "the rule suggests me" is +0.25, so with no data the v4 ladder decides. Late night tilts toward 5 (±0.05). Prior sd 0.1: with no data the rule wins about 85% of draws; about ten asks at a size move it.
- **Choice:** sample each arm's weights and ask the arm with the highest sampled `xᵀθ`.
- **Credit:** the observation goes to the size you *started*, or to the asked size when nothing started. This is implicit feedback: clicking 25 when 15 was offered teaches "25 here".
- **"Don't know the next step"** stays a rule: the immediate "find the next step · 5m" counter-offer.

### 3.4 What stays
- The availability model, now a feature of A.
- The v4 counter-offers (MCII's "then"). Whether they work is now measured by B's rewards.
- The start card: once a day, by rule. Its size comes from B.
- The rescue loop, still on its v2 bandit (out of scope).

### 3.5 Seeing what it learned
Insights → "What the coach learned":
- **Do prompts help you?** An inverse-propensity estimate: "With a prompt you started within 10 min X% of the time, without Y%". Shown once there are 20+ randomised decisions.
- **What it learned about prompting:** the three largest effect weights in plain words, for example "Coming back to the desk: prompts work better here."
- **Sizes:** the expected value of each size, and how many asks each has seen.

## 4. Code map
- **Pure logic:**
  - `Services/Coach/CoachLearning.swift`: `BayesianLinearModel` (Cholesky posterior and sampling).
  - `Services/Coach/CoachLearningPolicies.swift`: `CoachPromptFeatures`, `CoachPromptPolicy`, `CoachSizePolicy`, `CoachDecisionReward`, `CoachLiftEstimate`.
- **Storage:** new optional fields on `InterventionAttempt` (`decisionRaw`, `featuresRaw`, `propensity`, `treated`, `askedMinutes`). SwiftData adds optional attributes without a migration.
- **Wiring:** `TimerViewModel.evaluateIdleStarterIntervention` (decision and logging), `startLadderRecommendation` (Learner B), and the Insights `CoachStartFirstBlock`.
- **Tests:** `CoachLearningTests`. These cover the closed-form posterior and synthetic users: the policies must learn a planted effect, ignore a planted baseline, and shift the size for a user who only starts 5-minute blocks.
