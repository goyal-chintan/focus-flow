import SwiftUI
import SwiftData

/// Projects: master list on the left, this week's time, blocks and outcome mix on the right.
struct ProjectsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt)
    private var projects: [Project]
    @Query(filter: #Predicate<Project> { $0.archived }, sort: \Project.createdAt)
    private var archivedProjects: [Project]
    @Query(sort: \FocusSession.startedAt) private var sessions: [FocusSession]
    @Query private var allSettings: [AppSettings]
    @Environment(\.companionNowOverride) private var nowOverride

    @State private var selectedID: UUID?
    @State private var showingForm = false
    @State private var editingProject: Project?
    @State private var editingSession: FocusSession?
    @State private var projectToArchive: Project?
    @State private var showArchived = false
    @State private var saveError: String?

    @State private var draft = ProjectDraft()
    @State private var goalSheet: GoalSheet?
    @Query(sort: \ProjectGoal.deadline) private var goals: [ProjectGoal]

    /// Ranked projects first (#1, #2, …), then the rest in creation order.
    private var orderedProjects: [Project] {
        projects.sorted { lhs, rhs in
            switch (lhs.priorityRank, rhs.priorityRank) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.createdAt < rhs.createdAt
            }
        }
    }

    private var selectedProject: Project? {
        projects.first { $0.id == selectedID } ?? orderedProjects.first
    }

    var body: some View {
        let snapshot = CompanionSnapshot(sessions: sessions, settings: allSettings.first, projects: projects, now: nowOverride ?? Date())
        let weekTotals = snapshot.analytics.projectTotals(snapshot.samples, in: snapshot.thisWeek)

        VStack(alignment: .leading, spacing: FFSpace.sectionGap) {
            FFPageHeader("Projects", subtitle: projects.isEmpty ? nil : "\(projects.count) active") {
                Button {
                    startCreate()
                } label: {
                    Label("New project", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if projects.isEmpty {
                FFSection {
                    FFEmptyState(
                        systemImage: "folder.badge.plus",
                        message: "No projects yet",
                        detail: "Projects colour your charts and let you see where the week went."
                    )
                }
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .top, spacing: FFSpace.l) {
                    projectList(weekTotals: weekTotals, today: GoalDataBuilder.seconds(samples: snapshot.samples, in: snapshot.today))
                        .frame(width: 260)
                    if let project = selectedProject {
                        ScrollView {
                            ProjectDetail(
                                project: project,
                                snapshot: snapshot,
                                sessions: sessions,
                                goals: goals.filter { $0.projectID == project.id && $0.status == .active },
                                onEdit: { startEdit(project) },
                                onArchive: { projectToArchive = project },
                                onSelectSession: { editingSession = $0 },
                                onAddGoal: { goalSheet = GoalSheet(goal: nil, projectID: project.id) }
                            )
                            .id(project.id)
                            .transition(.opacity)
                        }
                        .scrollIndicators(.automatic)
                    }
                }
                .animation(FFAnimation.gated(FFAnimation.page, reduceMotion: reduceMotion), value: selectedProject?.id)
            }
        }
        .padding(FFSpace.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingForm) { projectForm }
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
            Text("It disappears from pickers and charts. Its sessions are kept and you can restore it below the list.")
        }
    }

    // MARK: - List

    private func projectList(weekTotals: [FocusAnalytics.ProjectTotal], today: [String: TimeInterval]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(orderedProjects) { project in
                let seconds = weekTotals.first { $0.project.projectUUID == project.id }?.seconds ?? 0
                let todaySeconds = today[GoalDataBuilder.projectKey(project)] ?? 0
                let target = project.dailyTarget(on: nowOverride ?? Date()).map { TimeInterval($0 * 60) }
                Button {
                    selectedID = project.id
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: FFSpace.s) {
                            // Unranked shows nothing, not a "–" that reads like a remove button.
                            Text(project.priorityRank.map { "#\($0)" } ?? "")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(project.priorityRank == 1 ? Color.white : .secondary)
                                .frame(width: 24, height: 18)
                                .background(RoundedRectangle(cornerRadius: 5).fill(project.priorityRank == nil ? Color.clear : project.priorityRank == 1 ? FFPalette.project(project.color) : FFPalette.track))
                                .help(project.priorityRank.map { "Priority \($0)" } ?? "No priority")
                            Image(systemName: project.icon ?? "folder.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(FFPalette.project(project.color))
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            Text(project.name).ffText(.body).lineLimit(1)
                            Spacer(minLength: FFSpace.xs)
                            Text(seconds > 0 ? "\(FFFormat.duration(seconds)) this week" : "—")
                                .ffText(.caption)
                                .monospacedDigit()
                                .help("Focus on this project this week")
                        }
                        if let target, target > 0 {
                            PaceBar(fraction: min(1, todaySeconds / target), expected: 0, color: FFPalette.project(project.color), height: 4)
                                .padding(.leading, 56)
                                .help("Today: \(FFFormat.duration(todaySeconds)) of \(FFFormat.duration(target))")
                        }
                    }
                    .padding(.horizontal, FFSpace.s)
                    .padding(.vertical, 6)
                    .ffHoverRow(isSelected: project.id == selectedProject?.id)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(project.priorityRank.map { "Priority \($0), " } ?? "")\(project.name), \(FFFormat.duration(seconds)) this week")
                .accessibilityAddTraits(project.id == selectedProject?.id ? .isSelected : [])
            }

            if !archivedProjects.isEmpty {
                Divider().padding(.vertical, FFSpace.s)
                Button {
                    withAnimation(FFAnimation.gated(FFAnimation.control, reduceMotion: reduceMotion)) { showArchived.toggle() }
                } label: {
                    HStack {
                        Text("Archived (\(archivedProjects.count))").ffText(.callout)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showArchived ? 90 : 0))
                    }
                    .padding(.horizontal, FFSpace.s)
                    .frame(height: 30)
                    .ffHoverRow()
                }
                .buttonStyle(.plain)

                if showArchived {
                    ForEach(archivedProjects) { project in
                        HStack(spacing: FFSpace.s) {
                            Text(project.name).ffText(.callout).lineLimit(1)
                            Spacer()
                            Button("Restore") { restore(project) }
                                .buttonStyle(.link)
                                .font(FFTextStyle.caption.font)
                        }
                        .padding(.horizontal, FFSpace.s)
                        .frame(height: 28)
                    }
                    .transition(.opacity)
                }
            }
        }
        .padding(FFSpace.s - 2)
        .ffSurface()
    }

    // MARK: - Actions

    private func startCreate() {
        draft = ProjectDraft()
        draft.rank = projects.contains { $0.priorityRank != nil } ? nil : 1
        editingProject = nil
        showingForm = true
    }

    private func startEdit(_ project: Project) {
        draft = ProjectDraft(project: project)
        editingProject = project
        showingForm = true
    }

    private func archive() {
        guard let project = projectToArchive else { return }
        project.archived = true
        if timerVM.selectedProject?.id == project.id { timerVM.selectedProject = nil }
        if selectedID == project.id { selectedID = projects.first { $0.id != project.id }?.id }
        saveWithFeedback(modelContext, errorBinding: $saveError)
        projectToArchive = nil
    }

    private func restore(_ project: Project) {
        project.archived = false
        saveWithFeedback(modelContext, errorBinding: $saveError)
        selectedID = project.id
    }

    private var projectForm: some View {
        ProjectFormView(
            draft: $draft,
            project: editingProject,
            title: editingProject == nil ? "New project" : "Edit project"
        ) {
            let target: Project
            if let editing = editingProject {
                target = editing
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
            if editingProject == nil {
                timerVM.selectedProject = target
                timerVM.noteProjectSelected()
            }
            selectedID = target.id
        }
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

            FFSection("Blocks this week") {
                if weekSessions.isEmpty {
                    FFEmptyState(systemImage: "tray", message: "No blocks on \(project.name) this week")
                } else {
                    VStack(spacing: 2) {
                        ForEach(weekSessions) { session in
                            SessionRow(session: session) { onSelectSession(session) }
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
            Image(systemName: goal.isBossFight ? "flag.checkered" : "scope")
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
            Button("Archive", action: onArchive).buttonStyle(.bordered)
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
