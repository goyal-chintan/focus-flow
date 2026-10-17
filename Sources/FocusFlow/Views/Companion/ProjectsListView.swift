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
    @Query private var priorities: [WeeklyPriority]

    @State private var selectedID: UUID?
    @State private var showingForm = false
    @State private var editingProject: Project?
    @State private var editingSession: FocusSession?
    @State private var projectToArchive: Project?
    @State private var showArchived = false
    @State private var saveError: String?

    @State private var formName = ""
    @State private var formColor = "blue"
    @State private var formIcon = "folder.fill"
    @State private var formBlockProfiles: [BlockProfile] = []
    @State private var formWorkMode: WorkMode = .deepWork
    @State private var formGuardianSensitivity: GuardianSensitivity = .normal
    @State private var formDifficultyBias: DifficultyBias = .moderate

    private var selectedProject: Project? {
        projects.first { $0.id == selectedID } ?? projects.first
    }

    var body: some View {
        let snapshot = CompanionSnapshot(sessions: sessions, settings: allSettings.first, now: nowOverride ?? Date())
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
                    projectList(weekTotals: weekTotals)
                        .frame(width: 232)
                    if let project = selectedProject {
                        ScrollView {
                            ProjectDetail(
                                project: project,
                                snapshot: snapshot,
                                sessions: sessions,
                                priorities: priorities.map(PrioritySample.init),
                                onEdit: { startEdit(project) },
                                onArchive: { projectToArchive = project },
                                onSelectSession: { editingSession = $0 }
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

    private func projectList(weekTotals: [FocusAnalytics.ProjectTotal]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(projects) { project in
                let seconds = weekTotals.first { $0.project.projectUUID == project.id }?.seconds ?? 0
                Button {
                    selectedID = project.id
                } label: {
                    HStack(spacing: FFSpace.s) {
                        Image(systemName: project.icon ?? "folder.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FFPalette.project(project.color))
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text(project.name).ffText(.body).lineLimit(1)
                        Spacer(minLength: FFSpace.xs)
                        Text(seconds > 0 ? FFFormat.duration(seconds) : "—")
                            .ffText(.caption)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, FFSpace.s)
                    .frame(height: 30)
                    .ffHoverRow(isSelected: project.id == selectedProject?.id)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(project.name), \(FFFormat.duration(seconds)) this week")
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
        formName = ""
        formColor = "blue"
        formIcon = "folder.fill"
        formBlockProfiles = []
        formWorkMode = .deepWork
        formGuardianSensitivity = .normal
        formDifficultyBias = .moderate
        editingProject = nil
        showingForm = true
    }

    private func startEdit(_ project: Project) {
        formName = project.name
        formColor = project.color
        formIcon = project.icon ?? "folder.fill"
        formBlockProfiles = project.effectiveBlockProfiles
        formWorkMode = project.workMode
        formGuardianSensitivity = project.guardianSensitivity
        formDifficultyBias = project.difficultyBias
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
            name: $formName,
            color: $formColor,
            icon: $formIcon,
            selectedBlockProfiles: $formBlockProfiles,
            workMode: $formWorkMode,
            guardianSensitivity: $formGuardianSensitivity,
            difficultyBias: $formDifficultyBias,
            title: editingProject == nil ? "New Project" : "Edit Project"
        ) {
            let profiles = deduplicated(formBlockProfiles)
            let target: Project
            if let editing = editingProject {
                target = editing
            } else {
                target = Project(name: "", color: formColor, icon: formIcon)
                modelContext.insert(target)
            }
            target.name = formName.trimmingCharacters(in: .whitespaces)
            target.color = formColor
            target.icon = formIcon
            target.blockProfiles = profiles
            target.blockProfile = profiles.first
            target.workMode = formWorkMode
            target.guardianSensitivity = formGuardianSensitivity
            target.difficultyBias = formDifficultyBias
            saveWithFeedback(modelContext, errorBinding: $saveError)
            if editingProject == nil {
                timerVM.selectedProject = target
                timerVM.noteProjectSelected()
            }
            selectedID = target.id
        }
    }

    private func deduplicated(_ profiles: [BlockProfile]) -> [BlockProfile] {
        var seen = Set<UUID>()
        return profiles.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Detail

private struct ProjectDetail: View {
    let project: Project
    let snapshot: CompanionSnapshot
    let sessions: [FocusSession]
    let priorities: [PrioritySample]
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onSelectSession: (FocusSession) -> Void

    @State private var selectedDay: Date?

    private var key: AnalyticsProjectKey { AnalyticsProjectKey(project: project, customLabel: nil) }
    private var color: Color { FFPalette.project(project.color) }

    var body: some View {
        let analytics = snapshot.analytics
        let projectSamples = snapshot.samples.filter { sample in sample.normalisedShares.contains { $0.project == key } }
        let weekDays = weekDays(analytics)
        let weekSeconds = weekDays.reduce(0) { $0 + $1.seconds }
        let weekSessions = sessions
            .filter { $0.type == .focus && $0.actualDuration >= 60 && $0.effectiveEnd > snapshot.thisWeek.start && $0.startedAt < snapshot.thisWeek.end }
            .filter { session in FocusSample(session).normalisedShares.contains { $0.project == key } }
            .sorted { $0.startedAt > $1.startedAt }
        let allTime = projectSamples.reduce(0) { total, sample in
            total + sample.activeSeconds * (sample.normalisedShares.first { $0.project == key }?.fraction ?? 0)
        }
        let mix = analytics.outcomeMix(projectSamples.filter { $0.project == key })
        let linked = priorities.filter { $0.projectID == project.id && snapshot.thisWeek.contains($0.weekStart) }

        VStack(alignment: .leading, spacing: FFSpace.sectionGap) {
            header(linked: linked)

            HStack(alignment: .top, spacing: FFSpace.l) {
                FFStat(label: "This week", value: FFFormat.duration(weekSeconds), caption: "\(weekSessions.count) block\(weekSessions.count == 1 ? "" : "s")")
                Divider()
                FFStat(
                    label: "Daily average",
                    value: FFFormat.duration(weekSeconds / Double(max(1, daysElapsedThisWeek(analytics)))),
                    caption: "This week so far"
                )
                Divider()
                FFStat(label: "All time", value: FFFormat.duration(allTime), caption: "\(projectSamples.count) blocks")
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(FFSpace.l)
            .ffSurface()

            FFSection("This week", subtitle: "Daily focus on \(project.name)") {
                DailyFocusChart(
                    days: weekDays,
                    goal: snapshot.goal,
                    colors: ProjectColorScale([key]),
                    singleColor: color,
                    showGoal: false,
                    selectedDay: $selectedDay,
                    height: 170
                )
            }

            FFSection("Real work vs busywork", subtitle: mix.ratedCount > 0 ? "\(mix.ratedCount) rated blocks, all time" : nil) {
                if mix.ratedCount == 0 {
                    FFEmptyState(systemImage: "checklist", message: "Rate your sessions after each block to see this")
                } else {
                    OutcomeMixBar(mix: mix)
                }
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

    private func header(linked: [PrioritySample]) -> some View {
        HStack(alignment: .center, spacing: FFSpace.m) {
            Image(systemName: project.icon ?? "folder.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(color.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).ffText(.title3).lineLimit(1)
                Text(headerCaption(linked: linked)).ffText(.caption).lineLimit(1)
            }
            Spacer(minLength: FFSpace.s)
            Button("Edit", action: onEdit).buttonStyle(.bordered)
            Button("Archive", action: onArchive).buttonStyle(.bordered)
        }
    }

    private func headerCaption(linked: [PrioritySample]) -> String {
        var parts: [String] = []
        if !linked.isEmpty { parts.append("Serves " + linked.map(\.title).joined(separator: ", ")) }
        let profiles = project.effectiveBlockProfiles.map(\.name)
        if !profiles.isEmpty { parts.append("Blocks with " + profiles.joined(separator: ", ")) }
        if parts.isEmpty { parts.append("No blocking profile") }
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

    private func daysElapsedThisWeek(_ analytics: FocusAnalytics) -> Int {
        (analytics.calendar.dateComponents([.day], from: snapshot.thisWeek.start, to: snapshot.now).day ?? 0) + 1
    }
}
