import SwiftUI
import SwiftData

/// Editable copy of a goal and its key results; applied to SwiftData on save.
struct GoalDraft: Equatable {
    struct KeyResultDraft: Identifiable, Equatable {
        var id = UUID()
        var existingID: UUID?
        var title = ""
        /// Empty until you type it: a default like 10 turned one-off steps into "0 / 10".
        var target: Double?
        var unit = ""
    }

    var existingID: UUID?
    var title = ""
    var projectID: UUID?
    var why = ""
    var startDate = Calendar.current.startOfDay(for: Date())
    var deadline = Calendar.current.date(byAdding: .day, value: 30, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    var isBossFight = false
    var keyResults: [KeyResultDraft] = [KeyResultDraft()]

    init(projectID: UUID? = nil) {
        self.projectID = projectID
    }

    init(goal: ProjectGoal) {
        existingID = goal.id
        title = goal.title
        projectID = goal.projectID
        why = goal.why ?? ""
        startDate = goal.startDate
        deadline = goal.deadline
        isBossFight = goal.isBossFight
        keyResults = goal.sortedKeyResults.map {
            KeyResultDraft(existingID: $0.id, title: $0.title, target: $0.target, unit: $0.unit ?? "")
        }
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var validKeyResults: [KeyResultDraft] { keyResults.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty } }
    /// Every key result you named needs a number: a goal is measured in counts.
    var missingTargets: Bool { validKeyResults.contains { ($0.target ?? 0) < 1 } }
    var isValid: Bool { !trimmedTitle.isEmpty && deadline > startDate && !missingTargets }
    /// Nothing entered: the project form treats an untouched draft as "no goal".
    var isEmpty: Bool { trimmedTitle.isEmpty && validKeyResults.isEmpty }

    /// Creates or updates the goal; key results removed from the draft are deleted with their entries.
    @MainActor
    @discardableResult
    func apply(in context: ModelContext, existing: ProjectGoal?) -> ProjectGoal {
        let goal = existing ?? {
            let created = ProjectGoal(title: trimmedTitle, projectID: projectID, startDate: startDate, deadline: deadline)
            context.insert(created)
            return created
        }()
        goal.title = trimmedTitle
        goal.projectID = projectID
        let trimmedWhy = why.trimmingCharacters(in: .whitespacesAndNewlines)
        goal.why = trimmedWhy.isEmpty ? nil : trimmedWhy
        goal.startDate = startDate
        goal.deadline = deadline
        goal.isBossFight = isBossFight

        let keep = Set(validKeyResults.compactMap(\.existingID))
        for kr in goal.keyResults where !keep.contains(kr.id) {
            context.delete(kr)
        }
        var results: [GoalKeyResult] = []
        for (index, draft) in validKeyResults.enumerated() {
            let unit = draft.unit.trimmingCharacters(in: .whitespaces)
            if let id = draft.existingID, let kr = goal.keyResults.first(where: { $0.id == id }) {
                kr.title = draft.title.trimmingCharacters(in: .whitespaces)
                kr.kindRaw = GoalKeyResultKind.count.rawValue
                kr.target = max(1, draft.target ?? 1)
                kr.unit = unit.isEmpty ? nil : unit
                kr.order = index
                results.append(kr)
            } else {
                let kr = GoalKeyResult(
                    title: draft.title.trimmingCharacters(in: .whitespaces), kind: .count, target: max(1, draft.target ?? 1),
                    unit: unit.isEmpty ? nil : unit, order: index
                )
                context.insert(kr)
                results.append(kr)
            }
        }
        goal.keyResults = results
        return goal
    }
}

/// The fields of a goal (used by the goal sheet and the project form).
struct GoalEditorFields: View {
    @Binding var draft: GoalDraft
    var projects: [Project] = []
    var showsProject = true

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpace.l) {
            field("What do you want to get done?") {
                TextField("e.g. Interview-ready for data roles", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(alignment: .top, spacing: FFSpace.l) {
                if showsProject {
                    field("Project") {
                        Picker("Project", selection: $draft.projectID) {
                            Text("None").tag(UUID?.none)
                            ForEach(projects) { project in
                                Label(project.name, systemImage: project.icon ?? "folder.fill").tag(Optional(project.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    }
                }
                field("Starts") {
                    DatePicker("Starts", selection: $draft.startDate, displayedComponents: .date).labelsHidden()
                }
                field("Deadline") {
                    DatePicker("Deadline", selection: $draft.deadline, in: draft.startDate.addingTimeInterval(86_400)..., displayedComponents: .date)
                        .labelsHidden()
                }
            }
            quickDeadlines
            Toggle(isOn: $draft.isBossFight) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Make this my main goal").ffText(.body)
                    Text("Today's suggestions and the coach lean on it first.").ffText(.caption)
                }
            }
            .toggleStyle(.switch)
            keyResultsEditor
            field("Why it matters (optional)") {
                TextField("What changes when this is done?", text: $draft.why, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
            }
        }
    }

    private var quickDeadlines: some View {
        HStack(spacing: FFSpace.s) {
            Text("Deadline in").ffText(.caption)
            ForEach([(7, "1 week"), (14, "2 weeks"), (30, "1 month"), (90, "3 months")], id: \.0) { days, label in
                Button(label) {
                    draft.deadline = Calendar.current.date(byAdding: .day, value: days, to: draft.startDate) ?? draft.deadline
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
        }
    }

    private var keyResultsEditor: some View {
        VStack(alignment: .leading, spacing: FFSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("How will you measure it?").ffText(.headline)
                    Text("A number you'll count up to. Each day the goal shows how many keep you on pace.").ffText(.caption)
                }
                Spacer()
                Button {
                    draft.keyResults.append(.init())
                } label: {
                    Label("Add a Number", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if !draft.keyResults.isEmpty {
                // Column names, so three bare fields read as "60 · LeetCode · questions".
                HStack(spacing: FFSpace.s) {
                    Text("Target").frame(width: 56, alignment: .trailing)
                    Text("What you count").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Unit (optional)").frame(width: 100, alignment: .leading)
                    Color.clear.frame(width: 30, height: 1)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            ForEach($draft.keyResults) { $kr in
                HStack(spacing: FFSpace.s) {
                    TextField("60", value: $kr.target, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("How many")
                    TextField("LeetCode", text: $kr.title)
                        .textFieldStyle(.roundedBorder)
                    TextField("questions", text: $kr.unit)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .accessibilityLabel("Unit")
                    Button {
                        draft.keyResults.removeAll { $0.id == kr.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this number")
                }
            }
            if draft.keyResults.isEmpty {
                Text("Without a number the goal can't show a pace. Add one: “60 LeetCode questions”, “3 referral asks”.").ffText(.caption)
            }
            if draft.missingTargets {
                Label("Give each one a target number.", systemImage: "exclamationmark.triangle.fill")
                    .ffText(.caption)
                    .foregroundStyle(FFPalette.atRisk)
            }
            // Goals count; one-off steps ("Book the call with Rik") are tasks on Today.
            Text("Single steps (“Book the call with Rik”) are tasks, not goals. A task linked to a number adds 1 when you tick it.")
                .ffText(.caption)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }
}

/// Sheet to create or edit a goal.
struct GoalFormView: View {
    let goal: ProjectGoal?
    var defaultProjectID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt) private var projects: [Project]
    @State private var draft = GoalDraft()
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: FFSpace.l) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal == nil ? "New goal" : "Edit goal").ffText(.title3)
                        Text("Something you want done by a date, and the number that proves it.").ffText(.callout)
                    }
                    GoalEditorFields(draft: $draft, projects: projects)
                }
                .padding(FFSpace.xl)
            }
            Divider()
            HStack(spacing: FFSpace.s) {
                if let goal {
                    Button("Delete…", role: .destructive) { confirmDelete = true }
                    Button(goal.status == .active ? "Mark done" : "Reopen") {
                        goal.status = goal.status == .active ? .done : .active
                        try? modelContext.save()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    draft.apply(in: modelContext, existing: goal)
                    try? modelContext.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!draft.isValid)
            }
            .padding(FFSpace.l)
        }
        .frame(width: 620, height: 600)
        .onAppear {
            draft = goal.map(GoalDraft.init(goal:)) ?? GoalDraft(projectID: defaultProjectID)
        }
        .confirmationDialog("Delete \(goal?.title ?? "goal")?", isPresented: $confirmDelete) {
            Button("Delete goal and its progress", role: .destructive) {
                if let goal { modelContext.delete(goal) }
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("Its key results and logged progress are deleted. Focus sessions are kept.")
        }
    }
}
