import SwiftUI
import SwiftData

/// Settings → Distractions (coach v8 §3.3): what each app is *for each project*. A cell shows the
/// role and who decided it (you, learned from your blocks, or the default); its menu changes it
/// for that project only. Global rules stay in the lists below.
struct AppsByProjectSection: View {
    @Environment(TimerViewModel.self) private var timerVM
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.name) private var projects: [Project]
    // Re-draws when a role is set.
    @Query private var records: [AppRoleRuleRecord]
    @Query private var items: [IdleDistractionItem]

    static let maxRows = 12

    var body: some View {
        let book = timerVM.appRoleBook()
        let names = timerVM.appRoleNames()
        let rows = Self.rows(book: book, records: records)
        Section {
            if rows.isEmpty || projects.isEmpty {
                Text("Apps show up here once they've been open in your blocks.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        Text("App").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(projects) { project in
                            Text(project.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    ForEach(rows, id: \.self) { key in
                        GridRow {
                            Text(names[key] ?? key).font(.system(size: 12)).lineLimit(1).frame(minWidth: 110, alignment: .leading)
                            ForEach(projects) { project in
                                roleCell(key: key, name: names[key] ?? key, project: project, book: book)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Apps by project")
        } footer: {
            Text("Slack can be work for Office and a pull during Learning. Learned roles come from time inside a project's blocks (an hour over 3 days); yours always win.")
        }
    }

    private func roleCell(key: String, name: String, project: Project, book: AppRoleBook) -> some View {
        let area = AreaGroup.of(project.areaRaw == nil ? nil : project.area)
        let decision = book.role(key: key, name: name, in: .project(project.id, area))
        return Menu {
            ForEach([AppRole.tool, .pull], id: \.self) { role in
                Button("\(role.title) in \(project.name)") {
                    timerVM.setAppRole(key: key, kind: AppRoleBook.isHost(key) ? .website : .app, name: name, scope: .project(project.id), role: role)
                }
            }
            if decision.source == .user {
                Divider()
                Button("Back to default") {
                    timerVM.setAppRole(key: key, kind: AppRoleBook.isHost(key) ? .website : .app, name: name, scope: .project(project.id), role: .neutral)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle().fill(color(decision.role)).frame(width: 7, height: 7)
                Text(decision.role.title).font(.system(size: 11, weight: .medium))
                Text(decision.source.title).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(minHeight: 30)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(decision.reason)
        .accessibilityLabel("\(name) in \(project.name): \(decision.role.title), \(decision.source.title). \(decision.reason)")
    }

    private func color(_ role: AppRole) -> Color {
        switch role {
        case .tool: FFPalette.goal
        case .pull: FFPalette.atRisk
        case .neutral: Color.secondary.opacity(0.5)
        }
    }

    /// The apps with the most block time, plus any with a per-project rule.
    static func rows(book: AppRoleBook, records: [AppRoleRuleRecord]) -> [String] {
        let byMinutes = book.evidence
            .map { (key: $0.key, minutes: $0.value.values.map(\.minutes).reduce(0, +)) }
            .filter { $0.minutes >= 10 && !AppUsageTracker.isIgnoredSystemBundleIdentifier($0.key) && !AppRoleBook.isBrowser($0.key) }
            .sorted { $0.minutes > $1.minutes }
            .map(\.key)
        var keys: [String] = []
        for key in records.map(\.key) + byMinutes where !keys.contains(key) { keys.append(key) }
        return Array(keys.prefix(maxRows))
    }
}
