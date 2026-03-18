import SwiftUI

@Observable
final class FFDesignLabStore {
    private(set) var variants: [FFDesignVariant] = []
    private(set) var activeVariantId: UUID?
    private(set) var undoStack: [FFDesignTokens] = []
    private(set) var componentDecisions: [ComponentDecision] = []
    private(set) var promotedSnapshots: [PromotedDesignSnapshot] = []
    private let maxUndoSteps = 50

    private let runtimeRootURL: URL
    private let variantsDir: URL
    private let componentDecisionsDir: URL
    private let promotedSnapshotsDir: URL
    private let activeIdFile: URL

    init() {
        runtimeRootURL = DesignLabStorageRoots.runtimeRootURL
        variantsDir = DesignLabStorageRoots.variantsRootURL
        componentDecisionsDir = DesignLabStorageRoots.decisionsRootURL
        promotedSnapshotsDir = DesignLabStorageRoots.snapshotsRootURL
        activeIdFile = runtimeRootURL.appendingPathComponent("active-variant-id.txt")

        ensureDirectoryExists()
        loadAll()
    }

    private func ensureDirectoryExists() {
        guard DesignLabStorageRoots.isFocusFlow2RuntimeStorageURL(runtimeRootURL) else {
            assertionFailure("Design Lab runtime storage escaped FocusFlow2")
            return
        }

        [runtimeRootURL, variantsDir, componentDecisionsDir, promotedSnapshotsDir].forEach { url in
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - CRUD

    func loadAll() {
        ensureDirectoryExists()
        let decoder = Self.makeStableJSONDecoder()

        variants = loadCodableFiles(from: variantsDir, decoder: decoder)
            .sorted { $0.modifiedAt > $1.modifiedAt }

        componentDecisions = loadCodableFiles(from: componentDecisionsDir, decoder: decoder)
            .sorted { $0.componentID < $1.componentID }

        promotedSnapshots = loadCodableFiles(from: promotedSnapshotsDir, decoder: decoder)
            .sorted { $0.createdAt > $1.createdAt }

        if let idString = try? String(contentsOf: activeIdFile, encoding: .utf8),
           let id = UUID(uuidString: idString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            activeVariantId = id
        }
    }

    func save(_ variant: FFDesignVariant) {
        var variant = variant
        variant.modifiedAt = Date()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(variant) else { return }

        let file = variantsDir.appendingPathComponent("\(variant.id.uuidString).json")
        let backup = variantsDir.appendingPathComponent("\(variant.id.uuidString).backup.json")

        if FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: file, to: backup)
        }

        try? data.write(to: file, options: .atomic)

        if let idx = variants.firstIndex(where: { $0.id == variant.id }) {
            variants[idx] = variant
        } else {
            variants.insert(variant, at: 0)
        }
    }

    func delete(_ variant: FFDesignVariant) {
        let file = variantsDir.appendingPathComponent("\(variant.id.uuidString).json")
        let backup = variantsDir.appendingPathComponent("\(variant.id.uuidString).backup.json")
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: backup)
        variants.removeAll { $0.id == variant.id }
        if activeVariantId == variant.id {
            activeVariantId = nil
            try? FileManager.default.removeItem(at: activeIdFile)
        }
    }

    // MARK: - Component Decisions

    func componentDecision(for componentID: DesignLabComponentID) -> ComponentDecision? {
        componentDecisions.first { $0.componentID == componentID }
    }

    func saveComponentDecision(_ decision: ComponentDecision) throws {
        if let existing = componentDecision(for: decision.componentID),
           existing.isLocked,
           existing != decision {
            throw DesignLabStorageError.lockedDecisionMutationNotAllowed(decision.componentID.rawValue)
        }

        if (decision.state == .locked || decision.state == .promoted), decision.lockedAt == nil {
            throw DesignLabStorageError.promoteRequiresLockedState(decision.componentID.rawValue)
        }

        if decision.state == .promoted && decision.promotedAt == nil {
            throw DesignLabStorageError.promotedDecisionMissingTimestamp(decision.componentID.rawValue)
        }

        try ensureRuntimeStorageWritable()

        let fileURL = componentDecisionsDir.appendingPathComponent("\(decision.componentID.fileStem).json")
        try Self.stableJSONData(decision).write(to: fileURL, options: .atomic)
        upsertComponentDecision(decision)
    }

    func promote(componentID: DesignLabComponentID, with snapshot: PromotedDesignSnapshot) throws {
        guard let decision = componentDecision(for: componentID) else {
            throw DesignLabStorageError.promoteRequiresLockedState(componentID.rawValue)
        }
        guard decision.isLocked else {
            throw DesignLabStorageError.promoteRequiresLockedState(componentID.rawValue)
        }

        try savePromotedSnapshot(snapshot)
    }

    func savePromotedSnapshot(_ snapshot: PromotedDesignSnapshot) throws {
        for decision in snapshot.componentDecisions where !decision.isLocked {
            throw DesignLabStorageError.snapshotContainsUnlockedDecision(decision.componentID.rawValue)
        }

        for decision in snapshot.componentDecisions where decision.state == .promoted && decision.promotedAt == nil {
            throw DesignLabStorageError.promotedDecisionMissingTimestamp(decision.componentID.rawValue)
        }

        try ensureRuntimeStorageWritable()

        let fileURL = promotedSnapshotsDir.appendingPathComponent("\(snapshot.snapshotID.uuidString).json")
        try Self.stableJSONData(snapshot).write(to: fileURL, options: .atomic)
        upsertPromotedSnapshot(snapshot)
    }

    // MARK: - Active Variant

    func setActive(_ variant: FFDesignVariant, applying tokens: FFDesignTokens) {
        activeVariantId = variant.id
        tokens.apply(from: variant.tokens)
        try? variant.id.uuidString.write(to: activeIdFile, atomically: true, encoding: .utf8)
    }

    func clearActive() {
        activeVariantId = nil
        try? FileManager.default.removeItem(at: activeIdFile)
    }

    // MARK: - Undo

    func pushUndo(_ tokens: FFDesignTokens) {
        undoStack.append(tokens.copy())
        if undoStack.count > maxUndoSteps { undoStack.removeFirst() }
    }

    @discardableResult
    func popUndo(into tokens: FFDesignTokens) -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        tokens.apply(from: previous)
        return true
    }

    // MARK: - Export / Import

    func exportJSON(_ tokens: FFDesignTokens) -> String? {
        guard let data = try? Self.stableJSONData(tokens) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func importJSON(_ jsonString: String) -> FFDesignTokens? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? Self.makeStableJSONDecoder().decode(FFDesignTokens.self, from: data)
    }

    func lockAsDefault(_ tokens: FFDesignTokens) {
        let code = generateSwiftCode(tokens)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    func exportRepositoryArtifacts(
        for snapshot: PromotedDesignSnapshot,
        repoRootURL: URL
    ) throws {
        try exportSnapshotMarkdown(snapshot, repoRootURL: repoRootURL)
        try exportSnapshotJSON(snapshot, repoRootURL: repoRootURL)
        try exportTokenBootstrapJSON(snapshot.tokenSet, repoRootURL: repoRootURL)
        try exportComponentDecisionArtifacts(snapshot.componentDecisions, repoRootURL: repoRootURL)
    }

    func exportComponentDecisionArtifacts(
        _ decision: ComponentDecision,
        repoRootURL: URL
    ) throws {
        let docsRoot = repoRootURL
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("design-lab", isDirectory: true)
        let tokenRoot = repoRootURL
            .appendingPathComponent("design-tokens", isDirectory: true)

        try ensureDirectoryExists(at: docsRoot)
        try ensureDirectoryExists(at: tokenRoot)

        let markdownURL = docsRoot.appendingPathComponent("component-decision-\(decision.componentID.fileStem).md")
        let jsonURL = tokenRoot.appendingPathComponent("component-decision-\(decision.componentID.fileStem).json")
        try makeComponentDecisionMarkdown(decision).write(to: markdownURL, atomically: true, encoding: .utf8)
        try Self.stableJSONData(decision).write(to: jsonURL, options: .atomic)
    }

    func exportComponentDecisionArtifacts(
        _ decisions: [ComponentDecision],
        repoRootURL: URL
    ) throws {
        for decision in decisions.sorted(by: { $0.componentID < $1.componentID }) {
            try exportComponentDecisionArtifacts(decision, repoRootURL: repoRootURL)
        }
    }

    func exportSnapshotMarkdown(
        _ snapshot: PromotedDesignSnapshot,
        repoRootURL: URL
    ) throws {
        let docsRoot = repoRootURL
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("design-lab", isDirectory: true)
        try ensureDirectoryExists(at: docsRoot)

        let markdownURL = docsRoot.appendingPathComponent("promoted-snapshot-\(snapshot.snapshotID.uuidString).md")
        try makePromotedSnapshotMarkdown(snapshot).write(to: markdownURL, atomically: true, encoding: .utf8)
    }

    func exportSnapshotJSON(
        _ snapshot: PromotedDesignSnapshot,
        repoRootURL: URL
    ) throws {
        let tokenRoot = repoRootURL
            .appendingPathComponent("design-tokens", isDirectory: true)
        try ensureDirectoryExists(at: tokenRoot)

        let jsonURL = tokenRoot.appendingPathComponent("promoted-snapshot-\(snapshot.snapshotID.uuidString).json")
        try Self.stableJSONData(snapshot).write(to: jsonURL, options: .atomic)
    }

    func exportTokenBootstrapJSON(
        _ tokens: FFDesignTokens,
        repoRootURL: URL
    ) throws {
        let tokenRoot = repoRootURL
            .appendingPathComponent("design-tokens", isDirectory: true)
        try ensureDirectoryExists(at: tokenRoot)

        let jsonURL = tokenRoot.appendingPathComponent("bootstrap.json")
        try Self.stableJSONData(tokens).write(to: jsonURL, options: .atomic)
    }

    private func generateSwiftCode(_ t: FFDesignTokens) -> String {
        """
        // Generated by Design Lab — paste into DesignSystem.swift to update FF* defaults
        // Spacing
        enum FFSpacing {
            static let xxs: CGFloat = \(t.spacing.xxs)
            static let xs: CGFloat = \(t.spacing.xs)
            static let sm: CGFloat = \(t.spacing.sm)
            static let md: CGFloat = \(t.spacing.md)
            static let lg: CGFloat = \(t.spacing.lg)
            static let xl: CGFloat = \(t.spacing.xl)
        }
        // Radius
        enum FFRadius {
            static let control: CGFloat = \(t.radius.control)
            static let card: CGFloat = \(t.radius.card)
            static let hero: CGFloat = \(t.radius.hero)
        }
        // Sizing
        enum FFSize {
            static let controlMin: CGFloat = \(t.sizing.controlMin)
            static let iconFrame: CGFloat = \(t.sizing.iconFrame)
            static let heroIcon: CGFloat = \(t.sizing.heroIcon)
        }
        // Typography
        enum FFType {
            static let heroTimer = Font.system(size: \(t.ring.timerFontSize), weight: .\(t.ring.timerFontWeight.rawValue), design: .rounded)
            static let heroLabel = Font.system(size: \(t.typography.heroLabelSize), weight: .\(t.typography.heroLabelWeight.rawValue), design: .rounded)
            static let title = Font.system(size: \(t.typography.titleSize), weight: .\(t.typography.titleWeight.rawValue), design: .rounded)
            static let titleLarge = Font.system(size: \(t.typography.titleLargeSize), weight: .\(t.typography.titleLargeWeight.rawValue), design: .rounded)
            static let cardValue = Font.system(size: \(t.typography.cardValueSize), weight: .\(t.typography.cardValueWeight.rawValue), design: .rounded)
            static let body = Font.system(size: \(t.typography.bodySize), weight: .\(t.typography.bodyWeight.rawValue), design: .rounded)
            static let callout = Font.system(size: \(t.typography.calloutSize), weight: .\(t.typography.calloutWeight.rawValue), design: .rounded)
            static let meta = Font.system(size: \(t.typography.metaSize), weight: .\(t.typography.metaWeight.rawValue), design: .rounded)
            static let micro = Font.system(size: \(t.typography.microSize), weight: .\(t.typography.microWeight.rawValue), design: .rounded)
        }
        // Colors
        enum FFColor {
            static let focus = Color.\(t.color.focusToken.rawValue)
            static let success = Color.\(t.color.successToken.rawValue)
            static let warning = Color.\(t.color.warningToken.rawValue)
            static let danger = Color.\(t.color.dangerToken.rawValue)
            static let deepFocus = Color.\(t.color.deepFocusToken.rawValue)
        }
        // Motion
        enum FFMotion {
            static let popover = Animation.spring(response: \(t.motion.popoverResponse), dampingFraction: \(t.motion.popoverDamping))
            static let section = Animation.spring(response: \(t.motion.sectionResponse), dampingFraction: \(t.motion.sectionDamping))
            static let control = Animation.spring(response: \(t.motion.controlResponse), dampingFraction: \(t.motion.controlDamping))
            static let breathing = Animation.easeInOut(duration: \(t.motion.breathingDuration)).repeatForever(autoreverses: true)
        }
        """
    }

    private func ensureRuntimeStorageWritable() throws {
        guard DesignLabStorageRoots.isFocusFlow2RuntimeStorageURL(runtimeRootURL) else {
            throw DesignLabStorageError.invalidStorageRoot(runtimeRootURL.path)
        }
    }

    private func ensureDirectoryExists(at url: URL) throws {
        guard DesignLabStorageRoots.isDescendant(url, of: DesignLabStorageRoots.focusFlow2RootURL) ||
                DesignLabStorageRoots.isDescendant(url, of: FileManager.default.temporaryDirectory) ||
                url.path.contains("/docs/design-lab") ||
                url.path.contains("/design-tokens") else {
            throw DesignLabStorageError.invalidStorageRoot(url.path)
        }

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func loadCodableFiles<T: Decodable>(from directory: URL, decoder: JSONDecoder) -> [T] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix(".backup.json") }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(T.self, from: data)
            }
    }

    private func upsertComponentDecision(_ decision: ComponentDecision) {
        if let index = componentDecisions.firstIndex(where: { $0.componentID == decision.componentID }) {
            componentDecisions[index] = decision
        } else {
            componentDecisions.append(decision)
        }
        componentDecisions.sort { $0.componentID < $1.componentID }
    }

    private func upsertPromotedSnapshot(_ snapshot: PromotedDesignSnapshot) {
        if let index = promotedSnapshots.firstIndex(where: { $0.snapshotID == snapshot.snapshotID }) {
            promotedSnapshots[index] = snapshot
        } else {
            promotedSnapshots.insert(snapshot, at: 0)
        }
        promotedSnapshots.sort { $0.createdAt > $1.createdAt }
    }

    private func makeComponentDecisionMarkdown(_ decision: ComponentDecision) -> String {
        let formatter = ISO8601DateFormatter()
        let adjustments = decision.tunedOverrides.map { override in
            "- `\(override.tokenPath)` = `\(override.value)`" + (override.note.map { " (\($0))" } ?? "")
        }.joined(separator: "\n")
        let suggestions = decision.suggestionHistory.map { suggestion in
            """
            - `\(suggestion.signalID)` for `\(suggestion.componentID.displayName)` at \(Int((suggestion.confidence * 100).rounded()))%
              - \(suggestion.explanation)
            """
        }.joined(separator: "\n")

        return """
        # Component Decision

        - Component: \(decision.componentID.displayName)
        - State: \(decision.state.displayName)
        - Variant winner: \(decision.variantWinner?.rawValue ?? "none")
        - Version: \(decision.version)
        - Locked at: \(decision.lockedAt.map(formatter.string(from:)) ?? "n/a")
        - Promoted at: \(decision.promotedAt.map(formatter.string(from:)) ?? "n/a")

        ## Notes

        \(decision.notes.isEmpty ? "_No notes captured._" : decision.notes)

        ## Tuned Overrides

        \(adjustments.isEmpty ? "_No overrides captured._" : adjustments)

        ## Guided Fix History

        \(suggestions.isEmpty ? "_No guided fixes recorded._" : suggestions)
        """
    }

    private func makePromotedSnapshotMarkdown(_ snapshot: PromotedDesignSnapshot) -> String {
        let formatter = ISO8601DateFormatter()
        let decisionList = snapshot.componentDecisions
            .sorted { $0.componentID < $1.componentID }
            .map { decision in
                "- \(decision.componentID.displayName): \(decision.state.displayName) via \(decision.variantWinner?.rawValue ?? "none")"
            }
            .joined(separator: "\n")

        let surfaces = snapshot.targetSurfaces
            .map { "- \($0.displayName)" }
            .joined(separator: "\n")

        return """
        # Promoted Design Snapshot

        - Snapshot ID: \(snapshot.snapshotID.uuidString)
        - Created At: \(formatter.string(from: snapshot.createdAt))

        ## Target Surfaces

        \(surfaces)

        ## Component Decisions

        \(decisionList)
        """
    }

    private static func makeStableJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeStableJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func stableJSONData<T: Encodable>(_ value: T) throws -> Data {
        try makeStableJSONEncoder().encode(value)
    }
}
