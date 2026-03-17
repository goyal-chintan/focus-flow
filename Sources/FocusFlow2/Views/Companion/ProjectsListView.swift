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
        ScrollView {
            VStack(spacing: FFSpacing.lg) {
                PremiumSurface(style: .hero) {
                    PremiumSectionHeader(
                        "Projects",
                        eyebrow: "Workspace",
                        subtitle: "\(projects.count) active projects"
                    ) {
                        Button {
                            resetForm()
                            editingProject = nil
                            showingAddSheet = true
                        } label: {
                            Label("New Project", systemImage: "plus.circle.fill")
                                .font(FFType.meta)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(FFColor.focus)
                    }
                }

                if projects.isEmpty {
                    PremiumSurface(style: .card, alignment: .center) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("No projects yet")
                            .font(FFType.title)
                            .foregroundStyle(.secondary)
                        Text("Create a project to categorize focus sessions and attach blocking profiles when needed.")
                            .font(FFType.meta)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    PremiumSurface(style: .card) {
                        PremiumSectionHeader(
                            "Active Projects",
                            eyebrow: "Library",
                            subtitle: "Edit a project, attach a blocking profile, or archive it when it is done."
                        )

                        LazyVStack(spacing: FFSpacing.sm) {
                            ForEach(projects) { project in
                                projectRow(project)
                            }
                        }
                    }
                }
            }
            .padding(FFSpacing.lg)
        }
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

    private func projectRow(_ project: Project) -> some View {
        let count = project.sessions.filter { $0.type == .focus && $0.completed }.count

        return HStack(spacing: FFSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                    .fill(colorFromName(project.color).opacity(0.15))

                Image(systemName: project.icon ?? "folder.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colorFromName(project.color))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: FFSpacing.xs) {
                    Text(project.name)
                        .font(FFType.body.weight(.medium))

                    if let profile = project.blockProfile {
                        Text(profile.name)
                            .font(FFType.micro)
                            .foregroundStyle(FFColor.focus)
                            .padding(.horizontal, FFSpacing.xs)
                            .padding(.vertical, 3)
                            .background(FFColor.focus.opacity(0.12), in: Capsule())
                    }
                }

                Text("\(count) focus session\(count == 1 ? "" : "s")")
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: FFSpacing.xs) {
                Button {
                    formName = project.name
                    formColor = project.color
                    formIcon = project.icon ?? "folder.fill"
                    formBlockProfile = project.blockProfile
                    editingProject = project
                    showingAddSheet = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)

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
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.vertical, FFSpacing.sm)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
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
