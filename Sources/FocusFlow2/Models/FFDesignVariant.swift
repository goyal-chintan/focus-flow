import Foundation

struct FFDesignVariant: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var createdAt: Date
    var modifiedAt: Date
    var tokens: FFDesignTokens
    var isLocked: Bool

    init(name: String, description: String = "", tokens: FFDesignTokens) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.tokens = tokens
        self.isLocked = false
    }

    static func == (lhs: FFDesignVariant, rhs: FFDesignVariant) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
