import SwiftUI
import SwiftData

/// Settings → Distractions: rules, the allowed (work) list and blocking profiles. The coach's
/// suggestions and the "Distraction / It's work" answers live where the time shows: Insights and
/// Today (structural redesign 2026-10-30).
struct DistractionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @Query(animation: .smooth(duration: 0.25)) private var allDistractionItems: [IdleDistractionItem]
    @Query private var allSettings: [AppSettings]
    @AppStorage(SettingsTab.storageKey) private var selectedSettingsTab: SettingsTab = .general

    @State private var editorDestination: DistractionEditorDestination?
    @State private var itemToDelete: IdleDistractionItem?
    @State private var saveError: String?
    @State private var installedApps: [(name: String, bundleID: String)] = []
    @State private var isLoadingInstalledApps = false

    // Website rules only fire when browser domain tracking (coachCollectRawDomains) is on.
    private var domainTrackingEnabled: Bool {
        allSettings.first?.coachCollectRawDomains == true
    }

    private var hasActiveWebsiteRules: Bool {
        allDistractionItems.contains { $0.status == .active && $0.targetKind == .website && $0.severity != .allowed }
    }

    private var suggestionCount: Int {
        DistractionSuggestionsList.pending(allDistractionItems).count
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

    private var distractionRules: [IdleDistractionItem] {
        activeRules.filter { $0.severity != .allowed }
    }

    private var allowedRules: [IdleDistractionItem] {
        activeRules.filter { $0.severity == .allowed }
    }

    var body: some View {
        Form {
            summarySection
            distractionRulesSection
            allowedSection
            BlockingProfilesSection()
        }
        .formStyle(.grouped)
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
            "Delete this rule?",
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let itemToDelete {
                    withAnimation(rowAnimation) {
                        modelContext.delete(itemToDelete)
                    }
                    saveWithFeedback(modelContext, errorBinding: $saveError)
                }
                self.itemToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
        } message: {
            Text("The coach stops using it unless it learns it again.")
        }
    }

    private var rowAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.25)
    }

    @MainActor
    private func loadInstalledAppsIfNeeded() async {
        guard installedApps.isEmpty, isLoadingInstalledApps == false else { return }
        isLoadingInstalledApps = true
        defer { isLoadingInstalledApps = false }
        installedApps = await InstalledAppCatalog.loadInstalledApps()
    }

    // MARK: Summary

    private var summaryLine: String {
        var parts = ["\(distractionRules.count) active"]
        parts.append("\(allowedRules.count) allowed")
        return parts.joined(separator: " · ")
    }

    private var summarySection: some View {
        Section {
            LabeledContent {
                Button {
                    editorDestination = DistractionEditorDestination(kind: .addManual, item: nil)
                } label: {
                    Label("Add Rule…", systemImage: "plus")
                }
                .accessibilityLabel("Add distraction rule")
            } label: {
                Text(summaryLine)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(rowAnimation, value: summaryLine)
                Text(suggestionCount > 0
                     ? "\(suggestionCount) suggestion\(suggestionCount == 1 ? "" : "s") from the coach wait in Insights → What derails me?"
                     : "Mark apps and sites from Today or Insights with Distraction or It's work.")
            }

            if !domainTrackingEnabled && hasActiveWebsiteRules {
                LabeledContent {
                    // Turn it on here; Permissions only holds the macOS approvals it may then ask for.
                    HStack(spacing: 6) {
                        Button("Turn On") {
                            allSettings.first?.coachCollectRawDomains = true
                            saveWithFeedback(modelContext, errorBinding: $saveError)
                        }
                        .keyboardShortcut(.defaultAction)
                        Button("Permissions…") {
                            selectedSettingsTab = .integrations
                            openSettings()
                        }
                    }
                    .fixedSize()
                } label: {
                    Label {
                        Text("Website rules need browser domain tracking.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    // MARK: Rules

    private var distractionRulesSection: some View {
        Section {
            if distractionRules.isEmpty {
                Text("No distraction rules yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(distractionRules) { item in
                SettingsListRow(
                    title: displayName(for: item),
                    detail: detail(for: item, includeEvidence: true)
                ) {
                    targetIcon(for: item)
                } trailing: {
                    Picker("Strength", selection: Binding(
                        get: { item.severity },
                        set: { setSeverity($0, for: item) }
                    )) {
                        Text("Nudge").tag(IdleDistractionSeverity.minor)
                        Text("Strong").tag(IdleDistractionSeverity.major)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityLabel("Strength for \(displayName(for: item))")

                    ruleMenu(for: item)
                }
                .transition(.opacity)
            }
        } header: {
            Text("Distraction rules")
        }
    }

    private var allowedSection: some View {
        Section {
            if allowedRules.isEmpty {
                Text("Nothing marked as work yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(allowedRules) { item in
                SettingsListRow(
                    title: displayName(for: item),
                    detail: detail(for: item, includeEvidence: false)
                ) {
                    targetIcon(for: item)
                } trailing: {
                    ruleMenu(for: item)
                }
                .transition(.opacity)
            }
        } header: {
            Text("Allowed (work)")
        }
    }

    private func ruleMenu(for item: IdleDistractionItem) -> some View {
        SettingsRowMenu(accessibilityLabel: "More actions for \(displayName(for: item))") {
            Button("Edit…") {
                editorDestination = DistractionEditorDestination(kind: .editRule, item: item)
            }
            if item.severity == .allowed {
                Button("Treat as Distraction") { setSeverity(.minor, for: item) }
            } else {
                Button("Mark as Work") { setSeverity(.allowed, for: item) }
            }
            Divider()
            Button("Delete…", role: .destructive) {
                itemToDelete = item
            }
        }
    }

    // MARK: Row content

    private func displayName(for item: IdleDistractionItem) -> String {
        switch item.targetKind {
        case .app:
            return settingsAppDisplayName(forBundleIdentifier: item.key)
        case .website:
            return AppUsageEntry.domainDisplayName(for: item.key)
        }
    }

    private func detail(for item: IdleDistractionItem, includeEvidence: Bool) -> String {
        var parts: [String] = []
        switch item.targetKind {
        case .app:
            parts.append("App")
        case .website:
            // Hosts without a friendly name are already the title; don't repeat them.
            parts.append(displayName(for: item) == item.key ? "Website" : item.key)
        }
        if includeEvidence && item.evidenceCount > 0 {
            parts.append("Ignored \(item.evidenceCount) nudge\(item.evidenceCount == 1 ? "" : "s")")
        } else if item.source == .manual {
            parts.append("Added by you")
        } else {
            parts.append("Learned")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func targetIcon(for item: IdleDistractionItem) -> some View {
        switch item.targetKind {
        case .app:
            SettingsAppIcon(bundleIdentifier: item.key)
        case .website:
            SettingsSymbolTile(systemName: "globe")
        }
    }

    // MARK: Mutations

    private func setSeverity(_ severity: IdleDistractionSeverity, for item: IdleDistractionItem) {
        guard item.severity != severity else { return }
        withAnimation(rowAnimation) {
            item.severity = severity
            item.updatedAt = Date()
        }
        saveWithFeedback(modelContext, errorBinding: $saveError)
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

/// Add/edit sheet: search installed apps or type a website, then pick how to treat it.
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

    private static let visibleAppLimit = 60

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
        case .addManual: "Add Distraction"
        case .editRule: "Edit Rule"
        case .reviewSuggestion: "Review Suggestion"
        }
    }

    private var filteredApps: [(name: String, bundleID: String)] {
        let query = appSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseApps = mergedInstalledApps()
        guard !query.isEmpty else {
            return Array(baseApps.prefix(Self.visibleAppLimit))
        }
        return baseApps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleID.localizedCaseInsensitiveContains(query)
        }
    }

    private var canSave: Bool {
        switch targetKind {
        case .app: selectedAppBundleID != nil
        case .website: hasWebsiteInput
        }
    }

    private var primaryActionTitle: String {
        destination.kind == .addManual ? "Add Rule" : "Save"
    }

    private var hasWebsiteInput: Bool {
        !websiteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Type", selection: $targetKind) {
                        Label("App", systemImage: "app").tag(IdleDistractionTargetKind.app)
                        Label("Website", systemImage: "globe").tag(IdleDistractionTargetKind.website)
                    }
                    .pickerStyle(.segmented)

                    Picker("Treat as", selection: $severity) {
                        Text("Nudge").tag(IdleDistractionSeverity.minor)
                        Text("Strong").tag(IdleDistractionSeverity.major)
                        Text("Work (allowed)").tag(IdleDistractionSeverity.allowed)
                    }
                } header: {
                    Text(editorTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                switch targetKind {
                case .app:
                    appSection
                case .website:
                    websiteSection
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(primaryActionTitle) { saveRule() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 440, height: 540)
        .saveErrorOverlay($saveError)
        .task(id: targetKind) {
            guard targetKind == .app else { return }
            await loadInstalledAppsIfNeeded()
        }
    }

    // MARK: App

    private var appSection: some View {
        Section {
            TextField("Search", text: $appSearchText, prompt: Text("Search installed apps"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()

            if let selectedAppBundleID {
                SettingsListRow(
                    title: settingsAppDisplayName(forBundleIdentifier: selectedAppBundleID),
                    detail: "Selected"
                ) {
                    SettingsAppIcon(bundleIdentifier: selectedAppBundleID)
                } trailing: {
                    Button {
                        self.selectedAppBundleID = nil
                        appSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Clear selected app")
                    .accessibilityLabel("Clear selected app")
                }
            }

            if isLoadingInstalledApps && installedApps.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading installed apps…")
                        .foregroundStyle(.secondary)
                }
            } else if filteredApps.isEmpty {
                Text("No installed apps match “\(appSearchText)”.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredApps, id: \.bundleID) { app in
                    Button {
                        selectedAppBundleID = app.bundleID
                    } label: {
                        HStack(spacing: 10) {
                            SettingsAppIcon(bundleIdentifier: app.bundleID)
                                .frame(width: 18, height: 18)
                            Text(app.name)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if app.bundleID == selectedAppBundleID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select \(app.name)")
                    .accessibilityAddTraits(app.bundleID == selectedAppBundleID ? .isSelected : [])
                }
            }
        } header: {
            Text("App")
        }
    }

    // MARK: Website

    private var websiteSection: some View {
        Section {
            HStack {
                TextField("Website", text: $websiteInput, prompt: Text("youtube.com"))
                    .labelsHidden()
                    .onSubmit { if canSave { saveRule() } }
                if hasWebsiteInput {
                    Button {
                        websiteInput = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear website input")
                    .accessibilityLabel("Clear website input")
                }
            }
        } header: {
            Text("Website")
        } footer: {
            Text("A host or a full URL.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Save

    private func mergedInstalledApps() -> [(name: String, bundleID: String)] {
        var apps = installedApps
        if let selectedAppBundleID,
           !apps.contains(where: { $0.bundleID.caseInsensitiveCompare(selectedAppBundleID) == .orderedSame }) {
            apps.insert((name: settingsAppDisplayName(forBundleIdentifier: selectedAppBundleID), bundleID: selectedAppBundleID), at: 0)
        }
        return apps.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
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
                ?? settingsAppDisplayName(forBundleIdentifier: resolvedKey)
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
                withAnimation(.smooth(duration: 0.25)) {
                    modelContext.insert(result.item)
                }
            }

            try modelContext.save()
            dismiss()
        } catch {
            saveWithFeedback(modelContext, errorBinding: $saveError)
        }
    }
}
