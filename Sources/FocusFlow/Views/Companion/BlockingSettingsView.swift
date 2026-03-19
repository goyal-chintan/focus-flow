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
        .background(.background)
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
        List {
            ForEach(profiles) { profile in
                profileRow(profile)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func profileRow(_ profile: BlockProfile) -> some View {
        LiquidGlassPanel(cornerRadius: LiquidDesignTokens.CornerRadius.control) {
            HStack(spacing: 14) {
                profileIcon(profile)
                profileInfo(profile)
                Spacer()
                profileActions(profile)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
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
                        .font(.system(size: 9, weight: .bold))
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
        HStack(spacing: 6) {
            if !profile.isDefault {
                actionIconButton("star", helpText: "Set as default") {
                    setDefault(profile)
                }
            }

            actionIconButton("pencil", helpText: "Edit profile") {
                editingProfile = profile
            }

            actionIconButton("trash", tint: .red, helpText: "Delete profile") {
                modelContext.delete(profile)
                try? modelContext.save()
            }
        }
    }

    private func actionIconButton(
        _ systemName: String,
        tint: Color = .secondary,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.glass)
        .tint(tint)
        .help(helpText)
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
