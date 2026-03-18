import SwiftUI

struct DesignLabSidebar: View {
    @Binding var selectedCategory: DesignLabCategory
    @Environment(FFDesignTokens.self) private var tokens
    @Environment(FFDesignLabStore.self) private var store
    @State private var showingSaveAlert = false
    @State private var showingCompare = false
    @State private var newVariantName = ""

    var body: some View {
        List {
            categoriesSection
            variantsSection
            actionsSection
        }
        .listStyle(.sidebar)
        .alert("Save Variant", isPresented: $showingSaveAlert) {
            TextField("Name", text: $newVariantName)
            Button("Save") { saveVariant() }
            Button("Cancel", role: .cancel) { newVariantName = "" }
        } message: {
            Text("Enter a name for this design variant")
        }
        .sheet(isPresented: $showingCompare) {
            VariantCompareView()
                .frame(minWidth: 600, minHeight: 400)
        }
    }

    private var categoriesSection: some View {
        Section("Categories") {
            ForEach(DesignLabCategory.allCases, id: \.self) { category in
                Button {
                    selectedCategory = category
                } label: {
                    Label(category.title, systemImage: category.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
                .listRowBackground(
                    selectedCategory == category ? Color.accentColor.opacity(0.2) : Color.clear
                )
            }
        }
    }

    private var variantsSection: some View {
        Section("Variants") {
            ForEach(store.variants) { variant in
                variantRow(variant)
            }
            Button {
                newVariantName = ""
                showingSaveAlert = true
            } label: {
                Label("Save Current...", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            Button { store.pushUndo(tokens); tokens.apply(from: FFDesignTokens()); store.clearActive() } label: {
                Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
            }.buttonStyle(.plain)

            Button { showingCompare = true } label: {
                Label("Compare...", systemImage: "square.split.2x1")
            }.buttonStyle(.plain)

            Button { store.lockAsDefault(tokens) } label: {
                Label("Export JSON to Clipboard", systemImage: "arrow.up.doc")
            }.buttonStyle(.plain)

            Button { importFromClipboard() } label: {
                Label("Import JSON from Clipboard", systemImage: "arrow.down.doc")
            }.buttonStyle(.plain)
        }
    }

    private func variantRow(_ variant: FFDesignVariant) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(variant.name).font(.body)
                Text(variant.modifiedAt, style: .date).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.activeVariantId == variant.id {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.setActive(variant, applying: tokens) }
        .contextMenu {
            Button("Delete", role: .destructive) { store.delete(variant) }
        }
    }

    private func saveVariant() {
        guard !newVariantName.isEmpty else { return }
        store.save(FFDesignVariant(name: newVariantName, tokens: tokens.copy()))
        newVariantName = ""
    }

    private func importFromClipboard() {
        guard let string = NSPasteboard.general.string(forType: .string),
              let imported = store.importJSON(string) else { return }
        store.pushUndo(tokens)
        tokens.apply(from: imported)
    }
}
