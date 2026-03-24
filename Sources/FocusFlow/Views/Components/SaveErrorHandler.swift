import SwiftUI
import SwiftData

/// Lightweight save wrapper that surfaces errors as user-visible feedback
struct SaveErrorModifier: ViewModifier {
    @Binding var saveError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let error = saveError {
                    SaveErrorBanner(message: error) {
                        withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.3)) {
                            saveError = nil
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    .zIndex(100)
                }
            }
    }
}

struct SaveErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

extension View {
    func saveErrorOverlay(_ error: Binding<String?>) -> some View {
        modifier(SaveErrorModifier(saveError: error))
    }
}

/// Helper function to save with error handling
func saveWithFeedback(_ context: ModelContext, errorBinding: Binding<String?>) {
    do {
        try context.save()
    } catch {
        withAnimation(.spring(response: 0.3)) {
            errorBinding.wrappedValue = "Couldn't save: \(error.localizedDescription)"
        }
        // Auto-dismiss after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation(.spring(response: 0.3)) {
                if errorBinding.wrappedValue != nil {
                    errorBinding.wrappedValue = nil
                }
            }
        }
    }
}
