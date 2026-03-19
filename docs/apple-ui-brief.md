# Apple UI Design Brief — FocusFlow

## Design Source of Truth

Use Apple platform design principles, Human Interface Guidelines, and Liquid Glass concepts as inspiration.

## Mandatory Rules

- Prefer standard SwiftUI components and system behaviors over custom-drawn UI.
- Keep the content layer clean and readable.
- Use Liquid Glass style mainly for navigation, bars, sheets, menus, and controls.
- Do not put glass effects on content cards, list rows, or dense data regions unless clearly justified.
- Never stack glass on glass.
- Maintain strong visual hierarchy: content first, controls second, decoration last.
- Keep typography highly legible and calm.
- Use spacing and grouping to make scanning easy.
- Use light/dark mode correctly.
- Respect accessibility and reduced-transparency style fallbacks.

## Anti-Goals

- No "frosted blur everywhere"
- No oversized floating elements unless functionally justified
- No flashy gradients or neon
- No custom ornamental effects that fight readability
- No crowded toolbars
- No trying to imitate Apple by copying screenshots literally

## Interaction Tone

- Responsive, lightweight, restrained
- Menus, sheets, and search should feel native
- Motion should support clarity, not show off

## Review Checklist

- [ ] Is the content clearly primary?
- [ ] Are controls visually lighter than content?
- [ ] Is glass limited to the right layer?
- [ ] Is there any glass-on-glass?
- [ ] Is text legible at a glance?
- [ ] Does layout feel balanced and not cramped?
- [ ] Does it still look good in dark mode?

## FocusFlow-Specific Design Decisions

### Canonical Mockup References (per state)

| State | Reference Mockup | Key Characteristics |
|-------|-----------------|---------------------|
| **Idle** | `popover_idle_liquid_glass_refined` | No header, ring first, PROJECT label, blue dot picker, presets with CUST, blocking profile, gradient CTA |
| **Focusing** | `popover_focusing_dark` | FocusFlow header + action buttons, ACTIVE CONTEXT section, ring with blue glow, Pause/Stop controls |
| **Paused** | `popover_paused_dark` | FocusFlow header, amber ring with glow, pause duration, motivation text, amber RESUME CTA |
| **Break** | `popover_break_light` | FocusFlow header, green ring, NEXT SESSION context, SKIP BREAK button |

### Color Language

| State | Ring Color | Glow | CTA Gradient |
|-------|-----------|------|-------------|
| Idle | Subtle grey | None | Blue gradient |
| Focusing | Electric Blue (#3E90FF) | Blue breathing pulse | — |
| Paused | Amber (#FFC07A) | Amber breathing pulse | Amber gradient |
| Break | Mint (#5ED4A0) | Green breathing pulse | — |

### Animation Principles

- Timer ring glow **breathes** (subtle 2s pulse) during active states
- State transitions use **spring animations** (response: 0.35, damping: 0.82)
- Progress ring animates smoothly (0.75s easeInOut)
- No gratuitous motion — every animation serves clarity

### Glass Usage

- `.obsidianGlass()` on: control buttons, project picker, presets row, blocking profile card
- `.buttonStyle(.glass)` / `.glassProminent` on: popover sheets (create project)
- **Never** on: timer ring, text content, footer bar, section labels
