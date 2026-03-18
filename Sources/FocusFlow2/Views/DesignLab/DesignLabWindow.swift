import SwiftUI

enum DesignLabCategory: String, CaseIterable, Hashable {
    case workbench, spacing, radius, sizing, ring, typography, color, motion, layout

    var title: String {
        switch self {
        case .workbench: "Workbench"
        default: rawValue.capitalized
        }
    }

    var icon: String {
        switch self {
        case .workbench: "square.grid.3x3.fill"
        case .spacing: "ruler"
        case .radius: "square.on.circle"
        case .sizing: "arrow.up.left.and.arrow.down.right"
        case .ring: "timer"
        case .typography: "textformat.size"
        case .color: "paintpalette"
        case .motion: "waveform.path"
        case .layout: "rectangle.3.group"
        }
    }
}

struct DesignLabWindow: View {
    @Environment(FFDesignTokens.self) private var tokens
    @Environment(FFDesignLabStore.self) private var store
    @State private var selectedCategory: DesignLabCategory = .workbench

    var body: some View {
        NavigationSplitView {
            DesignLabSidebar(selectedCategory: $selectedCategory)
        } detail: {
            detailContent
        }
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Undo") { _ = store.popUndo(into: tokens) }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(store.undoStack.isEmpty)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedCategory {
        case .workbench: DesignLabWorkbenchView()
        case .spacing: SpacingLabSection()
        case .radius: RadiusLabSection()
        case .sizing: SizingLabSection()
        case .ring: RingLabSection()
        case .typography: TypographyLabSection()
        case .color: ColorLabSection()
        case .motion: MotionLabSection()
        case .layout: LayoutLabSection()
        }
    }
}
