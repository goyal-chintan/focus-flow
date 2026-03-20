# Apple Liquid Glass -- Complete Technical Reference

Compiled from WWDC25 sessions (219, 356, 359), Apple Developer Documentation,
and developer community analysis. Current as of iOS 26 / macOS Tahoe 26 beta.

---

## 1. Core APIs

### 1.1 The `Glass` Type

```swift
struct Glass {
    static var regular: Glass    // Default, adaptive, works anywhere
    static var clear: Glass      // High transparency, requires dimming layer
    static var identity: Glass   // No-op (disables glass; for conditional toggling)

    func tint(_ color: Color) -> Glass      // Blends color into the glass
    func interactive() -> Glass             // iOS only: adds scaling, bounce, shimmer on tap/drag
}
```

**Method chaining** -- order is irrelevant:
```swift
.glassEffect(.regular.tint(.orange).interactive())
.glassEffect(.clear.interactive().tint(.blue))   // same result regardless of order
```

### 1.2 `glassEffect(_:in:isEnabled:)` View Modifier

```swift
func glassEffect<S: Shape>(
    _ glass: Glass = .regular,
    in shape: S = DefaultGlassEffectShape,
    isEnabled: Bool = true
) -> some View
```

**Parameters:**
- `glass` -- `.regular` (default), `.clear`, or `.identity`
- `shape` -- Any `Shape`. Common: `.capsule`, `.circle`, `RoundedRectangle(cornerRadius: 16)`, `.rect(cornerRadius: .containerConcentric)`, `.ellipse`
- `isEnabled` -- `true` by default; set `false` to disable at runtime

### 1.3 `GlassEffectContainer`

```swift
struct GlassEffectContainer<Content: View>: View {
    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content)
    init(@ViewBuilder content: () -> Content)
}
```

**What it does:**
- Combines multiple glass shapes into a **single sampling region** (glass cannot sample other glass; the container provides the shared region)
- Enables **morphing transitions** between child glass views
- **Improves rendering performance** -- reduces from multiple `CABackdropLayer` offscreen passes (3 textures each) to one shared pass
- `spacing` parameter controls the **morphing threshold**: elements within this distance (in points) visually blend and morph together

### 1.4 `glassEffectID(_:in:)` Modifier

```swift
func glassEffectID<ID: Hashable>(
    _ id: ID,
    in namespace: Namespace.ID
) -> some View
```

Enables **morphing transitions** when views conditionally appear/disappear within the same `GlassEffectContainer`.

**Requirements for morphing (ALL must be met):**
1. Elements are in the same `GlassEffectContainer`
2. Each view has a unique `glassEffectID` with a shared `@Namespace`
3. Views are conditionally shown/hidden
4. State changes are wrapped in `withAnimation`

### 1.5 `glassEffectTransition(_:isEnabled:)`

```swift
func glassEffectTransition(
    _ transition: GlassEffectTransition,
    isEnabled: Bool = true
) -> some View
```

**`GlassEffectTransition` cases:**
- `.matchedGeometry` -- **default**; morphing/hero transition between glass elements
- `.materialize` -- fade/appear transition (glass gradually modulates light bending)
- `.identity` -- no transition animation

### 1.6 `glassEffectUnion(id:namespace:)`

Alternative to `GlassEffectContainer` for grouping. Combines glass effects when they share:
- Identical identifiers
- Same effect types
- Similar shapes

Useful when `GlassEffectContainer` spacing alone is insufficient for the desired grouping.

### 1.7 Button Styles

```swift
.buttonStyle(.glass)           // Translucent glass -- for secondary actions
.buttonStyle(.glassProminent)  // Opaque glass -- for primary actions
```

**`.glass` behavior:**
- System-owned layout (`.padding()` and similar modifiers have limited effect)
- Includes **system bounce animation** on press
- Toolbar buttons in `.confirmationAction`/`.cancellationAction` slots automatically adopt glass style
- Applies `.tint()` for accent color

**`.glassProminent` behavior:**
- More opaque and visually heavier
- Designed for primary call-to-action

### 1.8 AppKit (macOS)

```swift
button.bezelStyle = .glass
button.bezelColor = .systemBlue
```

- Multiple toolbar buttons automatically group onto one glass piece
- Use `NSToolbarItemGroup` or spacers to override grouping
- `UIGlassEffect` available in UIKit via `UIVisualEffectView`

---

## 2. Material System & Visual Layers

### 2.1 Liquid Glass Internal Layer Composition

Apple's Liquid Glass is composed of multiple rendering layers (from WWDC25 Session 219):

| Layer | Behavior |
|-------|----------|
| **Highlights** | Responds to geometry and device motion (specular) |
| **Shadow** | Opacity increases over text, decreases over light backgrounds |
| **Glow/Illumination** | Spreads from fingertip on interaction; radiates to nearby glass |
| **Tint** | Generates tone ranges based on content brightness behind |
| **Dimming** | Only present on `.clear` variant |
| **Lensing** | Real-time light bending -- concentrates light rather than scattering |

**Rendering:** GPU-accelerated Gaussian blur via **Metal 3 API** on M1+ chips. Each `CABackdropLayer` requires 3 offscreen textures per render pass.

### 2.2 Variant Rules

**`.regular` (default)**
- Adaptive -- works over any background
- Has all visual layers (highlights, shadow, glow, tint, lensing)
- Small elements (navbars, tabbars): can flip light/dark, high adaptation
- Large elements (sidebars, menus): adapt context but do NOT flip light/dark

**`.clear`**
- Permanent high transparency with dimming layer
- Use ONLY when ALL three conditions are met:
  1. Element sits over media-rich content (photos, videos)
  2. Content layer is not negatively affected by dimming
  3. Content above the glass is bold and bright
- NEVER mix `.regular` and `.clear` in adjacent elements

**`.identity`**
- Disables glass entirely; use for conditional toggling:
```swift
.glassEffect(reduceTransparency ? .identity : .regular)
```

### 2.3 Legacy Material Hierarchy (pre-Liquid Glass, still available)

These are `ShapeStyle` materials used with `.background()`:

| Material | Translucency | Use Case |
|----------|-------------|----------|
| `.ultraThinMaterial` | Mostly translucent | Lightest blur, maximum background visibility |
| `.thinMaterial` | More translucent than opaque | Light overlay |
| `.regularMaterial` | Balanced | General-purpose |
| `.thickMaterial` | More opaque than translucent | Heavier overlay |
| `.ultraThickMaterial` | Mostly opaque | Maximum obscuring |
| `.bar` | System bar appearance | Navigation/tab bars |

All automatically adapt to light/dark mode. Support vibrancy effects (primary, secondary, tertiary, separator).

**Backward compatibility fallback** (pre-iOS 26):
```swift
.background(.ultraThinMaterial)
// Plus linear gradient with .primary.opacity() values: 0.08, 0.05, 0.01, then clear
// Plus stroke with .primary.opacity(0.2) and lineWidth: 0.7
```

---

## 3. Animation Patterns

### 3.1 Recommended Animation for Glass Morphing

```swift
withAnimation(.bouncy) {
    isExpanded.toggle()
}
```

The `.bouncy` preset provides elastic morphing transitions -- this is the most commonly demonstrated animation for glass state changes.

### 3.2 Spring Parameters Used in Practice

```swift
// For custom spring control:
.spring(duration: type.duration, bounce: 0.2)   // bounce: 0.2 is the common value
.spring(response: 0.3, dampingFraction: 0.6)    // for more advanced control
```

- `bounce: 0.2` adds physics-based elastic feel
- `.bouncy` is the system preset that Apple consistently uses in demos

### 3.3 Morphing Behavior

When glass elements morph (expand/collapse):
- **Thicker material** appearance with deeper shadows
- **More pronounced lensing** effect
- The glass "stretches and deforms like a real fluid"
- Elements appear by **gradually modulating light bending** (materialization)

### 3.4 How Popovers/Menus Animate

- Bubble menus **"pop open" inline** from their trigger
- Elements can **"lift up temporarily"** during interaction
- Spotlight opens with the window appearing slightly larger then gradually decreasing to standard size (spring scale-down)
- Menu bar items float without a visible bar background -- items dim the area behind slightly

### 3.5 Transition Types

| Transition | Behavior |
|-----------|----------|
| `.matchedGeometry` (default) | Morphing hero transition between glass shapes |
| `.materialize` | Gradual light-bending fade-in appearance |
| `.identity` | No animation |

### 3.6 Size-Based Animation Behavior

- **Small elements** (nav bars, tab bars): Flip light/dark aggressively, high adaptation
- **Large elements** (sidebars, menus): Adapt context but do NOT flip to avoid distraction
- **Morphing states**: Simulate thicker material with deeper shadows, more pronounced lensing

---

## 4. Interaction Patterns

### 4.1 Press/Tap Feedback

When `.interactive()` is applied:
- **Scaling on press** (view scales down slightly)
- **Bouncing animation** on release
- **Shimmering effect** across the glass surface
- **Touch-point illumination** -- glow radiates from fingertip
- Glow **spreads to nearby Liquid Glass elements**
- Material **"illuminates from within"**

When using `.buttonStyle(.glass)`:
- System-provided **bounce animation when pressed**
- Fully system-owned -- no manual styling needed

### 4.2 Hover States (macOS)

- Glass elements respond to hover with subtle highlight changes
- Toolbar buttons in glass style have system hover feedback
- Menu bar items highlight on hover (standard unanimated highlight)

### 4.3 Hit Testing

**Known issue:** Buttons with glass effect only register hits on the content area, not the transparent glass area.

**Fix:**
```swift
Button { ... } label: { ... }
    .glassEffect(.regular, in: .capsule)
    .contentShape(.capsule)  // Define clickable region matching visual bounds
```

---

## 5. Control Sizing & Typography

### 5.1 macOS Control Sizes

| Size | Shape | Use Case |
|------|-------|----------|
| **Mini** | Rounded rectangle | Compact, high-density layouts (inspector panels) |
| **Small** | Rounded rectangle | Compact layouts |
| **Medium** | Rounded rectangle | Standard controls |
| **Large** | **Capsule** | Prominent actions |
| **X-Large** (NEW) | **Liquid Glass capsule** | Emphasis in spacious areas |

### 5.2 Shape System (Concentric Design)

Three shape types in the new design system:

1. **Fixed shapes** -- Constant corner radius regardless of container
2. **Capsules** -- Radius = 50% of container height
3. **Concentric shapes** -- Radius calculated by subtracting padding from parent's radius

Glass controls **nest perfectly into rounded corners of windows**, maintaining concentricity.

### 5.3 Standard Sizing Values from Examples

- Button/icon touch target: **44x44 points** (standard)
- Icon frames in glass: **60x60** or **80x80 points** (common)
- Icon font size in glass elements: **36 points** (from morphing examples)
- HStack spacing within GlassEffectContainer: **16-40 points** (typical range)
- GlassEffectContainer spacing (morphing threshold): **20-40 points** (typical)

### 5.4 Typography

- System font: **SF Pro** with bolder weights for clarity
- **Left-aligned** text in alerts and onboarding
- Text on glass automatically receives **vibrant treatment** -- adjusts color, brightness, saturation based on background
- Use system text styles (`.title`, `.headline`, `.body`, etc.) -- not custom sizes
- High contrast text recommended on glass: `.foregroundStyle(.white)` or `.bold()`

---

## 6. Color & Tinting

### 6.1 Tinting API

```swift
.glassEffect(.regular.tint(.blue))
.glassEffect(.regular.tint(.purple.opacity(0.6)))   // with opacity
```

**Rules:**
- Tinting is for conveying **semantic meaning** (primary action, state) -- NOT decoration
- Apply tint ONLY to **primary elements and actions**
- When everything is tinted, nothing stands out
- Apply `.tint(.blue)` exclusively to primary actions with `.glassProminent`

### 6.2 How Glass Handles Color

- Glass **automatically adapts its color scheme** (light/dark) based on content behind it
- Tint layer **generates tone ranges** based on background brightness
- Sidebar glass reflects light from nearby colorful content automatically (ambient reflection)
- System semantic colors (`label`, `secondarySystemBackground`) automatically adapt to glass context

### 6.3 Accent Colors on Glass

- Use `.tint()` modifier on the `Glass` type
- Accent colors blend INTO the glass material, not overlay
- System automatically adjusts readability
- Custom 4-color palette recommended for app personality (applied to decorative elements, not glass)

---

## 7. Accessibility

### 7.1 Automatic Adaptations (No Code Required)

| Setting | Effect |
|---------|--------|
| **Reduce Transparency** | Frostier appearance, increased opacity |
| **Increase Contrast** | Predominantly black/white with border highlight |
| **Reduce Motion** | Elastic properties disabled, decreased effect intensity |
| **Tinted Mode** (iOS 26.1+) | User-controlled opacity increase |

### 7.2 Manual Overrides (When Needed)

```swift
@Environment(\.accessibilityReduceTransparency) var reduceTransparency
@Environment(\.accessibilityReduceMotion) var reduceMotion

.glassEffect(reduceTransparency ? .identity : .regular)
```

**Best practice:** Let the system handle accessibility automatically.

---

## 8. Anti-Patterns -- What Apple Says NOT to Do

### Hard Rules

1. **NEVER apply glass to content layers** -- no glass on lists, tables, cards, media, scrollable content, or full-screen backgrounds. Glass is ONLY for the navigation layer floating above content.

2. **NEVER stack glass-on-glass** without a `GlassEffectContainer` -- causes visual clutter and rendering issues (glass cannot sample other glass).

3. **NEVER mix `.regular` and `.clear` variants** in adjacent elements.

4. **NEVER tint everything** -- defeats purpose; nothing stands out when all elements are tinted.

5. **NEVER allow content-glass intersections in steady state** -- reposition elements instead.

6. **NEVER apply glass to inner views** -- apply to the control itself.

7. **NEVER place multiple glass elements without `GlassEffectContainer`** -- breaks light interaction between elements and wastes rendering performance.

### Soft Guidelines

8. Avoid glass for purely decorative purposes.
9. Avoid overriding accessibility settings manually.
10. Avoid exceeding ~40-point spacing in containers for morphing.
11. Avoid custom font sizing -- use system text styles.
12. Avoid placing screen-specific actions (like checkout) in tab bars.
13. Avoid mixing symbols with text in single buttons (perceived as one control).

---

## 9. What Apple Does in Their Own Apps

### Spotlight (macOS Tahoe)
- Opens with spring animation: window appears slightly larger, then springs down to standard size
- Glass search field with real-time content adaptation
- Gesture invocation (pinch) has a different animation curve than keyboard shortcut

### Safari
- Tab bar uses Liquid Glass with content flowing behind
- URL bar glass adapts to page content beneath
- Toolbars group into glass bubbles that animate as modes change

### Control Center
- Glass elements morph when expanding/collapsing
- Interactive glass with touch illumination
- Elements pop open inline from triggers

### Menu Bar (macOS Tahoe)
- No longer a visible bar -- items float at top of screen
- Dims area behind slightly (no solid background)
- Icons group in glass bubbles
- Bubbles spring to life when scrolling content underneath

### Sidebars (macOS Tahoe)
- Inset design, built with Liquid Glass
- Content flows behind for immersive feel
- Scroll views extend beneath sidebars by default
- Ambient reflection from nearby colorful content

### Tab Bars (iOS 26)
- Dedicated Search tab included
- Media playback via accessory views
- Glass morphing between states

---

## 10. Complete Morphing Example

```swift
struct MorphingToolbar: View {
    @State private var isExpanded = false
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer(spacing: 30) {
            HStack(spacing: 20) {
                Button {
                    withAnimation(.bouncy) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "xmark" : "plus")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive())
                .glassEffectID("toggle", in: namespace)

                if isExpanded {
                    Button { } label: {
                        Image(systemName: "camera")
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive())
                    .glassEffectID("camera", in: namespace)

                    Button { } label: {
                        Image(systemName: "photo")
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive())
                    .glassEffectID("photo", in: namespace)

                    Button { } label: {
                        Image(systemName: "doc")
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive())
                    .glassEffectID("doc", in: namespace)
                }
            }
        }
    }
}
```

---

## 11. Known Issues & Pitfalls

1. **Rotation animation bug:** `rotationEffect(_:anchor:)` distorts glass shape during animation. Workaround: bridge to UIKit via `UIViewRepresentable`.

2. **Menu in GlassEffectContainer:** Breaks morphing animation on iOS 26.1 -- avoid this combination.

3. **Menu morphing (iOS 26.0-26.0.1):** Apply `glassEffect()` to outer Menu (not label), set as interactive.

4. **Menu morphing (iOS 26.1):** Create custom `ButtonStyle`, apply `glassEffect` to button label within style, then use `buttonStyle(_:)` on Menu.

5. **Hit testing:** Glass area outside content is not tappable by default -- use `.contentShape()` to fix.

6. **`.glassProminent`:** Was not compiling in Xcode 26.0 beta -- check latest beta.

7. **Performance:** Each uncontained glass element creates its own `CABackdropLayer` with 3 offscreen textures. Always group with `GlassEffectContainer`.

---

## 12. Platform Availability

iOS 26.0+, iPadOS 26.0+, macOS 26.0+ (Tahoe), watchOS 26.0+, tvOS 26.0+, visionOS 26.0+

Requires Xcode 26+. Metal 3 / M1+ for optimal GPU-accelerated rendering.

---

## Sources

- WWDC25 Session 219: Meet Liquid Glass
- WWDC25 Session 356: Get to know the new design system
- WWDC25 Session 359: Design foundations from idea to interface
- Apple Developer Documentation: GlassEffectContainer, glassEffect(_:in:), GlassEffectTransition
- Conor Luddy: iOS 26 Liquid Glass Ultimate Reference (github.com/conorluddy/LiquidGlassReference)
- JuniperPhoton: Adopting Liquid Glass -- Experiences and Pitfalls
- Swift with Majid: Glassifying custom SwiftUI views
- Donny Wals: Designing custom UI with Liquid Glass on iOS 26
- Tanaschita: Understanding SwiftUI's liquid glass button styles
- SerialCoder.dev: Transforming Glass Views with glassEffectID
