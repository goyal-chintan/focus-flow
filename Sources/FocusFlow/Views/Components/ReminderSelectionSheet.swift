import SwiftUI

struct ReminderSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selectedListId: String?
    let initialSelectedIds: Set<String>
    let onConfirm: ([RemindersService.ReminderItem]) -> Void

    @State private var reminders: [RemindersService.ReminderItem] = []
    @State private var selectedIds: Set<String> = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Reminders")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().opacity(0.3)

            // Content
            if isLoading {
                ProgressView()
                    .padding(.vertical, 40)
            } else if let loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(loadError)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 40)
            } else if reminders.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text("No incomplete reminders")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(reminders, id: \.id) { reminder in
                            Button {
                                toggle(reminder.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedIds.contains(reminder.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(selectedIds.contains(reminder.id) ? LiquidDesignTokens.Spectral.primaryContainer : .secondary)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(reminder.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.primary)
                                        if !reminder.list.isEmpty {
                                            Text(reminder.list)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                    if let due = reminder.dueDate {
                                        Text(due, style: .date)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    selectedIds.contains(reminder.id)
                                        ? Color.white.opacity(0.06)
                                        : Color.clear
                                )
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 300)
            }

            Divider().opacity(0.3)

            // Footer buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)

                Button("Add") {
                    let chosen = reminders.filter { selectedIds.contains($0.id) }
                    onConfirm(chosen)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .tint(LiquidDesignTokens.Spectral.primaryContainer)
                .buttonBorderShape(.capsule)
                .disabled(selectedIds.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 380, height: 460)
        .task { await load() }
    }

    private func toggle(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        selectedIds = initialSelectedIds
        guard RemindersService.shared.authStatus == .authorized else {
            isLoading = false
            loadError = "Reminders permission is not granted."
            return
        }
        reminders = await RemindersService.shared.fetchIncompleteReminders(
            listId: selectedListId
        )
        isLoading = false
    }
}
