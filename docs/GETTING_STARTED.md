# Getting started with FocusFlow

FocusFlow helps you start the work that matters to you, one short block at a time. It lives in your menu bar and around your MacBook's notch.

This guide takes about five minutes to read. You need about one minute to set the app up.

---

## 1. Install it

You need macOS 26 (Tahoe) or later.

Pick one way:

- **Homebrew:** run these two commands.

  ```bash
  brew tap goyal-chintan/focusflow
  ```

  ```bash
  brew install --cask focusflow
  ```

- **Download:** get the latest `.dmg` from [Releases](https://github.com/goyal-chintan/focus-flow/releases/latest). Drag FocusFlow into Applications. The first time, right-click the app and choose **Open**.
- **From source:** see [Option 3 in the README](../README.md#option-3--build-from-source).

FocusFlow has no Dock icon. Look for its icon in the menu bar at the top of the screen.

---

## 2. The welcome tour (one minute)

The first time you open FocusFlow, a short tour opens. It has five steps. Each step asks one thing:

| Step | What you do | Why |
|---|---|---|
| **Welcome** | Read three lines. | You learn what the app does. |
| **What matters most** | Name your #1 thing, for example "Interview prep". Choose its kind and how much time a day you want for it. | Everything else in the app points at your #1. |
| **One result** | Say what you will count, how many, and by when. For example "60 practice problems in 1 month". You can skip this. | The app turns it into one small step a day. |
| **Your coach** | Choose Gentle, Data or Challenger. You see what each one would say to you. | You pick the tone that gets you moving. |
| **First block** | Turn the notch display on or off. Then press **Start 5 minutes**. | Starting is the habit. Five minutes is enough. |

You can press **Skip** at any time. Nothing is saved until the last step.

**To see the tour again:** open Settings (⌘,) → **General** → **Getting started** → **Show the welcome tour**.

---

## 3. Every day

### Start a block

A block is a short, timed stretch of focus. Start with 5, 15 or 25 minutes. Longer blocks are fine once you're moving.

You can start a block from three places:

- **The notch:** move the pointer over the black area around the notch. Click **5**, **15** or **25 min**.
- **The menu bar icon:** click it, choose a time, and press start.
- **Anywhere:** press **⌃⌥Space** (Control + Option + Space). This starts a 5-minute block.

### While a block runs

- The notch shows a ring and the time left.
- Move the pointer over the notch to pause, add 5 minutes, or finish.
- If your project has a goal, the notch shows a **+1** button. Click it each time you finish one item, for example one practice problem.

### When the coach speaks

The coach is a small card that asks you to start. It speaks only when you are at your Mac and not already in a block.

- Click **5**, **15** or **25 min** to start.
- Click **Not now, because…** and pick a reason. The coach uses your answer:

| Your reason | What the coach does next |
|---|---|
| Busy with work | It stays quiet for an hour. |
| Too tired | It stays quiet for an hour. In the evening, it waits until tomorrow. |
| It feels too big | It offers a 5-minute block instead. |
| I don't know the next step | It offers a 5-minute block to find the next step. |

The coach learns which moments work for you. It gets better after a week or two of use.

### When a block ends

A small window opens. Say how it went, take a break, or keep going. Sessions shorter than one minute are not saved.

---

## 4. Your #1, your goals, and the truth

Open the main window: click the menu bar icon, then the chart button at the top. You can also hover the notch and click **Goals**.

- **Projects:** rank your projects. Mark each one as Personal, Learning, Work or Other. Give each a daily target.
- **Goals:** each goal has a deadline and things you count. The app shows whether you are ahead, on pace or behind.
- **Today's lever:** the one small step that keeps your most urgent goal on track, for example "3 practice problems today".
- **Today:** an honest split of your day, for example "6h tracked · 1h on your #1 · 15% own work". When a project is marked Work, your daily goal counts only your own work.
- **Insights → Drift:** what you planned against what you did, project by project.

---

## 5. Where things are

| I want to… | Go to |
|---|---|
| Start a block fast | ⌃⌥Space, or the notch |
| Change the coach's tone | Settings → Coach |
| Hide the notch display | Settings → General → Notch |
| Set my daily goal | Settings → General → Daily goals |
| See the tour again | Settings → General → Getting started |
| Add or rank projects | Main window → Projects |
| Add a goal | Main window → Goals → New goal |
| Check permissions | Settings → Permissions |

---

## 6. Privacy

Everything stays on your Mac. There is no account and no cloud. Your data is in `~/Library/Application Support/FocusFlow/`.

Some features ask for macOS permissions, for example Calendar or browser Automation. Each one is optional. The [README](../README.md#permissions) says why each one is needed.

---

## 7. Common questions

**The coach never speaks.**
It stays quiet while you are in a block, when you are away from your Mac, and during its quiet hours. Check Settings → Coach.

**I don't have a notch.**
FocusFlow shows a small pill at the top centre of the screen instead.

**I closed the tour by mistake.**
Open Settings → General → **Show the welcome tour**.

**How do I start over?**
Quit FocusFlow. Move `~/Library/Application Support/FocusFlow/` to the Trash. Open FocusFlow again. Keep a copy of that folder if you might want your history back.

---

Want to help build FocusFlow? Start with the [README](../README.md#run-from-source) and the design notes in [docs/plans](plans/).
