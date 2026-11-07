import SwiftUI

// Where the day went, and your focus rhythm (6 Nov 2026). Read-only while drawing; answers run in
// menu actions.

extension LeakCategory {
    var color: Color {
        switch self {
        case .own: FFPalette.accent
        case .work: Color.blue.opacity(0.5)
        case .rest: FFPalette.goal.opacity(0.55)
        case .office: Color.purple.opacity(0.6)
        case .side: Color.teal.opacity(0.7)
        case .unblockedOwn: FFPalette.accent.opacity(0.45)
        case .pull: FFPalette.atRisk
        case .away: Color.gray.opacity(0.3)
        case .other: Color.gray.opacity(0.55)
        }
    }
}

/// "At the laptop 12:40–19:10 · 6h 30m", one stacked bar, and what each part was.
struct DayAccountBar: View {
    let minutes: [LeakCategory: Double]
    let caption: String

    var body: some View {
        let parts = LeakCategory.allCases.compactMap { c in minutes[c].flatMap { $0 >= 1 ? (c, $0) : nil } }
        let total = max(1, parts.map(\.1).reduce(0, +))
        VStack(alignment: .leading, spacing: FFSpace.s) {
            Text(caption).ffText(.callout).monospacedDigit()
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    ForEach(parts, id: \.0) { c, m in
                        Rectangle().fill(c.color).frame(width: max(2, geo.size.width * m / total))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .frame(height: 12)
            FlowRow(spacing: FFSpace.m) {
                ForEach(parts.sorted { $0.1 > $1.1 }, id: \.0) { c, m in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(c.color).frame(width: 9, height: 9)
                        Text("\(c.title) \(FFFormatLite.duration(m))").ffText(.caption).monospacedDigit()
                    }
                    .help(c.caption)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A gap between sittings: when, how long, what filled it, and your one-tap reason.
struct GapRow: View {
    let gap: DayAccount.Gap
    let isOpen: Bool
    let setReason: (GapReason?) -> Void
    /// Split this part at a time inside it; nil hides the option.
    var split: ((Date) -> Void)? = nil
    /// Join this part back with the one before; nil when it isn't one of your splits.
    var join: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: FFSpace.m) {
            RoundedRectangle(cornerRadius: 2).fill(gap.dominant.color).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(FFFormat.clock(gap.start))–\(isOpen ? "now" : FFFormat.clock(gap.end)) · \(FFFormatLite.duration(gap.minutes))")
                    .ffText(.body).monospacedDigit()
                Text(gap.summary.isEmpty ? "Nothing recorded" : gap.summary).ffText(.caption).monospacedDigit()
            }
            Spacer(minLength: FFSpace.s)
            Menu {
                ForEach(GapReason.allCases, id: \.self) { reason in
                    Button(reason.title) { setReason(reason) }
                }
                if let split, !gap.splitPoints().isEmpty {
                    Divider()
                    Menu("Split at…") {
                        ForEach(gap.splitPoints(), id: \.self) { point in
                            Button(FFFormat.clock(point)) { split(point) }
                        }
                    }
                }
                if let join {
                    Button("Join with the part before", action: join)
                }
                if gap.reason != nil {
                    Divider()
                    Button("Clear") { setReason(nil) }
                }
            } label: {
                Text(gap.reason?.title ?? "Why?")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(gap.reason == nil ? FFPalette.accent : (gap.reason!.isFine ? FFPalette.goal : FFPalette.atRisk))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Why was \(FFFormat.clock(gap.start)) to \(FFFormat.clock(gap.end)) a gap?")
        }
        .padding(.vertical, 2)
    }
}

/// Where today went: the bar, then each gap of 30+ min with its reason.
struct DayAccountSection: View {
    let account: DayAccount
    let now: Date
    let setReason: (Date, GapReason?) -> Void
    var split: ((Date) -> Void)? = nil
    var join: ((Date) -> Void)? = nil
    var isSplitPoint: (Date) -> Bool = { _ in false }

    var body: some View {
        if let span = account.span, account.spanMinutes >= 30 {
            VStack(alignment: .leading, spacing: FFSpace.m) {
                DayAccountBar(minutes: account.minutes,
                              caption: "At the laptop \(FFFormat.clock(span.start))–\(Calendar.current.isDate(now, inSameDayAs: account.day) ? "now" : FFFormat.clock(span.end)) · \(FFFormatLite.duration(account.spanMinutes)), \(FFFormatLite.duration(account.minutes[.own] ?? 0)) own work")
                if !account.gaps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gaps between sittings").ffText(.headline)
                        Text("Say what each was: family and rest are fine; tired, wasted time and side projects are what the coach helps with.")
                            .ffText(.caption).fixedSize(horizontal: false, vertical: true)
                        ForEach(account.gaps.reversed()) { gap in
                            GapRow(gap: gap, isOpen: abs(gap.end.timeIntervalSince(now)) < 90,
                                   setReason: { setReason(gap.start, $0) },
                                   split: split,
                                   join: join.flatMap { j in isSplitPoint(gap.start) ? { j(gap.start) } : nil })
                        }
                    }
                }
                if !account.hasRollup {
                    Text("This day is older than the hourly record, so a gap shows its length but not what filled it.").ffText(.caption)
                }
            }
            .accessibilityIdentifier("today.dayAccount")
        }
    }
}

/// Insights: how you sit, with the week's hours by kind.
struct FocusRhythmSection: View {
    let rhythm: FocusRhythm
    let week: [LeakCategory: Double]
    let weekSpan: Double
    /// Days this week with the hourly record (the bar covers only those).
    var recordedDays = 7

    var body: some View {
        FFSection("Your focus rhythm", subtitle: "How you sit and where the hours go: your last 4 weeks, and this week's time at the laptop.") {
            VStack(alignment: .leading, spacing: FFSpace.l) {
                if weekSpan >= 60 {
                    DayAccountBar(minutes: week, caption: "At the laptop \(recordedDays == 1 ? "today" : "the last \(recordedDays) days with an hourly record"): \(FFFormatLite.duration(weekSpan)), \(FFFormatLite.duration(week[.own] ?? 0)) of it own work")
                }
                let findings = rhythm.findings
                if findings.isEmpty {
                    FFEmptyState(systemImage: "waveform.path.ecg", message: "Not enough sittings yet",
                                 detail: "After about 8 sittings this says how long you sit, what your good days look like, and why you stop.")
                }
                ForEach(findings) { finding in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: finding.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(FFPalette.accent)
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.title).ffText(.headline)
                            Text(finding.sentence).ffText(.body).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier("insights.rhythm")
    }
}
