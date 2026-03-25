import Foundation

struct EarnedBreakSuggestionInput {
    let effectiveEffortSeconds: Int
    let overtimeSeconds: Int
    let runCreditSeconds: Int
    let adaptationMinutes: Int
}

struct EarnedBreakSuggestion {
    let suggestedMinutes: Int
    let adaptationAppliedMinutes: Int
}

struct EarnedBreakSuggestionEngine {
    func suggest(_ input: EarnedBreakSuggestionInput) -> EarnedBreakSuggestion {
        let effortMinutes = max(0, input.effectiveEffortSeconds / 60)
        let baseline: Int
        switch effortMinutes {
        case ..<25: baseline = 5
        case 25..<40: baseline = 8
        case 40..<55: baseline = 12
        case 55..<75: baseline = 15
        default: baseline = 20
        }

        let overtimeBonus = input.overtimeSeconds > 0 ? 2 : 0
        let clampedAdaptation = min(3, max(-3, input.adaptationMinutes))
        let raw = baseline + overtimeBonus + clampedAdaptation
        let suggested = min(20, max(5, raw))

        return EarnedBreakSuggestion(
            suggestedMinutes: suggested,
            adaptationAppliedMinutes: clampedAdaptation
        )
    }
}
