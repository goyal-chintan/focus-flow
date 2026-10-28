# Notch companion and goal-aware coach

Date: 2026-10-28 · Status: building · Builds on `2026-10-28-priorities-goals-design.md`

## Why
The user wants to track and start without opening the menu bar popover again and again: "rather than clicking again and again, I can reuse the notch to track and keep tracking". The coach should also understand the goal, not only the clock.

## 1. The notch companion
- **Placement.** A black island that merges with the MacBook notch. `NotchGeometry` finds it from `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea`. A display without a notch gets a 180 pt "virtual notch" on its top edge. The island prefers the built-in display. It follows display changes.
- **Compact** (always visible, about 74 pt wings): a ring on the left wing and a number on the right.
  - Focusing: block progress in the project colour, and the time left.
  - Paused: dimmed.
  - Overtime: an orange "+M:SS".
  - Break: green.
  - Idle: own-work progress against the daily goal, and today's own-work time.
  - Coach waiting: a breathing orange dot and "Start?".
- **Expanded** on hover (140 ms delay so passing through doesn't open it; closes 380 ms after the pointer leaves) or on a click. The island springs open (response 0.42, damping 0.82; a fade with Reduce Motion) and sizes to its content: no empty band.
  - **Idle:** the own-work ring; the coach's hook when one is waiting; today's lever with its reason; one-click 5 · 15 · 25 starts on the lever's project; the short honest verdict; a link to Goals.
  - **Focus:** the project chip, a 44 pt timer, the intent, a progress line, then Pause, +5 min, Finish, and "LeetCode +1", which logs progress on the block's goal, linked to the session.
  - **Overtime:** Keep going, Break 5 min, End.
  - **Break:** next lever, Start next block, Pause break.
- **Window.** A borderless, non-activating panel above the menu bar (`mainMenu + 3`). It never takes the keyboard. It is resized to the island so clicks beside it reach the menu bar.
- **Settings → General → Notch** turns it off.

## 2. Goal-aware copy
`CoachFacts.goal` holds the most urgent count result: done, target, how far behind pace, and days left.
- **Challenger start nudge:** "18 days left. LeetCode is 11 behind." with "Today's lever: 3 LeetCode questions." under it.
- **Data:** "LeetCode: 14 of 60 · 11 behind pace · 18d left."
- **Gentle:** "Today's step: 3 LeetCode questions?"
- **Rescues** add what the drift costs: "LeetCode is 11 behind with 18 days left."

When the goal is on pace, the copy raises no alarm.

## 3. Wording rules
- **Rates below one a day:** shown as "1 every 3 days", not "0.3/day".
- **"Behind" counts:** whole numbers. Under one reads "Slightly behind".
- **Unit-less levers:** read "Referral asks: 1 today". A count of one uses the singular unit ("1 SQL question").
