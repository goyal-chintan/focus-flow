import SwiftUI
import SwiftData

struct ProjectPickerView: View {
    @Binding var selectedProject: Project?
    @Binding var customLabel: String
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt)
    private var projects: [Project]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 8) {
            // Inline search/select
            HStack(spacing: 8) {
                Image(systemName: selectedProject?.icon ?? "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                TextField("Search or create project...", text: $searchText)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        if let match = filteredProjects.first(where: { $0.name.lowercased() == searchText.lowercased() }) {
                            selectedProject = match
                            searchText = match.name
                            customLabel = ""
                        } else if !searchText.isEmpty {
                            createAndSelect(name: searchText)
                        }
                    }

                if selectedProject != nil || !searchText.isEmpty {
                    Button {
                        selectedProject = nil
                        searchText = ""
                        customLabel = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))

            // Dropdown suggestions
            if !searchText.isEmpty && selectedProject == nil {
                VStack(spacing: 0) {
                    ForEach(filteredProjects) { project in
                        Button {
                            selectedProject = project
                            searchText = project.name
                            customLabel = ""
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: project.icon ?? "folder.fill")
                                    .font(.caption)
                                    .foregroundStyle(colorFromName(project.color))
                                Text(project.name)
                                    .font(.subheadline)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }

                    // Create new option
                    if !filteredProjects.contains(where: { $0.name.lowercased() == searchText.lowercased() }) {
                        Button {
                            createAndSelect(name: searchText)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                Text("Create \"\(searchText)\"")
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.smooth(duration: 0.2), value: searchText)
        .onChange(of: selectedProject) { _, newValue in
            if let project = newValue {
                searchText = project.name
            }
        }
    }

    private var filteredProjects: [Project] {
        if searchText.isEmpty { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func createAndSelect(name: String) {
        let project = Project(name: name)
        modelContext.insert(project)
        try? modelContext.save()
        selectedProject = project
        searchText = name
        customLabel = ""
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
