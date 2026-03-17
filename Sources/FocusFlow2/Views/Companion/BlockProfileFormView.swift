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
        ScrollView {
            VStack(alignment: .leading, spacing: FFSpacing.lg) {
                PremiumSurface(style: .hero) {
                    PremiumSectionHeader(
                        profile == nil ? "New Blocking Profile" : "Edit Profile",
                        eyebrow: "Blocking",
                        subtitle: "Configure websites and apps to keep distractions out of your focus sessions."
                    )
                }

                PremiumSurface(style: .card) {
                    PremiumSectionHeader("Profile Name", eyebrow: "Basics")
                    nameSection
                }

                PremiumSurface(style: .card) {
                    PremiumSectionHeader("Blocked Websites", eyebrow: "Web", subtitle: "Domain-based blocking during focus sessions.")
                    websiteSection
                }

                PremiumSurface(style: .card) {
                    PremiumSectionHeader("Blocked Apps", eyebrow: "Apps", subtitle: "Quit and keep distracting apps from relaunching.")
                    appSection
                }

                PremiumSurface(style: .card) {
                    PremiumSectionHeader("Quick Fill", eyebrow: "Presets", subtitle: "Seed the list with common distraction clusters.")
                    quickFillSection
                }

                PremiumSurface(style: .card) {
                    PremiumSectionHeader("Save", eyebrow: "Finish")
                    actionButtons
                }
            }
            .padding(FFSpacing.lg)
        }
        .frame(width: 500, height: 720)
        .onAppear {
            installedApps = AppBlocker.installedApps()
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            TextField("e.g. Social Media, Full Focus", text: $name)
                .textFieldStyle(.plain)
                .font(FFType.body)
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.sm)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
        }
    }

    private var websiteSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            websiteAddRow
            websiteList
        }
    }

    private var websiteAddRow: some View {
        HStack(spacing: FFSpacing.sm) {
            TextField("domain.com", text: $newWebsite)
                .textFieldStyle(.plain)
                .font(FFType.body)
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.sm)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
                .onSubmit { addWebsite() }
            Button("Add") { addWebsite() }
                .buttonStyle(.glass)
                .disabled(newWebsite.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private var websiteList: some View {
        if !websites.isEmpty {
            VStack(spacing: FFSpacing.xs) {
                ForEach(websites, id: \.self) { site in
                    HStack {
                        Text(site)
                            .font(FFType.body)
                        Spacer()
                        Button {
                            websites.removeAll { $0 == site }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, FFSpacing.md)
                    .padding(.vertical, FFSpacing.sm)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
                }
            }
        }
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
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
            Label("Add App", systemImage: "plus.app.fill")
                .font(FFType.meta)
        }
        .buttonStyle(.glass)
    }

    @ViewBuilder
    private var blockedAppsList: some View {
        if !blockedApps.isEmpty {
            VStack(spacing: FFSpacing.xs) {
                ForEach(blockedApps, id: \.self) { bundleID in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appName(for: bundleID))
                                .font(FFType.body)
                            Text(bundleID)
                                .font(FFType.micro)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button {
                            blockedApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, FFSpacing.md)
                    .padding(.vertical, FFSpacing.sm)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
                }
            }
        }
    }

    private var quickFillSection: some View {
        HStack(spacing: FFSpacing.sm) {
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

    private var actionButtons: some View {
        HStack(spacing: FFSpacing.sm) {
            Button { dismiss() } label: {
                Text("Cancel").frame(maxWidth: .infinity).padding(.vertical, FFSpacing.sm)
            }
            .buttonStyle(.glass)

            Button { save(); dismiss() } label: {
                Text("Save").frame(maxWidth: .infinity).padding(.vertical, FFSpacing.sm)
            }
            .buttonStyle(.glassProminent)
            .tint(FFColor.focus)
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
