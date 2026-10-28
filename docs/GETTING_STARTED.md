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

**To see the tour again:** open Settings (⌘,) → **General** → **Getting started** → **Show Tour**.

---

## 3. Set up your projects and goals

### Add a project

A project is anything you want time for, for example "Interview prep", "Office" or "Side project".

1. Open the main window: click the menu bar icon, then the chart button at the top.
2. Click **Projects**, then **New project**.
3. Fill in the cards, top to bottom:

| Card | What to enter |
|---|---|
| Name, icon, color | A short name you will recognise in the menu bar. |
| What kind of work is it? | **Personal** or **Learning** counts as your own work. **Work** is your job. The honest split keeps them apart. |
| Priority | **#1** is where most of your focus should go. The coach starts there. When you take a rank, the others move down one. |
| Why it matters | One line. It shows on the project, so hard days have a reason. |
| Daily time target | How much focus this project should get on a normal day, for example 2h. Turn on **Weekdays only** for office work. |
| Goal (new projects only) | Optional. You can also add goals later in the Goals tab. |
| Focus protection | Optional. Which apps and sites to block, and how strict the coach is during blocks. |

4. Click **Save**.

To change a project later, select it in **Projects** and click **Edit**. To rank projects, give each one a priority.

### Add a goal

A goal has a deadline and one or more **key results**: things you can count. For example "Interview-ready by 28 Nov" with "60 LeetCode questions" and "10 SQL sets".

1. In the main window, click **Goals**, then **New goal**.
2. Pick the project, the deadline, and the key results with their targets.
3. Click **Save**.

The goal card then shows your pace: **ahead**, **on pace** or **behind**, and how many a day you need. To log progress, click **+1** on the key result, or tick a task linked to it (see below).

---

## 4. Every day

### Plan the day

Open **Today** in the main window. Under **Today's tasks**, write the 3–5 things that would make today a good day. Keep each one small: "2 LeetCode questions" beats "prep".

- **Link a task to a goal.** Pick it in the **Goal** menu next to the field. Ticking the task then adds to that key result.
- **Use today's levers.** The chips under the field are the steps that keep your goals on pace, for example "+ 3 LeetCode questions". Click one to add it as a linked task.
- **Unfinished yesterday?** Click **Bring them over**. Yesterday's list stays as it was, so its count stays honest.
- **Right-click a task** to move it to the top or to tomorrow, or to delete it.

You see "2 of 5 done" on Today, in the menu bar panel and on the notch.

### Start a block

A block is a short, timed stretch of focus. Start with 5, 15 or 25 minutes. The size the coach suggests is already selected. Longer blocks are fine once you're moving.

You can start a block from three places:

- **The menu bar icon:** click a task to make it the block's goal, choose a size, and press **Start**.
- **The notch:** move the pointer over the black area around the notch. Click **5**, **15** or **25 min**. The block starts on your next task.
- **Anywhere:** press **⌃⌥Space** (Control + Option + Space). It starts a short block on your next task. With nothing planned, it starts a short block whose job is to find the next step.

### While a block runs

- The notch shows a ring and the time left.
- Move the pointer over the notch to pause, add 5 minutes, or **Finish**.
- Tick the block's task there when it's done. If the project has a goal, **+1** logs one more item.

### When the coach speaks

The coach is a small card that asks you to start. It speaks only when you are at your Mac and not already in a block.

- Click **5**, **15** or **25 min** to start. The card says which task the block is for.
- Click **Not now, because…** and pick a reason. The coach uses your answer:

| Your reason | What the coach does next |
|---|---|
| Busy with work | It stays quiet for an hour. |
| Too tired | It stays quiet for an hour. In the evening, it waits until tomorrow. |
| It feels too big | It offers a 5-minute block instead. |
| I don't know the next step | It offers a 5-minute block to find the next step. |

The coach learns which moments and which sizes work for you. It gets better after a week or two of use.

### When a block ends: log it

A small window opens. It logs the block against your plan, top to bottom:

1. **Did you finish it?** If the block was for a task, click **Done** or **Not yet**.
2. **Tasks:** tick anything else you finished. Type in **Add something you finished** for work you hadn't planned. Type in **Next step** to add a task for later.
3. **Goal:** the key-result bars move as you tick. **+1** logs progress that isn't a task.
4. **What did this block produce?** Shipped, Moved it forward, or Busywork. The coach learns from this.

Then take the break you earned, start the next block, or click **Done for today**. Everything saves as you click. Blocks shorter than one minute are not saved.

---

## 5. See the truth

- **Today:** your own work against your daily goal, and where the day went: for example "6h tracked · 1h on your #1 · 15% own work". When a project is marked Work, the daily goal counts only your own work.
- **Goals:** each goal's pace, and how many a day you need.
- **Insights → Said vs did:** what you planned for each project against what it got, and how many planned tasks you finished.
- **Insights → Is the coach getting you started?:** how often a prompt led to a start, compared with no prompt.
- **History:** the days you showed up.

---

## 6. Where things are

| I want to… | Go to |
|---|---|
| Plan today's tasks | Main window → Today → Today's tasks |
| Start a block fast | ⌃⌥Space, or the notch |
| Add or rank projects | Main window → Projects → New project |
| Add a goal | Main window → Goals → New goal |
| Log goal progress | +1 on the goal, or tick a linked task |
| Change the coach's tone | Settings → Coach → Style |
| Stop the coach asking | Settings → Coach → Help me start |
| Set quiet hours | Settings → Coach → Limits |
| Hide the notch display | Settings → General → Notch |
| Set my daily goal | Settings → General → Daily goals |
| See the tour again | Settings → General → Getting started → Show Tour |
| Check permissions | Settings → Permissions |

---

## 7. Privacy

Everything stays on your Mac. There is no account and no cloud. Your data is in `~/Library/Application Support/FocusFlow/`.

Some features ask for macOS permissions, for example Calendar or browser Automation. Each one is optional. The [README](../README.md#permissions) says why each one is needed.

---

## 8. Common questions

**The coach never speaks.**
It stays quiet while you are in a block, when you are away from your Mac, during quiet hours, and after the day's limit. Check Settings → Coach → Starting and Limits.

**I don't have a notch.**
FocusFlow shows a small pill at the top center of the screen instead.

**I closed the tour by mistake.**
Open Settings → General → **Show Tour**.

**Where did weekly priorities go?**
Ranked projects, goals and today's tasks replace them. Your old priorities stay in the data, so past sessions keep their history.

**How do I start over?**
Quit FocusFlow. Move `~/Library/Application Support/FocusFlow/` to the Trash. Open FocusFlow again. Keep a copy of that folder if you might want your history back.

---

Want to help build FocusFlow? Start with the [README](../README.md#run-from-source) and the design notes in [docs/plans](plans/).
