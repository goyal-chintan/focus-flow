import SwiftUI
import SwiftData

struct DistractionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allDistractionItems: [IdleDistractionItem]
    @Query private var allSettings: [AppSettings]

    @State private var editorDestination: DistractionEditorDestination?
    @State private var itemToDelete: IdleDistractionItem?
    @State private var saveError: String?
    @State private var installedApps: [(name: String, bundleID: String)] = []
    @State private var isLoadingInstalledApps = false

    private var domainTrackingEnabled: Bool {
        allSettings.first?.coachCollectRawDomains == true
    }

    private var hasActiveWebsiteRules: Bool {
        allDistractionItems.contains { $0.status == .active && $0.targetKind == .website }
    }

    private var suggestionItems: [IdleDistractionItem] {
        allDistractionItems
            .filter {
                $0.status == .pending &&
                $0.evidenceCount >= IdleDistractionCatalog.suggestionEvidenceThreshold
            }
            .sorted { lhs, rhs in
                if lhs.evidenceCount != rhs.evidenceCount {
                    return lhs.evidenceCount > rhs.evidenceCount
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private var activeRules: [IdleDistractionItem] {
        allDistractionItems
            .filter { $0.status == .active }
            .sorted { lhs, rhs in
                if lhs.source != rhs.source {
                    return lhs.source == .manual
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private var allowedRulesCount: Int {
        activeRules.filter { $0.severity == .allowed }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LiquidDesignTokens.Spacing.large) {
                pageHeaderSection

                if !domainTrackingEnabled && hasActiveWebsiteRules {
                    domainTrackingWarningSection
                }

                if suggestionItems.isEmpty && activeRules.isEmpty {
                    emptyStateSection
                } else {
                    if !suggestionItems.isEmpty {
                        suggestionsSection
                    }

                    if !activeRules.isEmpty {
                        activeRulesSection
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.clear)
        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
        .saveErrorOverlay($saveError)
        .sheet(item: $editorDestination) { destination in
            DistractionRuleEditor(
                destination: destination,
                installedApps: installedApps,
                isLoadingInstalledApps: isLoadingInstalledApps,
                loadInstalledAppsIfNeeded: loadInstalledAppsIfNeeded,
                saveError: $saveError
            )
        }
        .confirmationDialog(
            "Delete Rule",
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let itemToDelete {
                    modelContext.delete(itemToDelete)
                    saveWithFeedback(modelContext, errorBinding: $saveError)
                }
                self.itemToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
        } message: {
            Text("This removes the idle distraction rule. Future coaching will stop using it unless FocusFlow learns it again.")
        }
    }

    @MainActor
    private func loadInstalledAppsIfNeeded() async {
        guard installedApps.isEmpty, isLoadingInstalledApps == false else { return }
        isLoadingInstalledApps = true
        defer { isLoadingInstalledApps = false }
        installedApps = await InstalledAppCatalog.loadInstalledApps()
    }

    // Warning shown when website rules exist but coachCollectRawDomains is off (the default).
    // Without domain tracking, browser visits are never resolved to a host, so website rules
    // cannot match and alerts will not fire.
    private var domainTrackingWarningSection: some View {
        LiquidGlassPanel {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LiquidDesignTokens.Spectral.amberDark)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Website rules won't fire")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)

                    Text("Browser domain tracking is off. Enable it in Settings → Coach → \"Collect raw browser domains\" for your website rules to trigger idle alerts.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
        }
    }

    private var pageHeaderSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.large) {
                LiquidSectionHeader(
                    "Distractions",
                    subtitle: "Idle coaching rules for outside-session recovery."
                ) {
                    quickAddButton
                }

                Text("These rules affect idle and outside-session coaching globally. Focus-session blocking profiles stay under Projects.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: LiquidDesignTokens.Spacing.medium) {
                    summaryMetricTile(
                        title: "Active",
                        value: activeRules.count,
                        caption: "live rules",
                        accent: LiquidDesignTokens.Spectral.destructive
                    )
                    summaryMetricTile(
                        title: "Pending",
                        value: suggestionItems.count,
                        caption: "waiting review",
                        accent: LiquidDesignTokens.Spectral.amberDark
                    )
                    summaryMetricTile(
                        title: "Allowed",
                        value: allowedRulesCount,
                        caption: "safe exceptions",
                        accent: LiquidDesignTokens.Spectral.mintDark
                    )
                }
            }
            .padding(18)
        }
    }

    private var quickAddButton: some View {
        LiquidActionButton(
            title: "Add Rule",
            icon: "plus",
            role: .secondary,
            fillsWidth: false
        ) {
            editorDestination = DistractionEditorDestination(kind: .addManual, item: nil)
        }
        .accessibilityLabel("Add distraction rule")
    }

    private var suggestionsSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.medium) {
                LiquidSectionHeader(
                    "Suggestions",
                    subtitle: "\(suggestionItems.count) pending suggestion\(suggestionItems.count == 1 ? "" : "s")"
                )

                VStack(spacing: 12) {
                    ForEach(suggestionItems) { item in
                        suggestionCard(item)
                    }
                }
            }
            .padding(18)
        }
    }

    private var activeRulesSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.medium) {
                LiquidSectionHeader(
                    "Active Rules",
                    subtitle: "\(activeRules.count) rule\(activeRules.count == 1 ? "" : "s") currently shaping idle coaching"
                )

                VStack(spacing: 12) {
                    ForEach(activeRules) { item in
                        activeRuleCard(item)
                    }
                }
            }
            .padding(18)
        }
    }

    private var emptyStateSection: some View {
        LiquidGlassPanel(cornerRadius: LiquidDesignTokens.CornerRadius.card) {
            VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.medium) {
                Text("No idle rules yet")
                    .font(LiquidDesignTokens.Typography.headlineLarge)

                Text("Start with a manual rule for something FocusFlow missed, or wait until repeated ignored nudges turn into a suggestion.")
                    .font(LiquidDesignTokens.Typography.bodySmall)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    emptyStateRow(
                        icon: "plus.circle.fill",
                        title: "Quick add",
                        detail: "Create a rule for Ghostty, YouTube, or any app/site you already know becomes idle drift."
                    )
                    emptyStateRow(
                        icon: "sparkles",
                        title: "Learned suggestions",
                        detail: "FocusFlow promotes repeated ignored nudges into reviewable suggestions instead of silently escalating."
                    )
                }
            }
            .padding(18)
        }
    }

    private func summaryMetricTile(title: String, value: Int, caption: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(value)")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(accent)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control, style: .continuous)
                .fill(LiquidDesignTokens.Surface.containerLow)
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control, style: .continuous)
                        .stroke(LiquidDesignTokens.Surface.glassStroke, lineWidth: 0.5)
                )
        )
    }

    private func emptyStateRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LiquidDesignTokens.Spectral.primaryContainer)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func suggestionCard(_ item: IdleDistractionItem) -> some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.medium) {
            HStack(alignment: .top, spacing: 12) {
                targetGlyph(for: item)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    Text(item.key)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        compactBadge(text: item.targetKind.label, systemImage: item.targetKind.systemImage, tint: .secondary)
                        compactBadge(text: "Suggested: \(item.severity.label)", systemImage: item.severity.systemImage, tint: item.severity.tint)
                        compactBadge(
                            text: "\(item.evidenceCount) ignored nudges",
                            systemImage: "bell.slash",
                            tint: LiquidDesignTokens.Spectral.amberDark
                        )
                    }
                }

                Spacer(minLength: 0)
            }

            Text("FocusFlow noticed repeated non-response for this target. Review it before it affects stronger idle coaching.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                LiquidActionButton(
                    title: "Review Suggestion",
                    icon: "checkmark",
                    role: .primary,
                    tint: LiquidDesignTokens.Spectral.amberDark
                ) {
                    editorDestination = DistractionEditorDestination(kind: .reviewSuggestion, item: item)
                }
                .accessibilityLabel("Review suggestion for \(item.displayName)")

                LiquidActionButton(
                    title: "Dismiss",
                    icon: "xmark",
                    role: .secondary
                ) {
                    dismissSuggestion(item)
                }
                .accessibilityLabel("Dismiss suggestion for \(item.displayName)")
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func activeRuleCard(_ item: IdleDistractionItem) -> some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.medium) {
            HStack(alignment: .top, spacing: 12) {
                targetGlyph(for: item)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    Text(item.key)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        compactBadge(text: item.targetKind.label, systemImage: item.targetKind.systemImage, tint: .secondary)
                        compactBadge(text: item.source.label, systemImage: item.source.systemImage, tint: item.source.tint)
                        compactBadge(text: item.severity.label, systemImage: item.severity.systemImage, tint: item.severity.tint)
                        if item.source == .suggested {
                            compactBadge(
                                text: "\(item.evidenceCount) signals",
                                systemImage: "chart.bar.fill",
                                tint: LiquidDesignTokens.Spectral.amberDark
                            )
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Button {
                        editorDestination = DistractionEditorDestination(kind: .editRule, item: item)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit rule")
                    .accessibilityLabel("Edit rule")

                    Button {
                        itemToDelete = item
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete rule")
                    .accessibilityLabel("Delete rule")
                }
            }

            Text(ruleDescription(for: item))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(cardBackground)
    }

    private func targetGlyph(for item: IdleDistractionItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(item.targetKind.tint.opacity(0.14))
                .frame(width: 44, height: 44)

            Image(systemName: item.targetKind.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(item.targetKind.tint)
                .accessibilityHidden(true)
        }
    }

    private func compactBadge(text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(ObsidianGradients.glassPanel())
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(LiquidDesignTokens.Surface.glassStroke, lineWidth: 0.5)
            )
    }

    private func dismissSuggestion(_ item: IdleDistractionItem) {
        item.status = .dismissed
        item.updatedAt = Date()
        saveWithFeedback(modelContext, errorBinding: $saveError)
    }

    private func ruleDescription(for item: IdleDistractionItem) -> String {
        switch item.severity {
        case .allowed:
            return "FocusFlow treats this target as allowed during idle coaching, so it will not contribute to stronger prompts."
        case .minor:
            return "FocusFlow treats this as a nudge-level idle distraction and can use it in gentle outside-session interventions."
        case .major:
            return "FocusFlow treats this as a strong idle distraction and can escalate coaching faster when it appears."
        }
    }
}

private struct DistractionEditorDestination: Identifiable {
    enum Kind {
        case addManual
        case editRule
        case reviewSuggestion
    }

    let id = UUID()
    let kind: Kind
    let item: IdleDistractionItem?
}

private struct DistractionRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let destination: DistractionEditorDestination
    let installedApps: [(name: String, bundleID: String)]
    let isLoadingInstalledApps: Bool
    let loadInstalledAppsIfNeeded: () async -> Void
    @Binding private var saveError: String?

    @State private var targetKind: IdleDistractionTargetKind
    @State private var selectedAppBundleID: String?
    @State private var appSearchText: String
    @State private var websiteInput: String
    @State private var severity: IdleDistractionSeverity

    init(
        destination: DistractionEditorDestination,
        installedApps: [(name: String, bundleID: String)],
        isLoadingInstalledApps: Bool,
        loadInstalledAppsIfNeeded: @escaping () async -> Void,
        saveError: Binding<String?>
    ) {
        self.destination = destination
        self.installedApps = installedApps
        self.isLoadingInstalledApps = isLoadingInstalledApps
        self.loadInstalledAppsIfNeeded = loadInstalledAppsIfNeeded
        self._saveError = saveError

        let initialItem = destination.item
        let initialTargetKind = initialItem?.targetKind ?? .app
        _targetKind = State(initialValue: initialTargetKind)
        _selectedAppBundleID = State(initialValue: initialTargetKind == .app ? initialItem?.key : nil)
        _appSearchText = State(initialValue: "")
        _websiteInput = State(initialValue: initialTargetKind == .website ? (initialItem?.key ?? "") : "")
        _severity = State(initialValue: initialItem?.severity ?? .minor)
    }

    private var editorTitle: String {
        switch destination.kind {
        case .addManual:
            return "Add Distraction"
        case .editRule:
            return "Edit Rule"
        case .reviewSuggestion:
            return "Review Suggestion"
        }
    }

    private var editorSubtitle: String {
        switch destination.kind {
        case .addManual:
            return "Create a manual rule for an app or website."
        case .editRule:
            return "Adjust how idle coaching should treat this target."
        case .reviewSuggestion:
            return "Decide whether this learned pattern should stay allowed, nudge-level, or strong."
        }
    }

    private var filteredApps: [(name: String, bundleID: String)] {
        let normalizedQuery = appSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseApps = mergedInstalledApps()
        guard !normalizedQuery.isEmpty else {
            return Array(baseApps.prefix(8))
        }

        return baseApps.filter {
            $0.name.localizedCaseInsensitiveContains(normalizedQuery)
                || $0.bundleID.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    private var canSave: Bool {
        switch targetKind {
        case .app:
            return selectedAppBundleID != nil
        case .website:
            return !websiteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var primaryActionTitle: String {
        destination.kind == .reviewSuggestion ? "Activate Rule" : "Save Rule"
    }

    private var selectedApp: (name: String, bundleID: String)? {
        guard let selectedAppBundleID else { return nil }
        return mergedInstalledApps().first(where: { $0.bundleID == selectedAppBundleID })
    }

    private var hasWebsiteInput: Bool {
        !websiteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var editorWidth: CGFloat {
        destination.kind == .reviewSuggestion ? 420 : 400
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.large) {
                LiquidSectionHeader(editorTitle, subtitle: editorSubtitle)

                targetTypeSection

                switch targetKind {
                case .app:
                    appSelectionSection
                case .website:
                    websiteSection
                }

                severitySection

                if let item = destination.item, destination.kind == .reviewSuggestion {
                    reviewContextSection(item)
                }

                actionButtons
            }
            .padding(20)
        }
        .frame(minWidth: 380, idealWidth: editorWidth, maxWidth: editorWidth, alignment: .topLeading)
        .background(LiquidDesignTokens.Surface.background)
        .saveErrorOverlay($saveError)
        .task(id: targetKind) {
            guard targetKind == .app else { return }
            await loadInstalledAppsIfNeeded()
        }
    }

    private var targetTypeSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Target Type")

            HStack(spacing: 10) {
                targetKindButton(.app)
                targetKindButton(.website)
            }
        }
    }

    private var appSelectionSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            HStack(alignment: .center, spacing: 10) {
                sectionLabel("App")
                Spacer(minLength: 0)
                if selectedApp != nil {
                    inlineUtilityButton("Clear selected app", systemImage: "xmark.circle.fill") {
                        clearSelectedApp()
                    }
                }
            }

            if let selectedApp {
                selectedAppSummary(selectedApp)
            }

            TextField(
                selectedApp == nil ? "Search installed apps" : "Search to replace selected app",
                text: $appSearchText
            )
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .evidenceSafeGlass(cornerRadius: LiquidDesignTokens.CornerRadius.control)

            if isLoadingInstalledApps && installedApps.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading installed apps…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            } else if filteredApps.isEmpty {
                Text("No installed apps match this search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredApps, id: \.bundleID) { app in
                            Button {
                                selectedAppBundleID = app.bundleID
                                appSearchText = ""
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(app.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(app.bundleID)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 0)

                                    if app.bundleID == selectedAppBundleID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(targetKind.tint)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control, style: .continuous)
                                        .fill(app.bundleID == selectedAppBundleID ? LiquidDesignTokens.Surface.containerHigh : LiquidDesignTokens.Surface.containerLow)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control, style: .continuous)
                                                .stroke(
                                                    app.bundleID == selectedAppBundleID ? targetKind.tint.opacity(0.26) : LiquidDesignTokens.Surface.glassStroke,
                                                    lineWidth: 0.5
                                                )
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Select \(app.name)")
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    private var websiteSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            HStack(alignment: .center, spacing: 10) {
                sectionLabel("Website")
                Spacer(minLength: 0)
                if hasWebsiteInput {
                    inlineUtilityButton("Clear website input", systemImage: "xmark.circle.fill") {
                        clearWebsiteInput()
                    }
                }
            }

            TextField("youtube.com or https://youtube.com", text: $websiteInput)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .evidenceSafeGlass(cornerRadius: LiquidDesignTokens.CornerRadius.control)

            Text("Enter a host or URL. FocusFlow normalizes it into one website rule.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var severitySection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Severity")

            HStack(spacing: 10) {
                severityButton(.allowed)
                severityButton(.minor)
                severityButton(.major)
            }
        }
    }

    private func reviewContextSection(_ item: IdleDistractionItem) -> some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Why FocusFlow suggested this")

            VStack(alignment: .leading, spacing: 8) {
                Text("\(item.displayName) crossed the suggestion threshold after \(item.evidenceCount) ignored nudges.")
                Text("Saving here will activate the rule for future idle coaching.")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control, style: .continuous)
                    .fill(LiquidDesignTokens.Surface.containerLow)
                    .overlay(
                        RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control, style: .continuous)
                            .stroke(LiquidDesignTokens.Surface.glassStroke, lineWidth: 0.5)
                    )
            )
        }
    }

    private var actionButtons: some View {
        HStack(spacing: LiquidDesignTokens.Spacing.medium) {
            Spacer(minLength: 0)

            LiquidActionButton(
                title: "Cancel",
                icon: "xmark",
                role: .secondary
            ) {
                dismiss()
            }
            .frame(width: 112)

            LiquidActionButton(
                title: primaryActionTitle,
                icon: "checkmark",
                role: .primary
            ) {
                saveRule()
            }
            .disabled(!canSave)
            .frame(width: destination.kind == .reviewSuggestion ? 156 : 138)
        }
        .padding(.top, 4)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func targetKindButton(_ kind: IdleDistractionTargetKind) -> some View {
        let isSelected = kind == targetKind
        return Button {
            targetKind = kind
        } label: {
            Label(kind.label, systemImage: kind.systemImage)
                .font(LiquidDesignTokens.Typography.controlLabel)
                .foregroundStyle(isSelected ? kind.tint : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .background(
                    RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control, style: .continuous)
                        .fill(isSelected ? LiquidDesignTokens.Surface.containerHigh : LiquidDesignTokens.Surface.containerLow)
                        .overlay(
                            RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control, style: .continuous)
                                .stroke(isSelected ? kind.tint.opacity(0.3) : LiquidDesignTokens.Surface.glassStroke, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose \(kind.label.lowercased()) target type")
    }

    private func severityButton(_ option: IdleDistractionSeverity) -> some View {
        let isSelected = option == severity
        return Button {
            severity = option
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(option.label, systemImage: option.systemImage)
                    .font(LiquidDesignTokens.Typography.controlLabel)
                    .foregroundStyle(isSelected ? option.tint : Color.secondary)
                Text(option.helperText)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.primary.opacity(0.85) : Color.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control, style: .continuous)
                    .fill(isSelected ? LiquidDesignTokens.Surface.containerHigh : LiquidDesignTokens.Surface.containerLow)
                    .overlay(
                        RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control, style: .continuous)
                            .stroke(isSelected ? option.tint.opacity(0.3) : LiquidDesignTokens.Surface.glassStroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set severity to \(option.label)")
    }

    private func mergedInstalledApps() -> [(name: String, bundleID: String)] {
        var apps = installedApps
        if let selectedAppBundleID,
           !apps.contains(where: { $0.bundleID == selectedAppBundleID }) {
            let fallbackName = destination.item?.displayName
                ?? AppUsageEntry.recommendationDisplayLabel(for: "app:\(selectedAppBundleID)")
            apps.insert((name: fallbackName, bundleID: selectedAppBundleID), at: 0)
        }

        return apps.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func selectedAppSummary(_ app: (name: String, bundleID: String)) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(targetKind.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(app.bundleID)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control, style: .continuous)
                .fill(LiquidDesignTokens.Surface.containerLow)
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control, style: .continuous)
                        .stroke(targetKind.tint.opacity(0.18), lineWidth: 0.5)
                )
        )
    }

    private func inlineUtilityButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(LiquidDesignTokens.Typography.controlSmall)
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control, style: .continuous)
                        .fill(LiquidDesignTokens.Surface.containerLow)
                )
        }
        .buttonStyle(.plain)
    }

    private func clearSelectedApp() {
        selectedAppBundleID = nil
        appSearchText = ""
    }

    private func clearWebsiteInput() {
        websiteInput = ""
    }

    private func saveRule() {
        let now = Date()

        let resolvedKey: String
        let resolvedDisplayName: String
        switch targetKind {
        case .app:
            guard let selectedAppBundleID else { return }
            resolvedKey = selectedAppBundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            resolvedDisplayName = mergedInstalledApps()
                .first(where: { $0.bundleID == selectedAppBundleID })?
                .name
                ?? AppUsageEntry.recommendationDisplayLabel(for: "app:\(resolvedKey)")
        case .website:
            let trimmedWebsite = websiteInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedWebsite.isEmpty else { return }
            resolvedKey = AppUsageEntry.normalizedBrowserHost(from: trimmedWebsite)
                ?? trimmedWebsite.lowercased()
            resolvedDisplayName = AppUsageEntry.domainDisplayName(for: resolvedKey)
        }

        do {
            var existingItems = try modelContext.fetch(FetchDescriptor<IdleDistractionItem>())
            let source: IdleDistractionSource
            switch destination.kind {
            case .addManual:
                source = .manual
            case .editRule:
                source = destination.item?.source ?? .manual
            case .reviewSuggestion:
                source = .suggested
            }
            let result = IdleDistractionRuleUpserter.upsert(
                items: &existingItems,
                preferredItem: destination.item,
                targetKind: targetKind,
                key: resolvedKey,
                displayName: resolvedDisplayName,
                severity: severity,
                source: source,
                now: now
            )
            if result.inserted {
                modelContext.insert(result.item)
            }

            try modelContext.save()
            dismiss()
        } catch {
            presentSaveError(error)
        }
    }

    private func presentSaveError(_ error: Error) {
        withAnimation(.spring(response: 0.3)) {
            saveError = "Couldn't save: \(error.localizedDescription)"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation(.spring(response: 0.3)) {
                if saveError != nil {
                    saveError = nil
                }
            }
        }
    }
}

private extension IdleDistractionTargetKind {
    var label: String {
        switch self {
        case .app:
            return "App"
        case .website:
            return "Website"
        }
    }

    var systemImage: String {
        switch self {
        case .app:
            return "app.fill"
        case .website:
            return "globe"
        }
    }

    var tint: Color {
        switch self {
        case .app:
            return LiquidDesignTokens.Spectral.primaryContainer
        case .website:
            return LiquidDesignTokens.Spectral.amberDark
        }
    }
}

private extension IdleDistractionSeverity {
    var label: String {
        switch self {
        case .allowed:
            return "Allowed"
        case .minor:
            return "Nudge"
        case .major:
            return "Strong"
        }
    }

    var helperText: String {
        switch self {
        case .allowed:
            return "Ignore it during idle coaching"
        case .minor:
            return "Use gentle nudges"
        case .major:
            return "Escalate faster"
        }
    }

    var systemImage: String {
        switch self {
        case .allowed:
            return "checkmark.circle.fill"
        case .minor:
            return "bell.fill"
        case .major:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .allowed:
            return LiquidDesignTokens.Spectral.mintDark
        case .minor:
            return LiquidDesignTokens.Spectral.amberDark
        case .major:
            return LiquidDesignTokens.Spectral.destructive
        }
    }
}

private extension IdleDistractionSource {
    var label: String {
        switch self {
        case .manual:
            return "Manual"
        case .suggested:
            return "Learned"
        }
    }

    var systemImage: String {
        switch self {
        case .manual:
            return "slider.horizontal.3"
        case .suggested:
            return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .manual:
            return LiquidDesignTokens.Spectral.primaryContainer
        case .suggested:
            return LiquidDesignTokens.Spectral.amberDark
        }
    }
}
