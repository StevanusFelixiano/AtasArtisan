import SwiftUI

// Pieces the onboarding, History and Profile boards draw that the shared components don't have yet:
// the framed painting with its caption, the giraffe on a plain pastel circle, the slowly turning dashed ring
// (`<at-spin>`), the WhatsApp glyph (`<at-icon name="wa">`) and the cream pill with a choc-100 border.
// Prefixed `Ob` so they can't collide with names other features add.

extension View {
    /// Design-system type at an explicit size (the boards often use a style at a size the scale doesn't name).
    func obText(_ style: Brand.Style, _ size: CGFloat, weight: CGFloat? = nil, tracking: CGFloat = 0, _ color: Color = Brand.cocoa) -> some View {
        self.font(Brand.font(style, size: size, weight: weight))
            .tracking(size * tracking)
            .foregroundStyle(color)
    }
}

/// A painting in its caramel frame: 10–12 pt mat, dashed cream inner border, slight tilt, soft drop shadow.
struct ObPainting: View {
    var art: String
    var width: CGFloat
    var height: CGFloat
    var mat: CGFloat = 10
    var inset: CGFloat = 5
    var tilt: Double = -2
    var label: String

    var body: some View {
        Image(art).resizable().scaledToFill()
            .frame(width: width, height: height)
            .clipped()
            .padding(inset)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.cream.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .padding(mat)
            .background(RoundedRectangle(cornerRadius: 10).fill(Brand.caramel))
            .shadow(color: Brand.cocoa.opacity(0.25), radius: 15, y: 14)
            .rotationEffect(.degrees(tilt))
            .accessibilityElement()
            .accessibilityLabel("\(label), a giraffe painting")
    }
}

/// "*Girl with a Croissant* · oil on canvas"
struct ObCaption: View {
    var title: String
    var body: some View {
        // Manrope has no italic: the title is slanted by hand, as the browser does on the board.
        HStack(spacing: 0) {
            Text(title).transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.2, d: 1, tx: 2, ty: 0))
            Text(" · oil on canvas")
        }
        .obText(.footnote, 12, Brand.ink3)
        .lineLimit(1)
        .accessibilityHidden(true)
    }
}

/// The giraffe on a plain pastel circle (the boards' `image-slot` circles, without the Mascot's dashed ring).
struct ObArtCircle: View {
    var pose: String
    var size: CGFloat
    var fill: Color
    var art: CGFloat? = nil
    var body: some View {
        ZStack(alignment: .bottom) {
            Circle().fill(fill)
            Image(pose).resizable().scaledToFill().frame(width: art ?? size, height: art ?? size)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// `<at-spin>`: a dashed ring turning once every 14 s.
struct ObSpinRing: View {
    var size: CGFloat
    var color: Color = Brand.caramel
    @State private var turn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Circle()
            .inset(by: size * 0.01)
            .stroke(color, style: StrokeStyle(lineWidth: 1.2, dash: [size * 0.03, size * 0.03]))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(turn ? 360 : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { turn = true }
            }
            .accessibilityHidden(true)
    }
}

/// `<at-icon name="wa">`: the WhatsApp speech bubble with a handset, stroked like the other line icons.
struct ObWhatsAppGlyph: View {
    var size: CGFloat = 20
    var body: some View {
        WhatsAppShape()
            .stroke(style: StrokeStyle(lineWidth: 2 * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private struct WhatsAppShape: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
            var path = Path()
            // Bubble: M7.9 20 A9 9 0 1 0 4 16.1 L2 22 z (the long way round a radius-9 circle at 12,12).
            path.move(to: p(7.9, 20))
            path.addArc(center: p(12, 12), radius: 9 * s, startAngle: .degrees(117.1), endAngle: .degrees(152.9), clockwise: true)
            path.addLine(to: p(2, 22))
            path.closeSubpath()
            // Handset.
            path.move(to: p(9, 9.2))
            path.addCurve(to: p(14.8, 15), control1: p(9.2, 11.8), control2: p(12, 14.6))
            path.addLine(to: p(16, 13.6))
            path.addLine(to: p(14.1, 12.6))
            path.addLine(to: p(13.2, 13.3))
            path.addCurve(to: p(11.2, 11.3), control1: p(12.3, 12.9), control2: p(11.6, 12.2))
            path.addLine(to: p(11.9, 10.4))
            path.addLine(to: p(10.9, 8.5))
            path.closeSubpath()
            return path
        }
    }
}

/// Icon + title on a pill button (the boards put a 18–20 pt line icon before the label).
struct ObIconLabel: View {
    var title: String
    var symbol: String? = nil
    var whatsApp = false
    var body: some View {
        HStack(spacing: 10) {
            if whatsApp { ObWhatsAppGlyph(size: 20) }
            if let symbol { Image(systemName: symbol).font(.system(size: 17, weight: .semibold)) }
            Text(title)
        }
    }
}

/// The cream pill with a 4 pt choc-100 border ("Open WhatsApp again", "I've installed it").
struct ObOutlinePill: ButtonStyle {
    var fill: Color = Brand.cream
    var border: Color = Brand.choc100
    var ink: Color = Brand.cocoa
    var full = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Brand.font(.headline, size: 17, weight: 600))
            .lineLimit(1)
            .foregroundStyle(ink)
            .padding(.horizontal, 24)
            .frame(maxWidth: full ? .infinity : nil, minHeight: 60)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(border, lineWidth: 4))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .contentShape(Capsule())
    }
}

/// 1-1 Splash: caramel screen, giraffe in a turning ring, the cream logo pill, "Proofing the dough…".
/// RootView shows `LoaderView` while the session loads; this is the board's version of that moment.
struct SplashView: View {
    var body: some View {
        ZStack {
            Brand.caramel.ignoresSafeArea()
            VStack(spacing: 40) {
                ZStack {
                    ObSpinRing(size: 260, color: Brand.cream)
                    ObArtCircle(pose: "pose-neutral", size: 216, fill: Brand.choc100)
                }
                Text("ataste")
                    .obText(.display, 46, tracking: -0.03, Brand.caramel)
                    .padding(.horizontal, 26).padding(.top, 6).padding(.bottom, 10)
                    .background(Capsule().fill(Brand.cream))
                    .background(Capsule().fill(Brand.cocoa).offset(y: 5))
                    .accessibilityLabel("Ataste")
            }
        }
        .overlay(alignment: .bottom) {
            Text("Proofing the dough…").obText(.title2, 20, Brand.cream).padding(.bottom, 50)
        }
    }
}
