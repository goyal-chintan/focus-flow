import SwiftUI

enum CompanionTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case calendar = "Calendar"
    case weekly = "Week"
    case insights = "Insights"
    case projects = "Projects"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: "sun.max.fill"
        case .calendar: "calendar"
        case .weekly: "chart.bar.fill"
        case .insights: "brain.head.profile"
        case .projects: "folder.fill"
        case .settings: "gearshape.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .today: "Daily progress"
        case .calendar: "Session history"
        case .weekly: "Trends and history"
        case .insights: "Patterns and tips"
        case .projects: "Manage projects"
        case .settings: "Timer preferences"
        }
    }

    var tint: Color {
        switch self {
        case .today: .blue
        case .calendar: .red
        case .weekly: .purple
        case .insights: .indigo
        case .projects: .mint
        case .settings: .orange
        }
    }
}

struct CompanionWindowView: View {
    @State private var selectedTab: CompanionTab = .today
    @AppStorage("companionRequestedTab") private var requestedTabRaw: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 240)
        } detail: {
            detailContent
                .navigationTitle(selectedTab.rawValue)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
                .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
                .background(windowBackground)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if let tab = CompanionTab(rawValue: requestedTabRaw), tab != .today {
                selectedTab = tab
            }
            requestedTabRaw = ""
        }
        .onChange(of: requestedTabRaw) { _, newValue in
            guard !newValue.isEmpty, let tab = CompanionTab(rawValue: newValue) else { return }
            withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.section) {
                selectedTab = tab
            }
            requestedTabRaw = ""
        }
    }

    private var sidebar: some View {
        List(CompanionTab.allCases, selection: $selectedTab) { tab in
            CompanionSidebarRow(tab: tab, isSelected: selectedTab == tab)
                .tag(tab)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                .listRowBackground(Color.clear)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(windowBackground)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .today:
            TodayStatsView()
        case .calendar:
            CalendarTabView()
        case .weekly:
            WeeklyStatsView()
        case .insights:
            InsightsView()
        case .projects:
            ProjectsListView()
        case .settings:
            SettingsView()
        }
    }

    private var windowBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
    }
}

private struct CompanionSidebarRow: View {
    let tab: CompanionTab
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pillRadius: CGFloat = LiquidDesignTokens.CornerRadius.picker

    var body: some View {
        HStack(spacing: LiquidDesignTokens.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control)
                    .fill(tab.tint.opacity(isSelected ? 0.22 : 0.1))
                    .frame(width: 30, height: 30)

                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? tab.tint : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.rawValue)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                Text(tab.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
                .fill(isSelected ? tab.tint.opacity(0.12) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
                        .stroke(isSelected ? tab.tint.opacity(0.26) : .clear, lineWidth: 1)
                )
                .shadow(color: isSelected ? tab.tint.opacity(0.15) : .clear, radius: 6, y: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: pillRadius))
        .animation(reduceMotion ? nil : FFMotion.control, value: isSelected)
    }
}
