import SwiftUI
import SwiftData

struct TimeSplitView: View {
    let totalDuration: TimeInterval
    @Binding var splits: [SplitEntry]

    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt)
    private var projects: [Project]

    @State private var editingCustomIndex: Int? = nil
    @State private var customLabelText: String = ""

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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SPLIT TIME")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(remainingText)
                    .font(.system(size: 12))
                    .foregroundStyle(remainingMinutes == 0 ? .green : (remainingMinutes < 0 ? .red : .secondary))
            }

            ForEach(splits.indices, id: \.self) { index in
                splitRow(at: index)
            }

            if remainingMinutes > 0 {
                Button {
                    splits.append(SplitEntry(minutes: remainingMinutes))
                } label: {
                    Label("Add Split", systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            }
        }
    }

    @ViewBuilder
    private func splitRow(at index: Int) -> some View {
        HStack(spacing: 8) {
            if editingCustomIndex == index {
                TextField("Custom label", text: $customLabelText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6))
                    .onSubmit {
                        splits[index].customLabel = customLabelText.isEmpty ? "Custom" : customLabelText
                        editingCustomIndex = nil
                    }
                    .onExitCommand {
                        editingCustomIndex = nil
                    }
            } else {
                Menu {
                    ForEach(projects) { project in
                        Button(project.name) {
                            splits[index].project = project
                            splits[index].customLabel = ""
                            editingCustomIndex = nil
                        }
                    }
                    Divider()
                    Button("Custom...") {
                        splits[index].project = nil
                        customLabelText = splits[index].customLabel
                        editingCustomIndex = index
                    }
                } label: {
                    Text(splits[index].label)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 4) {
                Button {
                    if splits[index].minutes > 1 {
                        splits[index].minutes -= 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decrease minutes")

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
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Increase minutes")
            }

            if splits.count > 1 {
                Button {
                    splits.remove(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove split")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
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
