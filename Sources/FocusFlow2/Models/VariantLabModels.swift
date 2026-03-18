import Foundation
import SwiftUI

enum VariantLabMenuVariant: String, CaseIterable, Identifiable, Codable {
    case variantA = "A"
    case variantB = "B"
    case variantC = "C"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .variantA: return "A \u{00B7} Hero Glass"
        case .variantB: return "B \u{00B7} Structured Rail"
        case .variantC: return "C \u{00B7} Minimal Stage"
        }
    }

    var subtitle: String {
        switch self {
        case .variantA: return "Expressive hero timer with floating controls"
        case .variantB: return "Data-first layout with split control lanes"
        case .variantC: return "Calm typography-forward layout with subtle accent"
        }
    }

    func title(for component: VariantLabComponent) -> String {
        "\(rawValue) \u{00B7} \(component.variantTitle(for: self))"
    }

    func subtitle(for component: VariantLabComponent) -> String {
        component.variantSubtitle(for: self)
    }
}

enum VariantLabComponent: String, CaseIterable, Identifiable, Codable {
    case timerRing = "Timer Ring"
    case buttons = "Buttons"
    case effects = "Glass Effects"
    case motion = "Motion"
    case layout = "Layout"

    var id: String { rawValue }

    func variantTitle(for variant: VariantLabMenuVariant) -> String {
        switch (self, variant) {
        case (.timerRing, .variantA): return "Hero Ring"
        case (.timerRing, .variantB): return "Rail Ring"
        case (.timerRing, .variantC): return "Stage Ring"
        case (.buttons, .variantA): return "Floating CTA"
        case (.buttons, .variantB): return "Utility Buttons"
        case (.buttons, .variantC): return "Quiet Controls"
        case (.effects, .variantA): return "Glow Glass"
        case (.effects, .variantB): return "Frosted Plate"
        case (.effects, .variantC): return "Edge Glass"
        case (.motion, .variantA): return "Pulse Motion"
        case (.motion, .variantB): return "Rail Motion"
        case (.motion, .variantC): return "Drift Motion"
        case (.layout, .variantA): return "Floating Slider"
        case (.layout, .variantB): return "Balanced Rail"
        case (.layout, .variantC): return "Compact Stack"
        }
    }

    func variantSubtitle(for variant: VariantLabMenuVariant) -> String {
        switch (self, variant) {
        case (.timerRing, .variantA): return "Thicker expressive countdown ring"
        case (.timerRing, .variantB): return "Balanced ring with meter lane"
        case (.timerRing, .variantC): return "Thin premium ring with calm center"
        case (.buttons, .variantA): return "Prominent one-tap focus call-to-action"
        case (.buttons, .variantB): return "Clear utility hierarchy for frequent actions"
        case (.buttons, .variantC): return "Minimal labels with low visual noise"
        case (.effects, .variantA): return "Soft inner glow and depth highlights"
        case (.effects, .variantB): return "Neutral frosted material with less tint"
        case (.effects, .variantC): return "Clean glass edge treatment with low chroma"
        case (.motion, .variantA): return "Spring-forward pulse on interaction"
        case (.motion, .variantB): return "Structured horizontal motion response"
        case (.motion, .variantC): return "Subtle drift and breathing transitions"
        case (.layout, .variantA): return "Loose popover stack with a floating slider rail"
        case (.layout, .variantB): return "Balanced split layout with centered controls"
        case (.layout, .variantC): return "Compact layout with tighter spacing and denser controls"
        }
    }

    var icon: String {
        switch self {
        case .timerRing: return "timer"
        case .buttons: return "rectangle.portrait.on.rectangle.portrait.angled"
        case .effects: return "drop.degreesign.fill"
        case .motion: return "waveform.path"
        case .layout: return "rectangle.3.group"
        }
    }

    var subtitle: String {
        switch self {
        case .timerRing:
            return "Countdown ring, label rhythm, and glow"
        case .buttons:
            return "CTA hierarchy, hit area, and quiet premium chrome"
        case .effects:
            return "Glass opacity, border, highlight, and depth"
        case .motion:
            return "Spring response, damping, and interaction feel"
        case .layout:
            return "Menu slider placement, spacing, and control shapes"
        }
    }

    var checklistItems: [String] {
        switch self {
        case .timerRing:
            return [
                "Is the number dominant without feeling oversized?",
                "Is the ring thickness visually balanced?",
                "Does the label sit calmly under the timer?",
                "Does the glow support the state without shouting?"
            ]
        case .buttons:
            return [
                "Is the primary action obvious in the first second?",
                "Do button heights feel easy to tap and elegant?",
                "Do the secondary actions stay quiet?",
                "Does the control rail align with the rest of the UI?"
            ]
        case .effects:
            return [
                "Does the surface read as glass, not tinted plastic?",
                "Is the border thin enough to feel native?",
                "Do highlights stay subtle instead of shiny?",
                "Can the content still read clearly at a glance?"
            ]
        case .motion:
            return [
                "Does press feel immediate, not sticky?",
                "Does release settle smoothly without overshoot?",
                "Do hover and transition share the same rhythm?",
                "Does the animation still feel calm at 1x speed?"
            ]
        case .layout:
            return [
                "Does each layout keep the slider easy to find?",
                "Does the shape stay aligned at compact and wide sizes?",
                "Is the control spacing comfortable without feeling loose?",
                "Does the popover still read as premium glass?"
            ]
        }
    }

    var reviewPrompt: String {
        switch self {
        case .timerRing:
            return "Keep the countdown correct, then refine typography and ring balance."
        case .buttons:
            return "Make the primary action feel premium without adding noise."
        case .effects:
            return "Tune the glass first. Then check whether the content still feels airy."
        case .motion:
            return "Pick the feel of the interaction before you touch the numbers again."
        case .layout:
            return "Compare the same menu slider in different shapes before you freeze the layout."
        }
    }
}

enum VariantLabScenario: String, CaseIterable, Identifiable, Codable {
    case idle
    case running
    case paused
    case overtime
    case sessionComplete

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Running"
        case .paused: return "Paused"
        case .overtime: return "Overtime"
        case .sessionComplete: return "Session Complete"
        }
    }

    func snapshot(transitionStep: Int) -> VariantLabScenarioSnapshot {
        let loopedStep = transitionStep % 3
        switch self {
        case .idle:
            return VariantLabScenarioSnapshot(
                stateLabel: ["Ready", "Plan", "Prime"][loopedStep],
                timerText: "25:00",
                projectName: "No Project",
                projectIcon: "scope",
                chips: [
                    VariantLabChip(title: "Focus", tone: .white.opacity(0.12)),
                    VariantLabChip(title: "No blockers", tone: .white.opacity(0.10))
                ],
                primaryAction: "Start Focus",
                secondaryAction: "Setup",
                footer: "No sessions yet today",
                progress: 0.0,
                highlight: .white.opacity(0.95)
            )
        case .running:
            return VariantLabScenarioSnapshot(
                stateLabel: ["In Flow", "Deep Work", "Momentum"][loopedStep],
                timerText: "12:41",
                projectName: "FocusFlow Premium UI",
                projectIcon: "sparkles.rectangle.stack",
                chips: [
                    VariantLabChip(title: "Blocking Active", tone: .white.opacity(0.14)),
                    VariantLabChip(title: "Session 2/4", tone: .white.opacity(0.11))
                ],
                primaryAction: "Pause",
                secondaryAction: "Stop",
                footer: "2 sessions \u{00B7} 47m focused",
                progress: 0.49,
                highlight: .white.opacity(0.92)
            )
        case .paused:
            return VariantLabScenarioSnapshot(
                stateLabel: ["Paused", "Hold", "Interrupted"][loopedStep],
                timerText: "12:41",
                projectName: "FocusFlow Premium UI",
                projectIcon: "pause.circle",
                chips: [
                    VariantLabChip(title: "Paused 2:14", tone: .white.opacity(0.13)),
                    VariantLabChip(title: "Needs decision", tone: .white.opacity(0.10))
                ],
                primaryAction: "Resume",
                secondaryAction: "Discard",
                footer: "Pause timer running",
                progress: 0.49,
                highlight: .white.opacity(0.9)
            )
        case .overtime:
            return VariantLabScenarioSnapshot(
                stateLabel: ["Overtime", "Extra Push", "Finish Strong"][loopedStep],
                timerText: "+7:12",
                projectName: "FocusFlow Premium UI",
                projectIcon: "flame",
                chips: [
                    VariantLabChip(title: "On overtime", tone: .white.opacity(0.13)),
                    VariantLabChip(title: "Session 3/4", tone: .white.opacity(0.10))
                ],
                primaryAction: "Complete",
                secondaryAction: "Add 5m",
                footer: "Stay mindful of fatigue",
                progress: 1.0,
                highlight: .white.opacity(0.9)
            )
        case .sessionComplete:
            return VariantLabScenarioSnapshot(
                stateLabel: ["Completed", "Great Work", "Logged"][loopedStep],
                timerText: "25:00",
                projectName: "FocusFlow Premium UI",
                projectIcon: "checkmark.seal.fill",
                chips: [
                    VariantLabChip(title: "Focus Complete", tone: .white.opacity(0.13)),
                    VariantLabChip(title: "Reflection Ready", tone: .white.opacity(0.10))
                ],
                primaryAction: "Continue",
                secondaryAction: "Take Break",
                footer: "Captured and saved to timeline",
                progress: 1.0,
                highlight: .white.opacity(0.95)
            )
        }
    }
}

struct VariantLabChip: Identifiable {
    let id = UUID()
    let title: String
    let tone: Color
}

struct VariantLabScenarioSnapshot {
    let stateLabel: String
    let timerText: String
    let projectName: String
    let projectIcon: String
    let chips: [VariantLabChip]
    let primaryAction: String
    let secondaryAction: String
    let footer: String
    let progress: Double
    let highlight: Color
}

enum VariantLabMotionSpeed: String, CaseIterable, Identifiable, Codable {
    case x05 = "0.5x"
    case x1 = "1x"
    case x15 = "1.5x"

    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .x05: return 0.5
        case .x1: return 1.0
        case .x15: return 1.5
        }
    }
}

enum VariantLabCriterion: String, CaseIterable, Identifiable, Codable {
    case premiumFeel = "Premium Feel"
    case clarity = "Clarity"
    case calmness = "Calmness"
    case readability = "Readability"
    case delight = "Delight"

    var id: String { rawValue }
}

enum VariantLabDecisionAction: String, CaseIterable, Identifiable, Codable {
    case keep = "Keep"
    case reject = "Reject"
    case needsTweak = "Needs tweak"

    var id: String { rawValue }
}

struct VariantLabInteractionSnapshot: Codable {
    let isExpanded: Bool
    let hoverPreview: Bool
    let pressPreview: Bool
    let transitionStep: Int
}

struct VariantLabDecisionRecord: Codable {
    let timestamp: Date
    let roundName: String
    let scenario: VariantLabScenario
    let component: VariantLabComponent
    let variant: VariantLabMenuVariant
    let motionSpeed: VariantLabMotionSpeed
    let action: VariantLabDecisionAction
    let ratings: [String: Int]
    let notes: String
    let interaction: VariantLabInteractionSnapshot

    var markdownEntry: String {
        let date = ISO8601DateFormatter().string(from: timestamp)
        let sortedRatings = ratings.keys.sorted().map { key in
            "- \(key): \(ratings[key] ?? 0)/5"
        }.joined(separator: "\\n")

        let safeNotes = notes.isEmpty ? "(no notes)" : notes

        return """
        ## \(date) \u{00B7} Round \(roundName)
        - Scenario: \(scenario.displayName)
        - Component: \(component.rawValue)
        - Variant: \(variant.rawValue)
        - Action: \(action.rawValue)
        - Motion: \(motionSpeed.rawValue)
        - Interaction: open=\(interaction.isExpanded), hover=\(interaction.hoverPreview), press=\(interaction.pressPreview), transition=\(interaction.transitionStep)
        \(sortedRatings)
        - Notes: \(safeNotes)

        """
    }
}

func defaultVariantLabRatings() -> [VariantLabCriterion: Int] {
    Dictionary(uniqueKeysWithValues: VariantLabCriterion.allCases.map { ($0, 3) })
}
