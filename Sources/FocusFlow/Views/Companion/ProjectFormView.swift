import SwiftUI
import SwiftData

struct ProjectFormView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var name: String
    @Binding var color: String
    @Binding var icon: String
    @Binding var selectedBlockProfile: BlockProfile?
    @Query(sort: \BlockProfile.createdAt) private var blockProfiles: [BlockProfile]
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

    private var colorGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 30, maximum: 30), spacing: 10, alignment: .leading)]
    }

    private var iconGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 38, maximum: 38), spacing: 10, alignment: .leading)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.large) {
                LiquidSectionHeader(title, subtitle: "Customize identity and blocking behavior")

                nameSection
                colorSection
                iconSection
                blockProfileSection
                actionButtons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(width: 420)
        .frame(minHeight: 560)
        .background(.background)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Name")

            TextField("e.g. IntelliOps, Resume Prep", text: $name)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Color")

            LazyVGrid(columns: colorGridColumns, alignment: .leading, spacing: 10) {
                ForEach(colors, id: \.name) { item in
                    Button {
                        color = item.name
                    } label: {
                        Circle()
                            .fill(item.color)
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(item.name == color ? 0.9 : 0), lineWidth: 2)
                            )
                            .scaleEffect(item.name == color ? 1.16 : 1)
                            .shadow(color: item.color.opacity(item.name == color ? 0.4 : 0), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.22, dampingFraction: 0.8), value: color)
                    .help(item.name.capitalized)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Icon")

            LazyVGrid(columns: iconGridColumns, alignment: .leading, spacing: 10) {
                ForEach(icons, id: \.self) { sfSymbol in
                    Button {
                        icon = sfSymbol
                    } label: {
                        IconCell(sfSymbol: sfSymbol, selected: sfSymbol == icon)
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.22, dampingFraction: 0.8), value: icon)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var blockProfileSection: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.small) {
            sectionLabel("Block Profile")

            Menu {
                Button("None") { selectedBlockProfile = nil }
                Divider()
                ForEach(blockProfiles) { profile in
                    Button {
                        selectedBlockProfile = profile
                    } label: {
                        HStack {
                            Text(profile.name)
                            if profile.isDefault { Text("(Default)") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(selectedBlockProfile?.name ?? "None (no blocking)")
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
            }
            .buttonStyle(.plain)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: LiquidDesignTokens.Spacing.medium) {
            LiquidActionButton(
                title: "Cancel",
                icon: "xmark",
                role: .secondary
            ) {
                dismiss()
            }

            LiquidActionButton(
                title: "Save",
                icon: "checkmark",
                role: .primary
            ) {
                onSave()
                dismiss()
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.top, 4)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct IconCell: View {
    let sfSymbol: String
    let selected: Bool

    var body: some View {
        if selected {
            Image(systemName: sfSymbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.tint.opacity(0.5), lineWidth: 1.2)
                )
                .foregroundStyle(.tint)
                .scaleEffect(1.08)
        } else {
            Image(systemName: sfSymbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.secondary)
        }
    }
}
