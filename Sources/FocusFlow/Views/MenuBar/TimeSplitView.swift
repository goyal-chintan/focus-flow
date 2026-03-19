import SwiftUI
import SwiftData

struct TimeSplitView: View {
    let totalDuration: TimeInterval
    @Binding var splits: [SplitEntry]

    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt)
    private var projects: [Project]

    struct SplitEntry: Identifiable {
        let id = UUID()
        var project: Project?
        var customLabel: String = ""
        var minutes: Int

        var label: String {
            project?.name ?? (customLabel.isEmpty ? "Unlabeled" : customLabel)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiquidSectionHeader("Split Time") {
                Text(remainingText)
                    .font(.caption)
                    .foregroundStyle(remainingMinutes == 0 ? .green : (remainingMinutes < 0 ? .red : .secondary))
            }

            ForEach(splits.indices, id: \.self) { index in
                splitRow(at: index)
            }

            if remainingMinutes > 0 {
                LiquidActionButton(
                    title: "Add Split",
                    icon: "plus.circle",
                    role: .secondary
                ) {
                    splits.append(SplitEntry(minutes: remainingMinutes))
                }
            }
        }
    }

    @ViewBuilder
    private func splitRow(at index: Int) -> some View {
        LiquidGlassPanel(cornerRadius: LiquidDesignTokens.CornerRadius.control) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(projects) { project in
                        Button(project.name) {
                            splits[index].project = project
                            splits[index].customLabel = ""
                        }
                    }
                    Divider()
                    Button("Custom...") {
                        splits[index].project = nil
                    }
                } label: {
                    Text(splits[index].label)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Button {
                        if splits[index].minutes > 1 {
                            splits[index].minutes -= 1
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.caption2)
                    }
                    .buttonStyle(.glass)

                    Text("\(splits[index].minutes)m")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 32)

                    Button {
                        if remainingMinutes > 0 {
                            splits[index].minutes += 1
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption2)
                    }
                    .buttonStyle(.glass)
                }

                if splits.count > 1 {
                    Button {
                        splits.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    private var totalMinutes: Int { Int(totalDuration / 60) }

    private var allocatedMinutes: Int {
        splits.reduce(0) { $0 + $1.minutes }
    }

    private var remainingMinutes: Int {
        totalMinutes - allocatedMinutes
    }

    private var remainingText: String {
        if remainingMinutes == 0 { return "All time allocated" }
        if remainingMinutes < 0 { return "\(abs(remainingMinutes))m over!" }
        return "\(remainingMinutes)m remaining"
    }
}
