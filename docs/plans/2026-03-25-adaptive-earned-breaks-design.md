# Adaptive Earned Breaks Design

## Summary
Improve break awareness so FocusFlow rewards sustained mental effort with deserved breaks instead of always defaulting to short mechanical breaks. Add adaptive break suggestions, break-state controls, and ring escalation parity for break/pause states.

## Approved Scope
- Keep baseline Pomodoro action visible: `Planned 5m break`.
- Add adaptive action: `Suggested earned break`.
- Improve break-state controls to exactly:
  - `Start focusing`
  - `End session`
  - `Pause break`
- Fix/standardize ring color escalation behavior for break overrun and pause.
- Add bounded user-learning adaptation for break suggestions.
- Defer transparency/“what guardian learned” UX to a later feature.

## Goals
1. Reward deep effort (especially long sessions/overtime) with meaningful break suggestions.
2. Avoid rigid break timing that ignores actual effort and recovery needs.
3. Keep user control high with simple actionable choices.
4. Ensure visual urgency is consistent in break and pause states.

## Break Suggestion Model

### Inputs
- Current focus effort duration.
- Overtime contribution (if focus exceeded planned duration).
- Active run credit:
  - cumulative focus in run minus break minutes already taken in the same run.
- Lightweight historical adaptation signals:
  - break duration actually taken
  - whether user returned to focus after break
  - whether break ended early
  - break overrun behavior

### Baseline suggestion bands
- `<25m` effective effort: no earned bump (stay near planned 5m)
- `25–39m`: suggest 8m
- `40–54m`: suggest 12m
- `55–74m`: suggest 15m
- `75m+`: suggest 20m
- If focus had overtime, add `+2m` cap while respecting max 20m.

### Personal adaptation
- Start from baseline by effort band.
- Apply bounded adjustment from recent behavior: `-3m ... +3m`.
- Guardrails:
  - min break 5m
  - max break 20m
- Keep adaptation incremental per run (no abrupt swings).

## Session Complete UX
- Show two break buttons:
  - `Planned 5m break`
  - `Suggested earned break` (adaptive duration label)
- Reward messaging scales with effort depth:
  - stronger positive reinforcement for longer continuous effort/overtime.

## Break State Controls
- Break state primary controls become:
  - `Start focusing`
  - `End session`
  - `Pause break`
- `Pause break` behavior:
  - freeze break countdown
  - freeze overrun progression
  - resume continues from paused value

## Ring Escalation Behavior
- Ensure break overrun and pause share explicit escalation tiers:
  - green (normal)
  - amber (warning)
  - red (critical)
- Remove inconsistent behavior where break/pause can remain visually safe too long.
- Add parity logic so both states escalate deterministically based on thresholds.

## Data Flow
1. Focus completes or session ends after meaningful effort.
2. Earned-break calculator computes baseline suggestion from effort bands + run credit.
3. Adaptation layer applies bounded historical adjustment.
4. UI presents planned vs suggested break choices.
5. Break control actions and outcomes are logged:
   - suggested chosen/rejected
   - actual break length
   - returned to focus
   - early end
   - overrun
6. Adaptation store updates bounded coefficients for future suggestions.

## State + Persistence Additions
- Add per-run break learning signals in persisted model/store.
- Keep deterministic rules; no ML dependency in this iteration.
- Maintain compatibility with existing focus/break lifecycle and guardian models.

## Test Strategy

### Unit tests
- Earned break calculator:
  - effort bands
  - overtime bonus cap
  - run credit integration
  - adaptation clamp bounds

### Integration tests
- Session complete presents two break options.
- Break controls support `Start focusing`, `End session`, `Pause break`.
- Pause/resume break preserves timer correctness.
- Suggested break adaptation changes gradually based on outcomes.

### UI tests
- Break/pause ring color escalation parity (green/amber/red thresholds).
- Break state action availability and transitions.
- Suggested earned break label correctness for representative effort scenarios.

## Non-goals (deferred)
- Full transparency dashboard for learning explanations.
- Advanced ML/deep-learning policy selection.
- Complex motivational copy overhaul beyond this feature’s reward messaging needs.
