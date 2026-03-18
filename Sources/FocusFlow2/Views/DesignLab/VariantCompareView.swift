import SwiftUI

struct VariantCompareView: View {
    @Environment(FFDesignTokens.self) private var tokens
    @Environment(FFDesignLabStore.self) private var store
    @State private var variantAId = "current"
    @State private var variantBId = "current"

    var body: some View {
        VStack(spacing: 16) {
            Text("Compare Variants").font(.headline)

            HStack {
                Picker("Variant A", selection: $variantAId) {
                    Text("Current").tag("current")
                    ForEach(store.variants) { v in Text(v.name).tag(v.id.uuidString) }
                }
                Picker("Variant B", selection: $variantBId) {
                    Text("Current").tag("current")
                    ForEach(store.variants) { v in Text(v.name).tag(v.id.uuidString) }
                }
            }

            diffContent

            HStack {
                if let v = store.variants.first(where: { $0.id.uuidString == variantAId }) {
                    Button("Switch to A") { store.pushUndo(tokens); store.setActive(v, applying: tokens) }.buttonStyle(.bordered)
                }
                if let v = store.variants.first(where: { $0.id.uuidString == variantBId }) {
                    Button("Switch to B") { store.pushUndo(tokens); store.setActive(v, applying: tokens) }.buttonStyle(.bordered)
                }
            }
        }.padding()
    }

    private var diffContent: some View {
        let diffs = computeDiffs()
        return Group {
            if diffs.isEmpty {
                Text("No differences").foregroundStyle(.secondary).frame(maxHeight: .infinity)
            } else {
                Table(diffs) {
                    TableColumn("Token", value: \.path)
                    TableColumn("A", value: \.valueA)
                    TableColumn("B", value: \.valueB)
                }
            }
        }
    }

    private func computeDiffs() -> [TokenDiff] {
        let tokensA = resolve(variantAId)
        let tokensB = resolve(variantBId)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let dA = try? encoder.encode(tokensA), let dB = try? encoder.encode(tokensB),
              let a = try? JSONSerialization.jsonObject(with: dA) as? [String: Any],
              let b = try? JSONSerialization.jsonObject(with: dB) as? [String: Any]
        else { return [] }
        return flatDiff(a, b, prefix: "")
    }

    private func resolve(_ id: String) -> FFDesignTokens {
        if id == "current" { return tokens }
        return store.variants.first(where: { $0.id.uuidString == id })?.tokens ?? tokens
    }

    private func flatDiff(_ a: [String: Any], _ b: [String: Any], prefix: String) -> [TokenDiff] {
        var results: [TokenDiff] = []
        for key in Set(a.keys).union(b.keys).sorted() {
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            if let da = a[key] as? [String: Any], let db = b[key] as? [String: Any] {
                results += flatDiff(da, db, prefix: path)
            } else {
                let sa = "\(a[key] ?? "nil")", sb = "\(b[key] ?? "nil")"
                if sa != sb { results.append(TokenDiff(path: path, valueA: sa, valueB: sb)) }
            }
        }
        return results
    }
}

struct TokenDiff: Identifiable {
    let id = UUID()
    let path: String
    let valueA: String
    let valueB: String
}
