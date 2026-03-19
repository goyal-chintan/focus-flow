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
        .background(.background)
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
        }
    }

    private var emptyState: some View {
        LiquidGlassPanel {
            VStack(spacing: 14) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No projects yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Create a project to categorize and route your focus sessions.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }

    private var projectsList: some View {
        List {
            ForEach(projects) { project in
                projectRow(project)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
            }
            .onDelete { indexSet in
                withAnimation {
                    for index in indexSet {
                        let project = projects[index]
                        if timerVM.selectedProject?.id == project.id {
                            timerVM.selectedProject = nil
                        }
                        projects[index].archived = true
                    }
                    try? modelContext.save()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func projectRow(_ project: Project) -> some View {
        LiquidGlassPanel(cornerRadius: LiquidDesignTokens.CornerRadius.control) {
            HStack(spacing: 12) {
                Circle()
                    .fill(colorFromName(project.color))
                    .frame(width: 10, height: 10)

                Image(systemName: project.icon ?? "folder.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colorFromName(project.color))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.body.weight(.medium))

                    let count = project.sessions.filter { $0.type == .focus && $0.completed }.count
                    Text("\(count) focus session\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    rowIconButton(systemName: "pencil", helpText: "Edit project") {
                        formName = project.name
                        formColor = project.color
                        formIcon = project.icon ?? "folder.fill"
                        formBlockProfile = project.blockProfile
                        editingProject = project
                        showingAddSheet = true
                    }

                    rowIconButton(systemName: "archivebox", helpText: "Archive project") {
                        withAnimation {
                            project.archived = true
                            if timerVM.selectedProject?.id == project.id {
                                timerVM.selectedProject = nil
                            }
                            try? modelContext.save()
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func rowIconButton(systemName: String, helpText: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.glass)
        .tint(.secondary)
        .help(helpText)
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
