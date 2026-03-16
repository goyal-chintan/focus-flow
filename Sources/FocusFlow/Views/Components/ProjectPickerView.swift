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
                    ZStack {
                        RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous)
                            .fill(projectTint.opacity(selectionPulse ? 0.24 : 0.16))
                            .animation(FFMotion.control, value: selectionPulse)

                        Image(systemName: selectedProject?.icon ?? "tag")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(projectTint)
                            .contentTransition(.interpolate)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedProject?.name ?? "No Project")
                            .font(FFType.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .contentTransition(.interpolate)
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.sm)
                .scaleEffect(selectionPulse ? 1.01 : 1)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
                .ffCardChrome(cornerRadius: FFRadius.card)
                .animation(FFMotion.control, value: selectionPulse)
            }
            .buttonStyle(.plain)
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
