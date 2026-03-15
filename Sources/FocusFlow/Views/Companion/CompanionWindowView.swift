import SwiftUI

enum CompanionTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case weekly = "Week"
    case projects = "Projects"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: "sun.max.fill"
        case .weekly: "chart.bar.fill"
        case .projects: "folder.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct CompanionWindowView: View {
    @State private var selectedTab: CompanionTab = .today

    var body: some View {
        NavigationSplitView {
            List(CompanionTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Group {
                switch selectedTab {
                case .today:
                    TodayStatsView()
                case .weekly:
                    WeeklyStatsView()
                case .projects:
                    ProjectsListView()
                case .settings:
                    SettingsView()
                }
            }
            .navigationTitle(selectedTab.rawValue)
        }
    }
}
