import SwiftUI
import SwiftData

struct ProjectPickerView: View {
    @Binding var selectedProject: Project?
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt)
    private var projects: [Project]
    @Environment(\.modelContext) private var modelContext
    @State private var showCreateSheet = false
    @State private var newProjectName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Project")
                .font(.caption2.weight(.medium))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.secondary)

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
                HStack(spacing: 8) {
                    Image(systemName: selectedProject?.icon ?? "tag")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedProject != nil ? .blue : .secondary)
                        .frame(width: 16)

                    Text(selectedProject?.name ?? "No Project")
                        .font(.subheadline)
                        .foregroundStyle(selectedProject != nil ? .primary : .secondary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .popover(isPresented: $showCreateSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("New Project")
                    .font(.subheadline.weight(.medium))

                TextField("Project name", text: $newProjectName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit { createProject() }

                HStack(spacing: 8) {
                    Button("Cancel") {
                        showCreateSheet = false
                    }
                    .buttonStyle(.glass)

                    Spacer(minLength: 0)

                    Button("Create") {
                        createProject()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.blue)
                    .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(16)
            .frame(width: 260)
        }
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
}
