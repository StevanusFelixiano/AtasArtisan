import SwiftUI

// Pieces the onboarding, History and Profile boards draw that the shared components don't have yet:
// the painting caption, the dashed ring (`<at-spin>`), the WhatsApp glyph (`<at-icon name="wa">`)
// and the 1-1 splash. Prefixed `Ob` so they can't collide with names other features add.

extension View {
    /// Design-system type at an explicit size (the boards often use a style at a size the scale doesn't name).
    func obText(_ style: Brand.Style, _ size: CGFloat, weight: CGFloat? = nil, tracking: CGFloat = 0, _ color: Color = Brand.cocoa) -> some View {
        self.font(Brand.font(style, size: size, weight: weight))
            .tracking(size * tracking)
            .foregroundStyle(color)
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

/// `<at-spin>`: the dashed ring. It turns a quarter (`Motion.ringStep`) each time `turns` goes up, on the slow
/// critically damped `Motion.ringTurn`, then rests: a real step turns it, waiting never does. `from` is where it sits
/// at `turns` 0. Reduce Motion keeps it still.
struct ObRing: View {
    var size: CGFloat
    var color: Color = Brand.caramel
    var turns = 0
    var from: Angle = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Circle()
            .inset(by: size * 0.01)
            .stroke(color, style: StrokeStyle(lineWidth: 1.2, dash: [size * 0.03, size * 0.03]))
            .frame(width: size, height: size)
            .rotationEffect(reduceMotion ? .zero : .degrees(from.degrees + Motion.ringStep.degrees * Double(turns)))
            .animation(reduceMotion ? nil : Motion.ringTurn, value: turns)
            .accessibilityHidden(true)
    }
}

/// "Verify with WhatsApp": a pill label with the WhatsApp glyph as its icon.
struct ObWhatsAppLabel: View {
    var title: String
    var body: some View {
        Label { Text(title) } icon: { ObWhatsAppGlyph(size: 20) }
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

/// 1-1 Splash: caramel screen, giraffe in the dashed ring, the cream logo pill, "Proofing the dough…".
/// RootView shows it while the session loads. On launch the ring turns a quarter into place (−90° → 0°), the giraffe
/// settles from 0.9, the logo drops in from 24 pt above and the caption fades in; while it waits nothing moves. When
/// the app is `ready` the ring turns a further quarter and the logo bumps, then RootView crossfades to the next screen.
/// Reduce Motion: the logo and caption fade in; the ring and giraffe are still.
struct SplashView: View {
    var ready = false
    @State private var launched = false
    @State private var bumps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Brand.caramel.ignoresSafeArea()
            VStack(spacing: 40) {
                ZStack {
                    ObRing(size: 260, color: Brand.cream, turns: (launched ? 1 : 0) + (ready ? 1 : 0), from: SplashMotion.ringFrom)
                    Mascot(pose: "pose-neutral", size: 216, fill: Brand.choc100)
                        .entrance(launched, scale: SplashMotion.mascotFrom, Motion.bounce, fades: false, delay: SplashMotion.mascotDelay)
                }
                Text("ataste")
                    .obText(.display, 46, tracking: -0.03, Brand.caramel)
                    .padding(.horizontal, 26).padding(.top, 6).padding(.bottom, 10)
                    .background(Capsule().fill(Brand.cream))
                    .background(Capsule().fill(Brand.cocoa).offset(y: 5))
                    .kick(reduceMotion ? 0 : bumps, from: SplashMotion.readyBump)
                    .entrance(launched, offset: SplashMotion.logoOffset, Motion.arrive, fade: nil, delay: SplashMotion.logoDelay)
                    .accessibilityLabel("Ataste")
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .bottom) {
            Text("Proofing the dough…").obText(.title2, 20, Brand.cream).padding(.bottom, 50)
                .entrance(launched, Motion.fade, delay: SplashMotion.captionDelay)
        }
        .onAppear { launched = true }
        .onChange(of: ready) { _, r in if r { bumps += 1 } }
    }
}
