# FocusFlow — UI/UX Design Brief for Google Stitch / Gemini

**Purpose:** This is an open creative brief for generating UI/UX design concepts for FocusFlow. The goal is to explore and discover the best possible design — layout, visual hierarchy, interaction patterns, component design — for each screen of the app. The functionality is fixed. The design is not. Use this to generate diverse, opinionated visual directions and screen-level mockups.

**Date:** March 2026  
**Platform:** macOS 26 (Tahoe) — desktop-native application  
**Design Language:** Apple Liquid Glass (WWDC25)  
**Hardware Target:** MacBook Pro with Apple Silicon (M-series) — take full advantage of the GPU-accelerated material rendering these chips enable

---

## 1. What is FocusFlow?

FocusFlow is a **native macOS Pomodoro focus timer** that lives in the menu bar. It is not a to-do app, not a productivity dashboard — it is a precision instrument for managing deep work sessions on a Mac.

The app has two UI surfaces:
1. **Menu Bar Popover** — the primary control panel. Always one click away, drops from the menu bar icon.
2. **Companion Window** — a dedicated full window for analytics, project management, blocking rules, and settings.

---

## 2. Product Vision

### The Experience Goal

FocusFlow should feel like a **precision focus cockpit built into macOS itself**. Not an app that sits on top of the OS — an app that feels like it belongs to it, like it came with the machine.

Every interaction should feel intentional:
- Starting a focus session should feel like committing to something
- The active timer should feel alive and present, but never anxious
- Session completion should feel genuinely rewarding — a moment of closure
- Stats and history should feel insightful, not bureaucratic

The app is compact, powerful, and resident. It is **never in the way**, but always one click away with a satisfying, instant popover.

### Who Uses This

Makers, developers, writers, designers — people who do sustained creative or technical work and want a lightweight, beautiful way to run focused sessions and understand where their time actually goes. These users have expensive machines. They use professional creative apps. They have a high bar for what feels "native" and what feels like a third-party widget.

### Tone

> **Calm. Precise. Native. Purposeful.**

The app should NOT feel: gamified, loud, decorated, web-like, generic, or corporate.

---

## 3. Non-Negotiable Design Constraints

These are fixed. Everything else is open for exploration.

### 3.1 Apple Liquid Glass Design Language (WWDC25)

FocusFlow is designed exclusively for **macOS 26 (Tahoe)** and commits fully to the Liquid Glass design language Apple introduced at WWDC25.

**What Liquid Glass is:**
Liquid Glass is a physically-based translucent material — like a real pane of glass with light refraction, specular highlights, and soft shadow. It adapts dynamically to whatever is rendered behind it. It is not a flat blur; it bends light. It is not a static tint; it reacts to its environment. On Apple Silicon it runs as GPU-accelerated real-time rendering — the M-series chips make this possible in a way no previous Mac hardware could.

**Core rules for how it is used:**
- Glass materials belong on **controls and navigation layers** — buttons, pickers, toolbars, floating panels. Not on content (lists, form fields, stats cards).
- Related glass controls should share a **glass container** so they composite together correctly rather than fighting each other.
- When a button changes state (e.g., "Start Focus" → "Pause"), the glass shape should **morph fluidly** — not cut or cross-fade. This is the defining Liquid Glass interaction pattern.
- Controls should have physical **press feedback** — a springy, bouncy response that feels like touching real glass.
- **Never stack glass on glass** — the translucency breaks down and creates visual mud when glass sits on top of another glass element without a shared compositor.

### 3.2 Dark Mode as a First-Class Target

Dark mode on Tahoe is not inverted light mode. Liquid Glass in dark mode is a fundamentally different, more dramatic aesthetic. The glass takes on a near-black base tint with vivid spectral highlights catching on upper edges. Accent colors glow against the dark glass in a way they cannot in light mode. This is where the app is most visually striking.

**Dark mode is the hero showcase.** The menu bar popover floating against a dark macOS wallpaper, with the focus ring glowing, should look like nothing else on the platform.

### 3.3 Apple Silicon Performance Focus

The app targets MacBook Pro with M-series chips. This means:
- Smooth, real-time glass compositing at full resolution
- Fluid animations and transitions that feel instant
- The design can lean into complexity that would stutter on lesser hardware — rich material effects, layered depth, fluid state transitions

Do not design for lowest-common-denominator. Design for hardware that can deliver it.

### 3.4 Accessibility Baseline

- No state communicated by color alone — always pair with label, icon, or shape
- Interactive elements must be clearly distinct from static content
- Text must remain legible over translucent glass surfaces at the size it is shown
- Keyboard focus should always be visible

---

## 4. App States to Design For

The timer goes through distinct states that require visually different treatments. The design must make the current state unmistakably clear at a glance from the popover.

| State | What the user is doing | Design feel |
|-------|----------------------|-------------|
| **Idle** | Setting up — choosing project, duration | Calm, ready, inviting |
| **Focusing** | Timer counting down, work in progress | Alive, present, committed |
| **Paused** | Timer frozen, user stepped away | Slightly tense, time is passing |
| **Overtime** | Timer finished but user hasn't acted yet | Noticed, not urgent |
| **On Break** | Resting between sessions | Relaxed, different energy than focus |
| **Session Complete** | Reflecting on what was accomplished | Celebratory, ceremonial, warm |

The transitions *between* states matter as much as the states themselves. State changes drive the primary interaction choreography.

---

## 5. Color Intent (Semantic, Not Prescribed)

The exact palette is open to exploration. The semantic intent is fixed:

- A **focus/active color** — the primary accent during focus sessions. Should feel intentional and energetic but not aggressive.
- A **success/completion color** — used for break states and session completion. Should feel positive and calming.
- A **warning/escalation color** — for pause overtime and destructive states. Should escalate appropriately (mild → critical).
- A **depth/achievement color** — for the "Deep Focus" mood state and the most accomplished feeling moments. Could be more introspective and premium.

Colors must work over translucent glass in both light and dark backgrounds. They need to "glow" in dark mode and remain readable in light mode.

---

## 6. Screens — What Needs to Exist and Why

This section describes the required functionality of each screen. **How it is laid out, structured, and styled is the design challenge.** These are functional requirements, not wireframes or design specs.

---

### 6.1 Menu Bar Icon

The always-visible app presence in the macOS menu bar.

**What it must communicate:**
- The app is running (the icon is present)
- The current state: idle, focusing, paused, on break
- When active: the live timer countdown
- When paused: the pause duration
- When finished: the daily total

The icon itself represents the FocusFlow brand — a glass-inspired circular emblem with concentric ring elements (suggesting focus, aperture, or depth). The icon + live text pair should feel cohesive and legible whether the menu bar is light or dark.

---

### 6.2 Menu Bar Popover

**The hero surface.** Everything the user needs to run a focus session lives here.

**What the idle state provides:**
- The timer ring — the central visual element, shows selected duration, ready to start
- Pomodoro progress — how many sessions completed in this cycle (e.g., 2 of 4 before a long break)
- Project selection — which project to attribute this session to. Supports inline search and quick-create.
- Duration selection — quick presets (15 / 25 / 45 / 60 min) and a custom input option
- Primary call to action: start a focus session
- A footer with today's total and a way to open the companion window

**What the active/focusing state looks like:**
- Timer ring is running and draining in real time
- The state label and project name are the supporting context
- Controls simplify down to: pause and stop
- If a blocking profile is active, it should be visible as context (not a CTA)

**What the paused state adds:**
- How long the user has been paused is prominently shown
- Visual escalation as pause time grows — this communicates "you should get back to it"
- The primary action becomes: resume

**What the break state looks like:**
- A distinctly different (relaxed) visual register compared to the focus state
- Break countdown and type (short vs. long)
- Option to skip the break

---

### 6.3 Session Complete Panel

A **floating standalone window** that appears when a focus session ends — no title bar, no chrome, just a glass surface floating over the desktop.

This is the most ceremonial moment in the app. The design should make the user feel like they accomplished something.

**What it must contain:**
- A success moment: clear confirmation that the session ended, how long it ran, what project it was for
- Overtime notice if the user kept going past the original duration
- Mood reflection: the user rates how their focus felt (4 levels: Distracted / Neutral / Focused / Deep Focus)
- Achievement log: a place to capture what they actually finished in this session
- Time split (optional, progressive disclosure): ability to divide the session time across multiple projects
- What happens next: three choices — start a break, keep focusing, end for now

The window should **feel like a moment** — not a required form to dismiss. The emergence and close of this panel are interactions worth designing carefully.

---

### 6.4 Companion Window — Today

The first thing the user sees when they open the companion window. A daily summary.

**What it must show:**
- Today's cumulative focus time, session count, and streak — the three most important daily numbers
- A breakdown of time spent per project today (visual, proportional)
- A chronological timeline of sessions with mood and project context
- A reflection summary: mood distribution for the day, any achievements logged
- A way to manually log a past session that wasn't tracked

---

### 6.5 Companion Window — Week

Historical view. Answers "how has my focus been going?"

**What it must show:**
- A bar chart of daily focus time for the last 7 or 30 days (user can toggle)
- Summary stats: daily average, best day, total for the period
- Ability to tap into a specific day's detail

---

### 6.6 Companion Window — Projects

Where users manage the categories they track time against.

**What it must allow:**
- View all active projects with their session counts and visual identity (color + icon)
- Create a new project: give it a name, color, and SF Symbol icon
- Edit or archive existing projects (archiving soft-deletes; data is preserved)
- Associate a project with a blocking profile (optional)

---

### 6.7 Companion Window — Blocking

Website and app blocking during focus sessions.

**What it must allow:**
- Create named "blocking profiles" — sets of websites/apps to block during a session
- Each profile has a list of domains and/or apps to block when active
- One profile can be set as the default (auto-activates with every focus session)
- Projects can be linked to specific profiles
- Empty state when no profiles exist yet

---

### 6.8 Companion Window — Settings

App-level configuration.

**What it must show:**
- Timer durations: focus, short break, long break, sessions before long break
- Behavior toggles: auto-start breaks, auto-start next session, launch at login
- Sound: completion sound selection with preview, volume
- About info

---

## 7. Key Design Challenges

These are the hardest and most interesting UI/UX problems to solve. Use them as design prompts:

**1. The popover is the whole product.**
It is narrow (roughly 300px) and used on a high-frequency, glance-and-dismiss pattern. Every state — idle, focusing, paused, break — must feel distinct and complete within this constraint. Nothing can feel cramped, but nothing can feel sprawling either.

**2. State transitions are the signature interaction.**
The moment a focus session starts, the idle controls need to give way to the focus controls in a way that feels like transformation, not replacement. Glass morphing is the design language answer. How the Start button becomes the Pause button, how the project picker disappears and the project label takes its place — these transitions define the product feel.

**3. The session complete panel must earn its moment.**
It appears over the user's work. It asks them to pause and reflect. It must feel worth the interruption — ceremonial, warm, and fast to complete. Too much friction → users dismiss without engaging. Too little presence → it feels like just another dialog.

**4. Dark mode is the ambitious target.**
Light mode should look excellent. Dark mode should look extraordinary. A floating glass popover against a deep macOS wallpaper at night, with a glowing focus ring, is the product's hero shot. Design for this first and ensure light mode is equally refined.

**5. The companion window must feel like the same product as the popover.**
They are two very different surfaces (narrow popover vs. wide window with sidebar). They need a shared visual identity so opening the companion doesn't feel like switching apps.

---

## 8. What to Generate

### Full Screen Explorations
- Menu bar popover: idle state, focusing state, paused state, break state — light and dark
- Session complete panel — focus completion — light and dark
- Companion window: Today view, Week view, Projects view, Settings view — light and dark

### Component Studies
- Timer ring: across all states (idle, active, paused, break, overtime, complete)
- Action controls: the idle-to-focus state change, the focus-to-pause change
- Mood selector: idle and each selected state
- Project picker: collapsed chip and open overlay states
- Session progress tracker (Pomodoro dots): partial progress and completion
- Stat cards and stat summaries
- Companion sidebar: navigation items, selected vs. unselected states

### Transition Storyboards (3–5 frames)
- Start Focus: idle → focusing
- Pause: focusing → paused
- Session complete: panel emergence, success moment, mood selection
- Break start: focus → break visual shift

### Dark Mode Hero Shots
- Active timer popover in dark mode — premium hero
- Session complete panel over dark desktop
- Companion window full dark mode

### Visual Direction Variants (generate at least 3 distinct directions)
Each direction should interpret the Liquid Glass + premium macOS brief differently. For example — one could be very sparse and near-invisible (maximum translucency), one could be more of a deep dark cockpit (dramatic, instrument-panel), one could be warmer and softer (amber or neutral tones instead of cold blue). These are not constraints — they are invitations to interpret.

---

## 9. Brand Notes

The FocusFlow logo is a circular glass emblem with interior concentric rings — like a focus reticle, aperture, or radar. It reads as precision and depth. It should appear in the menu bar icon (small, template image), companion window sidebar, session complete panel, and app icon. The wordmark "FocusFlow" is a secondary element.

Copy style: action-first, warm but not playful. "Start Focus", "Take a Break", "How was your focus?" — direct and purposeful. No motivational poster language.

---

*This brief describes what FocusFlow does and why it exists. It does not prescribe how to design it. The design language (Liquid Glass, macOS Tahoe native, Apple Silicon-grade) and the product vision (precision focus tool, premium, calm) are fixed anchors. Everything else — layout, visual hierarchy, component shapes, color interpretation, motion language, spacing, type treatment — is the creative problem to solve.*
