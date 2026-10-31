# Onboarding v2: what, when, first step

Date: 2026-10-31. Branch: `feature/onboarding-v2`. Replaces the tour in `2026-10-28-onboarding-design.md`.

## 1. What is wrong with the current tour

The user's verdict: it feels like a Pomodoro timer, and a one-minute set-up loses the meaning.

The screens agree:

| Screen | What it says | Problem |
|---|---|---|
| Welcome | A big ring that reads **5 min**. "Start small. Start now." The first promise is "Blocks of 5, 15 or 25 minutes". The button is "Set me up · 1 min". | The first thing a new person learns is a block length. That is a timer app. |
| What matters most | Name, then **Kind** chips, a 10-dot **Color** row and **Time a day** chips. | Three choices with no meaning for the person. Kind and colour can be inferred. |
| One result | Count, target and deadline. | Good, but heavy for minute one. It is the only optional step, and it sits in the middle. |
| Your coach | Three style cards, a preview and three facts. | A full screen for one setting. |
| First block | A notch on/off toggle, a summary, confetti and **Start 5 minutes**. | It starts a block *now*, whatever the time. At 15:00 in the office, that 5-minute block on "Interview prep" is fake. The confetti celebrates a timer. |

It also never asks the two things the coach depends on most:

1. **When** the person does their own work. Without own-work windows, the coach guesses from history (coach audit 2026-10-30). On a new install there is no history, so the coach is either silent or wrong for the first weeks.
2. **Why** it matters. The coach quotes "My why" lines back on hard days (`CoachMessageComposer` `whyLines`, `DailyReminder.ownLines`), and the project page shows `purpose`. The tour leaves both empty.

## 2. What the evidence says

| Finding | Source | What we take from it |
|---|---|---|
| Plans of the form "when X happens, I will do Y" (implementation intentions) raise goal attainment by a medium-to-large effect (d ≈ 0.65 across 94 studies). | Gollwitzer, *American Psychologist* 54(7), 1999; Gollwitzer & Sheeran, *Adv. Exp. Soc. Psychol.* 38, 2006 | Ask **when** and **what first**. Not how long. |
| Asking people to write down the date and time they will act raised flu-shot uptake against a control letter. | Milkman et al., *PNAS* 108(26), 2011 | A concrete time beats a general intention. Make the tour end on a time. |
| Goals that express personal values are pursued with more sustained effort than goals felt as "should". | Sheldon & Elliot, *JPSP* 76(3), 1999 (self-concordance model) | Ask one line of **why**, and feed it to the coach. |
| Behaviour happens when motivation, ability and a prompt meet at the same moment. | Fogg, *Persuasive '09*, 2009 (B = MAP) | The prompt belongs in the person's window, not at install time. |
| Onboarding should be brief, skippable, teach by doing, and ask for permissions in context, not up front. | Apple Human Interface Guidelines, "Onboarding" | Three questions, Skip on every screen, no permission prompts. |

Not used: mental contrasting's "obstacle" step (Oettingen, *Eur. Rev. Soc. Psychol.* 23, 2012). It works, but it is a fourth question, and Insights already asks "What derails me?" from real data. We can add it later, in context.

## 3. The new tour

Four screens. Three questions and one confirmation. Each screen has one required decision at most, and it is preselected where we can guess well.

| # | Screen | Asks | Required? | Feeds |
|---|---|---|---|---|
| 1 | **What do you want more time for?** | Name (or tap a suggestion). One optional line: "Why does it matter?" A small "Counts as" menu. | Name only | `Project` (#1, area, purpose), `AppSettings.coachMyWhyText` |
| 2 | **When can you work on it?** | Pick one or two times of day (chips, or a custom time). How much a day. | One time (preselected) | `AppSettings.coachOwnWorkWindows`, `Project.dailyTargetMinutes` |
| 3 | **What's the first step?** | One concrete next action. Optional: "Track a number" (count, deadline, live pace). | No | `DailyTask` for the #1 project; `ProjectGoal` + `GoalKeyResult` when a number is tracked |
| 4 | **Here's your plan** | Coach tone (Gentle · Data · Challenger) on a live preview of what the coach will say at the next window. | No (preselected) | `AppSettings.coachStyle`, a `PlannedBlock` at the next window |

### 3.1 How it stays light

- **No welcome screen.** Screen 1 has a small "Welcome to FocusFlow" line above its question. The first click already does something.
- **Inferred, not asked:** colour (the suggestion's colour, else the next unused one), icon (the kind's), kind (from the suggestion; custom names default to Personal; the "Counts as" menu fixes a wrong guess).
- **Preselected:** the time-of-day chip that contains *now* (people often install during a free moment), else Evening. One hour a day. The current coach style.
- **Removed:** the colour row, the kind chips, the notch toggle (on by default, Settings → General), the coach facts row, the 5-minute ring, and the confetti.
- **Skip** is on every screen and writes only `onboardingCompletedAt`. Nothing is saved until the last screen.

### 3.2 How it is smart

- **Capacity check.** If "a day" is more than the chosen times hold, screen 2 says so: "That's more than 1h 30m of windows. Add a time or lower it."
- **Week line.** Screen 2 shows the result in plain words: "Every day 22:00–00:00 · 1h → 7h a week on Interview prep."
- **First-step suggestions** follow the kind (Learning: "Solve 2 easy problems"; Personal: "Write the first paragraph"; Work: "Outline the doc").
- **Pace line.** When a number is tracked, the pace recomputes on each change ("2/day for 1 month"), as today.
- **The preview is the real coach.** Screen 4 reuses `CoachStylePreviewCard` from Settings → Coach, fed with the first step and the regular block length. The tone switch rewrites it in place.
- **The ending depends on the clock:**
  - Inside a chosen window (or within 10 minutes of one): **Start now · 25 min** (the regular length), with "Finish" beside it.
  - Otherwise: **Done · see you at 22:00**. This saves a `PlannedBlock` at the next window start for the #1 project, so the planned-start cue appears then. "Start now instead" sits beside it.
- **Run it again** (Settings → General → Getting started, or the popover menu): every screen is prefilled from the store (the #1 project, its purpose, the windows, the style). The ending says **Save** if nothing changes the clock decision.

### 3.3 Words

No block lengths on screens 1–3. Vocabulary follows the screen audit: block, Start, Finish. Titles are questions. Subtitles say why we ask, in one line.

### 3.4 Look and motion: premium, not a template (revised twice on 2026-10-31)

Two rejected versions set the bounds:

- **v1, "AI slop":** a purple radial glow behind every screen, purple on every chip, rounded bold headings, gradient tiles. The colour meant nothing. Design write-ups list these as the giveaways of generated UI ([925 Studios](https://www.925studios.co/blog/ai-slop-design-tells), [Superdesign](https://www.superdesign.dev/blog/how-to-make-ai-ui-look-less-generic)).
- **v2, "a settings screen":** native grouped form rows. Correct, but no excitement and no sense that something is being made for you.

**The idea: you build one object, and you watch it come alive.** The window has two halves. On the left, the question and its controls. On the right, a stage with a single Liquid Glass card: *your #1*. Every answer changes the card at once, with a spring. The card replaces the progress bar. Its empty slots ("When?", "First step?") show what is still to come, and they fill in as you answer.

| Step | What the card does |
|---|---|
| 1. What | The card starts as an empty outline. Typing a name fills it. A kind button swaps the icon with a symbol bounce. A suggestion sets the project colour, and the card's coloured shadow fades to it. The why appears as a quote. |
| 2. When | A **24-hour day dial** lights up. The track is a faint sky (night navy, dawn orange, noon blue, dusk pink), so the colour means time of day. Each picked time draws on as an arc in the project colour. A dot marks *now*. The centre shows "1h a day". |
| 3. First step | A checklist row draws its circle and fades in the step. Tracking a number adds the pace line under it. |
| 4. Plan | The card lifts. A coach bubble springs out from under it with the real coach message, in the tone you pick. |
| Finish | The card shrinks and flies to the top-right, toward the menu bar where FocusFlow lives, and the window closes. That teaches where the app is without a sentence. |

**Colour has a job.** The base is the plain window background. The only strong colour is *your* project's colour, and it appears only after you choose it: on the card's icon, its arcs, its shadow and the Continue button. Before that, everything is neutral. The sky track on the dial is the one other colour, and it encodes the time of day. No preset is purple.

**Motion** (Apple, *Designing Fluid Interfaces*, WWDC 2018; Apple HIG, Motion):

- Springs, critically damped by default (damping 1.0, response 0.35–0.5). A little bounce (0.8) only on the dial arcs and the card's reaction to a choice, because those are physical changes.
- Each step's text **materializes**: opacity, an 8 pt blur and a 10 pt rise together, staggered by about 40 ms (label, title, subtitle, controls).
- Step changes push the left pane 24 pt in the direction of travel. The card never leaves the screen; only its content changes.
- Every animation can be interrupted. Clicking fast never queues motion.
- Reduce Motion: cross-fades only, with no blur, rise, pulse or fly-home.

**Type:** SF Pro. Titles are 30 pt bold with −0.6 tracking. Rounded type only for numbers (the dial centre).

**Controls** (`UI_DESIGN_GUIDE.md`): capsule `.glass` buttons, the selected one `.glassProminent` in the project colour, grouped in a `GlassEffectContainer`; text fields on `.glassEffect(.regular)`.

### 3.5 Revision 3: the coach meets you, full screen

The user's feedback on revision 2: the window was small, and the tour still read as a task tracker or a timer. **FocusFlow is a coach for your life goals.** It helps you focus, keeps you motivated, adapts to you, and tracks your goals for you. The tour must feel like meeting that coach and setting your direction, not like filling in a form.

**Full screen.** The tour covers the active display in a borderless window over a behind-window blur (`.fullScreenUI`), the same pattern as the rescue pause screen. It fades in over 0.45 s. It activates the app, because you type into it. Esc does not close it; Skip does.

**The coach speaks, in the first person.** Each screen is one question from the coach, with your answer below it. Your goal card, on the right, builds up as you answer.

| # | Screen | Coach says | You answer | Card |
|---|---|---|---|---|
| 0 | Meet | "Hi. I'm your coach." Then three promises, one at a time: *I learn when you work best. I show up at the right moment. I keep track of your goal for you.* | **Let's set your direction** | (none yet) |
| 1 | Direction | "What do you want to make happen in the next few months?" | A goal: tap one ("Land a better job", "Ship my side project", "Learn a new skill", "Write every week", "Read more books") or type your own. Then "Why does this matter to you?" | Goal name, kind, your why as a quote |
| 2 | Measure | "How will we know it's working?" | What to count, how many, by when (prefilled from the goal), and the very first step. "Decide later" skips the number. | A progress ring (0 of 60), pace and deadline; the first step |
| 3 | Rhythm | "When are you at your best?" | Times of day, and time a day | The day dial |
| 4 | Coach | "How should I talk to you?" Then "Here's my plan for you." | Gentle, Data or Challenger; Start now or Done | Coach chip; the live coach bubble |

The goal name becomes the #1 project's name ("Land a better job"), so the menu bar, notch and coach all speak in terms of your goal rather than a category. Tracking a number is on by default, because tracking goals is the coach's job; the goal's presets prefill a sensible number.

**Data stays the same** (§4): project (#1, area, purpose, daily target), own-work windows, My why, goal and key result, today's task, a planned block, coach style. Nothing new is collected.

## 4. Call graph

```
FocusFlowApp.onAppear → showOnboardingIfNeeded()            (unchanged)
  → OnboardingLaunch.decide(completedAt:hasSessions:)        (unchanged)
  → timerVM.openOnboarding → openWindow(id: "onboarding") → OnboardingView
Settings → General → "Show Tour" / popover menu "Welcome tour" → timerVM.openOnboarding (unchanged)

OnboardingView.finish(start:)
  → OnboardingDraft.commit(projects:goals:settings:in:now:regularMinutes:)
      → ProjectDraft.apply(to:others:in:)          rank 1, area, colour, icon, purpose, daily target
      → settings.coachMyWhyText += why             (deduplicated, ≤ 5 lines)
      → settings.coachOwnWorkWindows = windows
      → GoalDraft.apply(in:existing:)              only when a number is tracked
      → DailyTask insert                           first step; linked to the key result when there is one
      → PlannedBlock insert                        next window start, when not starting now
      → settings.coachStyle, coachPauseScreenEnabled, dailyFocusGoal (own work), onboardingCompletedAt
  → timerVM.startNextBlock(minutes: regularMinutes, projectID:)   only for "Start now"
```

Readers of what the tour now writes (no changes needed, all read live from settings or the store):

- `coachOwnWorkWindows`: `TimerViewModel.coachGuardrailInput` (daily cap), `currentOwnWorkWindow`, `hasDeclaredOwnWorkWindows`, `planTomorrowSlots`, `evaluatePlanTomorrowCheckIn`.
- `coachMyWhyLines`: the composer inputs in `TimerViewModel` and `DailyReminder.ownLines`.
- `Project.purpose`: `ProjectsListView` subtitle and `ProjectFormView`.
- `PlannedBlock`: `evaluatePlannedCue` → `presentPlannedCue` (uses `title` and `projectID`), `nextPlannedBlock` (popover).

Defaults to respect: quiet hours are 00:30–07:00, so no preset window starts before 07:00. Windows never wrap past midnight, so "Late night" ends at 00:00 (minute 1440).

## 5. Code

- `Services/Onboarding/OnboardingPlan.swift`: `OnboardingStep` (`what`, `when`, `firstStep`, `plan`), `OnboardingWindowPreset`, `OnboardingDraft` (windows, why, first step, inference, capacity, week line, next-window and ending decision, commit).
- `Views/Onboarding/OnboardingView.swift`: the four screens.
- `Views/Onboarding/OnboardingComponents.swift`: the hero card, the day dial, pills and the materialize modifier.
- `SettingsView`: the "Getting started" footer text.
- Tests: `OnboardingTests` updated for the four steps, the window presets, capacity, the ending decision, the commit (windows, why, task, planned block), and captures for every screen.
- Docs: `GETTING_STARTED.md` §2 and the `CLAUDE.md` tour line.

## 6. How we will know it works

The coach's own metric: prompts seen → starts within 20 minutes (coach journal). For the tour, two checks in the first week of a new store:

1. The first window has a planned-start cue, and it is seen.
2. A block starts in a declared window on day 1 or 2.

Both are visible in Settings → Coach → How the coach is doing → Today's coach log.
