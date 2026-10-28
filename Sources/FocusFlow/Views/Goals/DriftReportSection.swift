import SwiftUI
import SwiftData
import Charts

/// Insights → "Said vs did": each project's daily average against its target over 7 or 30 days,
/// your own work as a share of each day, and the plain findings (priorities-goals design §3.4).
struct DriftReportSection: View {
    let snapshot: CompanionSnapshot

    @Query(filter: #Predicate<Project> { !$0.archived }) private var projects: [Project]
    @State private var span: Span = .week

    enum Span: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        var id: Int { rawValue }
        var label: String { self == .week ? "7 days" : "30 days" }
    }

    var body: some View {
        let report = GoalDataBuilder.drift(samples: snapshot.samples, projects: projects, now: snapshot.now, days: span.rawValue, calendar: snapshot.calendar)
        let targeted = report.lines.contains { ($0.targetPerDay ?? 0) > 0 }
        FFSection("Said vs did", subtitle: "What you planned each project to get, and what it got (daily average).") {
            FFSegmentedPicker(title: "Period", options: Span.allCases, selection: $span, label: \.label)
        } content: {
            if report.lines.isEmpty {
                FFEmptyState(systemImage: "chart.bar.xaxis", message: "No focus in this period")
            } else {
                VStack(alignment: .leading, spacing: FFSpace.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(report.findings(format: FFFormat.duration), id: \.self) { line in
                            Label(line, systemImage: "arrow.right")
                                .ffText(.body)
                                .labelStyle(.titleAndIcon)
                        }
                        if !targeted {
                            Text("Give your projects a daily target (Projects → Edit) to compare plan and reality.").ffText(.caption)
                        }
                    }
                    saidVsDidChart(report)
                    ownShareChart(report)
                }
            }
        }
    }

    private func saidVsDidChart(_ report: DriftReport) -> some View {
        Chart {
            ForEach(report.lines) { line in
                BarMark(x: .value("Hours a day", line.actualPerDay / 3600), y: .value("Project", label(line)))
                    .foregroundStyle(FFPalette.project(line.colorName).opacity(line.area.isOwnWork ? 1 : 0.5))
                    .annotation(position: .trailing) {
                        Text(annotation(line)).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                    }
                if let target = line.targetPerDay, target > 0 {
                    // A tick at the target, across the project's bar.
                    RectangleMark(
                        x: .value("Target", target / 3600),
                        y: .value("Project", label(line)),
                        width: .fixed(3),
                        height: .ratio(0.9)
                    )
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .cornerRadius(1.5)
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(FFPalette.gridLine)
                AxisValueLabel { Text("\(value.as(Double.self).map { String(format: "%.0fh", $0) } ?? "")").font(.system(size: 10)) }
            }
        }
        .frame(height: CGFloat(max(2, report.lines.count)) * 34 + 24)
        .accessibilityLabel("Daily average per project against its target")
        .overlay(alignment: .topTrailing) {
            FFLegendItem(color: .primary, label: "Target")
        }
    }

    private func ownShareChart(_ report: DriftReport) -> some View {
        VStack(alignment: .leading, spacing: FFSpace.s) {
            Text("Your own work, share of each day").ffText(.headline)
            Chart(report.daily) { day in
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Own work", day.ownShare * 100))
                    .foregroundStyle(day.total == 0 ? FFPalette.track : FFPalette.accent)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine().foregroundStyle(FFPalette.gridLine)
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.system(size: 10)) }
                }
            }
            .frame(height: 110)
            .accessibilityLabel("Share of each day spent on personal and learning projects")
        }
    }

    private func label(_ line: DriftReport.Line) -> String {
        line.rank.map { "#\($0) \(line.name)" } ?? line.name
    }

    private func annotation(_ line: DriftReport.Line) -> String {
        guard let target = line.targetPerDay, target > 0 else { return FFFormat.duration(line.actualPerDay) }
        return "\(FFFormat.duration(line.actualPerDay)) of \(FFFormat.duration(target)) · \(Int(((line.share ?? 0) * 100).rounded()))%"
    }
}
