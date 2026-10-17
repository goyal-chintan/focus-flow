# Coach Rescue Loop: getting someone back when they drift

Date: 2026-10-17 · Status: approved for build · Extends `2026-10-17-coach-v2-learning-motivation-design.md`

## The problem in the user's words
> "How do you make it easy for someone to at least start a focus session (let's say 5 min for planning or anything) when someone is wasting time and doing non-important work? How can we get someone back? That should be the primary role of the focus coach. Notifications come and go; people start ignoring them."

Today's coach decides **when** to ask (learned windows, pacing, bandit) and **how** to word it. But it always asks the same size of thing ("Start 25m"), through one surface, and gives up after the panel hides. A drifting person has low motivation and high activation energy, so a big ask in a dismissible box loses.

## Principles (with sources)
1. **Shrink the ask as drift deepens.** Starting is the hard part. "Make it easy": the two-minute rule (Clear, *Atomic Habits*, 2018). Foot-in-the-door: a small yes raises the odds of a larger one (Freedman & Fraser, 1966). Momentum after starting: people tend to want to finish what they began (Zeigarnik effect).
2. **Friction beats reminders.** A pause at the moment of temptation changes behaviour more than a message that can be swiped away. The *one sec* field study (Grüning et al., *PNAS*, 2023) found a short forced delay before opening a distracting app markedly reduced opening attempts. Our version is gentler: a pause with a one-click way back to work, never a lock.
3. **Make drift visible.** People underestimate time spent on low-value activity. A quiet, honest counter ("YouTube 23m in your focus window") restores awareness without nagging.
4. **Autonomy, not shaming.** Every escalation has a respectful escape ("Real break · 15m", "Done for today"). Challenger means direct, not insulting (Self-Determination Theory).
5. **Learn what works for this person.** Every rung, message and quote is an arm with a reward, the same bandit as v2.

## 1. Detecting "wasting time" and "non-important work"
A `DriftMonitor` produces a **drift level 0–3** every tick while no session is running, only inside a learned focus window (or when pacing pressure ≥ 0.5):

| Signal | Source | Counts as drift when |
|---|---|---|
| Derailer time | Frontmost app/domain classified distracting, never work tools (existing derailer logic) | Rolling minutes in the last 30 min |
| Pseudo-work time | Work/neutral apps (Claude, Cursor, Arc…) with no session while pacing pressure ≥ 0.5, plus self-rated busywork patterns (`SessionOutcome.busywork` history for that project/context) | Rolling minutes in the last 30 min |
| Hopping | App switches per minute (existing `computeAppSwitchRate`) | ≥ 6 switches/min sustained 3 min (scanning, not doing) |
| Ignored rescues | Panels dismissed or ignored today in this window | Each ignore raises the level |

Level rules (tunable constants, unit-tested):
- **L0 OK:** nothing notable.
- **L1 Drifting:** ≥ 10 min derailer, or ≥ 20 min pseudo-work, or hopping.
- **L2 Lost:** ≥ 20 min derailer, or ≥ 40 min pseudo-work, or L1 plus one ignored rescue.
- **L3 Spiral:** ≥ 40 min derailer in the window, or L2 plus two ignored rescues.

Hard limits still apply: quiet hours, calendar busy, screen share, Done for today, real break, daily cap. Rescue panels count toward the cap; the ambient indicator does not.

## 2. The micro-commitment ladder: the ask shrinks with drift
| Level | Ask (primary button) | Block type |
|---|---|---|
| L1 | **Start {N}m on {priority}** (N from pacing, 25–50) | normal |
| L2 | **Just 10 minutes on {priority}** | normal, 10m |
| L3 | **5 minutes. Plan the next step.** | **Starter block** |

**Starter block:** a 5-minute session needs no project or priority. The popover shows a single prompt, "What's the very next step?", and a text field. At the end, a panel says **"Keep going: 20m on {that step}?"** (one click continues as a normal session with intent = the typed step; ⏎ accepts). If declined, it's still logged as a win: the session counts, the streak is kept, and the reward is +1.

Also: after any rescue start, once 5 minutes are in, the panel offers **"You're in. Make it 25?"** once (momentum ramp).

## 3. Escalation without notifications
Surfaces, gentlest first. The bandit picks among the ones a level allows.

1. **Ambient counter** (L1+, opt-in by default for the Challenger style): the menu bar title shows a small orange `YT 23m` (or `Drift 23m`) while drifting in a focus window. It clears when the user starts a session or the window closes. It is never shown outside focus windows.
2. **Rescue panel** (L1+): the existing non-activating panel with the ladder ask, one true fact, and a quote. Keyboard: **⏎ starts** when the panel is clicked; **Esc** = Not now.
3. **Pause screen** (L3 only, opt-in, default ON for the Challenger style, OFF for Gentle/Data): a full-screen, translucent, dimming overlay on the active display above the derailer app.
   - Content: a large quote, one honest line ("47 minutes on YouTube in your 22:00 window"), and the primary button **"Start 5 minutes"**.
   - Escapes: "Real break · 15m" and "Done for today".
   - It doesn't lock: Esc or the escape buttons work at any time, and after 8s a quiet ✕ appears.
   - Shown at most once per window, never during screen share or calendar busy.
4. **Global hotkey:** **⌃⌥Space** starts a starter block from anywhere (Carbon `RegisterEventHotKey`, no Accessibility permission needed). Shown in the panel footer ("⌃⌥Space starts 5 min anytime") and configurable in Settings → Coach.
5. Notifications stay opt-in, as before.

## 4. Message and quote engine
- **Situations:** `start` (window opens), `drift` (L1–L2), `spiral` (L3, pause screen), `comeback` (after a missed day), `streak` (on a run), `lateNight` (after 23:00, tone: "one small thing, then sleep"), `keepGoing` (after a starter block).
- **1% framings** built from the user's own data:
  - "1% better daily = 37× in a year." (1.01³⁶⁵ ≈ 37.8)
  - "1% of today is 14 minutes. Give 5 now." (1% of 24h = 14.4 min)
  - "You've been 1% worse for {N} days. Today you turn it."
- **Quote library: verified, attributed, short.** Every entry carries `author`, `source`, `attributionNote` ("widely attributed" where the origin is uncertain) and `situations`. Seed set; do not add unverified quotes:
  - James Clear, *Atomic Habits*: "You do not rise to the level of your goals. You fall to the level of your systems." · "Every action you take is a vote for the type of person you wish to become." · "Never miss twice."
  - Jocko Willink: "Discipline equals freedom." (book title, 2017)
  - Will Durant, *The Story of Philosophy* (summarising Aristotle): "We are what we repeatedly do. Excellence, then, is not an act, but a habit."
  - Stephen King, *On Writing*: "Amateurs sit and wait for inspiration, the rest of us just get up and go to work."
  - Annie Dillard, *The Writing Life*: "How we spend our days is, of course, how we spend our lives."
  - Seneca, *On the Shortness of Life*: "It is not that we have a short time to live, but that we waste a lot of it."
  - Marcus Aurelius, *Meditations* 5.20: "The impediment to action advances action. What stands in the way becomes the way."
  - Gretchen Rubin: "What you do every day matters more than what you do once in a while."
  - Jerzy Gregorek: "Hard choices, easy life. Easy choices, hard life."
  - Jim Rohn (widely attributed): "Motivation is what gets you started. Habit is what keeps you going." · "Discipline is the bridge between goals and accomplishment."
  - Sam Levenson (widely attributed): "Don't watch the clock; do what it does. Keep going."
  - Pablo Picasso (widely attributed): "Inspiration exists, but it has to find you working."
- **Per-quote learning:** the reward of a prompt also updates that quote's Beta posterior. Quotes that precede starts rise; dead ones fade. Never repeat the same quote within 3 days.
- **The user's "My why" lines** are weighted equal to quotes.

## 5. What success looks like
- Proximal metric: rescue → session start within 10 min, by level and surface (shown in Insights → "Is the coach helping?", plus a "Rescues" row by level).
- Ladder check: starter blocks that convert into a full block (≥ 20m), shown as "5-min starts that kept going".
- Guardrail check: pause screens per week ≤ 3; if the escape rate exceeds 80% for two weeks, the bandit stops using that surface.

## 6. Settings (Coach tab)
- **Rescue:** "Show drift time in menu bar" (default per style), "Pause screen when I spiral in a focus window" (default per style), Starter block length (2/5/10 min, default 5), Global start shortcut (default ⌃⌥Space, with an "off" choice).
