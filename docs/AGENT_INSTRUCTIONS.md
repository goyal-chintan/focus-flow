# FocusFlow — Agent Instructions

> **This is the authoritative workflow guide for any AI agent working on FocusFlow.**
> Follow these phases adaptively: skip steps only when clearly inapplicable (e.g., UI audit for a pure data-model change), and always justify the skip in your reasoning.

---

## Phase 0 — Orient Before Anything Else

**Always run this before writing a single line of code.**

1. **Invoke `using-superpowers` first.** No exceptions — it wires up skill awareness for the session.
2. **Read recent git history** to understand what already changed:
   ```bash
   git --no-pager log --oneline -15
   git --no-pager diff HEAD~3..HEAD --stat
   ```
3. **Read the decision log** — scan `docs/project-memory/decisions/DECISIONS.md` for entries related to the area you're touching. Never re-litigate a settled decision without surfacing it to the user.
4. **Check the session plan** if one exists at `~/.copilot/session-state/<session-id>/plan.md`.
5. **Summarise what you found** to the user in ≤5 sentences before proceeding.

---

## Phase 1 — Understand the Task

### For bugs and unexpected behaviour
- Invoke **`systematic-debugging`**. Complete Phases 1–3 (root cause confirmed) before proposing any fix. Never guess.

### For new features, UI changes, or non-trivial refactors
- Invoke **`brainstorming`**. Do not write code until the design is approved by the user.
- Ask clarifying questions **one at a time** using the `ask_user` tool.
- Prefer multiple-choice questions over open-ended ones.
- Mandatory clarification triggers:
  - Scope is ambiguous
  - Multiple reasonable approaches exist
  - The change affects a user-visible flow or data model
  - The request involves deleting data or making a destructive change

### For any UI or UX change (screens, components, flows, interactions, visual language)
- Invoke **`apple-grade-ui-system`** immediately — before any implementation.
- Run **Design Mode** to establish visual hierarchy, Liquid Glass usage, and layout intent.
- Run **Product Integration Mode** to confirm the change fits the full user journey and every interaction state is explicitly defined.
- Do not write any SwiftUI code until Design Mode output is reviewed and Product Integration Mode is complete.
- Non-functional visual language changes (colour, typography tone, motion style, glass treatment) require explicit user approval before implementation.

### For complex multi-step work
- Invoke **`writing-plans`** after brainstorming. Save the plan to `docs/plans/YYYY-MM-DD-<topic>-design.md` and commit it before touching implementation.

---

## Phase 2 — Branch

**Never commit directly to `main` unless explicitly told to.**

```bash
# Feature work
git checkout main && git pull
git checkout -b feature/<short-descriptive-name>

# Bug fixes
git checkout -b fix/<short-descriptive-name>
```

Use **`using-git-worktrees`** when the task needs isolation from the current workspace or runs alongside another branch.

---

## Phase 3 — Implement

### Core rules
- Make **surgical, minimal changes** — only touch what the task requires.
- Do not fix unrelated pre-existing issues unless they are directly caused by your change.
- Commit in logical, atomic units — one concern per commit.
- **Never commit secrets, credentials, or raw API keys.**
- All commit messages must include the trailer:
  ```
  Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
  ```

### Skill routing
| Situation | Skill to invoke |
|---|---|
| Complex multi-step task with independent subtasks | `dispatching-parallel-agents` |
| Executing an already-written plan | `executing-plans` |
| Multiple independent implementation tasks in one session | `subagent-driven-development` |
| TDD flow required | `test-driven-development` |

### Build verification (after every meaningful change)
```bash
swift build
swift test
```
Fix build errors immediately — never leave a broken build.

### SwiftUI type-check timeout fix
Complex view bodies trigger "unable to type-check this expression in reasonable time." Fix by extracting sections into `private var someSection: some View` computed properties or separate structs.

---

## Phase 4 — Audit

Run the appropriate audit gates based on what changed.

### Always (every task)
```bash
swift build          # Must pass with zero warnings introduced by your changes
swift test           # All existing tests must pass; new behaviour must have tests
```

### For any UI or UX change
`apple-grade-ui-system` is the **full-lifecycle approach** for UI work — not just an end-gate. It was already invoked in Phase 1 (Design Mode + Product Integration Mode). In Phase 4, complete the final gate:

**Gatekeeper Review Mode** — strict pass/block decision against the implemented code.
- If BLOCKED: fixes are mandatory. Do not proceed to Phase 5.
- If PASSED: record any UI decisions in the decision log before shipping.

UI hard rules for FocusFlow (violations = automatic BLOCKED):
| Rule | Detail |
|---|---|
| No glass-on-glass | Use `GlassEffectContainer` for grouped glass elements |
| No `.glass` on icon-only buttons | Use `.buttonStyle(.plain)` + `.frame(width: 28-30)` + `.contentShape(Rectangle())` |
| No glass panels on list rows | Use `Color.white.opacity(0.04)` fills; reserve panels for section containers |
| Popover background opacity | 0.45–0.55 max — higher kills translucency |
| Minimum text size | 10pt — Apple HIG floor, no exceptions |
| Minimum tap target | 30pt — use `.frame()` + `.contentShape(Rectangle())` |
| Conditional button styles | `if/else` branches for `.glassProminent` vs `.glass` — ternary causes type errors |
| No custom matchedGeometryEffect pills | Use per-button `.glass`/`.glassProminent` + `.capsule` instead |
| Timer ring proportions | 160pt ring, 6pt stroke, 36pt text — locked |
| No double chevrons on Menu labels | Native Menu renders its own; don't add one |

### For a large feature or end-of-sprint audit
Invoke **`requesting-code-review`** on the full diff before shipping.

---

## Phase 5 — Ship

### 1. Update the decision log
Add a dated entry to `docs/project-memory/decisions/DECISIONS.md` for any non-trivial architectural or UX decision made during the task. Use the existing format:

```markdown
## [Decision Title]

**Category:** Timer | UI | Data | Architecture | Notifications | Coach
**Date:** YYYY-MM-DD
**Status:** Active
**Session(s):** <session description>

### Problem
### Alternatives Considered
### Decision
### Rationale
### Outcomes
### Learnings
```

### 2. Update README.md
If the task adds, changes, or removes a user-visible feature or behaviour, update `README.md` accordingly. Keep feature descriptions factual and concise.

### 3. Raise the PR
Once `swift build` and `swift test` are both green and the audit gates have passed:

```bash
gh pr create \
  --base main \
  --title "<type>: <concise description>" \
  --body "$(cat <<'EOF'
## What changed
<bullet list of what was changed and why>

## How to test
<steps to verify manually>

## Checklist
- [ ] `swift build` passes
- [ ] `swift test` passes
- [ ] Decision log updated (if applicable)
- [ ] README updated (if applicable)
- [ ] UI audit passed (if UI-touching)
EOF
)"
```

Use prefix `feat:`, `fix:`, `perf:`, `refactor:`, or `docs:` in the title.

---

## User Interaction Rules

**Always ask the user before:**
- Deleting or migrating persistent data (SwiftData schema changes)
- Changing a settled architectural pattern (e.g., replacing the state machine, removing a service)
- Choosing between two designs where the trade-off is purely a product preference
- Taking more than 3 significant files out of scope (scope creep)

**Ask one question at a time** using the `ask_user` tool. Prefer multiple-choice. Offer a recommended option when you have one.

**Never assume silence means approval.** If a user hasn't responded to a key question, surface it again before shipping.

---

## Project-Specific Context

### Platform
- macOS 26+ (Tahoe) only — Liquid Glass APIs required
- Swift 6.2, SwiftUI, SwiftData, no external dependencies
- Menu bar app (`LSUIElement=true`), no dock icon
- App must be run via `bash Scripts/run.sh` (needs `.app` bundle for notifications)

### Architecture
- **MVVM + Scene-based**: `TimerViewModel` (`@Observable`) is the single source of truth
- Two UI surfaces: `MenuBarExtra` (popover) + `Window` (companion)
- SwiftData schema: `Project`, `FocusSession`, `AppSettings`, `TimeSplit`
- Entry point: `main.swift` calls `FocusFlowApp.main()` — `@main` is NOT on `FocusFlowApp`

### Timer State Machine
```
IDLE → startFocus() → FOCUSING → timerCompleted() → OVERTIME
                         ↓                               ↓
                      pause()                    continueAfterCompletion(.takeBreak) → ON_BREAK
                         ↓                       continueAfterCompletion(.continueFocusing) → FOCUSING
                      PAUSED                     continueAfterCompletion(.endSession) → IDLE
                         ↓
                      resume() → FOCUSING
```

### Key services
| Service | Responsibility |
|---|---|
| `AppUsageTracker` | Tracks frontmost app/browser domain; in-memory cache with periodic persist |
| `AppBlocker` | Event-driven blocking via NSWorkspace observers |
| `FocusCoachOpportunityModel` | Adaptive drift/intent scoring |
| `FocusCoachInterventionPlanner` | Routes coach interventions (notification vs strong prompt) |
| `NotificationService` | Singleton; guards all UNUserNotificationCenter calls behind bundle ID check |

### Coach escalation routing
```
idle + escalationLevel >= 2 + frontmostCategory == .productive
  → strong prompt window
idle + outsideSessionAwaitingStartFocus
  → strong prompt window
otherwise
  → notification nudge
```

### Hard-won lessons (do not repeat)
- `activate(ignoringOtherApps: true)` is deprecated and a no-op on macOS 14+/Tahoe — use `activate()`
- Adding stored properties with non-default types to `FocusCoachContext` requires an explicit `init`
- Complex view bodies cause type-check timeouts — extract to `private var` computed properties
- The `autoStartBreak` setting is intentionally unused — completion always shows `SessionCompleteWindowView`
- Sessions under 1 minute are auto-deleted in `stop()` and `cleanupOrphanedSessions()`
- Minimum session duration: 5 minutes (300s guard in `startFocus()`)

---

## Quick Skill Reference

| Need | Skill |
|---|---|
| Starting any session | `using-superpowers` |
| Designing a feature | `brainstorming` |
| **Any UI/UX change (design → build → review)** | **`apple-grade-ui-system`** |
| Debugging a bug | `systematic-debugging` |
| Writing an implementation plan | `writing-plans` |
| Executing a plan | `executing-plans` |
| UI quality gate | `apple-grade-ui-system` |
| Code review before merge | `requesting-code-review` |
| Responding to review comments | `receiving-code-review` |
| Fixing failing CI | `gh-fix-ci` |
| Addressing PR comments | `gh-address-comments` |
| Parallel independent tasks | `dispatching-parallel-agents` |
| Git isolation | `using-git-worktrees` |
| Claiming work is complete | `verification-before-completion` |
| Improving this file | `claude-md-improver` |
