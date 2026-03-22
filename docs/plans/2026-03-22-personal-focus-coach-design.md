# FocusFlow Personal Focus Coach — On-Device Intelligence Design

**Date:** 2026-03-22  
**Status:** Approved for implementation planning  
**Owner:** FocusFlow

---

## 1) Problem and Outcome

**Primary job:** reduce the gap between intention and action.

This coach should not just track minutes. It should help answer:
1. Did you start when you intended to?
2. Did you stay on the intended task?
3. If you drifted, what kind of drift happened?
4. How fast did you recover?
5. Which interventions actually worked for *you*?

---

## 2) Product Principles

1. **Personalized, not generic:** recommendations adapt to user behavior over time.
2. **Science-informed, not motivational fluff:** interventions map to established behavior-change mechanisms.
3. **Calm, low-friction UX:** 1-3 tap prompts, minimal mandatory input.
4. **Real-time coaching:** detect drift and intervene early, not only in weekly reports.
5. **On-device intelligence only:** private, explainable, fast, no cloud dependency.
6. **False-positive control:** separate genuine interruptions (meeting/family/stress) from avoidance patterns.
7. **Recovery-first posture:** optimize return-to-task speed, avoid shame-heavy nudging.

---

## 3) Science Evidence Lens (Guiding Constraints)

These references guide intervention strategy and metric selection:

- **Procrastination mechanism:** strong links with task aversiveness, delay, low self-efficacy, impulsiveness, and self-control deficits (Steel, 2007, PMID: 17201571).
- **Interventions work, especially structured approaches:** psychological treatments show benefit; CBT subgroup shows moderate effect (Rozental et al., 2018, PMID: 30214421).
- **Implementation intentions / MCII:** small-to-moderate improvements in goal attainment when plans are concrete (Wang et al., 2021, PMID: 34054628; Koestner et al., 2002, PMID: 12088128).
- **Break quality matters:** micro-breaks reliably improve vigor/fatigue, while performance gains depend on context/task demand (Albulescu et al., 2022, PMID: 36044424).
- **Emotional load is relevant:** procrastination correlates with negative emotions, so reason-aware interpretation is required (Nie et al., 2025, PMID: 41210118).

Design implication: coach must combine **behavior telemetry + quick contextual reasons + intervention outcome learning**.

---

## 4) Design Mode Deliverable

### 4.1 Screen Map and Placement Rationale

| Surface | Role | Why here |
|---|---|---|
| Menu bar popover | Active focus controls + live coach strip | Canonical place for immediate session decisions |
| Companion window → Insights tab | Deep pattern analysis, weekly coach reports | Better space for interpretation and trend context |
| Companion window → Settings | All coach configuration (aggressiveness, privacy, reason chips, prompt budget) | Keeps configuration out of transient UI |
| Session complete window | Post-session reflection and next-step capture | Natural moment for outcome feedback and recovery setup |

**Placement gate pass criteria:** no coach configuration in popover; popover remains action-oriented.

### 4.2 Primary / Secondary Action Hierarchy

- **Primary action:** `Start Focus` with explicit task + suggested duration.
- **Secondary actions:** `Snooze`, `Clean Restart (5m)`, `Mark Legit Interruption`, `I’m Back`.
- **Tertiary actions:** open detailed insights, adjust settings.

### 4.3 First-Glance Information (Top Visible Essentials)

- Current state: Stable / Drift Risk / High Risk.
- Time status: remaining time, break countdown, overrun indicator.
- One next best action: return now, restart short block, or end intentionally.
- Context safety: whether current interruption was marked genuine.

### 4.4 Interaction Flow Summary (see → click → result)

- See amber/red risk strip → tap compact action sheet → select 1 tap recovery → risk score drops or escalates based on behavior.
- See break 60s warning → tap `I’m Back` → timer resumes + context restored.
- End session midway → choose reason chip + next action → reduced false positives and better next recommendation.

### 4.5 Contradiction / Redundancy Audit

- No duplicate coach entry points for same job.
- No duplicate settings between popover and companion settings.
- Insight explanations and live interventions share the same metric definitions.

---

## 5) Product Integration Mode Artifacts

### 5.1 Feature Intent and Trigger

**Intent:** help user start faster, drift less, recover faster, and complete more sessions with less friction.  
**Triggers:** missed start window, fake-start signal, drift threshold, break overrun, repeated pauses, mid-session abandonment.

### 5.2 Discoverability Model

- **First discovery:** Insights tab “Focus Coach” onboarding card.
- **Re-entry:** live coach strip in active session + weekly report in Insights.
- **Education/help:** inline “Why this nudge?” explainer and settings info.

### 5.3 Journey Blueprint (Critical Paths)

#### A) Missed Start
`See` planned session missed → `Click` one-tap starter (5/10/15m) → `Response` immediate timer start + suggested app lock profile → `Next` live coach monitoring.

#### B) Early Fake Start
`See` high switch-rate + no task engagement signal → `Click` “Clean Restart” or “Return Now” → `Response` context reset and stricter lock suggestion → `Next` stabilized first 3 minutes.

#### C) Break Overrun
`See` break countdown expiry + overrun alert → `Click` reason chip + `I’m Back`/`Snooze` → `Response` logged context + adjusted risk model → `Next` resumed session with restored context.

#### D) Mid-Session End
`See` stop action confirmation → `Click` reason chip + next-step capture → `Response` classified as genuine exit vs avoidance → `Next` improved future start recommendations.

### 5.4 Failure and Recovery Path

- Missing telemetry source → degrade to session-timeline-only scoring.
- Notification permission denied → in-app strip only (no notification nudges).
- Invalid inference confidence → suppress intervention (no noisy prompt).

### 5.5 Completion Outcome State

At session end, store:
- completion quality,
- friction reason,
- next first step,
- intervention effects during session.

This powers personalized weekly adaptation.

---

## 6) What User Sees (Visual UX Spec)

## A) Pre-Session Coach Card (Menu Bar + Companion)
- Intended task (quick text or carry-forward).
- Resistance slider (1-5).
- Suggested session length (adaptive).
- Success condition (“What counts as done?”).
- Primary CTA: `Start Focus`.
- Motion: subtle glass pulse if planned start window is missed.

## B) Live Focus Coach Strip (Real-Time)
- Color states: Green (stable), Amber (drift risk), Red (high risk).
- Tap action sheet (compact): `Return Now`, `Clean Restart 5m`, `Snooze 10m`.
- Motion: non-jarring tint and blur transitions.

## C) Break Re-entry Card
- Visible countdown + 60-second warning.
- One-tap `I’m Back`.
- Overrun state shows 1-3 reason chips and optional snooze.

## D) Session End Quick Review (≤10s)
- 1-tap success quality.
- 1-tap friction reason.
- one-line next action capture.

## E) Weekly Coach Report (Insights)
- Top trigger patterns.
- Best session length by task type.
- Break patterns helping/hurting re-entry.
- Interventions ranked by effectiveness for this user.

---

## 7) Functional Architecture (On-Device)

### 7.1 Core Entities

- `TaskIntent`
- `SessionRun`
- `BreakEpisode`
- `Interruption`
- `AppUsageSegment`
- `InterventionAttempt`
- `InterventionOutcome`
- `PersonalModelSnapshot`

### 7.2 Event Taxonomy

1. **Timeline events**
   - session planned, started, paused, resumed, completed, abandoned
   - break started, ended, extended
2. **Behavior events**
   - foreground app changes
   - app switches/minute
   - blocked app open attempts
   - inactivity bursts
   - screen lock/unlock
   - notification interactions
3. **Coach events**
   - risk score change
   - nudge displayed
   - nudge action selected
   - nudge dismissed/snoozed
4. **Context reason events**
   - meeting, family, stress, fatigue, legit distraction, resistance, other

### 7.3 Derived Metrics Layer (Intelligence Signals)

- Start latency = actual start - planned start
- Activation friction index (weighted delay + hesitation behaviors)
- Pause creep (pauses/session, avg pause)
- Break creep (extensions, overrun minutes)
- Resume latency (break end to real restart)
- Recovery speed (drift detected to stable)
- Session survival curve (minute-level retention)
- Switching entropy (app-switch scatter)
- Avoidance fingerprint (predictive apps/actions before derailment)
- False break rate (break turns into non-restorative wandering)

### 7.4 Real-Time Risk Model (Every ~30s)

`risk = w1*startDelay + w2*switchSpike + w3*nonWorkDominance + w4*inactivityBurst + w5*pauseCreep + w6*breakOverrun + w7*blockedAttempts`

- Uses exponentially weighted recent behavior and task-type priors.
- Confidence gating: only intervene when risk and confidence exceed threshold.
- Reason chips reduce penalty for genuine interruptions.

### 7.5 Intervention Policy Engine

**Ladder:**
1. Soft: passive strip hint.
2. Medium: 1-3 tap guided choice.
3. Strong: only after repeated unresolved drift.

**Hard limits to avoid annoyance:**
- prompt budget per session,
- cooldown windows,
- snooze respected,
- no repeated identical prompts in short interval.

### 7.6 Intervention Effectiveness Learning

For each intervention, log:
- context,
- timestamp,
- selected action,
- whether start improved,
- whether drift reduced,
- whether completion probability increased.

Weekly adaptation:
- upweight high-yield interventions,
- suppress low-yield/noisy interventions,
- recalibrate thresholds by task type and time-of-day.

---

## 8) Reason-Capture and False Positive Control

### 8.1 Prompt Policy

Reason chips appear only on anomaly events:
- long break overrun,
- mid-session stop,
- repeated drift episode.

No long forms. Max 1-3 taps plus optional snooze.

### 8.2 Reason Chips (v1)

- `Urgent Meeting`
- `Family / Personal`
- `Stress Spike`
- `Fatigue`
- `Legit Distraction`
- `Resistance / Avoidance`
- `Other`

### 8.3 Model Handling

- Genuine reason tags lower punitive escalation.
- Repeated `Resistance / Avoidance` raises pre-session support intensity.
- Weekly reports separate “life interruptions” vs “avoidance loops.”

---

## 9) UI Spec Matrix (Coach + Insights Surfaces)

| Category | Status | Notes |
|---|---|---|
| Buttons | Complete | Primary: Start/Return. Secondary: Snooze/Clean Restart. States defined. |
| Information visualization | Complete | Risk strip + weekly pattern cards. No noisy charts by default. |
| Settings icons | Complete | Single SF Symbol family, consistent semantics. |
| Placement rules | Complete | Controls in popover; config in Settings; insights in companion tab. |
| Window/modal/sheet behavior | Complete | Compact anomaly sheet with explicit close/snooze paths. |
| Forms/new info requests | Complete | 1-3 tap chips, optional short text only at session end. |
| Dialog/box design | Complete | Clear title/body/actions and destructive confirmation for end/discard. |
| Typography | Complete | Existing LiquidDesignTokens scale preserved. |
| Colors | Complete | Green/Amber/Red risk semantics with contrast checks. |
| Components | Complete | Reuse Liquid panels/buttons/chips; no native `Form` sheets. |
| Animation | Complete | Purposeful micro-motion; reduced-motion fallback required. |
| State coverage | Complete | idle/focusing/paused/onBreak/overtime + coach states + anomaly states. |
| Button integrity | Complete | label-action trace required in implementation reviews. |
| Implementation quality | Complete | single-trigger actions, explicit errors, no timing workarounds. |

---

## 10) PM Integration Review

**PM Integration Verdict:** Pass

- **Product-model fit:** strong; coach maps to existing session lifecycle.
- **Clarity vs complexity:** low friction due compact prompts and anomaly-only reasons.
- **Conflict risk:** controlled by strict placement (no settings in transient surfaces).
- **Journey integrity:** full path covers start, focus, break, recovery, and end reflection.

---

## 11) Reliability, Error Handling, and Testing

### 11.1 Error Handling

- Telemetry unavailable → fallback scoring mode.
- Permission denied states must show actionable copy.
- No silent failures for user-visible operations.

### 11.2 Functional Test Scenarios

1. Missed planned start with eventual quick start.
2. Fake start in first 3 minutes.
3. Repeated drift with escalating interventions.
4. Long break overrun with reason chips and snooze.
5. Mid-session stop with genuine reason.
6. Mid-session stop with avoidance reason.
7. Notification off / app-usage restricted fallback.
8. Rapid state transitions (pause-resume loops).

### 11.3 Success Metrics (v1)

- Start latency reduction.
- Completion rate improvement.
- Reduced pause creep and break creep.
- Faster recovery after drift.
- Lower prompt-dismiss rate over time (better precision).

---

## 12) Explicit Assumptions

1. User consents to local behavior telemetry collection.
2. Existing app usage tracking remains available on macOS target versions.
3. User prefers calm interventions over strict enforcement.
4. On-device adaptation is sufficient for v1 sophistication target.
5. Coach effectiveness is evaluated over weeks, not single sessions.

---

## 13) Scope for v1

### In Scope
- Real-time on-device risk scoring.
- Adaptive intervention ladder.
- Anomaly reason chips + snooze.
- Weekly personalized coach reports.
- Settings for prompt intensity/privacy.

### Out of Scope
- Cloud model inference.
- Cross-device sync intelligence.
- Free-text heavy journaling workflows.

---

## 14) Final Product Statement

The Focus Coach should feel like a **calm, intelligent operator**: it understands your failure modes, intervenes at high-leverage moments, distinguishes genuine interruptions from avoidance, and helps you restart quickly with minimal friction.

