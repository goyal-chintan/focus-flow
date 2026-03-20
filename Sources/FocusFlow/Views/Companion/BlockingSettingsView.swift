import SwiftUI
import SwiftData

struct BlockingSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BlockProfile.createdAt) private var profiles: [BlockProfile]

    @State private var editingProfile: BlockProfile?
    @State private var showNewProfile = false

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
        .sheet(isPresented: $showNewProfile) {
            BlockProfileFormView(profile: nil)
        }
        .sheet(item: $editingProfile) { profile in
            BlockProfileFormView(profile: profile)
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
        LiquidGlassPanel {
            VStack(spacing: 14) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No blocking profiles")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Create profiles to block distracting websites and apps during focus sessions.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }

    private var profileList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(profiles) { profile in
                    profileRow(profile)
                }
            }
        }
    }

    private func profileRow(_ profile: BlockProfile) -> some View {
        HStack(spacing: 14) {
            profileIcon(profile)
            profileInfo(profile)
            Spacer()
            profileActions(profile)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func profileIcon(_ profile: BlockProfile) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(profile.isDefault ? Color.blue.opacity(0.18) : Color.secondary.opacity(0.12))
                .frame(width: 40, height: 40)

            Image(systemName: profile.isDefault ? "shield.checkered" : "shield")
                .foregroundStyle(profile.isDefault ? .blue : .secondary)
                .font(.system(size: 17, weight: .semibold))
        }
    }

    private func profileInfo(_ profile: BlockProfile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(profile.name)
                    .font(.body.weight(.medium))

                if profile.isDefault {
                    Text("DEFAULT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                }
            }

            Text(profileSummary(profile))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func profileActions(_ profile: BlockProfile) -> some View {
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
                modelContext.delete(profile)
                try? modelContext.save()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete profile")
        }
        .opacity(0.7)
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
        try? modelContext.save()
    }
}
