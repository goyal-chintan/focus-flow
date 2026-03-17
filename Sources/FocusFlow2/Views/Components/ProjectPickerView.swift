import SwiftUI
import SwiftData

struct ProjectPickerView: View {
    @Binding var selectedProject: Project?
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt)
    private var projects: [Project]
    @Environment(\.modelContext) private var modelContext
    @State private var showCreateSheet = false
    @State private var newProjectName = ""
    @State private var selectionPulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            Menu {
                Button {
                    selectedProject = nil
                } label: {
                    HStack {
                        Text("No Project")
                        if selectedProject == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                if !projects.isEmpty {
                    Divider()
                    ForEach(projects) { project in
                        Button {
                            selectedProject = project
                        } label: {
                            HStack {
                                Label(project.name, systemImage: project.icon ?? "folder.fill")
                                if selectedProject?.id == project.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Divider()
                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Project...", systemImage: "plus.circle")
                }
            } label: {
                HStack(spacing: FFSpacing.sm) {
                    Image(systemName: selectedProject?.icon ?? "tag")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(projectTint)
                        .contentTransition(.interpolate)

                    Text(selectedProject?.name ?? "No Project")
                        .font(FFType.body)
                        .foregroundStyle(.primary)
                        .contentTransition(.interpolate)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.sm + 2)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .onChange(of: selectedProject?.name) { _, _ in
                withAnimation(FFMotion.control) {
                    selectionPulse = true
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation(FFMotion.control) {
                        selectionPulse = false
                    }
                }
            }
        }
        .popover(isPresented: $showCreateSheet) {
            PremiumSurface(style: .card) {
                PremiumSectionHeader("New Project", subtitle: "Create a quick project without leaving the timer.")

                TextField("Project name", text: $newProjectName)
                    .textFieldStyle(.plain)
                    .font(FFType.body)
                    .padding(.horizontal, FFSpacing.md)
                    .padding(.vertical, FFSpacing.sm)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12))
                    }
                    .onSubmit { createProject() }

                HStack(spacing: FFSpacing.sm) {
                    Button("Cancel") { showCreateSheet = false }
                        .buttonStyle(.glass)

                    Button("Create") { createProject() }
                        .buttonStyle(.glassProminent)
                        .tint(FFColor.focus)
                        .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(FFSpacing.md)
            .frame(width: 320)
        }
    }

    private var projectTint: Color {
        guard let selectedProject else { return .secondary }
        return colorFromName(selectedProject.color)
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let project = Project(name: name)
        modelContext.insert(project)
        try? modelContext.save()
        selectedProject = project
        newProjectName = ""
        showCreateSheet = false
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
