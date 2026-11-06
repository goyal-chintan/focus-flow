import Foundation

// Coach v8 §3.4: one day, hour by hour. Blocks come from sessions (every day you have); calls,
// away time, pulls and other laptop time come from the hourly rollup (`ActivityHour`, from the
// phase 1 install on). Pure; `TimerViewModel.dayTimeline` feeds it.

struct DayTimeline: Equatable, Sendable {
    struct Hour: Equatable, Sendable, Identifiable {
        let hour: Int
        var own: Double = 0
        var work: Double = 0
        var call: Double = 0
        var away: Double = 0
        var pull: Double = 0
        var other: Double = 0

        var id: Int { hour }
        var total: Double { own + work + call + away + pull + other }
    }

    struct Row: Equatable, Sendable {
        var hourStart: Date
        var key: String
        var label: String
        var inBlock: Bool
        var seconds: Int
    }

    struct Block: Equatable, Sendable {
        var start: Date
        var end: Date
        var own: Bool
    }

    let day: Date
    let hours: [Hour]
    /// The hourly rollup covers this day (calls, away and pulls are known).
    let hasRollup: Bool

    var ownMinutes: Double { hours.map(\.own).reduce(0, +) }
    var callMinutes: Double { hours.map(\.call).reduce(0, +) }
    var awayMinutes: Double { hours.map(\.away).reduce(0, +) }
    var pullMinutes: Double { hours.map(\.pull).reduce(0, +) }
    var workMinutes: Double { hours.map(\.work).reduce(0, +) }

    /// The hours worth drawing: first to last with anything in them.
    var activeRange: ClosedRange<Int>? {
        let used = hours.filter { $0.total >= 1 }.map(\.hour)
        guard let first = used.min(), let last = used.max() else { return nil }
        return first...last
    }

    /// `isPull(key, label, hour)`: the app's role outside a block at that hour is a pull.
    static func build(day: Date, rows: [Row], blocks: [Block], isPull: (String, String, Int) -> Bool,
                      calendar: Calendar = .current) -> DayTimeline {
        let start = calendar.startOfDay(for: day)
        var hours = (0..<24).map { Hour(hour: $0) }
        for block in blocks {
            for index in 0..<24 {
                guard let hourStart = calendar.date(byAdding: .hour, value: index, to: start),
                      let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) else { continue }
                let overlap = min(block.end, hourEnd).timeIntervalSince(max(block.start, hourStart))
                guard overlap > 0 else { continue }
                if block.own { hours[index].own += overlap / 60 } else { hours[index].work += overlap / 60 }
            }
        }
        var dayRows = 0
        for row in rows {
            guard calendar.isDate(row.hourStart, inSameDayAs: start) else { continue }
            dayRows += 1
            let index = calendar.component(.hour, from: row.hourStart)
            let minutes = Double(row.seconds) / 60
            switch row.key {
            case "call": hours[index].call += minutes
            case "away": hours[index].away += minutes
            default:
                // Time in a block is already the block's; outside it, a pull or other laptop time.
                guard !row.inBlock else { continue }
                if isPull(row.key, row.label, index) { hours[index].pull += minutes } else { hours[index].other += minutes }
            }
        }
        // An hour holds 60 minutes: blocks first, then calls, away, pulls, other.
        for index in hours.indices {
            var room = 60.0
            func take(_ value: inout Double) { value = min(value, room); room -= value }
            take(&hours[index].own); take(&hours[index].work); take(&hours[index].call)
            take(&hours[index].away); take(&hours[index].pull); take(&hours[index].other)
        }
        return DayTimeline(day: start, hours: hours, hasRollup: dayRows > 0)
    }
}
