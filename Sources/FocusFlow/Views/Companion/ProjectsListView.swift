import SwiftUI
import SwiftData

// Projects live in the companion window's main sidebar (structural redesign 2026-10-30): one row
// per project under "Projects", no list inside the page. Selecting a row shows `ProjectsListView`
// for that project.

/// Ranked projects first (#1, #2, …), then the rest in creation order.
func orderedProjects(_ projects: [Project]) -> [Project] {
    projects.sorted { lhs, rhs in
        switch (lhs.priorityRank, rhs.priorityRank) {
        case let (l?, r?): return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.createdAt < rhs.createdAt
        }
    }
}

/// The sidebar's "Projects" section: rank, icon, name and this week's time (the header names the period).
struct ProjectsSidebarSection: View {
    let onNewProject: () -> Void

    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt) private var projects: [Project]
    @Query(filter: #Predicate<Project> { $0.archived }) private var archivedProjects: [Project]
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    @Environment(\.companionNowOverride) private var nowOverride

    var body: some View {
        let now = nowOverride ?? Date()
        let analytics = FocusAnalytics()
        let week = analytics.weekInterval(containing: now)
        // Newest first: stop a day before the week, which still catches a block across Monday 00:00.
        let samples = sessions.prefix { $0.startedAt > week.start.addingTimeInterval(-86_400) }
            .filter { $0.type == .focus }
            .map(FocusSample.init)
        let totals = GoalDataBuilder.seconds(samples: samples, in: week)
        Section {
            ForEach(orderedProjects(projects)) { project in
                ProjectSidebarRow(project: project, weekSeconds: totals[GoalDataBuilder.projectKey(project)] ?? 0)
                    .tag(CompanionDestination.project(project.id))
            }
            if !archivedProjects.isEmpty {
                Label("Archived (\(archivedProjects.count))", systemImage: "archivebox")
                    .foregroundStyle(.secondary)
                    .tag(CompanionDestination.archivedProjects)
            }
        } header: {
            HStack(spacing: FFSpace.xs) {
                Text("Projects")
                Spacer(minLength: FFSpace.xs)
                if !projects.isEmpty {
                    Text("this week")
                        .font(.system(size: 10, weight: .regular))
                        .help("The time beside each project is this week's focus on it")
                }
                Button(action: onNewProject) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 30, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New project")
                .accessibilityLabel("New project")
            }
        }
    }
}

private struct ProjectSidebarRow: View {
    let project: Project
    let weekSeconds: TimeInterval

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: project.icon ?? "folder.fill")
                .foregroundStyle(FFPalette.project(project.color))
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(project.name).lineLimit(1)
            if let rank = project.priorityRank {
                // Unranked shows nothing, not a "–" that reads like a remove button.
                Text(rank == 1 ? "★" : "#\(rank)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(rank == 1 ? FFPalette.project(project.color) : .secondary)
                    .help("Priority \(rank)")
            }
            Spacer(minLength: 4)
            // Nothing this week shows nothing, not a "–" that reads like a remove button.
            Text(weekSeconds >= 60 ? FFFormat.compactDuration(weekSeconds) : "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(project.priorityRank.map { "Priority \($0), " } ?? "")\(project.name), \(FFFormat.duration(weekSeconds)) this week")
    }
}

/// Create or edit one project (sidebar "+", a project's Edit button).
struct ProjectEditorSheet: View {
    let project: Project?
    var onSaved: (Project) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(TimerViewModel.self) private var timerVM
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt) private var projects: [Project]
    @State private var draft: ProjectDraft
    @State private var saveError: String?

    init(project: Project?, onSaved: @escaping (Project) -> Void = { _ in }) {
        self.project = project
        self.onSaved = onSaved
        _draft = State(initialValue: project.map(ProjectDraft.init(project:)) ?? ProjectDraft())
    }

    var body: some View {
        ProjectFormView(
            draft: $draft,
            project: project,
            title: project == nil ? "New project" : "Edit project"
        ) {
            let target: Project
            if let project {
                target = project
            } else {
                target = Project(name: "", color: draft.color, icon: draft.icon)
                modelContext.insert(target)
            }
            let previousList = target.reminderListID
            draft.apply(to: target, others: projects, in: modelContext)
            saveWithFeedback(modelContext, errorBinding: $saveError)
            if target.reminderListID != previousList {
                timerVM.reminderListChanged(forProject: target.id)
            }
            timerVM.scheduleReminderSync(after: .zero)
            if project == nil {
                timerVM.selectedProject = target
                timerVM.noteProjectSelected()
            }
            onSaved(target)
        }
        .saveErrorOverlay($saveError)
        .onAppear {
            // The first project becomes #1, so the goal has something to count.
            if project == nil, !projects.contains(where: { $0.priorityRank != nil }) { draft.rank = 1 }
        }
    }
}

/// One project's page: header, stats, today's tasks (with its Reminders list), goals, this week
/// and its blocks. Shows `projectID`, or the
/// first project when none is chosen.
struct ProjectsListView: View {
    var projectID: UUID?
    var onSelectProject: (UUID?) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt)
    private var projects: [Project]
    @Query(sort: \FocusSession.startedAt) private var sessions: [FocusSession]
    @Query private var allSettings: [AppSettings]
    @Query private var tasks: [DailyTask]
    @Environment(\.companionNowOverride) private var nowOverride

    @State private var editor: ProjectEditorTarget?
    @State private var editingSession: FocusSession?
    @State private var projectToArchive: Project?
    @State private var saveError: String?
    @State private var goalSheet: GoalSheet?
    @Query(sort: \ProjectGoal.deadline) private var goals: [ProjectGoal]

    private var selectedProject: Project? {
        projects.first { $0.id == projectID } ?? orderedProjects(projects).first
    }

    var body: some View {
        let snapshot = CompanionSnapshot(sessions: sessions, settings: allSettings.first, projects: projects, now: nowOverride ?? Date())

        Group {
            if let project = selectedProject {
                ScrollView {
                    ProjectDetail(
                        project: project,
                        snapshot: snapshot,
                        sessions: sessions,
                        taskTitles: Dictionary(tasks.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first }),
                        goals: goals.filter { $0.projectID == project.id && $0.status == .active },
                        onEdit: { editor = ProjectEditorTarget(project: project) },
                        onArchive: { projectToArchive = project },
                        onSelectSession: { editingSession = $0 },
                        onAddGoal: { goalSheet = GoalSheet(goal: nil, projectID: project.id) }
                    )
                    .padding(FFSpace.page)
                    .frame(maxWidth: 920, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(project.id)
                    .transition(.opacity)
                }
            } else {
                VStack(alignment: .leading, spacing: FFSpace.sectionGap) {
                    FFPageHeader("Projects") {
                        Button {
                            editor = ProjectEditorTarget(project: nil)
                        } label: {
                            Label("New project", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                    }
                    FFSection {
                        FFEmptyState(
                            systemImage: "folder.badge.plus",
                            message: "No projects yet",
                            detail: "Projects colour your charts, carry daily targets and let you see where the week went. They appear in the sidebar."
                        )
                    }
                    Spacer(minLength: 0)
                }
                .padding(FFSpace.page)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(FFAnimation.gated(FFAnimation.page, reduceMotion: reduceMotion), value: selectedProject?.id)
        .sheet(item: $editor) { target in
            ProjectEditorSheet(project: target.project) { onSelectProject($0.id) }
        }
        .sheet(item: $editingSession) { SessionEditView(session: $0) }
        .sheet(item: $goalSheet) { sheet in GoalFormView(goal: sheet.goal, defaultProjectID: sheet.projectID) }
        .saveErrorOverlay($saveError)
        .confirmationDialog(
            "Archive \(projectToArchive?.name ?? "project")?",
            isPresented: Binding(get: { projectToArchive != nil }, set: { if !$0 { projectToArchive = nil } }),
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) { archive() }
            Button("Cancel", role: .cancel) { projectToArchive = nil }
        } message: {
            Text("It disappears from pickers and charts. Its sessions are kept and you can restore it from Archived in the sidebar.")
        }
    }

    private func archive() {
        guard let project = projectToArchive else { return }
        project.archived = true
        if timerVM.selectedProject?.id == project.id { timerVM.selectedProject = nil }
        saveWithFeedback(modelContext, errorBinding: $saveError)
        onSelectProject(orderedProjects(projects).first { $0.id != project.id }?.id)
        projectToArchive = nil
    }
}

private struct ProjectEditorTarget: Identifiable {
    let id = UUID()
    let project: Project?
}

/// Sidebar → Archived: archived projects, each with Restore.
struct ArchivedProjectsView: View {
    var onRestore: (UUID) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { $0.archived }, sort: \Project.createdAt) private var archivedProjects: [Project]
    @State private var saveError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FFSpace.sectionGap) {
                FFPageHeader("Archived projects", subtitle: "Their blocks are kept. Restore one to see it in pickers and charts again.")
                FFSection {
                    if archivedProjects.isEmpty {
                        FFEmptyState(systemImage: "archivebox", message: "Nothing archived")
                    } else {
                        VStack(spacing: 2) {
                            ForEach(archivedProjects) { project in
                                HStack(spacing: FFSpace.m) {
                                    Image(systemName: project.icon ?? "folder.fill")
                                        .foregroundStyle(FFPalette.project(project.color))
                                        .frame(width: 18)
                                        .accessibilityHidden(true)
                                    Text(project.name).ffText(.body).lineLimit(1)
                                    Spacer()
                                    Button("Restore") { restore(project) }
                                        .buttonStyle(.bordered)
                                }
                                .padding(.horizontal, FFSpace.s)
                                .frame(minHeight: 36)
                                .ffHoverRow()
                            }
                        }
                        .padding(.horizontal, -FFSpace.s)
                    }
                }
            }
            .padding(FFSpace.page)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .saveErrorOverlay($saveError)
    }

    private func restore(_ project: Project) {
        project.archived = false
        saveWithFeedback(modelContext, errorBinding: $saveError)
        onRestore(project.id)
    }
}

/// A goal to create or edit from a project's detail.
struct GoalSheet: Identifiable {
    let id = UUID()
    let goal: ProjectGoal?
    let projectID: UUID?
}

// MARK: - Detail

private struct ProjectDetail: View {
    let project: Project
    let snapshot: CompanionSnapshot
    let sessions: [FocusSession]
    /// Today's and earlier tasks by id, so a block shows the task it was started for.
    var taskTitles: [UUID: String] = [:]
    let goals: [ProjectGoal]
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onSelectSession: (FocusSession) -> Void
    let onAddGoal: () -> Void

    @State private var selectedDay: Date?
    @AppStorage("companionRequestedTab") private var requestedTabRaw: String = ""

    private var key: AnalyticsProjectKey { AnalyticsProjectKey(project: project, customLabel: nil) }
    private var color: Color { FFPalette.project(project.color) }
    private var target: TimeInterval? { project.dailyTargetMinutes.flatMap { $0 > 0 ? TimeInterval($0 * 60) : nil } }

    var body: some View {
        let analytics = snapshot.analytics
        let weekDays = weekDays(analytics)
        let weekSessions = sessions
            .filter { $0.type == .focus && $0.actualDuration >= 60 && $0.effectiveEnd > snapshot.thisWeek.start && $0.startedAt < snapshot.thisWeek.end }
            .filter { session in FocusSample(session).normalisedShares.contains { $0.project == key } }
            .sorted { $0.startedAt > $1.startedAt }

        VStack(alignment: .leading, spacing: FFSpace.sectionGap) {
            header

            statsRow(analytics)

            // Tasks before goals: what to do today is the first question on a project's page, and
            // its Reminders list lives here, not only in the Edit sheet (2026-11-02).
            DailyTasksSection(now: snapshot.now, projectID: project.id)

            goalsSection

            FFSection("This week", subtitle: target.map { "Daily focus on \(project.name) against its \(FFFormat.duration($0)) target" } ?? "Daily focus on \(project.name)") {
                DailyFocusChart(
                    days: weekDays,
                    goal: target ?? snapshot.goal,
                    colors: ProjectColorScale([key]),
                    singleColor: color,
                    showGoal: target != nil,
                    selectedDay: $selectedDay,
                    height: 170
                )
            }

            FFSection("Blocks this week", subtitle: "What each block was for: its intent or task.") {
                if weekSessions.isEmpty {
                    FFEmptyState(systemImage: "tray", message: "No blocks on \(project.name) this week")
                } else {
                    VStack(spacing: 2) {
                        ForEach(weekSessions) { session in
                            SessionRow(session: session, taskTitle: session.taskID.flatMap { taskTitles[$0] }, hidesProject: true) { onSelectSession(session) }
                        }
                    }
                    .padding(.horizontal, -FFSpace.s)
                }
            }
        }
    }

    // MARK: Stats (target-aware)

    private func seconds(on day: FocusAnalytics.DayTotal) -> TimeInterval {
        day.byProject.first { $0.project == key }?.seconds ?? 0
    }

    private func statsRow(_ analytics: FocusAnalytics) -> some View {
        let todaySeconds = seconds(on: analytics.dayTotal(snapshot.samples, on: snapshot.now))
        let todayTarget = project.dailyTarget(on: snapshot.now).map { TimeInterval($0 * 60) }
        // Average over the last 7 days the target applies to (weekdays only when it is weekday-only).
        let last7 = analytics.dailyTotals(snapshot.samples, trailing: 7, endingAt: snapshot.now)
        let counted = target == nil ? last7 : last7.filter { project.dailyTarget(on: $0.day) != nil }
        let average = counted.isEmpty ? 0 : counted.reduce(0) { $0 + seconds(on: $1) } / Double(counted.count)
        let projectSamples = snapshot.samples.filter { sample in sample.normalisedShares.contains { $0.project == key } }
        let allTime = projectSamples.reduce(0) { total, sample in
            total + sample.activeSeconds * (sample.normalisedShares.first { $0.project == key }?.fraction ?? 0)
        }
        let todayCaption: String = if let todayTarget {
            "of \(FFFormat.duration(todayTarget))"
        } else if target != nil {
            "No target today"
        } else {
            "No daily target"
        }
        return HStack(alignment: .top, spacing: FFSpace.l) {
            FFStat(
                label: "Today",
                value: FFFormat.duration(todaySeconds),
                caption: todayCaption,
                valueColor: (todayTarget.map { todaySeconds >= $0 } ?? false) ? FFPalette.goal : nil
            )
            Divider()
            FFStat(
                label: "7-day average",
                value: "\(FFFormat.duration(average))/day",
                caption: target.map { "of \(FFFormat.duration($0))\(project.targetWeekdaysOnly == true ? " on weekdays" : "")" } ?? "Last 7 days"
            )
            Divider()
            FFStat(label: "All time", value: FFFormat.duration(allTime), caption: "\(projectSamples.count) block\(projectSamples.count == 1 ? "" : "s")")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(FFSpace.l)
        .ffSurface()
    }

    // MARK: Goals (compact; the full cards live in the Goals tab)

    private var goalsSection: some View {
        FFSection("Goals") {
            Button(action: onAddGoal) { Label("Add goal", systemImage: "plus") }
                .buttonStyle(.bordered)
        } content: {
            if goals.isEmpty {
                Text("No goal with a deadline yet. Add one (e.g. \"60 LeetCode by 28 Nov\") and the app shows whether you're on pace.")
                    .ffText(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 2) {
                    ForEach(goals) { goal in
                        goalRow(goal)
                    }
                }
                .padding(.horizontal, -FFSpace.s)
            }
        }
    }

    private func goalRow(_ goal: ProjectGoal) -> some View {
        let summary = GoalDataBuilder.summary(goal, now: snapshot.now)
        return HStack(spacing: FFSpace.m) {
            Image(systemName: goal.isBossFight ? "star.fill" : "scope")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(goal.title).ffText(.headline).lineLimit(1)
                Text("\(Int((summary.fraction * 100).rounded()))% done · due \(goal.deadline.formatted(.dateTime.day().month(.abbreviated)))")
                    .ffText(.caption)
                    .monospacedDigit()
            }
            Spacer(minLength: FFSpace.s)
            PaceStatusPill(status: summary.status)
            Button("Open in Goals") { requestedTabRaw = CompanionTab.goals.rawValue }
                .buttonStyle(.link)
                .font(FFTextStyle.callout.font)
        }
        .padding(.horizontal, FFSpace.s)
        .frame(minHeight: 40)
        .ffHoverRow()
        .accessibilityElement(children: .combine)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: FFSpace.m) {
            Image(systemName: project.icon ?? "folder.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(color.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).ffText(.title3).lineLimit(1)
                Text(headerCaption).ffText(.caption).lineLimit(1)
            }
            Spacer(minLength: FFSpace.s)
            Button("Edit", action: onEdit).buttonStyle(.bordered)
            // Archive is rare and hides the project: one step away, not beside Edit.
            Menu {
                Button("Archive…", role: .destructive, action: onArchive)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More project actions")
        }
    }

    /// "#1 · Learning · 4h/day · Interview-ready for a senior data role".
    private var headerCaption: String {
        var parts: [String] = []
        if let rank = project.priorityRank { parts.append("#\(rank)") }
        if project.areaRaw != nil { parts.append(project.area.title) }
        if let target {
            parts.append("\(FFFormat.duration(target))/day\(project.targetWeekdaysOnly == true ? " on weekdays" : "")")
        }
        if let purpose = project.purpose { parts.append(purpose) }
        if parts.isEmpty { return "Not ranked · no daily target" }
        return parts.joined(separator: " · ")
    }

    private func weekDays(_ analytics: FocusAnalytics) -> [FocusAnalytics.DayTotal] {
        let start = snapshot.thisWeek.start
        let days = (0..<7).compactMap { analytics.calendar.date(byAdding: .day, value: $0, to: start) }
        return analytics.dailyTotals(snapshot.samples, days: days).map { day in
            let slice = day.byProject.first { $0.project == key }
            return FocusAnalytics.DayTotal(day: day.day, seconds: slice?.seconds ?? 0, blocks: slice == nil ? 0 : 1, byProject: slice.map { [$0] } ?? [])
        }
    }
}
