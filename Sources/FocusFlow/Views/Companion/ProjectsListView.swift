import SwiftUI
import SwiftData

struct ProjectsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimerViewModel.self) private var timerVM
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt)
    private var projects: [Project]

    @State private var showingAddSheet = false
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
                projectsList
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showingAddSheet) {
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
                }
            }
        }
    }

    private var header: some View {
        LiquidSectionHeader("Projects", subtitle: "\(projects.count) active") {
            Button {
                resetForm()
                editingProject = nil
                showingAddSheet = true
            } label: {
                Label("New Project", systemImage: "plus")
                    .font(LiquidDesignTokens.Typography.controlLabel)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
            .buttonBorderShape(.capsule)
        }
    }

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

    private var projectsList: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(projects) { project in
                    projectCard(project)
                }
            }
        }
    }

    private func projectCard(_ project: Project) -> some View {
        let isSelected = timerVM.selectedProject?.id == project.id

        return VStack(alignment: .leading, spacing: 10) {
            // Top row: icon badge + actions
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colorFromName(project.color).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: project.icon ?? "folder.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(colorFromName(project.color))
                }

                Spacer()

                HStack(spacing: 4) {
                    Button {
                        formName = project.name
                        formColor = project.color
                        formIcon = project.icon ?? "folder.fill"
                        formBlockProfile = project.blockProfile
                        editingProject = project
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit project")

                    Button {
                        withAnimation {
                            project.archived = true
                            if timerVM.selectedProject?.id == project.id {
                                timerVM.selectedProject = nil
                            }
                            try? modelContext.save()
                        }
                    } label: {
                        Image(systemName: "archivebox")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Archive project")
                }
            }

            // Project name
            Text(project.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                .lineLimit(1)

            // Session count
            Text(sessionCountText(for: project))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? LiquidDesignTokens.Spectral.primaryContainer.opacity(0.4) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            timerVM.selectedProject = project
        }
    }

    private func sessionCountText(for project: Project) -> String {
        let count = project.sessions.filter { $0.type == .focus && $0.completed }.count
        if count == 0 { return "No sessions yet" }
        return "\(count) session\(count == 1 ? "" : "s")"
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
