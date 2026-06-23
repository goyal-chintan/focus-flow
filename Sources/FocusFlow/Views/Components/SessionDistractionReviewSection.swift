import SwiftUI

/// Shows apps/websites detected as distracting during the current focus session.
/// Each entry has inline buttons to classify as "Planned work" or "Distraction".
///
/// - Planned: records a project-scoped DriftMemory allowance so the coach won't flag it again.
/// - Distraction: inserts a manual IdleDistractionItem for future blocking/warnings.
struct SessionDistractionReviewSection: View {
    let entries: [AppUsageTracker.SessionDistractingEntry]
    let projectId: UUID?
    let projectName: String?

    @Environment(TimerViewModel.self) private var timerVM

    /// Per-entry classification (nil = undecided, true = planned, false = distraction)
    @State private var decisions: [String: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            entriesList
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LiquidDesignTokens.Spectral.amber)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                TrackedLabel(
                    text: "Apps Detected This Session",
                    font: .system(size: 10, weight: .semibold),
                    color: LiquidDesignTokens.Surface.onSurfaceMuted,
                    tracking: 1.5
                )
                if let name = projectName {
                    Text("Classify for \"\(name)\" — teaches Focus Coach")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted.opacity(0.7))
                }
            }
            Spacer()
        }
    }

    // MARK: - Entries

    private var entriesList: some View {
        VStack(spacing: 6) {
            ForEach(entries, id: \.normalizedKey) { entry in
                distractionRow(for: entry)
            }
        }
    }

    @ViewBuilder
    private func distractionRow(for entry: AppUsageTracker.SessionDistractingEntry) -> some View {
        let decision = decisions[entry.normalizedKey]
        HStack(spacing: 10) {
            // Icon
            Image(systemName: entry.isBrowserDomain ? "globe" : "app.badge.fill")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(LiquidDesignTokens.Spectral.amber.opacity(0.8))
                .frame(width: 22, alignment: .center)
                .accessibilityHidden(true)

            // Label + duration
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(formatDuration(entry.seconds))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
            }

            Spacer()

            // Decision area
            if let decided = decision {
                confirmedPill(decided: decided, key: entry.normalizedKey)
            } else {
                choiceButtons(entry: entry)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(LiquidDesignTokens.Spectral.amber.opacity(0.12), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Choice Buttons

    private func choiceButtons(entry: AppUsageTracker.SessionDistractingEntry) -> some View {
        HStack(spacing: 6) {
            classifyChip(label: "Planned", isPlanned: true, entry: entry)
            classifyChip(label: "Distraction", isPlanned: false, entry: entry)
        }
    }

    private func classifyChip(
        label: String,
        isPlanned: Bool,
        entry: AppUsageTracker.SessionDistractingEntry
    ) -> some View {
        Button {
            withAnimation(FFMotion.control) {
                decisions[entry.normalizedKey] = isPlanned
            }
            timerVM.classifySessionApp(entry: entry, isPlanned: isPlanned)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isPlanned
                    ? LiquidDesignTokens.Spectral.electricBlue
                    : LiquidDesignTokens.Surface.onSurfaceMuted)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isPlanned
                            ? LiquidDesignTokens.Spectral.electricBlue.opacity(0.10)
                            : Color.primary.opacity(0.06))
                        .overlay(Capsule().strokeBorder(
                            isPlanned
                                ? LiquidDesignTokens.Spectral.electricBlue.opacity(0.20)
                                : Color.primary.opacity(0.08),
                            lineWidth: 0.5))
                )
                .frame(minHeight: 30)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(isPlanned
            ? "Mark \(entry.displayLabel) as planned work"
            : "Mark \(entry.displayLabel) as a distraction")
    }

    // MARK: - Confirmed Pill (after selection)

    private func confirmedPill(decided: Bool, key: String) -> some View {
        Button {
            withAnimation(FFMotion.control) { decisions[key] = nil }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: decided ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(decided ? LiquidDesignTokens.Spectral.mint : LiquidDesignTokens.Spectral.salmon)
                    .accessibilityHidden(true)
                Text(decided ? "Planned" : "Distraction")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(decided ? LiquidDesignTokens.Spectral.mint : LiquidDesignTokens.Spectral.salmon)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill((decided ? LiquidDesignTokens.Spectral.mint : LiquidDesignTokens.Spectral.salmon).opacity(0.10))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(decided
            ? "Marked as planned work. Tap to undo."
            : "Marked as distraction. Tap to undo.")
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "< 1s" }
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return s > 0 ? "\(m)m \(s)s" : "\(m)m"
    }
}
