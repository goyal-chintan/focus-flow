import SwiftUI

/// Today's reminder line (clarity design: docs/plans/2026-10-28-clarity-fixes.md): Dan Koe's
/// questions alternating with challenging lines, and your own words every other day once you write
/// some. Same line all day; click for another.
/// `.strip` sits under the popover header; `.card` opens the Today tab and lets you write your own.
struct DailyReminderView: View {
    enum Style { case strip, card }

    var style: Style = .strip
    var now: Date = Date()

    @Environment(TimerViewModel.self) private var timerVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset = 0
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        if let line = timerVM.dailyReminder(now: now, offset: offset) {
            switch style {
            case .strip: strip(line)
            case .card: card(line)
            }
        }
    }

    private func next() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { offset += 1 }
    }

    // MARK: Strip (popover)

    private func strip(_ line: DailyReminderLine) -> some View {
        Button(action: next) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: line.isOwn ? "heart.fill" : (line.isQuestion ? "questionmark" : "quote.opening"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.orange.opacity(0.85))
                    .accessibilityHidden(true)
                Text(line.text)
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(.primary.opacity(0.8))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(line.text)
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(line.attribution) · click for another")
        .accessibilityLabel("Reminder: \(line.text), \(line.attribution)")
        .accessibilityHint("Shows another reminder")
    }

    // MARK: Card (Today)

    private func card(_ line: DailyReminderLine) -> some View {
        VStack(alignment: .leading, spacing: FFSpace.s) {
            HStack(alignment: .firstTextBaseline, spacing: FFSpace.s) {
                Image(systemName: line.isOwn ? "heart.fill" : (line.isQuestion ? "questionmark" : "quote.opening"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.text)
                        .font(.system(size: 19, weight: .medium, design: .serif))
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                        .id(line.text)
                        .transition(.opacity)
                    Text(line.isOwn ? line.attribution : (line.isQuestion ? "\(line.attribution) · answer it honestly, then start" : line.attribution))
                        .ffText(.caption)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: FFSpace.s) {
                Spacer(minLength: 0)
                Button("Another", action: next)
                    .buttonStyle(.borderless)
                    .help("Show another line")
                Button(timerVM.ownReminderLines.isEmpty ? "Write your own" : "Edit your lines") {
                    draft = timerVM.settings?.coachMyWhyText ?? ""
                    editing = true
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $editing, arrowEdge: .bottom) { editor }
            }
        }
        .padding(FFSpace.l)
        .background(
            RoundedRectangle(cornerRadius: FFRadius.section, style: .continuous)
                .fill(LinearGradient(colors: [.orange.opacity(0.12), .pink.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FFRadius.section, style: .continuous)
                .strokeBorder(.orange.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: FFSpace.s) {
            Text("Your lines").ffText(.headline)
            Text("One per line, up to five. FocusFlow shows one each day on the popover, the notch and here, and the coach uses them too.")
                .ffText(.caption)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(height: 110)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("If I don't change today, I'll be in the same place a year from now.")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                Spacer()
                Button("Cancel") { editing = false }
                Button("Save") {
                    timerVM.setReminderLines(draft)
                    offset = 0
                    editing = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(FFSpace.l)
        .frame(width: 380)
    }
}
