import SwiftUI
import SwiftData

/// Editable copy of a project (priorities-goals design §3.1, §3.6).
struct ProjectDraft {
    var name = ""
    var color = "blue"
    var icon = "folder.fill"
    var blockProfiles: [BlockProfile] = []
    var workMode: WorkMode = .deepWork
    var guardianSensitivity: GuardianSensitivity = .normal
    var difficultyBias: DifficultyBias = .moderate
    var area: ProjectArea = .personal
    var rank: Int?
    /// 0 = no target.
    var dailyTargetMinutes = 0
    var weekdaysOnly = false
    var purpose = ""
    /// The Reminders list synced with this project's tasks (nil = none).
    var reminderListID: String?
    /// "New list": create "FocusFlow · <name>" in Reminders on save (never on cancel).
    var createsReminderList = false
    /// New project, or a project without an active goal: also create this goal on save.
    var addsGoal = false
    var goal = GoalDraft()

    init() {}

    init(project: Project) {
        name = project.name
        color = project.color
        icon = project.icon ?? "folder.fill"
        blockProfiles = project.effectiveBlockProfiles
        workMode = project.workMode
        guardianSensitivity = project.guardianSensitivity
        difficultyBias = project.difficultyBias
        area = project.areaRaw == nil ? .other : project.area
        rank = project.priorityRank
        dailyTargetMinutes = project.dailyTargetMinutes ?? 0
        weekdaysOnly = project.targetWeekdaysOnly ?? false
        purpose = project.purpose ?? ""
        reminderListID = project.reminderListID
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    var isValid: Bool { !trimmedName.isEmpty && (!addsGoal || goal.isValid) }

    /// Writes the draft to `project`. Taking a rank that another project holds moves the others down.
    @MainActor
    func apply(to project: Project, others: [Project], in context: ModelContext) {
        project.name = trimmedName
        project.color = color
        project.icon = icon
        var seen = Set<UUID>()
        let profiles = blockProfiles.filter { seen.insert($0.id).inserted }
        project.blockProfiles = profiles
        project.blockProfile = profiles.first
        project.workMode = workMode
        project.guardianSensitivity = guardianSensitivity
        project.difficultyBias = difficultyBias
        project.area = area
        if let rank, project.priorityRank != rank {
            let rivals = others.filter { $0.id != project.id && !$0.archived }
            if rivals.contains(where: { $0.priorityRank == rank }) {
                for other in rivals {
                    if let r = other.priorityRank, r >= rank { other.priorityRank = r + 1 }
                }
            }
        }
        project.priorityRank = rank
        project.dailyTargetMinutes = dailyTargetMinutes > 0 ? dailyTargetMinutes : nil
        project.targetWeekdaysOnly = dailyTargetMinutes > 0 ? weekdaysOnly : nil
        let why = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        project.purpose = why.isEmpty ? nil : why
        let previousList = project.reminderListID
        if createsReminderList {
            let title = "FocusFlow · \(trimmedName)"
            project.reminderListID = RemindersService.shared.reminderLists().first { $0.title == title }?.id
                ?? RemindersService.shared.createList(title: title)
        } else {
            project.reminderListID = (reminderListID ?? "").isEmpty ? nil : reminderListID
        }
        if project.reminderListID != previousList {
            // Switched or stopped syncing: the tasks keep their titles but no longer mirror the old
            // list, so ticks and deletes never reach it.
            let projectID = project.id
            let linked = (try? context.fetch(FetchDescriptor<DailyTask>(predicate: #Predicate { $0.projectID == projectID && $0.reminderID != nil }))) ?? []
            for task in linked { task.reminderID = nil }
        }
        if addsGoal && goal.isValid {
            var goalDraft = goal
            goalDraft.projectID = project.id
            goalDraft.apply(in: context, existing: nil)
        }
    }
}

struct ProjectFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var draft: ProjectDraft
    /// The project being edited (nil when creating).
    let project: Project?
    let title: String
    let onSave: () -> Void

    @Query(sort: \BlockProfile.createdAt) private var blockProfiles: [BlockProfile]
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt) private var projects: [Project]
    @Query private var allSettings: [AppSettings]
    @State private var showProtection = false
    @State private var reminderLists: [(id: String, title: String, source: String)] = []

    private let colors: [(name: String, color: Color)] = [
        ("blue", .blue), ("indigo", .indigo), ("purple", .purple),
        ("pink", .pink), ("red", .red), ("orange", .orange),
        ("yellow", .yellow), ("green", .green), ("teal", .teal),
        ("mint", .mint)
    ]

    private let icons = [
        "folder.fill", "laptopcomputer", "book.fill", "hammer.fill",
        "paintbrush.fill", "music.note", "heart.fill", "star.fill",
        "bolt.fill", "leaf.fill", "brain.head.profile", "trophy.fill",
        "figure.run", "cup.and.saucer.fill", "briefcase.fill", "graduationcap.fill"
    ]

    private var tint: Color { FFPalette.project(draft.color) }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: FFSpace.l) {
                    identityCard
                    areaCard
                    priorityCard
                    purposeCard
                    targetCard
                    if remindersOn {
                        remindersCard
                    }
                    // A new project can start with its goal; existing goals are edited in the Goals tab.
                    if project == nil {
                        goalCard
                    }
                    protectionCard
                }
                .padding(FFSpace.xl)
            }
            Divider()
            actionBar
        }
        .frame(width: 560, height: 720)
        .background(FFPalette.windowBackground)
    }

    // MARK: Identity

    private var identityCard: some View {
        card {
            HStack(alignment: .center, spacing: FFSpace.m) {
                Image(systemName: draft.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.16)))
                    .animation(reduceMotion ? nil : FFAnimation.control, value: draft.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).ffText(.caption)
                    TextField("Project name, e.g. Interview prep", text: $draft.name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .semibold))
                }
            }
            HStack(spacing: 8) {
                ForEach(colors, id: \.name) { item in
                    Button {
                        draft.color = item.name
                    } label: {
                        Circle()
                            .fill(item.color)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(item.name == draft.color ? 0.85 : 0), lineWidth: 2).padding(-3))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(item.name.capitalized)
                    .accessibilityLabel("\(item.name.capitalized)\(item.name == draft.color ? ", selected" : "")")
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 32, maximum: 32), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(icons, id: \.self) { symbol in
                    Button {
                        draft.icon = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(symbol == draft.icon ? tint : .secondary)
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(symbol == draft.icon ? tint.opacity(0.16) : FFPalette.track))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(symbol) icon\(symbol == draft.icon ? ", selected" : "")")
                }
            }
        }
    }

    // MARK: Area

    private var areaCard: some View {
        card(title: "What kind of work is it?", subtitle: "Personal and learning time counts as your own work in the daily breakdown.") {
            HStack(spacing: FFSpace.s) {
                ForEach(ProjectArea.allCases) { area in
                    Button {
                        draft.area = area
                        if area == .work && draft.dailyTargetMinutes > 0 { draft.weekdaysOnly = true }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: area.symbol).font(.system(size: 16, weight: .semibold))
                            Text(area.title).font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(draft.area == area ? tint : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(draft.area == area ? tint.opacity(0.14) : FFPalette.track)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(draft.area == area ? tint.opacity(0.6) : .clear, lineWidth: 1.5)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(area.title)\(draft.area == area ? ", selected" : "")")
                }
            }
        }
    }

    // MARK: Priority

    private var priorityCard: some View {
        let others = projects.filter { $0.id != project?.id && $0.priorityRank != nil }.sorted { ($0.priorityRank ?? 99) < ($1.priorityRank ?? 99) }
        return card(title: "Priority", subtitle: "#1 is where most of your focus should go. The coach starts there.") {
            HStack(spacing: 6) {
                ForEach([1, 2, 3, 4, 5], id: \.self) { rank in
                    rankButton(String("#\(rank)"), selected: draft.rank == rank) { draft.rank = rank }
                }
                rankButton("None", selected: draft.rank == nil) { draft.rank = nil }
            }
            if !others.isEmpty {
                Text(others.map { "#\($0.priorityRank ?? 0) \($0.name)" }.joined(separator: " · "))
                    .ffText(.caption)
            }
            if let moves = rankMoves(others) {
                Label(moves, systemImage: "arrow.down")
                    .ffText(.caption)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    /// "Learning moves to #2" (and any below it), mirroring `ProjectDraft.apply`.
    private func rankMoves(_ others: [Project]) -> String? {
        guard let rank = draft.rank, project?.priorityRank != rank, others.contains(where: { $0.priorityRank == rank }) else { return nil }
        let moved = others.filter { ($0.priorityRank ?? 0) >= rank }
        guard let first = moved.first else { return nil }
        let rest = moved.dropFirst().map { "\($0.name) to #\(($0.priorityRank ?? 0) + 1)" }
        return (["\(first.name) moves to #\((first.priorityRank ?? 0) + 1)"] + rest).joined(separator: ", ")
    }

    // MARK: Reminders

    private var remindersOn: Bool {
        allSettings.first?.remindersIntegrationEnabled == true && RemindersService.shared.authStatus == .authorized
    }

    private static let newListTag = "focusflow.new-list"

    /// Lists no other project syncs (one list feeds one project), plus this project's own.
    private var freeLists: [(id: String, title: String, source: String)] {
        let taken = Set(projects.filter { $0.id != project?.id }.compactMap(\.reminderListID))
        return reminderLists.filter { !taken.contains($0.id) }
    }

    /// One list per project: its reminders due today, overdue or undated become this project's
    /// tasks, and changes go back.
    private var remindersCard: some View {
        card(title: "Reminders list", subtitle: "Reminders in it that are due today, overdue or undated show up as this project's tasks. Ticks, new tasks, moves and deletes sync back.") {
            Picker("List", selection: Binding(
                get: { draft.createsReminderList ? Self.newListTag : (draft.reminderListID ?? "") },
                set: { tag in
                    draft.createsReminderList = tag == Self.newListTag
                    draft.reminderListID = tag.isEmpty || tag == Self.newListTag ? nil : tag
                }
            )) {
                Text("Don't sync").tag("")
                ForEach(freeLists, id: \.id) { list in
                    Text(list.source.isEmpty ? list.title : "\(list.title) · \(list.source)").tag(list.id)
                }
                if let id = draft.reminderListID, !reminderLists.contains(where: { $0.id == id }) {
                    Text("List missing").tag(id)
                }
                if !draft.trimmedName.isEmpty {
                    Divider()
                    Text("New list “FocusFlow · \(draft.trimmedName)”").tag(Self.newListTag)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 320, alignment: .leading)
        }
        .onAppear { reminderLists = RemindersService.shared.reminderLists() }
    }

    // MARK: Why

    private var purposeCard: some View {
        card(title: "Why it matters", subtitle: "One line. It shows on the project, so hard days have a reason.") {
            TextField("e.g. Interview-ready for a senior data role", text: $draft.purpose)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private func rankButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        if selected {
            Button(label, action: action)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(tint)
                .accessibilityLabel("Priority \(label), selected")
        } else {
            Button(label, action: action)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .accessibilityLabel("Priority \(label)")
        }
    }

    // MARK: Target

    private var targetCard: some View {
        card(title: "Daily time target", subtitle: "How much focus this should get on a normal day. The breakdown and drift report measure against it.") {
            HStack(spacing: FFSpace.m) {
                Text(draft.dailyTargetMinutes == 0 ? "No target" : FFFormat.duration(TimeInterval(draft.dailyTargetMinutes * 60)))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 110, alignment: .leading)
                    .contentTransition(.numericText())
                Stepper("Daily target", value: $draft.dailyTargetMinutes, in: 0...720, step: 15)
                    .labelsHidden()
                Spacer()
                Toggle("Weekdays only", isOn: $draft.weekdaysOnly)
                    .toggleStyle(.checkbox)
                    .disabled(draft.dailyTargetMinutes == 0)
            }
            HStack(spacing: 6) {
                ForEach([30, 60, 120, 180, 240], id: \.self) { minutes in
                    Button(FFFormat.duration(TimeInterval(minutes * 60))) {
                        withAnimation(FFAnimation.gated(FFAnimation.control, reduceMotion: reduceMotion)) { draft.dailyTargetMinutes = minutes }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            if draft.dailyTargetMinutes > 0 {
                let days = draft.weekdaysOnly ? 5 : 7
                Text("≈ \(FFFormat.duration(TimeInterval(draft.dailyTargetMinutes * 60 * days))) a week")
                    .ffText(.caption)
            }
        }
    }

    // MARK: Goal

    private var goalCard: some View {
        card(title: "Goal", subtitle: "A deadline and the results that prove it. You'll see if you're on pace.") {
            Toggle("Set a goal with a deadline", isOn: $draft.addsGoal.animation(FFAnimation.gated(FFAnimation.control, reduceMotion: reduceMotion)))
                .toggleStyle(.switch)
            if draft.addsGoal {
                GoalEditorFields(draft: $draft.goal, showsProject: false)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Focus protection (existing settings, collapsed)

    private var protectionCard: some View {
        card {
            DisclosureGroup(isExpanded: $showProtection) {
                VStack(alignment: .leading, spacing: FFSpace.s) {
                    blockProfileSection
                    workModeSection
                    guardianSensitivitySection
                    difficultyBiasSection
                }
                .padding(.top, FFSpace.s)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus protection").ffText(.headline)
                    Text("Blocking, work mode and coach sensitivity").ffText(.caption)
                }
            }
        }
    }

    private var blockProfileSection: some View {
        menuRow("Block profiles", value: selectedBlockProfilesLabel, symbol: "shield.checkered") {
            Button("Clear all") { draft.blockProfiles = [] }
            Divider()
            ForEach(blockProfiles) { profile in
                Button {
                    toggleBlockProfile(profile)
                } label: {
                    Label(profile.name + (profile.isDefault ? " (Default)" : ""), systemImage: isProfileSelected(profile) ? "checkmark.circle.fill" : "circle")
                }
            }
        }
    }

    private var workModeSection: some View {
        menuRow("Work mode", value: draft.workMode.displayName, symbol: draft.workMode.icon) {
            ForEach(WorkMode.allCases, id: \.self) { mode in
                Button { draft.workMode = mode } label: { Label(mode.displayName, systemImage: mode.icon) }
            }
        }
    }

    private var guardianSensitivitySection: some View {
        menuRow("Coach sensitivity", value: draft.guardianSensitivity.displayName, symbol: "sensor.tag.radiowaves.forward") {
            ForEach(GuardianSensitivity.allCases, id: \.self) { value in
                Button(value.displayName) { draft.guardianSensitivity = value }
            }
        }
    }

    private var difficultyBiasSection: some View {
        menuRow("Difficulty bias", value: draft.difficultyBias.displayName, symbol: "dial.medium") {
            ForEach(DifficultyBias.allCases, id: \.self) { value in
                Button(value.displayName) { draft.difficultyBias = value }
            }
        }
    }

    /// A dropdown row whose whole width opens the menu.
    private func menuRow<Content: View>(_ label: String, value: String, symbol: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: FFSpace.s) {
                Label(label, systemImage: symbol).ffText(.body)
                Spacer(minLength: FFSpace.s)
                Text(value).ffText(.callout).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous).fill(FFPalette.track))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.visible)
    }

    private var selectedBlockProfilesLabel: String {
        let names = draft.blockProfiles.map(\.name)
        if names.isEmpty { return "None" }
        if names.count == 1 { return names[0] }
        return "\(names.count) profiles"
    }

    private func isProfileSelected(_ profile: BlockProfile) -> Bool {
        draft.blockProfiles.contains { $0.id == profile.id }
    }

    private func toggleBlockProfile(_ profile: BlockProfile) {
        if let index = draft.blockProfiles.firstIndex(where: { $0.id == profile.id }) {
            draft.blockProfiles.remove(at: index)
        } else {
            draft.blockProfiles.append(profile)
        }
    }

    // MARK: Chrome

    private var actionBar: some View {
        HStack {
            if !draft.isValid && !draft.trimmedName.isEmpty && draft.addsGoal {
                Text("The goal needs a name and a deadline after its start.").ffText(.caption)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                onSave()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .disabled(!draft.isValid)
        }
        .padding(FFSpace.l)
    }

    private func card<Content: View>(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: FFSpace.m) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).ffText(.headline)
                    if let subtitle { Text(subtitle).ffText(.caption).fixedSize(horizontal: false, vertical: true) }
                }
            }
            content()
        }
        .padding(FFSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ffSurface()
    }
}
