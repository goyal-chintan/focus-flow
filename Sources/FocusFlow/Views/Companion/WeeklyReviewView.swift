import SwiftUI

/// Coach v8 §3.5: the 5-minute weekly review, as a sheet over the companion window. Four steps,
/// each a recorded answer: last week, one pick, next week's plan, one line on what's in the way.
/// Nothing is written until Finish, so closing early changes nothing.
struct WeeklyReviewView: View {
    @Environment(TimerViewModel.self) private var timerVM
    let now: Date
    let close: () -> Void

    @State private var step = 0
    @State private var pickID: String?
    @State private var rows: [PlanRow] = []
    @State private var obstacle = ""
    @State private var finished: WeeklyReviewRecord?
    @State private var recs: [LifeRecommendation] = []

    struct PlanRow: Identifiable {
        let day: Date
        let type: DayType
        let existing: [Date]
        var on: Bool
        var time: Date
        var id: Date { day }
    }

    private static let titles = ["Last week", "One change", "Next week's blocks", "One line"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: FFSpace.l) {
                    if let finished {
                        done(finished)
                    } else {
                        switch step {
                        case 0: lastWeek
                        case 1: onePick
                        case 2: plan
                        default: oneLine
                        }
                    }
                }
                .padding(FFSpace.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 640, height: 640)
        .background(FFPalette.windowBackground)
        .onAppear(perform: load)
        .accessibilityIdentifier("weeklyReview")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly review").ffText(.title3)
                Text(finished == nil ? "Step \(step + 1) of 4 · \(Self.titles[min(step, 3)])" : "Done").ffText(.caption)
            }
            Spacer()
            Button("Close", action: close).buttonStyle(.glass)
        }
        .padding(FFSpace.l)
    }

    private var footer: some View {
        HStack {
            if finished == nil, step > 0 {
                Button("Back") { step -= 1 }.buttonStyle(.glass)
            }
            Spacer()
            if finished != nil {
                Button("Close", action: close).buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            } else if step < 3 {
                Button("Next") { step += 1 }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("weeklyReview.next")
            } else {
                Button("Finish", action: finish).buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("weeklyReview.finish")
            }
        }
        .padding(FFSpace.l)
    }

    // MARK: Steps

    private var lastWeek: some View {
        let week = timerVM.yourWeek(now: now)
        let outcomes = timerVM.lifeRecOutcomes(now: now)
        return VStack(alignment: .leading, spacing: FFSpace.l) {
            WeekVerdictSection(week: week)
            WeekDaysStrip(days: week.days, selected: .constant(nil))
            if !outcomes.isEmpty {
                VStack(alignment: .leading, spacing: FFSpace.s) {
                    Text("What you tried").ffText(.headline)
                    ForEach(Array(outcomes.enumerated()), id: \.offset) { _, item in
                        Label("\(item.record.title): \(item.outcome.title)", systemImage: item.outcome.symbol).ffText(.body)
                    }
                }
            }
            if let last = timerVM.lastWeeklyReview, !last.obstacle.isEmpty {
                Text("Last week you said what's in the way: “\(last.obstacle)”").ffText(.callout)
            }
        }
    }

    private var onePick: some View {
        VStack(alignment: .leading, spacing: FFSpace.m) {
            Text("Pick one change for the coming week. One is enough; it gets judged next Sunday.").ffText(.callout)
            ForEach(recs) { rec in
                pickRow(id: rec.id, title: rec.title, detail: "\(rec.evidence) → \(rec.actionTitle)")
            }
            pickRow(id: nil, title: "No change this week", detail: "Keep going as you are.")
        }
    }

    private func pickRow(id: String?, title: String, detail: String) -> some View {
        Button { pickID = id } label: {
            HStack(alignment: .top, spacing: FFSpace.m) {
                Image(systemName: pickID == id ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(pickID == id ? FFPalette.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).ffText(.headline)
                    Text(detail).ffText(.caption).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(FFSpace.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ffHoverRow(isSelected: pickID == id)
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: FFSpace.m) {
            Text("Days off first, plus two workday anchors. A time on the calendar is the plan; I cue each one.").ffText(.callout)
            ForEach($rows) { $row in
                HStack(spacing: FFSpace.m) {
                    Toggle("", isOn: $row.on).labelsHidden().disabled(!row.existing.isEmpty)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(DayTimelineView.title(row.day)).ffText(.body)
                        Text(row.type == .workday ? "Workday" : row.type.title).ffText(.caption)
                    }
                    .frame(width: 200, alignment: .leading)
                    if row.existing.isEmpty {
                        DatePicker("", selection: $row.time, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .disabled(!row.on)
                    } else {
                        Text("Planned \(row.existing.map { CoachQuestion.clock($0) }.joined(separator: ", "))").ffText(.callout)
                    }
                    Spacer()
                }
            }
        }
    }

    private var oneLine: some View {
        VStack(alignment: .leading, spacing: FFSpace.m) {
            Text("What's in the way this week? One line. I'll show it to you next Sunday.").ffText(.callout)
            TextField("Late office calls on Tuesday", text: $obstacle)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("weeklyReview.obstacle")
        }
    }

    private func done(_ record: WeeklyReviewRecord) -> some View {
        VStack(alignment: .leading, spacing: FFSpace.m) {
            Label("Saved.", systemImage: "checkmark.circle.fill").ffText(.title3).foregroundStyle(FFPalette.goal)
            Text("\(record.plannedBlocks) block\(record.plannedBlocks == 1 ? "" : "s") planned\(record.pickTitle.map { " · your change: \($0)" } ?? "").")
                .ffText(.body)
            Text("Next Sunday this review says whether the change worked.").ffText(.caption)
        }
    }

    // MARK: Data

    private func load() {
        guard rows.isEmpty else { return }
        recs = Array(timerVM.allLifeRecommendations(now: now).prefix(5))
        pickID = recs.first?.id
        let hours = timerVM.weeklyPlanHours(now: now)
        let days = timerVM.weeklyPlanDays(now: now)
        let anchors = WeeklyReviewPolicy.anchorDays(days.filter { $0.type == .workday && $0.planned.isEmpty }.map(\.day))
        let calendar = Calendar.current
        rows = days.map { item in
            let free = item.type != .workday && item.type != .sick
            let hour = free ? hours.free : hours.workday
            let time = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: item.day) ?? item.day
            return PlanRow(day: item.day, type: item.type, existing: item.planned,
                           on: item.planned.isEmpty && time > now && (free || anchors.contains(item.day)), time: time)
        }
    }

    private func finish() {
        let pick = recs.first { $0.id == pickID }
        let blocks = rows.filter { $0.on && $0.existing.isEmpty }.map { row -> Date in
            // The picker edits the time; keep it on the row's own day.
            let calendar = Calendar.current
            let parts = calendar.dateComponents([.hour, .minute], from: row.time)
            return calendar.date(bySettingHour: parts.hour ?? 10, minute: parts.minute ?? 0, second: 0, of: row.day) ?? row.time
        }
        finished = timerVM.completeWeeklyReview(pick: pick, blocks: blocks, obstacle: obstacle, now: Date())
    }
}
