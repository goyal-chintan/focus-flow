import SwiftUI
import SwiftData

struct BlockProfileFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let profile: BlockProfile?

    @State private var name: String
    @State private var websites: [String]
    @State private var blockedApps: [String]
    @State private var newWebsite: String = ""
    @State private var installedApps: [(name: String, bundleID: String)] = []

    init(profile: BlockProfile?) {
        self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
        _websites = State(initialValue: profile?.blockedWebsites ?? [])
        _blockedApps = State(initialValue: profile?.blockedApps ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(profile == nil ? "New Blocking Profile" : "Edit Profile")
                .font(.title3.weight(.semibold))

            nameSection
            websiteSection
            appSection
            quickFillSection

            Divider()
            actionButtons
        }
        .padding(24)
        .frame(width: 440, height: 580)
        .onAppear {
            installedApps = AppBlocker.installedApps()
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("e.g. Social Media, Full Focus", text: $name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var websiteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Blocked Websites")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            websiteAddRow
            websiteList
        }
    }

    private var websiteAddRow: some View {
        HStack {
            TextField("domain.com", text: $newWebsite)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addWebsite() }
            Button("Add") { addWebsite() }
                .buttonStyle(.glass)
                .disabled(newWebsite.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private var websiteList: some View {
        if !websites.isEmpty {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(websites, id: \.self) { site in
                        HStack {
                            Text(site)
                                .font(.subheadline)
                            Spacer()
                            Button {
                                websites.removeAll { $0 == site }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 120)
        }
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Blocked Apps")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            appPickerMenu
            blockedAppsList
        }
    }

    private var appPickerMenu: some View {
        Menu {
            ForEach(installedApps.filter { app in !blockedApps.contains(app.bundleID) }, id: \.bundleID) { app in
                Button(app.name) {
                    blockedApps.append(app.bundleID)
                }
            }
        } label: {
            Label("Add App", systemImage: "plus.app")
                .font(.subheadline)
        }
        .buttonStyle(.glass)
    }

    @ViewBuilder
    private var blockedAppsList: some View {
        if !blockedApps.isEmpty {
            VStack(spacing: 4) {
                ForEach(blockedApps, id: \.self) { bundleID in
                    HStack {
                        Text(appName(for: bundleID))
                            .font(.subheadline)
                        Text(bundleID)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button {
                            blockedApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var quickFillSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Social Media") {
                    let social = ["youtube.com", "x.com", "twitter.com", "reddit.com", "instagram.com", "facebook.com", "tiktok.com"]
                    for site in social where !websites.contains(site) {
                        websites.append(site)
                    }
                }
                .buttonStyle(.glass)

                Button("Entertainment") {
                    let ent = ["netflix.com", "twitch.tv", "disneyplus.com", "hulu.com"]
                    for site in ent where !websites.contains(site) {
                        websites.append(site)
                    }
                }
                .buttonStyle(.glass)

                Button("News") {
                    let news = ["news.ycombinator.com", "cnn.com", "bbc.com"]
                    for site in news where !websites.contains(site) {
                        websites.append(site)
                    }
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            Button { dismiss() } label: {
                Text("Cancel").frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.glass)

            Button { save(); dismiss() } label: {
                Text("Save").frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Helpers

    private func addWebsite() {
        let site = newWebsite.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
        guard !site.isEmpty, !websites.contains(site) else { return }
        websites.append(site)
        newWebsite = ""
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
        try? modelContext.save()
    }

    private func appName(for bundleID: String) -> String {
        installedApps.first { $0.bundleID == bundleID }?.name ?? bundleID
    }
}
