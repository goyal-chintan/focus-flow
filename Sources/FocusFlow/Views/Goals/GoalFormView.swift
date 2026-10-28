import SwiftUI
import SwiftData

/// Editable copy of a goal and its key results; applied to SwiftData on save.
struct GoalDraft: Equatable {
    struct KeyResultDraft: Identifiable, Equatable {
        var id = UUID()
        var existingID: UUID?
        var title = ""
        var kind: GoalKeyResultKind = .count
        var target: Double = 10
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
            KeyResultDraft(existingID: $0.id, title: $0.title, kind: $0.kind, target: $0.target, unit: $0.unit ?? "")
        }
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var validKeyResults: [KeyResultDraft] { keyResults.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty } }
    var isValid: Bool { !trimmedTitle.isEmpty && deadline > startDate }
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
                kr.kindRaw = draft.kind.rawValue
                kr.target = draft.kind == .checkbox ? 1 : max(1, draft.target)
                kr.unit = draft.kind == .checkbox || unit.isEmpty ? nil : unit
                kr.order = index
                results.append(kr)
            } else {
                let kr = GoalKeyResult(
                    title: draft.title.trimmingCharacters(in: .whitespaces), kind: draft.kind, target: draft.target,
                    unit: draft.kind == .checkbox || unit.isEmpty ? nil : unit, order: index
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
            field("Goal") {
                TextField("e.g. Apply for jobs by 28 Nov", text: $draft.title)
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
                    Text("This month's boss fight").ffText(.body)
                    Text("Your one main goal. Today's levers and the coach lean on it first.").ffText(.caption)
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
            Text("Quick:").ffText(.caption)
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
            HStack {
                Text("Key results").ffText(.headline)
                Text("How you'll know it's done").ffText(.caption)
                Spacer()
                Button {
                    draft.keyResults.append(.init())
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ForEach($draft.keyResults) { $kr in
                HStack(spacing: FFSpace.s) {
                    Picker("Kind", selection: $kr.kind) {
                        Image(systemName: "number").tag(GoalKeyResultKind.count).help("A number to reach")
                        Image(systemName: "checkmark.square").tag(GoalKeyResultKind.checkbox).help("Done or not")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 70)
                    if kr.kind == .count {
                        TextField("60", value: $kr.target, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 56)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Target")
                    }
                    TextField(kr.kind == .count ? "LeetCode" : "Apply for 10 jobs", text: $kr.title)
                        .textFieldStyle(.roundedBorder)
                    if kr.kind == .count {
                        TextField("questions", text: $kr.unit)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .accessibilityLabel("Unit")
                    }
                    Button {
                        draft.keyResults.removeAll { $0.id == kr.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove key result")
                }
            }
            if draft.keyResults.isEmpty {
                Text("Add at least one: \"60 LeetCode questions\", \"Ask for 3 referrals\", \"Apply\".").ffText(.caption)
            }
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
                        Text("A deadline and the results that prove it. The app tracks whether you're on pace.").ffText(.callout)
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
