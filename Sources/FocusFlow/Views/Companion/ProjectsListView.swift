import SwiftUI
import SwiftData

struct ProjectsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt)
    private var projects: [Project]

    @State private var showingAddSheet = false
    @State private var editingProject: Project?
    @State private var formName = ""
    @State private var formColor = "blue"
    @State private var formIcon = "folder.fill"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Projects")
                        .font(.title2.weight(.bold))
                    Text("\(projects.count) active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    resetForm()
                    editingProject = nil
                    showingAddSheet = true
                } label: {
                    Label("New Project", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(24)

            if projects.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("No projects yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Create a project to categorize your focus sessions")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(projects) { project in
                        HStack(spacing: 14) {
                            // Icon badge
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(colorFromName(project.color).opacity(0.15))
                                    .frame(width: 40, height: 40)
                                Image(systemName: project.icon ?? "folder.fill")
                                    .foregroundStyle(colorFromName(project.color))
                                    .font(.system(size: 18, weight: .medium))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(.body.weight(.medium))
                                let count = project.sessions.filter { $0.type == .focus && $0.completed }.count
                                Text("\(count) focus session\(count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Actions
                            HStack(spacing: 4) {
                                Button {
                                    formName = project.name
                                    formColor = project.color
                                    formIcon = project.icon ?? "folder.fill"
                                    editingProject = project
                                    showingAddSheet = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("Edit project")

                                Button {
                                    withAnimation {
                                        project.archived = true
                                        try? modelContext.save()
                                    }
                                } label: {
                                    Image(systemName: "archivebox")
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("Archive project")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(.background)
        .sheet(isPresented: $showingAddSheet) {
            ProjectFormView(
                name: $formName,
                color: $formColor,
                icon: $formIcon,
                title: editingProject == nil ? "New Project" : "Edit Project"
            ) {
                if let editing = editingProject {
                    editing.name = formName.trimmingCharacters(in: .whitespaces)
                    editing.color = formColor
                    editing.icon = formIcon
                } else {
                    let project = Project(
                        name: formName.trimmingCharacters(in: .whitespaces),
                        color: formColor,
                        icon: formIcon
                    )
                    modelContext.insert(project)
                }
                try? modelContext.save()
            }
        }
    }

    private func resetForm() {
        formName = ""
        formColor = "blue"
        formIcon = "folder.fill"
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
