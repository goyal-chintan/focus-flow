import SwiftUI

enum CompanionTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case weekly = "Week"
    case projects = "Projects"
    case blocking = "Blocking"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: "sun.max.fill"
        case .weekly: "chart.bar.fill"
        case .projects: "folder.fill"
        case .blocking: "shield.checkered"
        case .settings: "gearshape.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .today: "Daily focus and reflections"
        case .weekly: "Trends across recent days"
        case .projects: "Organize what matters"
        case .blocking: "Guard your attention"
        case .settings: "Tune the experience"
        }
    }
}

struct CompanionWindowView: View {
    @State private var selectedTab: CompanionTab = .today

    var body: some View {
        NavigationSplitView {
            ZStack {
                LinearGradient(
                    colors: [Color.white.opacity(0.1), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: FFSpacing.lg) {
                    PremiumSurface(style: .hero) {
                        HStack(spacing: FFSpacing.md) {
                            ZStack {
                                RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                                    .fill(FFColor.focus.opacity(0.16))

                                Image(systemName: "bolt.circle.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(FFColor.focus)
                            }
                            .frame(width: 52, height: 52)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("FocusFlow")
                                    .font(FFType.title)
                                Text("Premium focus workspace")
                                    .font(FFType.meta)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    VStack(spacing: FFSpacing.xs) {
                        ForEach(CompanionTab.allCases) { tab in
                            sidebarButton(for: tab)
                        }
                    }

                    Spacer()
                }
                .padding(FFSpacing.lg)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 280)
        } detail: {
            ZStack {
                LinearGradient(
                    colors: [Color.white.opacity(0.06), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Group {
                    switch selectedTab {
                    case .today:
                        TodayStatsView()
                    case .weekly:
                        WeeklyStatsView()
                    case .projects:
                        ProjectsListView()
                    case .blocking:
                        BlockingSettingsView()
                    case .settings:
                        SettingsView()
                    }
                }
            }
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            .toolbarBackground(.regularMaterial, for: .windowToolbar)
        }
    }

    private func sidebarButton(for tab: CompanionTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: FFSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous)
                        .fill((selectedTab == tab ? FFColor.focus : .secondary).opacity(selectedTab == tab ? 0.16 : 0.08))

                    Image(systemName: tab.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? FFColor.focus : .secondary)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.rawValue)
                        .font(FFType.callout)
                        .foregroundStyle(.primary)
                    Text(tab.subtitle)
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, FFSpacing.md)
            .padding(.vertical, FFSpacing.sm)
            .background(
                (selectedTab == tab ? Color.white.opacity(0.08) : Color.clear),
                in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                    .strokeBorder(selectedTab == tab ? FFColor.panelBorder : Color.clear)
            }
        }
        .buttonStyle(.plain)
    }
}
