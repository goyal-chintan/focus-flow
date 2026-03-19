# FocusFlow Premium UI/UX Redesign — Design Document

**Date:** 2026-03-16
**Status:** Approved

---

## Overview

Redesign FocusFlow so it feels like a premium native macOS product rather than a functional SwiftUI utility. The target is a calmer, more sculpted, more intentional app with the same core information architecture but substantially better product identity, spacing, sizing, motion, and interaction detail.

The redesign should lean into Apple's current material language without copying marketing effects literally. "Liquid glass" here means layered depth, restrained spectral highlights, clear hierarchy, subtle motion, tactile controls, and visual calm. It does not mean placing glass on every surface.

## Product Intent

FocusFlow should feel like a precision focus instrument:

- Calm, not loud
- Premium, not ornamental
- Native, not web-like
- Playful in moments of reward, not in the base shell
- Dense enough for productivity, but never cramped

The menu bar popover is the product's hero surface. The companion window is the deep-work control room. Both surfaces must look like the same app.

## Problems in the Current UI

### 1. Identity Is Not Carried Through the App

The repository already contains a brand direction, but the UI shell does not consistently express it. The companion app uses mostly stock window/sidebar styling, generic section headers, and generic empty states. The result is competent but anonymous.

### 2. Typography Is Undersized

Many controls and labels drop into 9-13 point sizes, which makes the app feel cheap and cramped. The timer stage is readable, but supporting text, segmented choices, footers, and editing flows are too small for a premium desktop product.

### 3. Spacing Is Inconsistent

The app mixes many local spacing values. That causes cards, forms, lists, and button groups to feel assembled independently rather than designed as one system.

### 4. Surface Language Is Fragmented

Some views use glass buttons, some use `GroupBox`, some use stock lists, some use plain sheets. Radii, padding, and affordance depth vary by screen. The product needs one coherent container language.

### 5. Interaction Flows Are Functional but Not Memorable

Project picking, manual session logging, editing, and completion all work, but they present as small-form utility flows rather than high-quality native product moments.

## Experience Goals

### Primary Goals

- Make the app feel immediately premium when the popover opens
- Increase readability and tap/click comfort across the whole app
- Create a single reusable visual system for all surfaces
- Strengthen brand presence without making the UI louder
- Make completion and session-start moments feel rewarding

### Non-Goals

- Do not redesign the timer state machine or data model behavior as part of this pass
- Do not introduce non-native rendering stacks or custom drawing systems that fight SwiftUI
- Do not rely on aggressive gradients, neon accents, or excessive blur

## Design Direction

### Visual Tone

Use an "ambient focus cockpit" direction:

- Icy neutral base materials
- Soft blue primary accent for focus state
- Warm green for success and break-ready actions
- Controlled orange/red only for warning or destructive states
- Sparse use of purple as a deep-focus highlight, not a default brand color

Glass should read as depth and separation. Large surfaces can use ultra-thin or regular material with controlled borders. Controls should use fewer but stronger highlights, avoiding the "every chip is equally important" problem.

### Typography

Adopt a larger native type ramp and use it consistently:

- Hero timer value: large, airy, monospaced digits
- Hero supporting labels: closer to small-body than micro-caption
- Section headers: compact but visible, not tiny uppercase metadata
- Card labels: short, calm, secondary
- Action labels: medium weight with larger vertical padding

Avoid `caption2` for normal product UI. Use uppercase sparingly and only where it adds structure.

### Spacing

Use one spacing system across the app:

- 4: micro alignment
- 8: compact internal spacing
- 12: control gaps
- 16: card internals
- 24: section spacing
- 32: hero and shell spacing

The redesign should remove one-off spacing values unless a layout truly requires an exception.

### Shape Language

Create a coherent radius system:

- 10-12: compact controls
- 16-18: cards and grouped control trays
- 24+: hero containers and modal sheets

Buttons, pickers, cards, and empty states should feel related, with borders and highlights tuned to the same family.

### Motion

Use motion to reinforce state:

- Stage transitions in the menu bar popover should slide/fade in a quiet, springy way
- Numeric changes should use content transitions where possible
- Hover states should add depth, not color noise
- Completion and start-focus moments should feel slightly ceremonial

Motion should never be generic decoration.

## Information Architecture

### Menu Bar Popover

The popover should become a composed control deck with three zones:

1. Hero stage
   - Timer ring
   - Time
   - Current state label
   - Session progress indicator

2. Context deck
   - Selected project
   - Duration control or break state context
   - Blocking state if relevant

3. Action deck
   - Primary action row
   - Secondary actions
   - Footer summary and shortcut into the companion app

The popover should be wider than the current implementation so the hero stage can breathe and the action controls can become properly sized.

### Companion Window

The companion window should feel custom, not default:

- A richer sidebar with clearer selection treatment
- A shared header pattern inside each section
- Content presented in premium panels instead of raw lists and `GroupBox` blocks
- Empty states that use iconography, copy, and spacing consistent with the brand

The companion window should preserve the existing tabs:

- Today
- Week
- Projects
- Blocking
- Settings

The structure stays recognizable, but the shell and panel composition become much more intentional.

## Core Flow Redesign

### Start Focus

The idle state should feel ready rather than empty. Selected project, duration, and the main call to action should read as one deliberate setup experience. Duration presets should feel like tactile segmented glass controls, and custom duration entry should read as part of the same family instead of a separate micro-form.

### Active Focus

When focusing, the app should reduce clutter. Pause and stop remain available, but the timer stage stays dominant. Supporting context like blocking or session streak should be visible without competing with the main task.

### Paused

The paused state should feel visually distinct and slightly tense. The elapsed pause time needs stronger visibility, with warning escalation communicated through tone and emphasis rather than only color.

### Session Complete

This should become the most delightful flow in the product:

- Strong success moment
- Clear session summary
- More expressive mood selection
- Achievement entry with better hierarchy
- Split-time control as progressive disclosure
- A single clear primary action, with subordinate secondary actions

It should feel like a reward and reflection step, not a compressed form.

### Project Management

Project list rows, project editing, and project creation should feel more premium and more visual:

- Better project swatch/icon presentation
- More breathing room in rows
- Better affordance styling for edit/archive
- More polished project form with stronger field grouping

### Settings and Blocking

Settings and blocking screens should use premium grouped panels rather than stock `GroupBox` styling. Controls should align to the new system, with clearer section descriptions and improved density.

## Shared Component Strategy

Create a reusable visual system before refactoring all screens:

- App spacing tokens
- Typography tokens
- Shape/radius tokens
- Accent and semantic color helpers
- Premium card and panel containers
- Premium button styles and segmented controls
- Field chrome for pickers, text fields, and trays
- Shared section headers and empty states

This reduces drift and makes the redesign maintainable.

## Brand Integration

The redesign should incorporate the existing FocusFlow mark and visual identity in restrained ways:

- Companion window header or sidebar brand moment
- About/settings surface
- Empty states and completion surfaces
- Possibly the timer hero or app shell, if subtle

The brand should signal craft and recognition, not dominate productivity content.

## Accessibility and Usability

- Increase the minimum perceived target size of key controls
- Improve readability at a glance from the menu bar popover
- Preserve sufficient contrast between text and translucent surfaces
- Avoid encoding state only with color
- Keep keyboard focus and native control behavior intact

## Technical Strategy

The redesign should be implemented in two layers:

1. Design system foundation
   - Shared tokens and components
   - Reusable shell primitives

2. Surface migration
   - Menu bar popover
   - Completion flow
   - Companion shell
   - Dashboard and list panels
   - Forms and settings

This keeps the work tractable and reduces one-off restyling.

## Verification

The repository currently has no test target, so verification for this redesign should combine:

- Fresh `swift build`
- Fresh `bash Scripts/run.sh`
- Manual visual QA of the menu bar popover and companion window
- Targeted checks for all major states:
  - idle
  - focusing
  - paused
  - on break
  - session complete
  - project creation/edit
  - manual session logging
  - session edit
  - settings
  - blocking profiles

## Risks

- Overusing glass and blur can reduce clarity
- A shell redesign can accidentally regress density or usability
- Introducing too many bespoke components can make SwiftUI maintenance harder
- Visual inconsistency can persist if shared tokens are not established first

The implementation should bias toward systemization first and spectacle second.
