import SwiftUI

enum DesignLabComponent: String, CaseIterable, Identifiable, Codable {
    case material = "Material"
    case motion = "Motion"
    case timerRing = "Timer Ring"
    case primaryButtons = "Primary Buttons"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .material: "drop.degreesign.fill"
        case .motion: "waveform.path"
        case .timerRing: "timer"
        case .primaryButtons: "rectangle.on.rectangle.angled"
        }
    }

    var tint: Color {
        switch self {
        case .material: .white
        case .motion: FFColor.deepFocus
        case .timerRing: FFColor.focus
        case .primaryButtons: FFColor.success
        }
    }

    var subtitle: String {
        switch self {
        case .material:
            "Glass opacity, border, highlight, and depth"
        case .motion:
            "Spring response, damping, and interaction feel"
        case .timerRing:
            "Countdown ring, label rhythm, and glow"
        case .primaryButtons:
            "CTA hierarchy, hit area, and quiet premium chrome"
        }
    }

    var checklistItems: [String] {
        switch self {
        case .material:
            [
                "Does the surface read as glass, not tinted plastic?",
                "Is the border thin enough to feel native?",
                "Do highlights stay subtle instead of shiny?",
                "Can the content still read clearly at a glance?"
            ]
        case .motion:
            [
                "Does press feel immediate, not sticky?",
                "Does release settle smoothly without overshoot?",
                "Do hover and transition share the same rhythm?",
                "Does the animation still feel calm at 1x speed?"
            ]
        case .timerRing:
            [
                "Is the number dominant without feeling oversized?",
                "Is the ring thickness visually balanced?",
                "Does the label sit calmly under the timer?",
                "Does the glow support the state without shouting?"
            ]
        case .primaryButtons:
            [
                "Is the primary action obvious in the first second?",
                "Do button heights feel easy to tap and elegant?",
                "Do the secondary actions stay quiet?",
                "Does the control rail align with the rest of the UI?"
            ]
        }
    }

    var reviewPrompt: String {
        switch self {
        case .material:
            "Tune the glass first. Then check whether the content still feels airy."
        case .motion:
            "Pick the feel of the interaction before you touch the numbers again."
        case .timerRing:
            "Keep the countdown correct, then refine typography and ring balance."
        case .primaryButtons:
            "Make the primary action feel premium without adding noise."
        }
    }

    func variantTitle(for variant: DesignLabVariant) -> String {
        switch (self, variant) {
        case (.material, .a): return "A · Crystal Glass"
        case (.material, .b): return "B · Balanced Material"
        case (.material, .c): return "C · Frosted Edge"
        case (.motion, .a): return "A · Pulse Motion"
        case (.motion, .b): return "B · Rail Motion"
        case (.motion, .c): return "C · Drift Motion"
        case (.timerRing, .a): return "A · Hero Ring"
        case (.timerRing, .b): return "B · Structured Ring"
        case (.timerRing, .c): return "C · Minimal Ring"
        case (.primaryButtons, .a): return "A · Floating CTA"
        case (.primaryButtons, .b): return "B · Structured Rail"
        case (.primaryButtons, .c): return "C · Quiet Stage"
        }
    }

    func variantSubtitle(for variant: DesignLabVariant) -> String {
        switch (self, variant) {
        case (.material, .a): return "High translucency, soft border, and bright highlights"
        case (.material, .b): return "Most balanced material hierarchy for regular use"
        case (.material, .c): return "Tighter edge treatment with a calmer presence"
        case (.motion, .a): return "Fast feedback with a spring-forward pulse"
        case (.motion, .b): return "Structured motion with strong settle behavior"
        case (.motion, .c): return "Gentle drift that prioritizes calmness"
        case (.timerRing, .a): return "Big timer, ring-first composition, strong emphasis"
        case (.timerRing, .b): return "Split layout with balanced controls and metrics"
        case (.timerRing, .c): return "Smaller stage with typography-forward rhythm"
        case (.primaryButtons, .a): return "Prominent CTA with floating glass treatment"
        case (.primaryButtons, .b): return "Straightforward utility rail with clear hierarchy"
        case (.primaryButtons, .c): return "Quiet controls with minimal visual weight"
        }
    }
}

enum DesignLabVariant: String, CaseIterable, Identifiable, Codable {
    case a = "A"
    case b = "B"
    case c = "C"

    var id: String { rawValue }

    var shortName: String { rawValue }

    var index: Int {
        switch self {
        case .a: 0
        case .b: 1
        case .c: 2
        }
    }
}

enum DesignLabVariantVerdict: String, CaseIterable, Identifiable, Codable {
    case keep = "Keep"
    case reject = "Reject"
    case needsTweak = "Needs tweak"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .keep: FFColor.success
        case .reject: FFColor.danger
        case .needsTweak: FFColor.warning
        }
    }
}

enum DesignLabDecisionPhase: String, CaseIterable, Identifiable, Codable {
    case draft
    case compared
    case tuned
    case locked
    case promoted

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .draft: "pencil"
        case .compared: "square.stack.3d.up"
        case .tuned: "slider.horizontal.3"
        case .locked: "lock.fill"
        case .promoted: "arrow.up.right.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .draft: .secondary
        case .compared: FFColor.focus
        case .tuned: FFColor.warning
        case .locked: FFColor.success
        case .promoted: FFColor.deepFocus
        }
    }
}

enum DesignLabSurfaceTarget: String, CaseIterable, Identifiable, Codable {
    case menuBar = "Menu Bar"
    case sessionComplete = "Session Complete"
    case dashboard = "Dashboard"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .menuBar: "menubar.rectangle"
        case .sessionComplete: "checkmark.seal.fill"
        case .dashboard: "rectangle.3.group.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .menuBar: "Small, fast, highly repeated"
        case .sessionComplete: "High-intent completion state"
        case .dashboard: "Broad overview and steady hierarchy"
        }
    }
}

struct DesignLabGuidedFixSuggestion: Identifiable, Codable, Hashable {
    let id: UUID
    let component: DesignLabComponent
    let title: String
    let explanation: String
    let adjustmentSummary: String
    let confidence: String

    init(
        component: DesignLabComponent,
        title: String,
        explanation: String,
        adjustmentSummary: String,
        confidence: String
    ) {
        self.id = UUID()
        self.component = component
        self.title = title
        self.explanation = explanation
        self.adjustmentSummary = adjustmentSummary
        self.confidence = confidence
    }
}

struct DesignLabSuggestionHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let detail: String
    let appliedAt: Date

    init(title: String, detail: String, appliedAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.detail = detail
        self.appliedAt = appliedAt
    }
}

struct DesignLabVariantDecision: Codable, Hashable {
    var verdict: DesignLabVariantVerdict
    var notes: String
    var updatedAt: Date

    init(
        verdict: DesignLabVariantVerdict = .needsTweak,
        notes: String = "",
        updatedAt: Date = .now
    ) {
        self.verdict = verdict
        self.notes = notes
        self.updatedAt = updatedAt
    }
}

struct DesignLabComponentDecision: Identifiable, Codable, Hashable {
    let id: UUID
    let component: DesignLabComponent
    var winner: DesignLabVariant
    var notes: String
    var phase: DesignLabDecisionPhase
    var lockedAt: Date?
    var promotedAt: Date?
    var suggestionHistory: [DesignLabSuggestionHistoryEntry]
    var variantDecisions: [String: DesignLabVariantDecision]
    var lastUpdatedAt: Date
    var version: Int

    init(
        component: DesignLabComponent,
        winner: DesignLabVariant = .a,
        notes: String = "",
        phase: DesignLabDecisionPhase = .draft,
        lockedAt: Date? = nil,
        promotedAt: Date? = nil,
        suggestionHistory: [DesignLabSuggestionHistoryEntry] = [],
        variantDecisions: [String: DesignLabVariantDecision] = Dictionary(
            uniqueKeysWithValues: DesignLabVariant.allCases.map { ($0.rawValue, DesignLabVariantDecision()) }
        ),
        lastUpdatedAt: Date = .now,
        version: Int = 1
    ) {
        self.id = UUID()
        self.component = component
        self.winner = winner
        self.notes = notes
        self.phase = phase
        self.lockedAt = lockedAt
        self.promotedAt = promotedAt
        self.suggestionHistory = suggestionHistory
        self.variantDecisions = variantDecisions
        self.lastUpdatedAt = lastUpdatedAt
        self.version = version
    }
}

struct DesignLabDecisionArchive: Codable {
    var version: Int
    var decisions: [DesignLabComponentDecision]
    var updatedAt: Date
}
