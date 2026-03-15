import SwiftUI
import SwiftData

struct BlockingSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BlockProfile.createdAt) private var profiles: [BlockProfile]
    @State private var editingProfile: BlockProfile?
    @State private var showNewProfile = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if profiles.isEmpty {
                emptyState
            } else {
                profileList
            }
        }
        .background(.background)
        .sheet(isPresented: $showNewProfile) {
            BlockProfileFormView(profile: nil)
        }
        .sheet(item: $editingProfile) { profile in
            BlockProfileFormView(profile: profile)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Blocking Profiles")
                    .font(.title2.weight(.bold))
                Text("\(profiles.count) profiles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showNewProfile = true
            } label: {
                Label("New Profile", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
        }
        .padding(24)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No blocking profiles")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Create profiles to block distracting websites and apps during focus sessions")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var profileList: some View {
        List {
            ForEach(profiles) { profile in
                profileRow(profile)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func profileRow(_ profile: BlockProfile) -> some View {
        HStack(spacing: 14) {
            profileIcon(profile)
            profileInfo(profile)
            Spacer()
            profileActions(profile)
        }
        .padding(.vertical, 4)
    }

    private func profileIcon(_ profile: BlockProfile) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(profile.isDefault ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.1))
                .frame(width: 40, height: 40)
            Image(systemName: profile.isDefault ? "shield.checkered" : "shield")
                .foregroundStyle(profile.isDefault ? .blue : .secondary)
                .font(.system(size: 18))
        }
    }

    private func profileInfo(_ profile: BlockProfile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(profile.name)
                    .font(.body.weight(.medium))
                if profile.isDefault {
                    Text("DEFAULT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            Text(profileSummary(profile))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func profileActions(_ profile: BlockProfile) -> some View {
        if !profile.isDefault {
            Button {
                setDefault(profile)
            } label: {
                Image(systemName: "star")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Set as default")
        }

        Button {
            editingProfile = profile
        } label: {
            Image(systemName: "pencil")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Edit profile")

        Button {
            modelContext.delete(profile)
            try? modelContext.save()
        } label: {
            Image(systemName: "trash")
                .foregroundStyle(.red.opacity(0.7))
        }
        .buttonStyle(.plain)
        .help("Delete profile")
    }

    private func profileSummary(_ profile: BlockProfile) -> String {
        var parts: [String] = []
        let wc = profile.blockedWebsites.count
        let ac = profile.blockedApps.count
        if wc > 0 { parts.append("\(wc) website\(wc == 1 ? "" : "s")") }
        if ac > 0 { parts.append("\(ac) app\(ac == 1 ? "" : "s")") }
        if parts.isEmpty { return "No blocks configured" }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func setDefault(_ profile: BlockProfile) {
        for p in profiles { p.isDefault = false }
        profile.isDefault = true
        try? modelContext.save()
    }
}
