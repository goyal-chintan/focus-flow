import SwiftUI
import SwiftData

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

/// What the companion's detail shows: a page, one project, or the archived projects.
enum CompanionDestination: Hashable {
    case tab(CompanionTab)
    case project(UUID)
    case archivedProjects

    var tab: CompanionTab {
        switch self {
        case .tab(let tab): tab
        case .project, .archivedProjects: .projects
        }
    }
}

extension CompanionTab {
    /// The pages listed at the top of the sidebar; projects are listed by name below them.
    static let pages: [CompanionTab] = [.today, .goals, .history, .insights]

    /// ⌘1–⌘5, in sidebar order (⌘5 opens your first project).
    var shortcutKey: KeyEquivalent {
        KeyEquivalent(Character("\((Self.allCases.firstIndex(of: self) ?? 0) + 1)"))
    }
}

/// The companion window (structural redesign 2026-10-30): one sidebar holds the pages and, under
/// "Projects", every project, so a project's page has no list of its own beside it.
struct CompanionWindowView: View {
    @State private var selection: CompanionDestination? = .tab(.today)
    @State private var showNewProject = false
    @AppStorage("companionRequestedTab", store: AppIsolation.defaults) private var requestedTabRaw: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(TimerViewModel.self) private var timerVM
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt) private var projects: [Project]

    private var current: CompanionDestination { selection ?? .tab(.today) }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detailContent
                .navigationTitle(title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(FFPalette.windowBackground.ignoresSafeArea())
        }
        .navigationSplitViewStyle(.prominentDetail)
        .background { CompanionTabShortcuts { open($0) } }
        .sheet(isPresented: $showNewProject) {
            ProjectEditorSheet(project: nil) { selection = .project($0.id) }
        }
        // Coach v8 §3.5: the weekly review (Insights button, or the Sunday invite).
        .sheet(isPresented: Binding(get: { timerVM.weeklyReviewRequested }, set: { timerVM.weeklyReviewRequested = $0 })) {
            WeeklyReviewView(now: Date()) { timerVM.weeklyReviewRequested = false }
                .environment(timerVM)
        }
        .onAppear {
            if let tab = CompanionTab.resolve(requestedTabRaw) {
                open(tab)
            }
            requestedTabRaw = ""
        }
        .onChange(of: requestedTabRaw) { _, newValue in
            guard !newValue.isEmpty, let tab = CompanionTab.resolve(newValue) else { return }
            open(tab)
            requestedTabRaw = ""
        }
    }

    private var title: String {
        switch current {
        case .tab(let tab): tab.rawValue
        case .project(let id): projects.first { $0.id == id }?.name ?? "Projects"
        case .archivedProjects: "Archived projects"
        }
    }

    /// Projects opens your #1 (or first) project; with none, the empty Projects page.
    private func open(_ tab: CompanionTab) {
        if tab == .projects, let first = orderedProjects(projects).first {
            selection = .project(first.id)
        } else {
            selection = .tab(tab)
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(CompanionTab.pages) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(CompanionDestination.tab(tab))
                        .help("\(tab.rawValue) (⌘\(String(tab.shortcutKey.character)))")
                }
            }
            ProjectsSidebarSection { showNewProject = true }
        }
        .listStyle(.sidebar)
    }

    /// Destination switches crossfade with a slight upward settle; Reduce Motion keeps the fade only.
    private var detailContent: some View {
        ZStack {
            destination(for: current)
                .id(current)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 8)),
                            removal: .opacity
                        )
                )
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : FFAnimation.page, value: current)
    }

    @ViewBuilder
    private func destination(for destination: CompanionDestination) -> some View {
        switch destination {
        case .tab(.today): TodayView()
        case .tab(.goals): GoalsView()
        case .tab(.history): HistoryView()
        case .tab(.insights): InsightsView()
        case .tab(.projects): ProjectsListView { id in selection = id.map(CompanionDestination.project) ?? .tab(.projects) }
        case .project(let id): ProjectsListView(projectID: id) { id in selection = id.map(CompanionDestination.project) ?? .tab(.projects) }
        case .archivedProjects: ArchivedProjectsView { selection = .project($0) }
        }
    }
}

/// Invisible ⌘1–⌘5 buttons that switch the companion's pages (⌘5: Projects).
private struct CompanionTabShortcuts: View {
    let open: (CompanionTab) -> Void

    var body: some View {
        ZStack {
            ForEach(CompanionTab.allCases) { tab in
                Button(tab.rawValue) { open(tab) }
                    .keyboardShortcut(tab.shortcutKey, modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
