import SwiftUI

struct ProjectFormView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var name: String
    @Binding var color: String
    @Binding var icon: String
    let title: String
    let onSave: () -> Void

    private let colors: [(name: String, color: Color)] = [
        ("blue", .blue), ("indigo", .indigo), ("purple", .purple),
        ("pink", .pink), ("red", .red), ("orange", .orange),
        ("yellow", .yellow), ("green", .green), ("teal", .teal),
        ("mint", .mint)
    ]

    private let icons = [
        "folder.fill", "laptopcomputer", "book.fill", "hammer.fill",
        "paintbrush.fill", "music.note", "heart.fill", "star.fill",
        "bolt.fill", "leaf.fill", "brain.head.profile", "trophy.fill",
        "figure.run", "cup.and.saucer.fill", "pencil.and.ruler.fill", "doc.text.fill"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.headline)

            // Name
            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. IntelliOps, Resume Prep", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // Color
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30)), count: 10), spacing: 8) {
                    ForEach(colors, id: \.name) { item in
                        Circle()
                            .fill(item.color)
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.8), lineWidth: 2)
                                    .opacity(item.name == color ? 1 : 0)
                            )
                            .scaleEffect(item.name == color ? 1.15 : 1)
                            .animation(.spring(response: 0.2), value: color)
                            .onTapGesture { color = item.name }
                    }
                }
            }

            // Icon
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 8), spacing: 8) {
                    ForEach(icons, id: \.self) { sfSymbol in
                        Image(systemName: sfSymbol)
                            .font(.system(size: 16))
                            .frame(width: 32, height: 32)
                            .background(
                                sfSymbol == icon
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .foregroundStyle(sfSymbol == icon ? .accentColor : .secondary)
                            .scaleEffect(sfSymbol == icon ? 1.1 : 1)
                            .animation(.spring(response: 0.2), value: icon)
                            .onTapGesture { icon = sfSymbol }
                    }
                }
            }

            // Buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save") {
                    onSave()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 360)
    }
}
