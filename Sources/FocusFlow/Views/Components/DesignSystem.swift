import SwiftUI

enum FFSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum FFRadius {
    static let control: CGFloat = 12
    static let card: CGFloat = 18
    static let hero: CGFloat = 28
}

enum FFType {
    static let heroTimer = Font.system(size: 52, weight: .ultraLight, design: .rounded)
    static let heroLabel = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let title = Font.system(.title3, design: .rounded).weight(.semibold)
    static let titleLarge = Font.system(.title2, design: .rounded).weight(.semibold)
    static let cardValue = Font.system(.title2, design: .rounded).weight(.semibold)
    static let body = Font.system(.body, design: .rounded)
    static let callout = Font.system(.callout, design: .rounded).weight(.semibold)
    static let meta = Font.system(.footnote, design: .rounded).weight(.medium)
    static let micro = Font.system(.caption, design: .rounded).weight(.medium)
}

enum FFColor {
    static let focus = Color.blue
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let deepFocus = Color.indigo
    static let panelBorder = Color.white.opacity(0.18)
    static let panelHighlight = Color.white.opacity(0.08)
    static let insetFill = Color.white.opacity(0.05)
}

enum FFMotion {
    static let popover = Animation.spring(response: 0.36, dampingFraction: 0.82)
    static let section = Animation.spring(response: 0.34, dampingFraction: 0.84)
    static let control = Animation.spring(response: 0.26, dampingFraction: 0.82)
    static let breathing = Animation.easeInOut(duration: 1.8).repeatForever(autoreverses: true)
}

extension View {
    func ffCardChrome(cornerRadius: CGFloat) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(FFColor.panelBorder)
        }
        .shadow(color: .black.opacity(0.08), radius: 22, y: 10)
    }
}
