import Foundation

enum VariantLabMaterialProfile: String, CaseIterable, Identifiable {
    case crystal = "Crystal"
    case balanced = "Balanced"
    case frosted = "Frosted"

    var id: String { rawValue }
}
