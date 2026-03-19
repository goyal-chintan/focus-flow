# FocusFlow Design Language — "Obsidian Glass"

> Created: 2026-03-19
> Status: Approved (brainstorming session)
> Canonical reference for all UI decisions in FocusFlow.

---

## Philosophy

FocusFlow uses **"Obsidian Glass"** — a design language that marries Apple's native Liquid Glass material system with a dark, premium brand identity. We don't fight the platform; we lean into it. The app feels like it belongs on macOS Tahoe while maintaining its own visual signature.

**Three principles:**
1. **Let the system do the glass.** Use native `.glassEffect()` and system materials — never fake glass with custom fills.
2. **Dark canvas, glass controls.** Content lives on a dark material surface. Interactive elements use native glass. Never the reverse.
3. **Gradient CTAs are our signature.** The blue→light-blue focus CTA and amber resume CTA are brand elements — they stay custom.

---

## Material Hierarchy

| Layer | Treatment | SwiftUI API | Examples |
|-------|-----------|-------------|----------|
| **Shell / Background** | System dark glass material | `.ultraThinMaterial` | Popover panel, companion window bg |
| **Interactive Controls** | Native glass effect | `.glassEffect(.regular, in: shape)` | Project picker, preset buttons, Pause/Stop, blocking profile |
| **Primary CTA** | Custom gradient fill | `LinearGradient` + shadow | "Start Focus Session", "Resume Focus" |
| **Selected/Active Control** | Prominent glass | `.glassEffect(.prominent, in: shape)` | Selected duration preset |
| **Decorative Surfaces** | No glass | Custom draw / plain color | Timer ring, section dividers |
| **Text / Labels** | Plain | No background treatment | Section headers, footer text, tracked labels |

### Rules
- **Never** apply `.glassEffect()` to content text, data displays, or the timer ring.
- **Never** stack glass on glass — a `.glassEffect()` control inside a `.glassEffect()` container.
- System `Menu` dropdowns get Liquid Glass automatically — do nothing, this is correct.
- `GlassEffectContainer` wraps groups of glass controls that need to composite correctly.

---

## Color Language

### Surface Colors (used as tints/overlays, NOT opaque fills)
These are reference values for when we need tinted overlays on top of the material:

| Token | Hex | Usage |
|-------|-----|-------|
| Surface tint | `#131315` at 60-80% opacity | Dark overlay when needed for contrast |
| Container low | `#1C1C1E` at 40% opacity | Subtle depth differentiation |
| On surface | `#E5E2E1` | Primary text color |
| On surface muted | `#E5E2E1` at 55% | Secondary/label text |

### Spectral Colors (accent "light sources")

| Token | Hex | Usage |
|-------|-----|-------|
| Electric Blue | `#AAC7FF` | Primary accent, focus state, links |
| Primary Container | `#3E90FF` | CTA gradient start, active ring |
| Amber | `#FFC07A` | Pause state, warning, resume CTA |
| Amber Dark | `#D4940A` | Pause ring stroke |
| Mint | `#5ED4A0` | Break state, success |
| Salmon | `#FFB4A8` | Focus label, warm accent |
| Destructive | `#FF6B6B` | Stop/discard actions |

### State-Specific Color Map

| State | Ring | Glow | CTA | Label |
|-------|------|------|-----|-------|
| Idle | Subtle white 15% | None | Blue gradient | Muted |
| Focusing | Electric Blue | Blue pulse | — | Blue |
| Paused | Amber | Amber pulse | Amber gradient | Amber |
| Break | Mint | Green pulse | — | Mint |

---

## Typography

Based on SF Pro, using Apple's weight scale. **Never** use bold or black weights — they're too heavy for this aesthetic.

| Role | Spec | Usage |
|------|------|-------|
| Display Large | 42pt ultraLight rounded | Timer time display |
| Display Medium | 28pt light rounded | Hero numbers |
| Headline Large | 20pt semibold | "Paused for 3:15" |
| Headline Medium | 16pt medium | Section titles, project names |
| Body Medium | 14pt regular | Content text |
| Body Small | 13pt regular | Secondary content |
| Label Large | 12pt semibold | Button labels |
| Label Medium | 11pt medium | Footer text |
| Label Small | 10pt medium | Tracked uppercase labels |
| Control Label | 15pt semibold | CTA button text |
| Control Small | 13pt medium | Glass button text |

### Tracking (letter spacing)
- Uppercase labels: 1.5–2.0pt tracking
- CTA text: 0.5pt tracking
- Body text: 0 (default)

---

## Corner Radius

All corners use **continuous** (squircle) style — `.continuous` in SwiftUI.

| Element | Radius |
|---------|--------|
| Controls (buttons, pickers) | 12pt |
| Cards / panels | 16pt |
| CTA buttons | 18pt |
| Popover shell | System-managed |

---

## Timer Ring Specification

The timer ring is a **custom-drawn** element (not glass).

- **Size:** 178pt diameter
- **Stroke width:** 5pt
- **Inner disc:** Radial gradient from `containerLow` → `background` (creates recessed look)
- **Track ring:** White at 6% opacity
- **Specular highlight:** White at 8% opacity, trim 0.62–0.88 (top-left edge)
- **Progress ring:** Angular gradient of state color with varying opacity
- **Glow:** Dual-layer shadow (inner 10-16pt, outer 20-28pt) with breathing animation

### Breathing Glow Animation
- **Cycle:** 2.0 seconds, easeInOut, repeating forever (autoreverses)
- **Inner shadow:** Oscillates between 0.3–0.55 opacity, 10–16pt radius
- **Outer shadow:** Oscillates between 0.12–0.3 opacity, 20–28pt radius
- **Active states only:** Focusing (blue), Paused (amber), Break (green)
- **Idle:** No glow (clear color)

---

## Animation & Motion

**Philosophy: Expressive & Delightful.** Animations should create moments of joy while always serving clarity. Motion communicates state, not decoration.

### State Transitions
- **Spring animation:** response 0.35, dampingFraction 0.82
- Content sections use `.transition(.opacity)` or `.move(edge:).combined(with: .opacity)`

### Timer Ring Animations
- **Progress stroke:** easeInOut 0.75s on value change
- **Start focus:** Ring fills with a satisfying sweep + glow intensifies
- **Pause:** Glow color shifts blue→amber with crossfade
- **Resume:** Amber→blue color shift
- **Complete:** Glow pulses brightly then settles

### Interactive Feedback
- **Button press:** Native SwiftUI press states (glass handles this)
- **Preset selection:** Spring animation (response 0.3, dampingFraction 0.8) on pill indicator
- **Custom input reveal:** Move + opacity transition (0.3s spring)

### Anti-patterns
- No bounce animations
- No scale-up effects on buttons
- No spinning/rotating elements
- No delay before animations start

---

## Popover States Reference

### Idle
- No header bar
- Timer ring centered at top (28pt top padding)
- "PROJECT" tracked label → glass picker row
- Duration presets in glass container (15 | 25 | 45 | 60 | CUST)
- Blocking profile glass card with toggle
- Blue gradient CTA "▶ Start Focus Session"
- Footer: ✨ "Today's Total" | time | gear

### Focusing
- "FocusFlow" header + action buttons
- "ACTIVE CONTEXT" blue tracked label + "Project: Name"
- Timer ring with blue glow breathing
- Pause | Stop glass buttons
- Footer: "Today's Total" | time (blue) | gear

### Paused
- "FocusFlow" header + action buttons
- Timer ring with amber glow breathing + amber progress indicator
- "Paused for X:XX" amber headline
- Motivation text (italic, muted)
- Amber gradient CTA "▶ RESUME FOCUS"
- "END SESSION" tracked text link
- Footer: amber dot + "TODAY'S TOTAL" | time | gear

### Break
- "FocusFlow" header + action buttons
- Timer ring with green glow breathing
- "NEXT SESSION" tracked label + project name
- "SKIP BREAK ›" glass button
- Footer: "FocusFlow macOS" | "TODAY'S TOTAL" | gear

---

## Companion Window

(To be detailed when we reach this screen. General principles apply.)

- Uses `.ultraThinMaterial` as window background
- Tab bar uses native glass
- Content areas use standard dark material, not opaque fills
- Charts and data visualizations are custom-drawn (no glass)
- Form inputs use `.glassEffect(.regular)` individually — never wrapped in glass panels

---

## Quality Checklist

Before shipping any screen, verify:

- [ ] Is content clearly primary? (timer/data > controls > decoration)
- [ ] Are controls visually lighter than content?
- [ ] Is glass limited to the control layer? (no glass on content)
- [ ] Zero glass-on-glass stacking?
- [ ] Text legible at a glance? (contrast ratio adequate on material bg)
- [ ] Layout balanced, not cramped?
- [ ] Looks good in dark mode? (materials adapt automatically)
- [ ] Animations are expressive but not distracting?
- [ ] System menus and dropdowns feel consistent with our controls?
- [ ] No opaque background colors fighting with system material?
