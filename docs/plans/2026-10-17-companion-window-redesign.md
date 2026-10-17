# Companion Window & Settings Redesign + On-Screen Coach Prompt

Date: 2026-10-17 · Status: proposal · Scope: the companion window (Today, Calendar, Week, Insights, Distractions, Projects, Settings, Blocking) and the coach prompt surface. The menu bar popover is out of scope apart from spot fixes (§6).

Evidence:
- **Renders** in both appearances, made with `UIEvidenceCaptureTests.testCaptureCompanionWindowTabsAndSettingsInBothAppearances`.
- **Style inventory** of colours, fonts, spacing, materials and charts.
- **Code reads.**

Caveat: off-screen renders draw AppKit-backed controls (switches, pickers, segmented controls, sidebar selection) in the light appearance, so colour and contrast findings for those controls are marked *(confirm live)*. Layout, hierarchy, copy and chart findings do not depend on that.

---

## 1. What's wrong

### 1.1 Information architecture: 7 tabs, overlapping content

| Concept | Shown in |
|---|---|
| Focus time and sessions | Today, Calendar (month grid + day detail), Week (bars + heatmap + summary), Insights (sparkline, peak hours, session lengths) |
| Distractions | Distractions tab (idle rules), Settings → Blocking (sheet), Projects (blocking profiles), Insights (Guardian Recommendations), Today (Domain Signals), Week (Domain Patterns) |
| Coach | Settings → Focus Coach (14 controls + debug), Insights → Coach Report, Distractions |

The same question ("what's distracting me?") gets 6 partial answers in 6 places, and the user has to assemble the picture.

### 1.2 Everything is a glass card
- Every section is a `LiquidGlassPanel` (`.glassEffect`): Settings 9, Insights 8, Week 5, Distractions 5, Today 4 (`Views/Components/LiquidGlassPanel.swift:23`).
- `.glass` buttons sit inside them (`WeeklyStatsView.swift:58-81`, `CalendarTabView.swift:407`, `SettingsView.swift:1644, 1659`).
- This breaks the project's own rule ("glass on controls only, never glass on glass", `CLAUDE.md`, `UI_DESIGN_GUIDE.md`).
- Result: a long stack of same-weight dark slabs with no hierarchy. Content should sit on the window background, not on glass.

### 1.3 Settings is a custom form fighting macOS
- Hand-built rows instead of `Form`, so alignment is inconsistent:
  - `ToggleRow` switches hug their label (`SettingsView.swift:1826-1837`).
  - Integration switches are pushed right with `Spacer` + `.labelsHidden` (`:752, :967`).
  - Steppers and pickers float at different x positions (render: "5 min", "4", "2", "Balanced").
- 37 controls in 9 equal-weight panels. Focus Coach alone has 14, plus a debug read-out ("Outside-session signal debug", `:1455-1481`).
- Information order is upside down: About sits above Permission Health. Notifications appear twice (banner `:346` and health row `:513`). Calendar and Reminders permissions appear three times each.
- Captions run 99–302 characters (`:1241, :1532, :1548, :1774-1780`).
- **Confirmed live** (in-app capture, 2026-10-17): Settings uses three different alignments. Durations steppers are right-aligned. The Behavior switches ("Launch at login", "Auto-resume on wake") are **centred** in the row. The Focus Coach switches hug their labels on the left. Switch tint is correct (system blue), so the earlier "no tint" finding was a capture artifact and is withdrawn.
- **Withdrawn:** the near-black section headers and white popups seen in both off-screen renders and in-app `cacheDisplay` captures are capture artifacts. The user's real screenshot (2026-10-17) shows white headers and dark popups. **Neither capture method is trustworthy for colour or contrast in this app.** Use real user screenshots, or grant the dev tool Screen Recording, for visual QA.
- **Confirmed in the real screenshot:**
  - Behavior switches ("Launch at login", "Auto-resume on wake") are centred mid-row, while every other control is right-aligned.
  - Steppers end at slightly different x positions row to row. Values and arrows don't share a column.
  - "Completion sound" sits in its own lighter, inset glass field (`SettingsView.swift:329` `.glassEffect` inside the panel), so that one row looks different from the rest. This is glass-on-glass.
  - Label styles vary: most labels are 13pt secondary grey, but "Wake recovery threshold" is primary white with a caption.
  - Rainbow icons: every row icon has its own colour (blue, green, pink, grey, yellow, cyan, purple). That's visual noise with no meaning.
  - The amber apology banner ("auto-start controls are hidden…") is shipped to users.
  - The daily-goal slider has about 30 tick marks and no labelled stops.
  - A stray capsule control floats over the Blocking caption at the bottom of the window (screenshot, x≈648 y≈1565). Unidentified, possibly an orphaned overlay or the macOS 26 scroll-edge element; investigate.

### 1.4 Typography and spacing: no system
- 17 distinct font sizes in the companion views (10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 22, 24, 28, 32, 36, 42, 52).
- 16 distinct padding values, 14 stack spacings, 7 corner radii.
- 42pt light "Today, 17 October" and "Calendar" headlines (`TodayStatsView.swift:67-70`) take about 20% of a 520pt window.

### 1.5 Charts are hand-drawn and unlabeled
- No Swift Charts anywhere. All 13 charts are custom shapes.
- Bar charts have no y-axis or gridlines, and no goal line (`BarChartView.swift:3-74`).
- The heatmap has no legend beyond the subtitle "Darker green = more focus time" (`WeeklyStatsView.swift:113`).
- The Today goal bar is a 4pt line with no label (`TodayStatsView.swift:169-193`).
- Colours vary by chart: blue `.blue`, green `#3DA86A`, `Color.green` at 3 opacities, orange.
- None of them answer the question the user cares about: *"Did I get my 2 hours of personal work today and this week, and when do I actually do it?"*

### 1.6 Jargon and fake insight
- Labels: "Earned blocks", "Recovered", "Goal runway", "42 · FRAGILE" (`InsightsView.swift:206`), "Domain Signals", "Idle coaching rules for outside-session recovery", "Guardian".
- **Hardcoded pseudo-science:** "your alertness drops ~25% after noon" (`InsightsView.swift:1102`) is shown as a personal insight with no source and no data behind the 25%.

### 1.7 Appearance and sizing
- The companion window forces dark (`.preferredColorScheme(.dark)`, `FocusFlowApp.swift:87, 97, 107, 118`) while the popover follows the system. In light mode the two surfaces don't match. The tokens are already adaptive (`LiquidDesignTokens.swift:186-195`), so forcing dark buys nothing.
- Default size 720×520 with `.windowResizability(.contentSize)` (`FocusFlowApp.swift:84-90`) is cramped for this content. *(Live check)* macOS reported FocusFlow's only standard window as 153×201pt while Settings was open. That points to a content-size collapse; verify.
- Sidebar: two-line rows with coloured tiles and truncated subtitles ("Trends and his…", "Timer preferen…"). *(confirm live)* The selected row draws as a black block with dark text.

---

## 2. Target information architecture

**Companion window: 4 destinations, single-line native sidebar**

| Sidebar item | Merges | Answers |
|---|---|---|
| **Today** | Today | Am I on track for today's goal? What's next? |
| **History** | Calendar + Week | How consistent am I over days, weeks and months? |
| **Insights** | Insights + Domain Signals/Patterns + Guardian recs | When do I focus best, what derails me, is the coach helping? |
| **Projects** | Projects + per-project blocking | What am I working on, and what is blocked for it? |

**Settings: a real macOS Settings scene** (`Settings { TabView }`, ⌘,) with toolbar tabs:

| Tab | Contents (all in `Form { }.formStyle(.grouped)`) |
|---|---|
| **General** | Launch at login (read from `SMAppService`), Appearance (System/Light/Dark), Sleep behaviour (one control), Daily goal |
| **Timer** | Focus/short/long break durations, sessions before long break, completion sound (with preview) |
| **Coach** | Coach on/off, **Style** (Gentle / Data / Challenger), "Remind me to start after [N] min", Ask why sessions end early, *Advanced ▸* (budgets, strong-prompt caps, skip action) |
| **Distractions** | Rules list (from Distractions tab) + blocking profiles (from the Blocking sheet) in one place, with suggestions inline |
| **Integrations & Permissions** | One row per item (Notifications, Calendar, Reminders, Browser domains, Screen Recording): status dot · one-line effect · one button. Calendar/Reminders pickers appear inline when connected |

The debug read-out moves behind `#if DEBUG` or ⌥-click on the Coach tab. "About" moves to the standard app menu (About FocusFlow).

`Form(.grouped)` gives right-aligned controls, correct switch tint, label/description pairs (`LabeledContent`), section headers and footers, dark/light correctness and accessibility for free. That fixes §1.3 almost entirely.

---

## 3. Visual system

- **Surfaces:** window background = system window background. Content sections = `GroupBox`-like plain containers (`Surface.containerLow`, radius 12, no glass). Glass only on the toolbar, segmented range picker and floating actions.
- **Type scale (6 styles only):** largeTitle 26 semibold (page title), title3 17 semibold (section), body 13, callout 12 secondary, caption 11 secondary, monospaced-digit numbers via `.monospacedDigit()`. Drop 42/52pt light headlines.
- **Spacing:** 4-pt grid using tokens only: 4, 8, 12, 16, 24. Page padding 24, section gap 16, row gap 8.
- **Radii:** 8 (controls), 12 (sections), 16 (hero only).
- **Colour:** one accent (`Spectral.primaryContainer`) for "your focus". Semantic green for goal met, orange for at-risk, red only for destructive. Project colours only inside project-specific marks. Remove ad-hoc `.blue/.green/#3DA86A`.
- **Appearance:** remove `.preferredColorScheme(.dark)`. Add Settings → General → Appearance (System default). Re-run the evidence renders in both modes as a gate.
- **Window:** default 960×640, min 780×540, resizable (`.windowResizability(.contentMinSize)`).

---

## 4. Screens

### Today
1. **Header row:** "Today" (largeTitle) + date (callout) on the left; **Log session** button on the right.
2. **Goal hero:**
   - Ring or progress with **"1h 40m of 2h"**.
   - Below it: "20m to go · next good window 22:00" (from the coach availability model, Coach v2 §8).
   - When met: "Goal met · +12m".
3. **Three stats, plain labels:** *Focus blocks* 3 · *Personal work* 1h 40m · *Streak* 6 days.
4. **Timeline:** today's sessions on a horizontal 24h strip (Swift Charts `RectangleMark`), coloured by project, with a "now" rule.
5. **Distractions today** (only if any confirmed derailer > 10m): top 3 with minutes. Link to Insights.

### History (merges Calendar + Week)
- Range picker: **Week · Month · 3 Months** (segmented, glass allowed here).
- **Daily focus chart:**
  - Swift Charts `BarMark` per day, stacked by project.
  - `RuleMark` at the daily goal (2h), labelled "Goal".
  - y-axis in hours with light gridlines. Days that meet the goal get a dot above the bar.
- **Consistency:** a GitHub-style calendar heatmap for Month and 3 Months, with a real legend (Less ▢▢▢▢ More) and goal-met days outlined.
- **Day detail:** click a bar or cell to show that day's sessions list (from the Calendar tab).
- **Summary row:** Total · Daily average · Days goal met (n/7) · Best day.

### Insights
1. **When you focus.** Hour-of-week heatmap (7×24, Swift Charts `RectangleMark`) of focus minutes, plus "Your best windows: weekdays 11–12, 22–00" (computed). This is the same data the coach's availability model learns, so the user sees what the coach believes.
2. **What derails you.** Confirmed derailers only, as horizontal bars (hours this week vs last week). One-click "Block during focus windows".
3. **Real work vs busywork** (Coach v2 §9). Share of sessions rated Shipped / Moved forward / Busywork, by project.
4. **Is the coach helping?** Prompt → start rate per style (Challenger / Data / Gentle), prompts per day, trend.
5. **Remove:**
   - the "42 · FRAGILE" score (opaque)
   - the hardcoded "~25% alertness" claim
   - "Focus Science tips" boilerplate, unless each tip cites a source

### Projects
List and detail (`NavigationSplitView` inner or a master/detail table). Detail shows this week's time, sessions, priority link (Coach v2 §9) and that project's blocking profile inline.

---

## 5. On-screen coach prompt (replaces notifications as the primary surface)

**Why:** most people (including this user) disable or ignore notifications. In the local store, strong window prompts were the only surface that was ever acted on, and the "notifications not authorized" escalation rule routed almost every prompt there.

**Surface:** a small floating panel. It is not a full window and not a notification.
- `NSPanel` with `.nonactivatingPanel` + `.hudWindow`-style vibrancy, level `.floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`. It does **not** steal keyboard focus, so typing in the current app continues.
- Position: top-right, under the menu bar icon, about 340×120pt. It slides in (respecting Reduce Motion).
- Content: one line of Challenger copy + one fact + **[Start 25m on {Project}]** (default button, ⏎ works when clicked) + "Not now ▾" (15m · 1h · Done for today).
- **Auto-hide after 20s** without interaction. It collapses into a pulsing dot on the menu bar icon until the popover is opened. Silence counts as "ignored" for the bandit reward.
- Never shown during screen share, a calendar-busy slot, full-screen video or presentation apps, or within 2h of a previous ignored panel.

**Notifications** become opt-in (Settings → Coach → "Also send notifications", default off). When enabled they use the actionable Start/Snooze category (already built in Phase 0).

**Strong window** (`CoachInterventionWindowView`) is retired for idle prompts. It stays only for the in-session "drift" check, restyled to the same panel. The `requestAppActivation` focus-steal is removed.

---

## 6. Popover spot fixes (keep its character)
- Fonts under 10pt: `TimerRingView.swift:204, 233`, `FocusCoachStripView.swift:48, 57`, `FocusCoachQuickPromptView.swift:43`, `FocusCoachPreSessionCard.swift:60, 137, 141`, `MenuBarPopoverView.swift:844, 889`.
- Glass-on-glass in the coach window (`CoachInterventionWindowView.swift:82` + `LiquidActionButton`).
- Long-break ring uses `.purple` instead of the documented mint (`TimerRingView.swift:483`).

---

## 7. Delivery plan

| Step | Work | Gate |
|---|---|---|
| 1 | Settings scene: `TabView` + `Form(.grouped)`, 5 tabs, remove debug/About, single permission surface | Evidence renders light/dark + live screenshot |
| 2 | Visual system tokens (type, spacing, radii), drop glass panels, remove forced dark, window size | Renders of all tabs both modes |
| 3 | Merge Calendar + Week → History with Swift Charts (goal line, axes, heatmap legend) | Chart renders with fixture data |
| 4 | Today + Insights rebuild (goal hero, timeline, hour-of-week heatmap, derailers, coach effectiveness), copy cleanup | Renders + copy review |
| 5 | On-screen coach panel (`NSPanel`), notifications opt-in | Live test: panel appears, doesn't steal focus, Start works |

Steps 1 and 5 have the highest impact on daily use and are independent of each other.
