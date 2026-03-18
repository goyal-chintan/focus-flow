import Foundation

enum DesignLabLifecycleState: String, Codable, CaseIterable, Identifiable {
    case draft
    case compared
    case tuned
    case locked
    case promoted

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .compared: return "Compared"
        case .tuned: return "Tuned"
        case .locked: return "Locked"
        case .promoted: return "Promoted"
        }
    }

    var allowsMutation: Bool {
        switch self {
        case .draft, .compared, .tuned:
            return true
        case .locked, .promoted:
            return false
        }
    }

    var canPromote: Bool { self == .locked }
}

enum DesignLabComponentID: String, Codable, CaseIterable, Identifiable, Comparable {
    case material
    case motion
    case timerRing
    case primaryButtons

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .material: return "Material"
        case .motion: return "Motion"
        case .timerRing: return "Timer Ring"
        case .primaryButtons: return "Primary Buttons"
        }
    }

    var fileStem: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .material: return 0
        case .motion: return 1
        case .timerRing: return 2
        case .primaryButtons: return 3
        }
    }

    static func < (lhs: DesignLabComponentID, rhs: DesignLabComponentID) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

enum DesignLabVariantChoice: String, Codable, CaseIterable, Identifiable {
    case a = "A"
    case b = "B"
    case c = "C"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        case .c: return "C"
        }
    }
}

enum DesignLabTargetSurface: String, Codable, CaseIterable, Identifiable {
    case menuBarPopover
    case sessionComplete
    case dashboard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .menuBarPopover: return "Menu Bar Popover"
        case .sessionComplete: return "Session Complete"
        case .dashboard: return "Dashboard"
        }
    }
}

struct DesignLabTokenOverride: Codable, Hashable, Identifiable {
    var tokenPath: String
    var value: String
    var note: String?

    var id: String { tokenPath }

    init(tokenPath: String, value: String, note: String? = nil) {
        self.tokenPath = tokenPath
        self.value = value
        self.note = note
    }

    init(tokenPath: String, numericValue: Double, note: String? = nil) {
        self.init(tokenPath: tokenPath, value: Self.format(numericValue), note: note)
    }

    init(tokenPath: String, booleanValue: Bool, note: String? = nil) {
        self.init(tokenPath: tokenPath, value: booleanValue ? "true" : "false", note: note)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

struct GuidedFixSuggestion: Codable, Hashable, Identifiable {
    var signalID: String
    var componentID: DesignLabComponentID
    var recommendedAdjustments: [DesignLabTokenOverride]
    var confidence: Double
    var explanation: String

    var id: String { signalID }

    init(
        signalID: String,
        componentID: DesignLabComponentID,
        recommendedAdjustments: [DesignLabTokenOverride],
        confidence: Double,
        explanation: String
    ) {
        self.signalID = signalID
        self.componentID = componentID
        self.recommendedAdjustments = recommendedAdjustments.sorted { $0.tokenPath < $1.tokenPath }
        self.confidence = max(0, min(1, confidence))
        self.explanation = explanation
    }
}

struct ComponentDecision: Codable, Hashable, Identifiable {
    var componentID: DesignLabComponentID
    var variantWinner: DesignLabVariantChoice?
    var tunedOverrides: [DesignLabTokenOverride]
    var suggestionHistory: [GuidedFixSuggestion]
    var notes: String
    var state: DesignLabLifecycleState
    var lockedAt: Date?
    var promotedAt: Date?
    var version: Int

    var id: DesignLabComponentID { componentID }

    var isLocked: Bool { state == .locked || state == .promoted }
    var canMutate: Bool { state.allowsMutation }

    init(
        componentID: DesignLabComponentID,
        variantWinner: DesignLabVariantChoice? = nil,
        tunedOverrides: [DesignLabTokenOverride] = [],
        suggestionHistory: [GuidedFixSuggestion] = [],
        notes: String = "",
        state: DesignLabLifecycleState = .draft,
        lockedAt: Date? = nil,
        promotedAt: Date? = nil,
        version: Int = 1
    ) {
        self.componentID = componentID
        self.variantWinner = variantWinner
        self.tunedOverrides = tunedOverrides.sorted { $0.tokenPath < $1.tokenPath }
        self.suggestionHistory = suggestionHistory.sorted { $0.signalID < $1.signalID }
        self.notes = notes
        self.state = state
        self.lockedAt = lockedAt
        self.promotedAt = promotedAt
        self.version = max(1, version)
    }
}

struct PromotedDesignSnapshot: Codable, Identifiable {
    var snapshotID: UUID
    var componentDecisions: [ComponentDecision]
    var tokenSet: FFDesignTokens
    var targetSurfaces: [DesignLabTargetSurface]
    var createdAt: Date

    var id: UUID { snapshotID }

    init(
        snapshotID: UUID = UUID(),
        componentDecisions: [ComponentDecision],
        tokenSet: FFDesignTokens,
        targetSurfaces: [DesignLabTargetSurface],
        createdAt: Date = Date()
    ) {
        self.snapshotID = snapshotID
        self.componentDecisions = componentDecisions.sorted { $0.componentID < $1.componentID }
        self.tokenSet = tokenSet
        self.targetSurfaces = targetSurfaces.sorted { $0.rawValue < $1.rawValue }
        self.createdAt = createdAt
    }
}

enum DesignLabStorageError: Error, LocalizedError, Equatable {
    case invalidStorageRoot(String)
    case lockedDecisionMutationNotAllowed(String)
    case promoteRequiresLockedState(String)
    case promotedDecisionMissingTimestamp(String)
    case snapshotContainsUnlockedDecision(String)

    var errorDescription: String? {
        switch self {
        case .invalidStorageRoot(let root):
            return "Invalid Design Lab storage root: \(root)"
        case .lockedDecisionMutationNotAllowed(let componentID):
            return "Locked component decision cannot be mutated: \(componentID)"
        case .promoteRequiresLockedState(let componentID):
            return "Component decision must be locked before promotion: \(componentID)"
        case .promotedDecisionMissingTimestamp(let componentID):
            return "Promoted component decision requires a promotion timestamp: \(componentID)"
        case .snapshotContainsUnlockedDecision(let componentID):
            return "Promoted snapshot contains an unlocked decision: \(componentID)"
        }
    }
}

enum DesignLabStorageRoots {
    private static let focusFlow2FolderName = "FocusFlow2"
    private static let designLabFolderName = "DesignLab"
    private static let appSupportOverrideEnv = "FOCUSFLOW2_APP_SUPPORT_ROOT"

    static var applicationSupportRootURL: URL {
        if let override = ProcessInfo.processInfo.environment[appSupportOverrideEnv],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    static var focusFlow2RootURL: URL {
        applicationSupportRootURL.appendingPathComponent(focusFlow2FolderName, isDirectory: true)
    }

    static var runtimeRootURL: URL {
        focusFlow2RootURL.appendingPathComponent(designLabFolderName, isDirectory: true)
    }

    static var variantLabRootURL: URL {
        focusFlow2RootURL.appendingPathComponent("VariantLab", isDirectory: true)
    }

    static var variantsRootURL: URL {
        runtimeRootURL.appendingPathComponent("variants", isDirectory: true)
    }

    static var decisionsRootURL: URL {
        runtimeRootURL.appendingPathComponent("component-decisions", isDirectory: true)
    }

    static var snapshotsRootURL: URL {
        runtimeRootURL.appendingPathComponent("promoted-snapshots", isDirectory: true)
    }

    static func isFocusFlow2RuntimeStorageURL(_ url: URL) -> Bool {
        isDescendant(url, of: runtimeRootURL)
    }

    static func isDescendant(_ url: URL, of root: URL) -> Bool {
        let normalizedURL = url.standardizedFileURL.path
        let normalizedRoot = root.standardizedFileURL.path
        return normalizedURL == normalizedRoot || normalizedURL.hasPrefix(normalizedRoot + "/")
    }
}
