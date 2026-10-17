import SwiftUI
import SwiftData

/// "This week's priorities": the user's 1–3 personal outcomes for the current week
/// (coach v2 design §9). Add, rename inline, reorder, mark done, link a project, delete.
struct WeeklyPrioritiesSection: View {
    static let maxPriorities = 3

    let projects: [Project]
    @Binding var saveError: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \WeeklyPriority.order, animation: .smooth(duration: 0.25)) private var allPriorities: [WeeklyPriority]
    @State private var priorityToDelete: WeeklyPriority?
    @FocusState private var focusedPriorityID: UUID?

    private var currentWeekStart: Date { WeeklyPriority.weekStart(for: Date()) }

    private var priorities: [WeeklyPriority] {
        let calendar = Calendar.current
        let weekStart = currentWeekStart
        return allPriorities
            .filter { calendar.isDate($0.weekStart, inSameDayAs: weekStart) }
            .sorted { lhs, rhs in
                lhs.order != rhs.order ? lhs.order < rhs.order : lhs.createdAt < rhs.createdAt
            }
    }

    var body: some View {
        Section {
            ForEach(Array(priorities.enumerated()), id: \.element.id) { index, priority in
                WeeklyPriorityRow(
                    priority: priority,
                    projects: projects,
                    canMoveUp: index > 0,
                    canMoveDown: index < priorities.count - 1,
                    focusedPriorityID: $focusedPriorityID,
                    onChange: save,
                    onMove: { offset in move(priority, by: offset) },
                    onDelete: { priorityToDelete = priority }
                )
            }
            .onMove(perform: moveRows)

            if priorities.isEmpty {
                Text("No priorities yet for this week.")
                    .foregroundStyle(.secondary)
            }

            if priorities.count < Self.maxPriorities {
                Button {
                    addPriority()
                } label: {
                    Label("Add Priority", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add a priority for this week")
            }
        } header: {
            HStack {
                Text("This week's priorities")
                Spacer()
                Text(weekLabel)
                    .foregroundStyle(.secondary)
            }
            .confirmationDialog(
                "Delete this priority?",
                isPresented: Binding(
                    get: { priorityToDelete != nil },
                    set: { if !$0 { priorityToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let priorityToDelete {
                        delete(priorityToDelete)
                    }
                    priorityToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    priorityToDelete = nil
                }
            } message: {
                Text(priorityToDelete.map { "“\($0.title.isEmpty ? "Untitled" : $0.title)” will be removed from this week." } ?? "")
            }
        } footer: {
            Text("1–3 outcomes that would make this week a win.")
                .foregroundStyle(.secondary)
        }
    }

    private var weekLabel: String {
        let start = currentWeekStart
        return "Week of \(start.formatted(.dateTime.month(.abbreviated).day()))"
    }

    // MARK: Mutations

    private func addPriority() {
        let priority = WeeklyPriority(
            title: "",
            weekStart: currentWeekStart,
            order: (priorities.map(\.order).max() ?? -1) + 1
        )
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            modelContext.insert(priority)
        }
        save()
        focusedPriorityID = priority.id
    }

    private func move(_ priority: WeeklyPriority, by offset: Int) {
        var ordered = priorities
        guard let index = ordered.firstIndex(where: { $0.id == priority.id }) else { return }
        let target = index + offset
        guard ordered.indices.contains(target) else { return }
        ordered.swapAt(index, target)
        renumber(ordered)
    }

    private func moveRows(from source: IndexSet, to destination: Int) {
        var ordered = priorities
        ordered.move(fromOffsets: source, toOffset: destination)
        renumber(ordered)
    }

    private func renumber(_ ordered: [WeeklyPriority]) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            for (index, item) in ordered.enumerated() {
                item.order = index
            }
        }
        save()
    }

    private func delete(_ priority: WeeklyPriority) {
        let remaining = priorities.filter { $0.id != priority.id }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            modelContext.delete(priority)
            for (index, item) in remaining.enumerated() {
                item.order = index
            }
        }
        save()
    }

    private func save() {
        saveWithFeedback(modelContext, errorBinding: $saveError)
    }
}

/// One priority: done toggle, inline title, project link and a More menu.
private struct WeeklyPriorityRow: View {
    @Bindable var priority: WeeklyPriority
    let projects: [Project]
    let canMoveUp: Bool
    let canMoveDown: Bool
    var focusedPriorityID: FocusState<UUID?>.Binding
    let onChange: () -> Void
    let onMove: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    priority.isDone.toggle()
                }
                onChange()
            } label: {
                Image(systemName: priority.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(priority.isDone ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(priority.isDone ? "Mark as not done" : "Mark as done")
            .accessibilityLabel(priority.isDone ? "Mark \(priority.title) as not done" : "Mark \(priority.title) as done")

            Group {
                if priority.isDone {
                    Text(priority.title.isEmpty ? "Priority" : priority.title)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("Priority", text: $priority.title, prompt: Text("What will be finished this week?"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focused(focusedPriorityID, equals: priority.id)
                        .onSubmit(onChange)
                        .onChange(of: priority.title) { _, _ in onChange() }
                }
            }
            .animation(.smooth(duration: 0.25), value: priority.isDone)

            Picker("Project", selection: Binding<UUID?>(
                get: { priority.projectID },
                set: { priority.projectID = $0; onChange() }
            )) {
                Text("No project").tag(UUID?.none)
                if !projects.isEmpty {
                    Divider()
                }
                ForEach(projects) { project in
                    Text(project.name).tag(Optional(project.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .controlSize(.small)
            .accessibilityLabel("Linked project")

            SettingsRowMenu(accessibilityLabel: "More actions for priority") {
                Button("Move Up") { onMove(-1) }
                    .disabled(!canMoveUp)
                Button("Move Down") { onMove(1) }
                    .disabled(!canMoveDown)
                Divider()
                Button("Delete…", role: .destructive, action: onDelete)
            }
        }
        .frame(minHeight: SettingsLayout.listRowMinHeight)
    }
}
