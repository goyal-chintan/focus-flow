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
    @State private var saveError: String?

    init(profile: BlockProfile?) {
        self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
        _websites = State(initialValue: profile?.blockedWebsites ?? [])
        _blockedApps = State(initialValue: profile?.blockedApps ?? [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.large) {
                LiquidSectionHeader(
                    profile == nil ? "New Blocking Profile" : "Edit Profile",
                    subtitle: "Control websites and apps allowed during focus"
                )

                nameSection
                websiteSection
                appSection
                quickFillSection
                actionButtons
            }
            .padding(24)
        }
        .frame(width: 460)
        .frame(minHeight: 620)
        .background(.background)
        .saveErrorOverlay($saveError)
        .onAppear {
            installedApps = AppBlocker.installedApps()
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Name")
            TextField("e.g. Social Media, Full Focus", text: $name)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
        }
    }

    private var websiteSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Blocked Websites")
            websiteAddRow
            websiteList
        }
    }

    private var websiteAddRow: some View {
        HStack(spacing: 8) {
            TextField("domain.com", text: $newWebsite)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
                .onSubmit { addWebsite() }

            Button {
                addWebsite()
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .disabled(newWebsite.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private var websiteList: some View {
        if !websites.isEmpty {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(websites, id: \.self) { site in
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)

                            Text(site)
                                .font(.subheadline)
                                .lineLimit(1)

                            Spacer()

                            Button {
                                websites.removeAll { $0 == site }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                                    .accessibilityLabel("Remove website")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
                    }
                }
            }
            .frame(maxHeight: 160)
        }
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Blocked Apps")
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
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
    }

    @ViewBuilder
    private var blockedAppsList: some View {
        if !blockedApps.isEmpty {
            LazyVStack(spacing: 6) {
                ForEach(blockedApps, id: \.self) { bundleID in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appName(for: bundleID))
                                .font(.subheadline)
                            Text(bundleID)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            blockedApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .accessibilityLabel("Remove app")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
                }
            }
        }
    }

    private var quickFillSection: some View {
        let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]

        return VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Quick Fill")

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                quickFillButton("Social Media") {
                    let social = ["youtube.com", "x.com", "twitter.com", "reddit.com", "instagram.com", "facebook.com", "tiktok.com"]
                    for site in social where !websites.contains(site) {
                        websites.append(site)
                    }
                }

                quickFillButton("Entertainment") {
                    let entertainment = ["netflix.com", "twitch.tv", "disneyplus.com", "hulu.com"]
                    for site in entertainment where !websites.contains(site) {
                        websites.append(site)
                    }
                }

                quickFillButton("News") {
                    let news = ["news.ycombinator.com", "cnn.com", "bbc.com"]
                    for site in news where !websites.contains(site) {
                        websites.append(site)
                    }
                }
            }
        }
    }

    private func quickFillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
    }

    private var actionButtons: some View {
        HStack(spacing: LiquidDesignTokens.Spacing.medium) {
            LiquidActionButton(
                title: "Cancel",
                icon: "xmark",
                role: .secondary
            ) {
                dismiss()
            }

            LiquidActionButton(
                title: "Save",
                icon: "checkmark",
                role: .primary
                ) {
                    save()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

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
        saveWithFeedback(modelContext, errorBinding: $saveError)
    }

    private func appName(for bundleID: String) -> String {
        installedApps.first { $0.bundleID == bundleID }?.name ?? bundleID
    }
}
