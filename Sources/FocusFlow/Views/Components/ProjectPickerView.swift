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
                                .accessibilityHidden(true)
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
                                        .accessibilityHidden(true)
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
                    Circle()
                        .fill(projectColor)
                        .frame(width: 7, height: 7)

                    Text(selectedProject?.name ?? "No Project")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    // Explicit indicator (system one hidden below) so the capsule reads as a menu.
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .padding(.horizontal, 12)
                .background {
                    RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.sm, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.sm, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                        )
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
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
                                .stroke(FFPalette.hairline, lineWidth: 0.5)
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
                .buttonStyle(.glass)
                .foregroundStyle(LiquidDesignTokens.Spectral.primaryContainer)
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
