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
        VStack(alignment: .leading, spacing: FFSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: FFSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time Allocation")
                        .font(FFType.callout)
                    Text("Split this session across projects or labels.")
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(remainingText)
                    .font(FFType.meta.weight(.semibold))
                    .foregroundStyle(remainingColor)
            }

            ForEach(splits.indices, id: \.self) { index in
                splitRow(at: index)
            }

            if remainingMinutes > 0 {
                Button {
                    splits.append(SplitEntry(minutes: remainingMinutes))
                } label: {
                    Label("Add Split", systemImage: "plus.circle")
                        .font(FFType.meta)
                }
                .buttonStyle(.glass)
            }
        }
    }

    @ViewBuilder
    private func splitRow(at index: Int) -> some View {
        PremiumSurface(style: .inset) {
            HStack(alignment: .center, spacing: FFSpacing.sm) {
                Menu {
                    ForEach(projects) { project in
                        Button(project.name) {
                            splits[index].project = project
                            splits[index].customLabel = ""
                        }
                    }
                    Divider()
                    Button("Custom Label") {
                        splits[index].project = nil
                    }
                } label: {
                    HStack(spacing: FFSpacing.sm) {
                        ZStack {
                            RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous)
                                .fill(projectTint(for: splits[index]).opacity(0.15))

                            Image(systemName: splits[index].project?.icon ?? "tag.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(projectTint(for: splits[index]))
                        }
                        .frame(width: 34, height: 34)

                        Text(splits[index].label)
                            .font(FFType.body.weight(.medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, FFSpacing.sm)
                    .padding(.vertical, FFSpacing.xs)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)

                minuteStepper(for: index)

                if splits.count > 1 {
                    Button {
                        splits.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if splits[index].project == nil {
                TextField("Custom label", text: $splits[index].customLabel)
                    .textFieldStyle(.plain)
                    .font(FFType.body)
                    .padding(.horizontal, FFSpacing.md)
                    .padding(.vertical, FFSpacing.sm)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1))
                    }
            }
        }
    }

    private func minuteStepper(for index: Int) -> some View {
        HStack(spacing: FFSpacing.xs) {
            Button {
                if splits[index].minutes > 1 {
                    splits[index].minutes -= 1
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)

            Text("\(splits[index].minutes)m")
                .font(FFType.meta.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 42)

            Button {
                if remainingMinutes > 0 {
                    splits[index].minutes += 1
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, FFSpacing.xs)
        .padding(.vertical, FFSpacing.xs)
        .background(Color.white.opacity(0.05), in: Capsule())
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

    private var remainingColor: Color {
        if remainingMinutes == 0 { return FFColor.success }
        if remainingMinutes < 0 { return FFColor.danger }
        return .secondary
    }

    private func projectTint(for split: SplitEntry) -> Color {
        guard let colorName = split.project?.color else { return .secondary }
        switch colorName {
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "teal": return .teal
        case "mint": return .mint
        default: return .blue
        }
    }
}
