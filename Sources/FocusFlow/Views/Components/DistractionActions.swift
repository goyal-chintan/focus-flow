import SwiftUI
import SwiftData

// "Distraction / It's work" where the time shows (structural redesign 2026-10-30): derailer rows
// in Today and Insights, and the coach's pending suggestions in Insights. Settings → Distractions
// keeps only the rules, the allowed list and blocking profiles.

/// Writes one distraction rule through `IdleDistractionRuleUpserter`, inserting it when new.
@MainActor
enum DistractionRuleWriter {
    static func mark(
        kind: IdleDistractionTargetKind,
        key: String,
        name: String,
        as severity: IdleDistractionSeverity,
        preferred: IdleDistractionItem? = nil,
        source: IdleDistractionSource,
        in context: ModelContext,
        now: Date = Date()
    ) throws {
        var items = try context.fetch(FetchDescriptor<IdleDistractionItem>())
        let result = IdleDistractionRuleUpserter.upsert(
            items: &items,
            preferredItem: preferred,
            targetKind: kind,
            key: key,
            displayName: name,
            severity: severity,
            source: source,
            now: now
        )
        if result.inserted { context.insert(result.item) }
        try context.save()
    }

    static func mark(_ target: DerailerTarget, name: String, as severity: IdleDistractionSeverity, in context: ModelContext) throws {
        try mark(
            kind: target.kind == .website ? .website : .app,
            key: target.key,
            name: name,
            as: severity,
            source: .manual,
            in: context
        )
    }
}

/// The two answers on a derailer row. "It's work" allows it, so the row leaves the list; a row
/// already marked a distraction says so and keeps "It's work" to take it back.
struct DerailerActionButtons: View {
    let name: String
    let target: DerailerTarget?
    let isConfirmed: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let target {
            HStack(spacing: FFSpace.xs) {
                if isConfirmed {
                    Label("Distraction", systemImage: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, FFSpace.s)
                        .frame(minHeight: 30)
                        .help("You marked \(name) a distraction. The coach nudges you off it.")
                } else {
                    Button("Distraction") { mark(target, as: .minor) }
                        .help("Treat \(name) as a distraction: the coach nudges you off it")
                        .accessibilityLabel("Mark \(name) as a distraction")
                }
                Button("It's work") { mark(target, as: .allowed) }
                    .help("\(name) is work: it stops counting here and the coach leaves it alone")
                    .accessibilityLabel("Mark \(name) as work")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
        }
    }

    private func mark(_ target: DerailerTarget, as severity: IdleDistractionSeverity) {
        withAnimation(FFAnimation.gated(FFAnimation.control, reduceMotion: reduceMotion)) {
            try? DistractionRuleWriter.mark(target, name: name, as: severity, in: modelContext)
        }
    }
}

/// The coach's pending suggestions (apps and sites you kept ignoring nudges for), answered in place.
struct DistractionSuggestionsList: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(animation: .smooth(duration: 0.25)) private var allItems: [IdleDistractionItem]
    @State private var confirmDismissAll = false

    /// Pending suggestions with enough evidence, most evidence first.
    static func pending(_ items: [IdleDistractionItem]) -> [IdleDistractionItem] {
        items
            .filter { $0.status == .pending && $0.evidenceCount >= IdleDistractionCatalog.suggestionEvidenceThreshold }
            .sorted { lhs, rhs in
                lhs.evidenceCount != rhs.evidenceCount ? lhs.evidenceCount > rhs.evidenceCount : lhs.updatedAt > rhs.updatedAt
            }
    }

    var body: some View {
        let items = Self.pending(allItems)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: FFSpace.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Label("The coach noticed", systemImage: "sparkles")
                        .ffText(.headline)
                        .labelStyle(.titleAndIcon)
                    Text("You kept ignoring nudges here. Is it a distraction?").ffText(.caption)
                    Spacer(minLength: FFSpace.s)
                    if items.count > 1 {
                        Button("Dismiss all") { confirmDismissAll = true }
                            .buttonStyle(.link)
                            .font(FFTextStyle.caption.font)
                    }
                }
                VStack(spacing: 2) {
                    ForEach(items) { item in
                        row(item)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, -FFSpace.s)
            }
            .accessibilityIdentifier("insights.distractionSuggestions")
            .confirmationDialog("Dismiss all suggestions?", isPresented: $confirmDismissAll, titleVisibility: .visible) {
                Button("Dismiss All", role: .destructive) { dismiss(items) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("FocusFlow will suggest them again only if the pattern returns.")
            }
        }
    }

    private func row(_ item: IdleDistractionItem) -> some View {
        let name = Self.displayName(item)
        return HStack(spacing: FFSpace.m) {
            Image(systemName: item.targetKind == .website ? "globe" : "app")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).ffText(.body).lineLimit(1)
                Text("Ignored \(item.evidenceCount) nudge\(item.evidenceCount == 1 ? "" : "s")")
                    .ffText(.caption)
                    .monospacedDigit()
            }
            Spacer(minLength: FFSpace.s)
            HStack(spacing: FFSpace.xs) {
                Button("Distraction") { accept(item, as: item.severity == .allowed ? .minor : item.severity) }
                    .accessibilityLabel("Mark \(name) as a distraction")
                Button("It's work") { accept(item, as: .allowed) }
                    .accessibilityLabel("Mark \(name) as work")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
            Button {
                dismiss([item])
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss suggestion for \(name)")
        }
        .padding(.horizontal, FFSpace.s)
        .frame(minHeight: 36)
        .ffHoverRow()
    }

    static func displayName(_ item: IdleDistractionItem) -> String {
        switch item.targetKind {
        case .app: settingsAppDisplayName(forBundleIdentifier: item.key)
        case .website: AppUsageEntry.domainDisplayName(for: item.key)
        }
    }

    private func accept(_ item: IdleDistractionItem, as severity: IdleDistractionSeverity) {
        withAnimation(FFAnimation.gated(FFAnimation.control, reduceMotion: reduceMotion)) {
            try? DistractionRuleWriter.mark(
                kind: item.targetKind, key: item.key, name: Self.displayName(item),
                as: severity, preferred: item, source: .suggested, in: modelContext
            )
        }
    }

    private func dismiss(_ items: [IdleDistractionItem]) {
        let now = Date()
        withAnimation(FFAnimation.gated(FFAnimation.control, reduceMotion: reduceMotion)) {
            for item in items {
                item.status = .dismissed
                item.updatedAt = now
            }
        }
        try? modelContext.save()
    }
}
