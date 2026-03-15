import SwiftUI
import SwiftData

struct ProjectPickerView: View {
    @Binding var selectedProject: Project?
    @Binding var customLabel: String
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt)
    private var projects: [Project]
    @State private var showCustomField = false

    var body: some View {
        VStack(spacing: 8) {
            Menu {
                Button {
                    selectedProject = nil
                    showCustomField = false
                    customLabel = ""
                } label: {
                    Label("No Project", systemImage: "minus.circle")
                }

                if !projects.isEmpty {
                    Divider()
                    ForEach(projects) { project in
                        Button {
                            selectedProject = project
                            showCustomField = false
                            customLabel = ""
                        } label: {
                            Label(project.name, systemImage: project.icon ?? "folder.fill")
                        }
                    }
                }

                Divider()
                Button {
                    selectedProject = nil
                    showCustomField = true
                } label: {
                    Label("Custom Label...", systemImage: "pencil")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: selectedProject?.icon ?? (showCustomField ? "pencil" : "tag"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text(pickerLabel)
                        .font(.subheadline)
                        .foregroundStyle(hasSelection ? .primary : .secondary)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if showCustomField {
                HStack {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("What are you working on?", text: $customLabel)
                        .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showCustomField)
    }

    private var pickerLabel: String {
        if let project = selectedProject { return project.name }
        if showCustomField { return customLabel.isEmpty ? "Type a label..." : customLabel }
        return "Select Project"
    }

    private var hasSelection: Bool {
        selectedProject != nil || (showCustomField && !customLabel.isEmpty)
    }
}
