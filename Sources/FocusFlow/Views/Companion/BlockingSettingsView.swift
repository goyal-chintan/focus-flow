import SwiftUI
import SwiftData

/// Standalone blocking-profiles list (one grouped Form section).
struct BlockingSettingsView: View {
    var body: some View {
        Form {
            BlockingProfilesSection()
        }
        .formStyle(.grouped)
    }
}

/// "Blocking profiles" Form section, shared with Settings → Distractions. Rows use the same
/// rhythm as distraction rules: colour tile, name, "N apps · M sites", default badge, actions.
struct BlockingProfilesSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \BlockProfile.createdAt, animation: .smooth(duration: 0.25)) private var profiles: [BlockProfile]
    @Query private var projects: [Project]

    @State private var editingProfile: BlockProfile?
    @State private var showNewProfile = false
    @State private var profileToDelete: BlockProfile?
    @State private var saveError: String?

    var body: some View {
        Section {
            if profiles.isEmpty {
                Text("No blocking profiles yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(profiles) { profile in
                profileRow(profile)
                    .transition(.opacity)
            }
        } header: {
            header
        } footer: {
            Text("Rules shape coaching between sessions. Profiles block apps and sites during focus.")
                .foregroundStyle(.secondary)
        }
    }

    // Presentations hang off the always-present header so they exist exactly once.
    private var header: some View {
        HStack {
            Text("Blocking profiles")
            Spacer()
            Button {
                showNewProfile = true
            } label: {
                Label("New Profile…", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .accessibilityLabel("New blocking profile")
        }
        .saveErrorOverlay($saveError)
        .sheet(isPresented: $showNewProfile) {
            BlockProfileFormView(profile: nil)
        }
        .sheet(item: $editingProfile) { profile in
            BlockProfileFormView(profile: profile)
        }
        .confirmationDialog(
            "Delete this blocking profile?",
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                        modelContext.delete(profile)
                    }
                    saveWithFeedback(modelContext, errorBinding: $saveError)
                }
                profileToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                profileToDelete = nil
            }
        } message: {
            Text("It's removed from any linked projects.")
        }
    }

    private func profileRow(_ profile: BlockProfile) -> some View {
        SettingsListRow(title: profile.name, detail: profileSummary(profile)) {
            SettingsSymbolTile(systemName: "shield.fill", tint: tileColor(for: profile))
        } trailing: {
            if profile.isDefault {
                SettingsBadge(text: "Default")
            }
            Button("Edit…") {
                editingProfile = profile
            }
            .accessibilityLabel("Edit \(profile.name)")

            SettingsRowMenu(accessibilityLabel: "More actions for \(profile.name)") {
                Button("Make Default") { setDefault(profile) }
                    .disabled(profile.isDefault)
                Divider()
                Button("Delete…", role: .destructive) {
                    profileToDelete = profile
                }
            }
        }
    }

    /// The first linked project's colour; the accent for the default profile; otherwise grey.
    private func tileColor(for profile: BlockProfile) -> Color {
        if let project = projects.first(where: { project in
            project.effectiveBlockProfiles.contains(where: { $0.id == profile.id })
        }) {
            return settingsProjectColor(project.color)
        }
        return profile.isDefault ? Color.accentColor : Color.gray
    }

    static func summary(apps: Int, sites: Int) -> String {
        if apps == 0 && sites == 0 { return "Nothing blocked yet" }
        let appsText = "\(apps) app\(apps == 1 ? "" : "s")"
        let sitesText = "\(sites) site\(sites == 1 ? "" : "s")"
        return "\(appsText) · \(sitesText)"
    }

    private func profileSummary(_ profile: BlockProfile) -> String {
        Self.summary(apps: profile.blockedApps.count, sites: profile.blockedWebsites.count)
    }

    private func setDefault(_ profile: BlockProfile) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
            for existing in profiles {
                existing.isDefault = false
            }
            profile.isDefault = true
        }
        saveWithFeedback(modelContext, errorBinding: $saveError)
    }
}
