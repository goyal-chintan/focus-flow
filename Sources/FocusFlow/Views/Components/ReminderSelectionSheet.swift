import SwiftUI

struct ReminderSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selectedDate: Date
    let selectedListId: String?
    let initialSelectedIds: Set<String>
    let onConfirm: ([RemindersService.ReminderItem]) -> Void

    @State private var reminders: [RemindersService.ReminderItem] = []
    @State private var selectedIds: Set<String> = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if isLoading {
                    ProgressView("Loading reminders...")
                        .padding(.vertical, 24)
                } else if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.vertical, 24)
                } else if remindersForSelectedDate.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checklist")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("No reminders due on this day")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 24)
                } else {
                    List(remindersForSelectedDate, id: \.id) { reminder in
                        Button {
                            toggle(reminder.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedIds.contains(reminder.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIds.contains(reminder.id) ? .blue : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reminder.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text(reminder.list)
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.inset)
                }
            }
            .padding(.horizontal, 12)
            .navigationTitle("Select Reminders")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let chosen = reminders.filter { selectedIds.contains($0.id) }
                        onConfirm(chosen)
                        dismiss()
                    }
                    .disabled(selectedIds.isEmpty)
                }
            }
            .task {
                await load()
            }
        }
        .frame(minWidth: 420, minHeight: 420)
    }

    private var remindersForSelectedDate: [RemindersService.ReminderItem] {
        let calendar = Calendar.current
        return reminders.filter {
            guard let due = $0.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: selectedDate)
        }
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
        reminders = await RemindersService.shared.fetchIncompleteReminders(listId: selectedListId)
        isLoading = false
    }
}

