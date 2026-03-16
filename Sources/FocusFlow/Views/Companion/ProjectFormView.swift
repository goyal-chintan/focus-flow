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
        [GridItem(.adaptive(minimum: 30, maximum: 30), spacing: 8, alignment: .leading)]
    }

    private var iconGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 36, maximum: 36), spacing: 8, alignment: .leading)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FFSpacing.lg) {
                PremiumSurface(style: .hero) {
                    PremiumSectionHeader(
                        title,
                        eyebrow: "Project",
                        subtitle: "Shape the visual identity and optional blocking behavior for this project."
                    )
                }

                PremiumSurface(style: .card) {
                    PremiumSectionHeader("Identity", eyebrow: "Basics", subtitle: "Name the project and pick a signature color and icon.")
                    nameSection
                    colorSection
                    iconSection
                }

                PremiumSurface(style: .card) {
                    PremiumSectionHeader("Blocking", eyebrow: "Optional", subtitle: "Attach a blocking profile if this project needs stricter guardrails.")
                    blockProfileSection
                }

                PremiumSurface(style: .card) {
                    PremiumSectionHeader("Save", eyebrow: "Finish", subtitle: "Store the project and make it available from the focus timer.")
                    actionButtons
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FFSpacing.lg)
        }
        .frame(width: 440)
        .frame(minHeight: 620)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            sectionLabel("Name")
            TextField("e.g. IntelliOps, Resume Prep", text: $name)
                .textFieldStyle(.plain)
                .font(FFType.body)
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.sm)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1))
                }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            sectionLabel("Color")
            LazyVGrid(columns: colorGridColumns, alignment: .leading, spacing: 8) {
                ForEach(colors, id: \.name) { item in
                    Circle()
                        .fill(item.color)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(Color.primary.opacity(0.8), lineWidth: 2).opacity(item.name == color ? 1 : 0))
                        .scaleEffect(item.name == color ? 1.15 : 1)
                        .animation(.spring(response: 0.2), value: color)
                        .onTapGesture { color = item.name }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            sectionLabel("Icon")
            LazyVGrid(columns: iconGridColumns, alignment: .leading, spacing: 8) {
                ForEach(icons, id: \.self) { sfSymbol in
                    IconCell(sfSymbol: sfSymbol, selected: sfSymbol == icon)
                        .animation(.spring(response: 0.2), value: icon)
                        .onTapGesture { icon = sfSymbol }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var blockProfileSection: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
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
                HStack(spacing: FFSpacing.sm) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FFColor.focus)
                    Text(selectedBlockProfile?.name ?? "None (no blocking)")
                        .font(FFType.body)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, FFSpacing.md)
                .padding(.vertical, FFSpacing.sm)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: FFSpacing.sm) {
            Button("Cancel") { dismiss() }
                .buttonStyle(.glass)
            Button("Save") { onSave(); dismiss() }
                .buttonStyle(.glassProminent)
                .tint(FFColor.focus)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(FFType.micro)
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .tracking(1.2)
    }
}

private struct IconCell: View {
    let sfSymbol: String
    let selected: Bool

    var body: some View {
        let bg: Color = selected ? FFColor.focus.opacity(0.2) : Color.secondary.opacity(0.08)
        let fg: Color = selected ? FFColor.focus : Color.secondary
        return Image(systemName: sfSymbol)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 34, height: 34)
            .background(bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(fg)
            .scaleEffect(selected ? 1.1 : 1)
    }
}
