import SwiftUI
import SwiftData

struct BlockingSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BlockProfile.createdAt) private var profiles: [BlockProfile]

    @State private var editingProfile: BlockProfile?
    @State private var showNewProfile = false
    @State private var profileToDelete: BlockProfile?
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: LiquidDesignTokens.Spacing.large) {
            header

            if profiles.isEmpty {
                emptyState
            } else {
                profileList
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .saveErrorOverlay($saveError)
        .sheet(isPresented: $showNewProfile) {
            BlockProfileFormView(profile: nil)
        }
        .sheet(item: $editingProfile) { profile in
            BlockProfileFormView(profile: profile)
        }
        .confirmationDialog(
            "Delete Blocking Profile",
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    modelContext.delete(profile)
                    saveWithFeedback(modelContext, errorBinding: $saveError)
                }
                profileToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                profileToDelete = nil
            }
        } message: {
            Text("This will permanently delete the blocking profile and remove it from any linked projects.")
        }
    }

    private var header: some View {
        LiquidSectionHeader("Blocking Profiles", subtitle: "\(profiles.count) profile\(profiles.count == 1 ? "" : "s")") {
            Button {
                showNewProfile = true
            } label: {
                Label("New Profile", systemImage: "plus")
                    .font(LiquidDesignTokens.Typography.controlLabel)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
            .buttonBorderShape(.capsule)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "shield.checkered")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text("No blocking profiles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Create profiles to block distracting\nwebsites and apps during focus sessions.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var profileList: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(profiles) { profile in
                    profileCard(profile)
                }
            }
        }
    }

    private func profileCard(_ profile: BlockProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: icon + name + default badge + actions
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(profile.isDefault ? Color.green.opacity(0.12) : Color.secondary.opacity(0.10))
                        .frame(width: 44, height: 44)
                    Image(systemName: profile.isDefault ? "shield.checkered" : "shield")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(profile.isDefault ? .green : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(profile.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LiquidDesignTokens.Surface.onSurface)

                        if profile.isDefault {
                            Text("DEFAULT")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.0)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.green.opacity(0.12))
                                )
                        }
                    }

                    Text(profileSummary(profile))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Actions
                HStack(spacing: 4) {
                    if !profile.isDefault {
                        Button {
                            setDefault(profile)
                        } label: {
                            Image(systemName: "star")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Set as default")
                    }

                    Button {
                        editingProfile = profile
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit profile")

                    Button {
                        profileToDelete = profile
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(LiquidDesignTokens.Spectral.salmon.opacity(0.6))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete profile")
                }
            }

            // Blocked items preview chips
            if !profile.blockedWebsites.isEmpty || !profile.blockedApps.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(profile.blockedWebsites.prefix(3)), id: \.self) { website in
                        Text(website)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                            )
                    }

                    let remaining = max(0, profile.blockedWebsites.count + profile.blockedApps.count - 3)
                    if remaining > 0 {
                        Text("+\(remaining) more")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func profileSummary(_ profile: BlockProfile) -> String {
        var parts: [String] = []
        let wc = profile.blockedWebsites.count
        let ac = profile.blockedApps.count
        if wc > 0 { parts.append("\(wc) website\(wc == 1 ? "" : "s")") }
        if ac > 0 { parts.append("\(ac) app\(ac == 1 ? "" : "s")") }
        if parts.isEmpty { return "No blocks configured" }
        return parts.joined(separator: " · ")
    }

    private func setDefault(_ profile: BlockProfile) {
        for existing in profiles {
            existing.isDefault = false
        }
        profile.isDefault = true
        saveWithFeedback(modelContext, errorBinding: $saveError)
    }
}
