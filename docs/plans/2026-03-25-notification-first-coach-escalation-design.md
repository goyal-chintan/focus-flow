# Notification-First Coach Escalation Design

## Summary
When Focus Coach outside-session prompts are suppressed or gated, the app can feel silent and passive.  
This design introduces a **notification-first escalation path** that still respects hard safety constraints (especially screen-share), keeps adaptive learning, and gives users stronger motivational nudges to re-enter focus.

## Approved goals
- Coach should not sit idle when a nudge is appropriate.
- Escalation order should be:
  1. Notification nudge first
  2. Strong prompt after one missed notification
- Screen-share contexts are a hard pass:
  - suppress **both** popups and notifications
- Acknowledgement is strict:
  - only `startFocus()` counts as a response
- Maintain adaptive behavior based on context and history:
  - time of day (night)
  - repeated snooze / denial / non-response
- Add stronger motivational copy mode (discipline-oriented, still respectful and non-shaming).

## Architecture

### New orchestration lane
Outside-session coach routing gains a new lane:

`Idle -> Notification Attempt -> Await Response -> Strong Prompt`

This sits above existing scoring/planner logic and does not replace it.

### Hard gates (unchanged + explicit)
- If screen-share-sensitive context is active and suppression is enabled:
  - no notification
  - no popover prompt
  - no strong window
- Existing release-window suppression remains in effect.

### Response semantics
- Escalation clears only on `startFocus()`.
- Opening app/popover, viewing prompt, or passive interaction does not count.

## Components and state

### TimerViewModel additions
- `pendingNotificationNudgeAt: Date?`
- `outsideSessionNudgeAttemptCount: Int`
- `outsideSessionAwaitingStartFocus: Bool`
- `outsideSessionEscalationCooldownUntil: Date?`
- adaptive timeout/cooldown counters (e.g., repeated non-response streak)

### Optional settings additions
- `coachOutsideSessionNotificationFallbackEnabled` (default true)
- `coachDisciplineModeEnabled` (default false)
- `coachOutsideSessionEscalationBaseMinutes` (default 5)

### Diagnostics visibility
Extend settings debug to show:
- last nudge channel used (notification / strong prompt / suppressed)
- suppression reason
- pending escalation age
- next eligible escalation time

## Data flow

1. Idle evaluation computes drift/work-intent/opportunity as today.
2. If no hard suppression and route is nudgable:
   - send one notification first
   - persist pending nudge state
3. Await response window:
   - if `startFocus()` occurs -> mark success, clear escalation state
4. If no response by timeout:
   - escalate once to strong prompt
   - enforce max 1 strong prompt per adaptive window
5. Update learning counters:
   - response / non-response / snooze / deny patterns
   - adapt future timeout and escalation cool-down

## Adaptive escalation policy

Base policy:
- max one strong prompt active per cycle
- escalation occurs after one missed notification

Adaptive timeout multiplier:
- **Night hours**: longer timeout/cool-down
- **Repeated non-response / snooze / denial**: progressively longer timeout
- **Recent successful re-focus**: slightly shorter timeout

This preserves persistence without becoming spammy.

## Messaging policy

### Notification + strong prompt copy
- Keep existing contextual reasoning (drift/work-intent context).
- Add optional **discipline mode** for stronger motivational framing:
  - progress/greatness framing
  - cost-of-procrastination framing
  - high-agency reminder language
- Guardrails:
  - no abusive, shaming, or harmful wording
  - short, actionable, respectful tone

## Error handling and safety
- Never escalate if screen-share suppression is active.
- No duplicate notification while `outsideSessionAwaitingStartFocus == true`.
- If app restarts mid-await window, restore pending state from persistence.
- Fallback if notification permission denied:
  - mark as notification-unavailable and route directly to in-app path (still respecting screen-share hard pass).

## Testing strategy

### Unit tests
- Notification-first route selected when eligible.
- One missed notification escalates to strong prompt.
- Screen-share hard pass suppresses both channels.
- Strict acknowledgment: only `startFocus()` clears escalation.
- Adaptive cooldown increases at night and after repeated non-response.

### Integration tests
- Pending escalation survives app relaunch.
- No duplicate escalations within cooldown.
- Suppression diagnostics surface correct reason.

### Contract/UI tests
- Debug panel shows escalation channel + suppression reason + next escalation time.
- Discipline-mode message templates are selected by context category.

## Out of scope
- Multi-step conversational notification replies.
- External push services.
- Full quote-library overhaul beyond integrating stronger optional discipline-mode templates.

