import SwiftUI

enum FFLabBackdropStyle: String, CaseIterable, Identifiable {
    case studio = "Studio"
    case aurora = "Aurora"
    case contrast = "Contrast"
    case texture = "Texture"

    var id: String { rawValue }
}

struct FFLabBackdropView: View {
    let style: FFLabBackdropStyle

    var body: some View {
        ZStack {
            baseGradient

            if style != .studio {
                topGlow
            }

            if style == .contrast {
                contrastBands
            }

            if style == .texture {
                textureLayer
            }

            vignette
        }
        .ignoresSafeArea()
    }

    private var baseGradient: some View {
        LinearGradient(
            colors: baseColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var topGlow: some View {
        RadialGradient(
            colors: [Color.white.opacity(style == .aurora ? 0.16 : 0.12), .clear],
            center: .topLeading,
            startRadius: 24,
            endRadius: style == .aurora ? 420 : 340
        )
        .blendMode(.screen)
    }

    private var contrastBands: some View {
        VStack(spacing: 14) {
            ForEach(0..<18, id: \.self) { index in
                Rectangle()
                    .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.06) : Color.white.opacity(0.018))
                    .frame(height: 12)
            }
        }
        .padding(.horizontal, 20)
        .blur(radius: 0.35)
    }

    private var textureLayer: some View {
        ZStack {
            ForEach(textureOrbs) { orb in
                Ellipse()
                    .fill(orb.color)
                    .frame(width: orb.size.width, height: orb.size.height)
                    .offset(x: orb.offset.width, y: orb.offset.height)
                    .blur(radius: orb.blur)
                    .blendMode(.screen)
            }

            VStack(spacing: 18) {
                ForEach(0..<14, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.038) : Color.white.opacity(0.014))
                        .frame(height: 8)
                }
            }
            .padding(.horizontal, 16)
            .blur(radius: 0.5)
        }
    }

    private var vignette: some View {
        LinearGradient(
            colors: [Color.clear, Color.black.opacity(0.22)],
            startPoint: .center,
            endPoint: .bottom
        )
        .blendMode(.multiply)
    }

    private var baseColors: [Color] {
        switch style {
        case .studio:
            return [Color.black.opacity(0.22), Color.white.opacity(0.02), Color.black.opacity(0.18)]
        case .aurora:
            return [Color.black.opacity(0.24), Color.indigo.opacity(0.10), Color.teal.opacity(0.07), Color.black.opacity(0.20)]
        case .contrast:
            return [Color.black.opacity(0.36), Color.black.opacity(0.22), Color.black.opacity(0.32)]
        case .texture:
            return [Color.black.opacity(0.26), Color.blue.opacity(0.07), Color.cyan.opacity(0.05), Color.black.opacity(0.28)]
        }
    }

    private var textureOrbs: [BackdropOrb] {
        [
            BackdropOrb(color: Color.white.opacity(0.16), size: CGSize(width: 260, height: 180), offset: CGSize(width: -180, height: -180), blur: 28),
            BackdropOrb(color: Color.cyan.opacity(0.12), size: CGSize(width: 220, height: 220), offset: CGSize(width: 220, height: -160), blur: 30),
            BackdropOrb(color: Color.indigo.opacity(0.12), size: CGSize(width: 300, height: 240), offset: CGSize(width: -140, height: 180), blur: 34),
            BackdropOrb(color: Color.white.opacity(0.08), size: CGSize(width: 180, height: 140), offset: CGSize(width: 260, height: 180), blur: 22)
        ]
    }
}

private struct BackdropOrb: Identifiable {
    let id = UUID()
    let color: Color
    let size: CGSize
    let offset: CGSize
    let blur: CGFloat
}
