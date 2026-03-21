import SwiftUI
import SwiftData

struct ProjectPickerView: View {
    @Binding var selectedProject: Project?
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt)
    private var projects: [Project]
    @Environment(\.modelContext) private var modelContext
    @State private var showCreateSheet = false
    @State private var newProjectName = ""
    @State private var saveError: String?

    private var projectColor: Color {
        guard let colorName = selectedProject?.color else { return LiquidDesignTokens.Spectral.electricBlue }
        return colorFromName(colorName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                HStack(spacing: 10) {
                    Circle()
                        .fill(projectColor)
                        .frame(width: 7, height: 7)

                    Text(selectedProject?.name ?? "No Project")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                        .lineLimit(1)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .accessibilityLabel("Project: \(selectedProject?.name ?? "No Project")")
        }
        .popover(isPresented: $showCreateSheet) {
            createProjectPopover
        }
        .saveErrorOverlay($saveError)
    }

    private var createProjectPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Project")
                .font(LiquidDesignTokens.Typography.headlineMedium)
                .foregroundStyle(LiquidDesignTokens.Surface.onSurface)

            TextField("Project name", text: $newProjectName)
                .textFieldStyle(.plain)
                .font(LiquidDesignTokens.Typography.bodyMedium)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LiquidDesignTokens.Surface.containerLow)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
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
                .tint(LiquidDesignTokens.Spectral.primaryContainer)
                .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let project = Project(name: name)
        modelContext.insert(project)
        saveWithFeedback(modelContext, errorBinding: $saveError)
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
        default: return LiquidDesignTokens.Spectral.electricBlue
        }
    }
}
