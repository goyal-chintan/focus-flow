# FocusFlow Liquid Glass Redesign — Design Document

**Date:** 2026-03-16
**Status:** Approved (Phase 1: Menu Bar Popover)
**Branch:** codex/premium-ui-redesign

---

## Problem

The current premium-ui-redesign applies translucent materials to content surfaces (stat cards, forms, lists) which violates Apple's core rule: "Glass is ONLY for the navigation layer floating above content." It also lacks glassEffectID morphing transitions, interactive() feedback on custom controls, and uses undersized controls with over-scaffolded section headers.

## Approach

Incremental foundation-first (Approach B). Fix design system, then migrate menu bar popover with real Liquid Glass APIs. User reviews visually before companion window is touched.

## Phase 1: Foundation + Menu Bar Popover

### Design System Changes
- Kill PremiumSurface for popover; replace with ContentPanel (opaque) and direct glassEffect() on controls
- Use Color.primary.opacity() instead of Color.white.opacity() (adapts to light/dark)
- Use .bouncy animation for glass transitions
- Centralize colorFromName() and moodColor() in DesignSystem.swift
- Add FFSize tokens (controlMin: 44, iconFrame: 60)
- Tiered shadows instead of one-size-fits-all

### Menu Bar Popover
- @Namespace + GlassEffectContainer(spacing:) + glassEffectID for action button morphing
- "Start Focus" morphs into "Pause" (same glassEffectID), "Stop" materializes beside it
- Duration presets: glass buttons with morphing selection
- Project picker: .glassEffect(.regular.interactive()) instead of manual material
- Timer ring: 5px stroke, soft glow, .largeTitle font, .subheadline label
- Remove PremiumSurface wrappers from all popover sections
- .bouncy animation for all state changes
- Fix paused state to use design tokens

### Session Completion
- Width: 380px (not 432px)
- Strip over-scaffolding: no instruction text, no eyebrows on every section
- Mood buttons with glassEffect + interactive
- Action buttons materialize in via GlassEffectContainer

## Phase 2: Companion Window (pending user approval of Phase 1)

Deferred until Phase 1 is visually reviewed and approved.

## Anti-Patterns to Enforce
- NEVER glass on content (lists, cards, forms)
- NEVER stack glass without GlassEffectContainer
- NEVER tint more than the single primary action per surface
- All interactive elements 44pt+ minimum
- System text styles, not custom font sizes
