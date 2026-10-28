import SwiftUI

/// The companion window's destinations (redesign spec §2; Goals: priorities-goals design §3.6).
enum CompanionTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case goals = "Goals"
    case history = "History"
    case insights = "Insights"
    case projects = "Projects"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .goals: "scope"
        case .history: "calendar"
        case .insights: "chart.xyaxis.line"
        case .projects: "folder"
        }
    }

    /// Resolves a `companionRequestedTab` value, including raw values of retired tabs:
    /// Calendar and Week merged into History; Distractions and Settings moved to the Settings scene.
    static func resolve(_ raw: String) -> CompanionTab? {
        if let tab = CompanionTab(rawValue: raw) { return tab }
        switch raw {
        case "Calendar", "Week": return .history
        case "Distractions", "Settings": return .today
        default: return nil
        }
    }
}

struct CompanionWindowView: View {
    @State private var selectedTab: CompanionTab? = .today
    @AppStorage("companionRequestedTab") private var requestedTabRaw: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentTab: CompanionTab { selectedTab ?? .today }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            detailContent
                .navigationTitle(currentTab.rawValue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(FFPalette.windowBackground.ignoresSafeArea())
        }
        .navigationSplitViewStyle(.prominentDetail)
        .onAppear {
            if let tab = CompanionTab.resolve(requestedTabRaw) {
                selectedTab = tab
            }
            requestedTabRaw = ""
        }
        .onChange(of: requestedTabRaw) { _, newValue in
            guard !newValue.isEmpty, let tab = CompanionTab.resolve(newValue) else { return }
            selectedTab = tab
            requestedTabRaw = ""
        }
    }

    private var sidebar: some View {
        List(CompanionTab.allCases, selection: $selectedTab) { tab in
            Label(tab.rawValue, systemImage: tab.icon)
                .tag(tab)
        }
        .listStyle(.sidebar)
    }

    /// Destination switches crossfade with a slight upward settle; Reduce Motion keeps the fade only.
    private var detailContent: some View {
        ZStack {
            destination(for: currentTab)
                .id(currentTab)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 8)),
                            removal: .opacity
                        )
                )
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : FFAnimation.page, value: currentTab)
    }

    @ViewBuilder
    private func destination(for tab: CompanionTab) -> some View {
        switch tab {
        case .today: TodayView()
        case .goals: GoalsView()
        case .history: HistoryView()
        case .insights: InsightsView()
        case .projects: ProjectsListView()
        }
    }
}
