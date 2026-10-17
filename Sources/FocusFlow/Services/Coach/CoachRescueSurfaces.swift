import Foundation

// MARK: - Pause screen content

/// What the pause screen shows (rescue loop design §3.3): a large vetted quote (or the user's
/// own "why"), one honest fact, "Start {N} minutes", and two respectful escapes.
struct CoachPauseScreenPresentation: Identifiable, Equatable, Sendable {
    let id: UUID
    let style: CoachStyle
    /// Quote or why line chosen by the learner; nil falls back to `fallbackLine`.
    let headline: CoachMotivationItem?
    let fallbackLine: String
    /// "47 minutes on YouTube in your 22:00 window". Nil when nothing true can be said.
    let fact: String?
    let starterMinutes: Int
    let attemptID: UUID?
    let level: DriftLevel
    let lateNight: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        style: CoachStyle,
        headline: CoachMotivationItem?,
        fallbackLine: String = CoachOnePercent.compounding,
        fact: String?,
        starterMinutes: Int,
        attemptID: UUID?,
        level: DriftLevel = .spiral,
        lateNight: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.style = style
        self.headline = headline
        self.fallbackLine = fallbackLine
        self.fact = fact
        self.starterMinutes = CoachStarterBlock.clampedMinutes(starterMinutes)
        self.attemptID = attemptID
        self.level = level
        self.lateNight = lateNight
        self.createdAt = createdAt
    }

    var primaryTitle: String { CoachStarterBlock.pauseScreenTitle(minutes: starterMinutes) }
    static let realBreakTitle = "Real break · 15m"
    static let realBreakMinutes = 15
    static let doneTitle = "Done for today"

    /// Small line above the quote.
    var eyebrow: String { lateNight ? "One small thing, then sleep" : "A pause, not a lock" }

    var accessibilityText: String {
        var parts: [String] = []
        switch headline {
        case .quote(let quote) where quote.isHouseLine: parts.append(quote.resolvedText(starterMinutes: starterMinutes))
        case .quote(let quote): parts.append("\(quote.text), \(quote.attribution)")
        case .why(let line): parts.append("Your why: \(line)")
        case nil: parts.append(fallbackLine)
        }
        if let fact { parts.append(fact) }
        return parts.joined(separator: ". ")
    }
}

/// The AppKit host for the pause screen. `TimerViewModel` owns the content.
@MainActor
protocol CoachPauseScreenHosting: AnyObject {
    func showPauseScreen(_ presentation: CoachPauseScreenPresentation)
    func hidePauseScreen()
}

// MARK: - Ambient menu bar counter

/// "YouTube 23m" or "Drift 23m" in the menu bar while drifting in a focus window.
enum CoachDriftCounter {
    static let maxNameLength = 10

    static func text(for drift: DriftAssessment) -> String? {
        guard drift.isActive, drift.level > .ok else { return nil }
        let minutes = drift.ambientMinutes
        let suffix = minutes > 0 ? " \(minutes)m" : ""
        if case .derailer(let name, _) = drift.dominantSignal {
            return "\(shortName(name))\(suffix)"
        }
        return "Drift\(suffix)"
    }

    static func shortName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxNameLength else { return trimmed }
        return String(trimmed.prefix(maxNameLength - 1)) + "…"
    }
}

// MARK: - Global shortcut

/// Registers ⌃⌥Space. Production uses `CoachGlobalHotkey` (Carbon); tests use a fake.
@MainActor
protocol CoachHotkeyRegistering: AnyObject {
    var isRegistered: Bool { get }
    var onPress: (() -> Void)? { get set }
    @discardableResult func register() -> Bool
    func unregister()
}
