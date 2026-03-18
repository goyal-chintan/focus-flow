import SwiftUI

struct TokenSlider: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let defaultValue: CGFloat
    var onEditStart: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(.body, design: .monospaced))
                .frame(width: 180, alignment: .leading)

            Slider(value: $value, in: range, step: step) { editing in
                if editing { onEditStart?() }
            }

            Text(formattedValue)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)

            Button {
                value = defaultValue
            } label: {
                Image(systemName: "arrow.counterclockwise").font(.caption)
            }
            .buttonStyle(.plain)
            .opacity(value != defaultValue ? 1 : 0.3)
            .disabled(value == defaultValue)
        }
    }

    private var formattedValue: String {
        if step >= 1 { String(format: "%.0f", value) }
        else if step >= 0.1 { String(format: "%.1f", value) }
        else { String(format: "%.2f", value) }
    }
}

struct TokenPicker<T: Hashable & CaseIterable & RawRepresentable>: View where T.AllCases: RandomAccessCollection, T.RawValue == String {
    let label: String
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(.body, design: .monospaced))
                .frame(width: 180, alignment: .leading)
            Picker("", selection: $selection) {
                ForEach(Array(T.allCases), id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .labelsHidden()
        }
    }
}

struct TokenColorPicker: View {
    let label: String
    @Binding var selection: FFColorToken

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(.body, design: .monospaced))
                .frame(width: 180, alignment: .leading)
            Circle().fill(selection.color).frame(width: 20, height: 20)
            Picker("", selection: $selection) {
                ForEach(FFColorToken.allCases, id: \.self) { color in
                    HStack {
                        Circle().fill(color.color).frame(width: 12, height: 12)
                        Text(color.rawValue)
                    }.tag(color)
                }
            }
            .labelsHidden().frame(width: 140)
        }
    }
}

struct TokenSpringPreview: View {
    let response: CGFloat
    let damping: CGFloat
    @State private var isAnimated = false

    var body: some View {
        HStack {
            Circle().fill(.blue).frame(width: 16, height: 16)
                .offset(x: isAnimated ? 120 : 0)
                .animation(.spring(response: response, dampingFraction: damping), value: isAnimated)
            Spacer()
            Button("Preview") { isAnimated.toggle() }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .frame(height: 24).padding(.leading, 188)
    }
}

struct LabSectionHeader: View {
    let title: String
    let resetAction: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button("Reset Section") { resetAction() }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }
}
