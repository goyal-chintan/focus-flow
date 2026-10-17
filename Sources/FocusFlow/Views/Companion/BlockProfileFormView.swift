import SwiftUI
import SwiftData

/// New/edit sheet for a blocking profile, in the same grouped-Form language as Settings.
struct BlockProfileFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let profile: BlockProfile?

    @State private var name: String
    @State private var websites: [String]
    @State private var blockedApps: [String]
    @State private var newWebsite: String = ""
    @State private var installedApps: [(name: String, bundleID: String)] = []
    @State private var saveError: String?

    init(profile: BlockProfile?) {
        self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
        _websites = State(initialValue: profile?.blockedWebsites ?? [])
        _blockedApps = State(initialValue: profile?.blockedApps ?? [])
    }

    private static let quickFills: [(title: String, sites: [String])] = [
        ("Social Media", ["youtube.com", "x.com", "twitter.com", "reddit.com", "instagram.com", "facebook.com", "tiktok.com"]),
        ("Entertainment", ["netflix.com", "twitch.tv", "disneyplus.com", "hulu.com"]),
        ("News", ["news.ycombinator.com", "cnn.com", "bbc.com"])
    ]

    private var rowAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.25)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Deep Work"))
                } header: {
                    Text(profile == nil ? "New Blocking Profile" : "Edit Blocking Profile")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                websitesSection
                appsSection
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 440, height: 560)
        .saveErrorOverlay($saveError)
        .task {
            let apps = await InstalledAppCatalog.loadInstalledApps()
            installedApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    // MARK: Websites

    private var websitesSection: some View {
        Section {
            ForEach(websites, id: \.self) { site in
                SettingsListRow(title: site) {
                    SettingsSymbolTile(systemName: "globe")
                } trailing: {
                    removeButton("Remove \(site)") {
                        withAnimation(rowAnimation) { websites.removeAll { $0 == site } }
                    }
                }
                .transition(.opacity)
            }

            HStack {
                TextField("Add website", text: $newWebsite, prompt: Text("domain.com"))
                    .labelsHidden()
                    .onSubmit(addWebsite)
                Button("Add", action: addWebsite)
                    .disabled(newWebsite.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            HStack {
                Text("Websites")
                Spacer()
                Menu("Quick Fill") {
                    ForEach(Self.quickFills, id: \.title) { fill in
                        Button(fill.title) { addSites(fill.sites) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .controlSize(.small)
            }
        }
    }

    // MARK: Apps

    private var appsSection: some View {
        Section {
            ForEach(blockedApps, id: \.self) { bundleID in
                SettingsListRow(title: appName(for: bundleID)) {
                    SettingsAppIcon(bundleIdentifier: bundleID)
                } trailing: {
                    removeButton("Remove \(appName(for: bundleID))") {
                        withAnimation(rowAnimation) { blockedApps.removeAll { $0 == bundleID } }
                    }
                }
                .transition(.opacity)
            }

            Menu {
                ForEach(installedApps.filter { !blockedApps.contains($0.bundleID) }, id: \.bundleID) { app in
                    Button(app.name) {
                        withAnimation(rowAnimation) { blockedApps.append(app.bundleID) }
                    }
                }
            } label: {
                Label("Add App", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(installedApps.isEmpty)
        } header: {
            Text("Apps")
        }
    }

    private func removeButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: Actions

    private func addWebsite() {
        let site = newWebsite.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
        guard !site.isEmpty, !websites.contains(site) else { return }
        withAnimation(rowAnimation) { websites.append(site) }
        newWebsite = ""
    }

    private func addSites(_ sites: [String]) {
        withAnimation(rowAnimation) {
            for site in sites where !websites.contains(site) {
                websites.append(site)
            }
        }
    }

    private func save() {
        if let profile {
            profile.name = name.trimmingCharacters(in: .whitespaces)
            profile.blockedWebsites = websites
            profile.blockedApps = blockedApps
        } else {
            let newProfile = BlockProfile(
                name: name.trimmingCharacters(in: .whitespaces),
                websites: websites,
                apps: blockedApps
            )
            modelContext.insert(newProfile)
        }
        saveWithFeedback(modelContext, errorBinding: $saveError)
    }

    private func appName(for bundleID: String) -> String {
        if let installed = installedApps.first(where: { $0.bundleID == bundleID }) {
            return installed.name
        }
        return AppDisplayNameResolver.displayName(forBundleIdentifier: bundleID) ?? bundleID
    }
}
