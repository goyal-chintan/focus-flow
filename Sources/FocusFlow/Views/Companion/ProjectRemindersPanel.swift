import AppKit
import EventKit
import SwiftData
import SwiftUI

/// A project's Reminders list, under its tasks (project tasks redesign 2026-11-02). It names the
/// list that feeds the project, says why nothing shows when nothing can (sync off, no access, no
/// list, list gone) with the one action that fixes it, and lists the project's later tasks (every
/// reminder is imported on its due day) with "Do Today", so nothing in the list is out of sight.
/// "Add to a Goal…" picks any of them into a goal's number.
struct ProjectRemindersPanel: View {
    let project: Project

    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Project> { !$0.archived }) private var projects: [Project]

    @State private var link: TimerViewModel.ProjectReminderLink?
    @State private var lists: [(id: String, title: String, source: String)] = []
    @State private var upcoming: [DailyTask] = []
    @State private var pickingIntoGoal = false
    @Query(sort: \ProjectGoal.deadline) private var goals: [ProjectGoal]
    @State private var showsUpcoming = true
    @State private var syncing = false
    @State private var syncedAt: Date?

    private static let newListTag = "focusflow.new-list"

    /// Reloads when the project's list, the sync toggle or today's tasks change.
    private struct ReloadKey: Hashable {
        let projectID: UUID
        let listID: String?
        let syncOn: Bool
        let revision: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpace.m) {
            statusRow
            if !upcoming.isEmpty {
                upcomingList
            }
        }
        .sheet(isPresented: $pickingIntoGoal) { GoalTaskPickerSheet(projectID: project.id) }
        .task(id: ReloadKey(projectID: project.id, listID: project.reminderListID,
                            syncOn: timerVM.remindersSyncOn, revision: timerVM.dailyTaskRevision)) {
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await reload() }
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusRow: some View {
        switch link {
        case nil:
            EmptyView()
        case .linked(let title):
            row(symbol: "checklist", tint: FFPalette.accent,
                title: "From Reminders: “\(title)”",
                detail: "Every reminder in it is one of \(project.name)'s tasks: today's above, later ones below on their day. Ticks, edits and new tasks sync both ways.\(syncedLine)") {
                if hasGoal {
                    Button("Add to a Goal…") { pickingIntoGoal = true }
                        .buttonStyle(.bordered)
                        .help("Pick reminders that count toward one of \(project.name)'s goals")
                }
                syncButton
                moreMenu
            }
        case .notLinked:
            row(symbol: "checklist", tint: .secondary,
                title: "Bring in a Reminders list",
                detail: "Pick the list that holds \(project.name)'s to-dos. Its reminders show up here as tasks.") {
                listMenu(label: "Choose list…")
            }
        case .listMissing:
            row(symbol: "exclamationmark.triangle.fill", tint: FFPalette.atRisk,
                title: "The linked Reminders list is gone",
                detail: "It was deleted or moved to another account, so nothing comes in. Choose another list.") {
                listMenu(label: "Choose list…")
            }
        case .syncOff:
            row(symbol: "checklist", tint: .secondary,
                title: "Reminders sync is off",
                detail: "Turn it on to see \(project.name)'s reminders here as tasks.") {
                Button("Turn On…") {
                    UserDefaults.standard.set(SettingsTab.integrations.rawValue, forKey: "settingsRequestedTab")
                    timerVM.openSettingsScene?()
                }
                .buttonStyle(.bordered)
                .help("Opens Settings ▸ Permissions & Sync")
            }
        case .noAccess:
            row(symbol: "lock.fill", tint: FFPalette.atRisk,
                title: "FocusFlow can't read Reminders",
                detail: "Allow it in System Settings ▸ Privacy & Security ▸ Reminders, then come back.") {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var hasGoal: Bool { goals.contains { $0.projectID == project.id && $0.status == .active } }

    private var syncedLine: String {
        guard let syncedAt else { return "" }
        return " Checked \(syncedAt.formatted(date: .omitted, time: .shortened))."
    }

    private func row<Actions: View>(
        symbol: String, tint: Color, title: String, detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: FFSpace.m) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).ffText(.headline).lineLimit(2)
                Text(detail).ffText(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: FFSpace.s)
            HStack(spacing: FFSpace.xs) { actions() }
        }
        .accessibilityElement(children: .contain)
    }

    private var syncButton: some View {
        Button(action: syncNow) {
            HStack(spacing: 6) {
                if syncing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise").accessibilityHidden(true)
                }
                Text("Sync Now")
            }
        }
        .buttonStyle(.bordered)
        .disabled(syncing)
        .help("Fetch this list from Reminders now")
    }

    private var moreMenu: some View {
        Menu {
            Menu("Change List") { listItems }
            Button("Open Reminders") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app"))
            }
            Divider()
            Button("Stop Syncing", role: .destructive) { timerVM.setReminderList(nil, for: project) }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More Reminders options")
        .accessibilityLabel("More Reminders options")
    }

    private func listMenu(label: String) -> some View {
        Menu(label) { listItems }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .fixedSize()
    }

    /// Lists no other project syncs (one list feeds one project), plus a new one for this project.
    @ViewBuilder
    private var listItems: some View {
        let taken = Set(projects.filter { $0.id != project.id }.compactMap(\.reminderListID))
        let free = lists.filter { !taken.contains($0.id) }
        ForEach(free, id: \.id) { list in
            let title = list.source.isEmpty ? list.title : "\(list.title) · \(list.source)"
            if list.id == project.reminderListID {
                Button { } label: { Label(title, systemImage: "checkmark") }
            } else {
                Button(title) { timerVM.setReminderList(list.id, for: project) }
            }
        }
        if !free.isEmpty { Divider() }
        Button("New List “FocusFlow · \(project.name)”") {
            if let id = RemindersService.shared.createList(title: "FocusFlow · \(project.name)") {
                timerVM.setReminderList(id, for: project)
            }
        }
    }

    // MARK: Upcoming

    private var upcomingList: some View {
        VStack(alignment: .leading, spacing: 2) {
            // The whole row toggles, not just the chevron.
            Button {
                withAnimation(FFAnimation.gated(FFAnimation.control, reduceMotion: reduceMotion)) { showsUpcoming.toggle() }
            } label: {
                HStack(spacing: FFSpace.s) {
                    Text("Later").ffText(.headline)
                    Text("\(upcoming.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .frame(minHeight: 18)
                        .background(Capsule().fill(FFPalette.track))
                    Text("Due after today. Bring one in when you want to do it now.")
                        .ffText(.caption)
                        .lineLimit(1)
                    Spacer(minLength: FFSpace.s)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showsUpcoming ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Later, \(upcoming.count)")
            .accessibilityHint(showsUpcoming ? "Hide" : "Show")

            if showsUpcoming {
                ForEach(upcoming) { item in
                    upcomingRow(item)
                }
                .transition(.opacity)
            }
        }
    }

    private func upcomingRow(_ task: DailyTask) -> some View {
        let result = task.keyResultID.flatMap { id in goals.flatMap(\.keyResults).first { $0.id == id } }
        return HStack(spacing: FFSpace.s) {
            Image(systemName: "circle")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(task.title).ffText(.body).lineLimit(2).help(task.title)
                    if task.reminderID != nil {
                        Image(systemName: "checklist")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Synced with Reminders")
                    }
                }
                if let result {
                    Label("Counts toward \(result.title)", systemImage: "target").ffText(.caption)
                }
            }
            Spacer(minLength: FFSpace.s)
            Text(Self.dueLabel(task.day))
                .ffText(.caption)
                .monospacedDigit()
            Button("Do Today") {
                withAnimation(FFAnimation.gated(FFAnimation.control, reduceMotion: reduceMotion)) {
                    timerVM.moveDailyTaskToToday(task)
                    upcoming.removeAll { $0.id == task.id }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(task.reminderID == nil ? "Move it to today" : "Move it to today. Its due date in Reminders moves to today too.")
            .accessibilityLabel("Do \(task.title) today")
        }
        .padding(.horizontal, FFSpace.xs)
        .frame(minHeight: 34)
        .ffHoverRow()
    }

    /// "Tomorrow", "Thu 6 Nov".
    static func dueLabel(_ due: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInTomorrow(due) { return "Tomorrow" }
        return due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    // MARK: Loading

    private func reload() async {
        link = timerVM.reminderLink(for: project)
        lists = timerVM.reminderBridge.reminderLists()
        upcoming = timerVM.laterTasks(forProject: project.id)
    }

    private func syncNow() {
        syncing = true
        Task {
            await timerVM.syncReminders()
            await reload()
            syncedAt = Date()
            syncing = false
        }
    }
}
