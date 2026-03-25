# Idle-First Guardian Intelligence Design

## Summary
This design makes FocusFlow guardian behavior strongest during idle/outside-session moments, since that is the highest-risk phase for procrastination. The system remains deterministic and explainable, with persisted memory that silently adapts from user chip inputs over time.

## Approved Decisions
- Deterministic memory engine first (no ML-first launch).
- Auto-adapt silently from behavior and user chip labels.
- Off-plan definition: mismatch against `selected project + work mode + on-duty state`.
- Idle-first protection: outside-session behavior is first-class, not secondary.
- Strict mode fast lane: prompt at 60s, escalate at 120s for off-context behavior.
- All modes remain protective (different cadence, not on/off behavior).
- Screen-share hard rule: suppress all guardian popups during screen sharing/interview context; continue silent tracking only.

## Definitions
- **Work intent**: one or more of:
  - app opened recently
  - project selected recently
  - recent delayed/abandoned start
  - within typical work period
  - context matches repeated historical missed-start pattern
- **Derailer**: context repeatedly labeled avoidant for a project/work mode (for example YouTube loops, side-repo Ghostty loops, over-planning chat loops).
- **Off-plan**: current context is not aligned with planned project/work mode and on-duty status.

## Architecture
### Core Components
- `AppUsageTracker`: capture app foreground and enrich context (domain/title/repo/workspace when available).
- `SuspiciousContextObservation`: normalized event model for in-session and idle contexts.
- `Adaptation Engine` (deterministic): computes confidence using recency, frequency, and user-labeled disposition.
- Memory stores:
  - `DriftClassificationMemory` (planned vs avoidant confirmations)
  - `ProjectContextRisk` (avoidant/planned counts + correlation signals)
- Intervention policy:
  - guardian state (`Observe`, `Watchful`, `Challenge`, `Release`)
  - chip micro-prompt, sticky cue, strong challenge routing

### Context Key
All learning and recommendations key to:
`(projectId | workMode | contextKey)`
where `contextKey` may be app bundle, browser domain/title signature, terminal/editor repo/workspace, or fallback app identity.

No global one-shot allowlists/blocklists are created from single events.

## Behavior Policy
### Active Session
- Detect off-plan drift quickly.
- Ask via compact chip prompt first when confidence is uncertain/new.
- Escalate if repeated unresolved drift.

### Idle / Outside Session (Priority Path)
- Default `Observe`.
- Move to `Watchful` on suspicious drift.
- Move to `Challenge` on high-confidence or repeated derailer pattern.
- Challenge requires:
  - `high_confidence_drift OR repeated_project_pattern`
  - not in `Release`
  - not clearly off-duty
  - likely work-intent window (or repeated derailer exception path)

### Mode Cadence
- Strict: prompt 60s, escalate 120s.
- Adaptive/Passive: slower cadence but still protective; never fully disabled unless user explicitly opts out.

## Interaction Design
- Smart micro-prompt uses chips:
  - planned research
  - required switch
  - real break
  - low-priority work
  - procrastinating
  - avoiding hard part
- Prompt should be brief, context-specific, and auto-dismiss if ignored.
- Prompt frequency and block recommendations adapt from outcomes.

## Ghostty / Terminal Handling
- Ghostty and terminal/editor contexts are first-class analyzable contexts.
- They are not permanently “bad” by default.
- They become risk/allow candidates per project/work mode based on repeated labeled outcomes.

## Privacy + Suppression Rules
- Keep all intelligence on-device.
- Respect existing detailed-domain collection setting.
- During screen sharing/interview context:
  - suppress all guardian popups (hard rule)
  - continue passive logging only
  - no blocking dialogs or attention-grabbing overlays

## Adaptation Algorithm (Deterministic)
For each context key:
- Record planned/avoidant labels with timestamp.
- Maintain recency windows and decay stale evidence.
- Raise confidence when avoidant repeats cluster.
- Lower confidence when planned confirmations accumulate.
- Increase intervention cadence for repeated unresolved derailers.
- Decrease cadence when user repeatedly confirms legitimate context.

## Testing Strategy
- Unit tests:
  - off-plan classification correctness
  - memory updates (planned/avoidant, decay windows)
  - strict timing policy (60/120)
  - release suppression behavior
  - screen-share suppression behavior
- Integration tests:
  - idle repeated derailer -> prompt -> escalation path
  - chip labels change future prompt frequency
  - Ghostty side-repo drift becomes project-scoped risk candidate
- UI tests:
  - one intervention surface at a time
  - no popup in screen-share mode
  - contextual chip sheet content fidelity

## Rollout
Phase 1 ships deterministic engine + full instrumentation.
Phase 2 may add a lightweight on-device ranker if precision plateaus, without changing persistence contracts.
