# Onboarding: set up in a minute, start in five

Date: 2026-10-28. Branch: `feature/onboarding`.

> Superseded by `2026-10-31-onboarding-v2-design.md` (what, when, first step, plan; no timer framing).

## 1. Goal

A new person opens FocusFlow and, in about a minute, has:

1. one project marked as their #1, with a daily target,
2. (optional) one goal with one countable result and a deadline,
3. a coach style they chose after seeing what it will say to them,
4. the notch companion on or off, by their choice,
5. a first 5-minute block running.

The last item is the point. The app's own success metric is "prompt → start". The tour ends on a start, not on "Done".

## 2. How long

Guidance from product onboarding practice (vendor research, not controlled studies): 3–5 steps, ask only what you use immediately, say why you ask, and make people do the core action instead of reading about it. No study we found gives completion rates by step count, so this is a judgement, not a measured optimum.

Chosen: **5 steps, 1 decision each**. The goal step has its own "Skip goal"; the whole tour can be skipped from any step.

| Step | Asks | Why the app needs it now |
|---|---|---|
| Welcome | nothing | Says what FocusFlow does in three lines. |
| What matters most | project name, kind, minutes a day | The coach, notch lever and daily split all key off the #1 project. |
| One result | what to count, how many, by when (optional) | Turns into "today's lever" and goal-aware prompts. |
| Your coach | Gentle, Data or Challenger | The preview uses the person's own goal, so the choice is concrete. |
| First block | notch on/off, start 5 min | The activation moment. |

Not asked: vision and anti-vision (too heavy for minute one; it lives in Goals), block profiles, blocking, calendar, permissions. Each of those is asked in context later.

## 3. Behaviour

- **First launch only.** Shown when `AppSettings.onboardingCompletedAt` is nil and the store has no sessions. A store with sessions (existing users) is marked done without showing the tour.
- **Again on request.** Settings → General → Getting started → "Show the welcome tour". The tour then pre-fills from the current #1 project and lets you pick an existing project instead of making a new one.
- **Nothing is written until the last step.** Skip at any point writes only `onboardingCompletedAt`.
- **Writes** go through the same `ProjectDraft.apply` and `GoalDraft.apply` as the forms, so rank shifting and key results behave the same. A new goal is the boss fight unless one already exists.
- **Start** uses `TimerViewModel.startNextBlock(minutes:projectID:)`, the same path as the notch.

## 4. Look and feel

- A fixed 640 × 600 window with hidden title bar.
- The background has a soft glow in the chosen project colour. It changes as you choose.
- The progress bar has 5 segments.
- Steps slide in the direction of travel.
- Return continues. Back is always visible after step 1.
- Live previews:
  - **Step 2:** a project card that updates as you type.
  - **Step 3:** a pace line that recalculates on each change ("2/day for 30 days").
  - **Step 4:** a speech bubble that rewrites itself for each coach style.
  - **Step 5:** a small animated notch.
- **Step 5** shows a short confetti burst when it appears. Reduce Motion turns off the glow drift, the slides and the confetti.

## 5. Code

- `Services/Onboarding/OnboardingPlan.swift`: pure.
  - `OnboardingDraft`: holds the answers. `commit` writes them to the store.
  - `launchDecision`: when to show the tour.
  - The suggestion presets.
  - The pace text and the coach preview text.
- `Views/Onboarding/OnboardingView.swift`: the window and the steps.
- `Views/Onboarding/OnboardingComponents.swift`: the shared parts, such as chips, the preview cards, the confetti and the mini notch.
- `FocusFlowApp`: adds the `Window(id: "onboarding")` scene, sets `timerVM.openOnboarding`, and makes the launch decision.
- Tests: `OnboardingTests` covers the launch decision, the commit and the copy. Captures for every step: `FOCUSFLOW_CAPTURE_OUTPUT_DIR=<dir> swift test --filter OnboardingTests/testCaptureOnboardingSteps`.
