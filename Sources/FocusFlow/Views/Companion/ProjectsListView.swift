import SwiftUI
import SwiftData

struct ProjectsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimerViewModel.self) private var timerVM
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt)
    private var projects: [Project]

    @State private var selectedProject: Project?
    @State private var showingAddSheet = false
    @State private var showBlockingSheet = false
    @State private var editingProject: Project?
    @State private var formName = ""
    @State private var formColor = "blue"
    @State private var formIcon = "folder.fill"
    @State private var formBlockProfile: BlockProfile?

    var body: some View {
        VStack(spacing: LiquidDesignTokens.Spacing.large) {
            header

            if projects.isEmpty {
                emptyState
            } else {
                projectsContent
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .onAppear { initSelectedProject() }
        .onChange(of: projects) { initSelectedProject() }
        .sheet(isPresented: $showingAddSheet) {
            projectFormSheet
        }
        .sheet(isPresented: $showBlockingSheet) {
            BlockingSettingsView()
        }
    }

    // MARK: - Header

    private var header: some View {
        LiquidSectionHeader("Projects", subtitle: "\(projects.count) active") {
            Button {
                resetForm()
                editingProject = nil
                showingAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Add project")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text("No projects yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Create a project to categorize\nand route your focus sessions.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Projects Content

    private var projectsContent: some View {
        VStack(spacing: LiquidDesignTokens.Spacing.large) {
            if let selected = selectedProject {
                heroCard(selected)
                    .animation(FFMotion.section, value: selected.id)
            }

            rosterSection

            blockingButton
        }
    }

    // MARK: - Hero Card

    private func heroCard(_ project: Project) -> some View {
        LiquidGlassPanel(cornerRadius: 16) {
            HStack(spacing: 18) {
                heroIcon(project)
                heroDetails(project)
                Spacer(minLength: 0)
                heroActions(project)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorFromName(project.color).opacity(0.08))
            )
        }
    }

    private func heroIcon(_ project: Project) -> some View {
        ZStack {
            Circle()
                .fill(colorFromName(project.color).opacity(0.2))
                .frame(width: 64, height: 64)
            Image(systemName: project.icon ?? "folder.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(colorFromName(project.color))
        }
    }

    private func heroDetails(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.name)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                .lineLimit(1)

            Text(heroStatsText(for: project))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if let profile = project.blockProfile {
                Text("🛡️ \(profile.name)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    )
            }
        }
    }

    private func heroActions(_ project: Project) -> some View {
        VStack(spacing: 6) {
            Button {
                formName = project.name
                formColor = project.color
                formIcon = project.icon ?? "folder.fill"
                formBlockProfile = project.blockProfile
                editingProject = project
                showingAddSheet = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit project")

            Button {
                withAnimation(FFMotion.section) {
                    project.archived = true
                    if timerVM.selectedProject?.id == project.id {
                        timerVM.selectedProject = nil
                    }
                    if selectedProject?.id == project.id {
                        selectedProject = projects.first(where: { $0.id != project.id })
                    }
                    try? modelContext.save()
                }
            } label: {
                Image(systemName: "archivebox")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Archive project")
        }
    }

    // MARK: - Roster

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            if projects.count > 1 {
                Text("All Projects")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(projects) { project in
                        rosterCard(project)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private func rosterCard(_ project: Project) -> some View {
        let isSelected = selectedProject?.id == project.id
        let sessionCount = project.sessions.filter { $0.type == .focus && $0.completed }.count

        return VStack(spacing: 8) {
            Image(systemName: project.icon ?? "folder.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(colorFromName(project.color))

            Text(project.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                .lineLimit(1)

            Text("\(sessionCount)")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .frame(width: 120, height: 90)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSelected ? LiquidDesignTokens.Spectral.primaryContainer.opacity(0.5) : Color.white.opacity(0.06),
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            withAnimation(FFMotion.section) {
                selectedProject = project
                timerVM.selectedProject = project
            }
        }
    }

    // MARK: - Blocking Button

    private var blockingButton: some View {
        Button {
            showBlockingSheet = true
        } label: {
            Label("Manage Blocking Profiles", systemImage: "shield.checkered")
                .font(LiquidDesignTokens.Typography.controlLabel)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
    }

    // MARK: - Form Sheet

    private var projectFormSheet: some View {
        ProjectFormView(
            name: $formName,
            color: $formColor,
            icon: $formIcon,
            selectedBlockProfile: $formBlockProfile,
            title: editingProject == nil ? "New Project" : "Edit Project"
        ) {
            var savedProject: Project?
            if let editing = editingProject {
                editing.name = formName.trimmingCharacters(in: .whitespaces)
                editing.color = formColor
                editing.icon = formIcon
                editing.blockProfile = formBlockProfile
                savedProject = editing
            } else {
                let project = Project(
                    name: formName.trimmingCharacters(in: .whitespaces),
                    color: formColor,
                    icon: formIcon
                )
                project.blockProfile = formBlockProfile
                modelContext.insert(project)
                savedProject = project
            }
            try? modelContext.save()
            if let savedProject {
                timerVM.selectedProject = savedProject
                selectedProject = savedProject
            }
        }
    }

    // MARK: - Helpers

    private func initSelectedProject() {
        if selectedProject == nil || !(projects.contains(where: { $0.id == selectedProject?.id })) {
            selectedProject = projects.first
        }
    }

    private func heroStatsText(for project: Project) -> String {
        let focusSessions = project.sessions.filter { $0.type == .focus && $0.completed }
        let count = focusSessions.count

        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let weekSeconds = focusSessions
            .filter { $0.startedAt >= startOfWeek }
            .reduce(0.0) { $0 + ($1.endedAt?.timeIntervalSince($1.startedAt) ?? $1.duration) }
        let hours = weekSeconds / 3600.0

        if count == 0 { return "No sessions yet" }
        let sessionLabel = "\(count) session\(count == 1 ? "" : "s")"
        let hourLabel = String(format: "%.1f hr\(hours >= 2 ? "s" : "") this week", hours)
        return "\(sessionLabel) · \(hourLabel)"
    }

    private func resetForm() {
        formName = ""
        formColor = "blue"
        formIcon = "folder.fill"
        formBlockProfile = nil
    }

    private func colorFromName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "teal": return .teal
        case "mint": return .mint
        default: return .blue
        }
    }
}
