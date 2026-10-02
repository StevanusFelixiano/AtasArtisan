import SwiftUI

/// The tab bar, design board "Ataste Tab Bar" direction 1a (Cocoa sticker): a cocoa capsule on a hard caramel edge,
/// and a stitched choc100 pill that stretches like dough between tabs and opens to show the label.
/// Motion values are the board's `TabMotion` table, one to one. It replaces the native Liquid Glass bar.
// ponytail: no badge and no disabled tab; nothing in the app drives either yet. Both are specced on the board.
struct AtasteTabBar: View {
    @Binding var selection: Int
    var hidden: Hidden?
    /// The bottom safe-area inset (34 on Face ID iPhones): the bar is placed from the screen edge, not the safe area.
    var safeBottom: CGFloat
    var retap: (Int) -> Void

    enum Hidden { case pushed, keyboard }

    /// The bar's top edge sits this far above the screen's bottom edge (30 + 64).
    static let top: CGFloat = 94

    private static let tabs: [(title: String, kind: TabIcon.Kind)] = [("Home", .home), ("History", .history), ("Profile", .profile)]
    private static let labelFont = Brand.uiFont(.roundo, size: 15, weight: 700)
    private static let labelWidths = tabs.map { ($0.title as NSString).size(withAttributes: [.font: labelFont]).width.rounded(.up) }

    @State private var width: CGFloat = 0
    @State private var pressed: Int?
    @State private var from = 0
    @State private var bounces = [0, 0, 0]
    @State private var hops = [0, 0, 0]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(stops: [.init(color: Brand.cream.opacity(0), location: 0),
                                   .init(color: Brand.cream.opacity(0.85), location: 0.7),
                                   .init(color: Brand.cream.opacity(0.85), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 124)
                .allowsHitTesting(false)
            bar
                .offset(y: hidden == nil || reduceMotion ? 0 : hidden == .keyboard ? 24 : 120)
                .scaleEffect(hidden == nil || reduceMotion ? 1 : 0.96, anchor: .bottom)
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
        }
        // TODO(root cause): ignoresSafeArea(edges: .bottom) left the bar inside the safe area (on the ZStack, on each
        // child, as an overlay or a sibling), so it is shifted down by the measured inset to sit 30pt above the edge.
        .offset(y: safeBottom)
        .opacity(hidden == nil ? 1 : 0)
        .animation(visibility, value: hidden)
        .allowsHitTesting(hidden == nil)
        .sensoryFeedback(.selection, trigger: selection)
        .sensoryFeedback(.impact(weight: .light), trigger: hops)
        .onChange(of: selection) { _, new in
            from = new
            if !reduceMotion { bounces[new] += 1 }
        }
    }

    private var visibility: Animation {
        switch hidden {
        case .pushed: reduceMotion ? TabMotion.Reduced.pushHide : TabMotion.pushHide
        case .keyboard: reduceMotion ? TabMotion.Reduced.keyboard : TabMotion.keyboardHide
        // ponytail: keyboard-down reuses the pop spring (0.42/0.72 vs the board's 0.40/0.80); indistinguishable.
        case nil: reduceMotion ? TabMotion.Reduced.show : TabMotion.popShow
        }
    }

    private var bar: some View {
        let cell = max(0, (width - 16) / 3)
        return ZStack(alignment: .leading) {
            pill(cell: cell)
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { i in tab(i, cell: cell) }
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background {
            Capsule().fill(Brand.cocoa)
                .background { Capsule().fill(Brand.caramel).offset(y: 4) }
                // CSS 0 18 30 −10: SwiftUI has no spread, so the shadow comes from a capsule inset by the spread.
                .background { Capsule().inset(by: 10).fill(Brand.cocoa).shadow(color: Brand.cocoa.opacity(0.45), radius: 15, y: 18) }
        }
    }

    // MARK: Selected pill

    @ViewBuilder
    private func pill(cell: CGFloat) -> some View {
        if reduceMotion {
            // No travel: the old pill fades out and the new one fades in.
            ForEach(0..<3, id: \.self) { i in
                pillShape(selected: i)
                    .frame(width: 59 + Self.labelWidths[i])
                    .padding(.leading, edges(i, cell: cell).l)
                    .opacity(selection == i ? 1 : 0)
                    .animation(TabMotion.Reduced.pill, value: selection)
            }
        } else {
            // Two edges on two springs: the edge nearest the new tab leads, the far one trails, so the pill stretches.
            let (l, r) = edges(selection, cell: cell)
            let right = selection > from
            pillShape(selected: selection)
                .scaleEffect(pressed == selection ? TabMotion.pillPressScale : CGSize(width: 1, height: 1))
                .animation(pressed == selection ? TabMotion.pressDown : TabMotion.pressUp, value: pressed == selection)
                .padding(.leading, l)
                .animation(right ? TabMotion.pillTrail : TabMotion.pillLead, value: l)
                .padding(.trailing, max(0, width - r))
                .animation(right ? TabMotion.pillLead : TabMotion.pillTrail, value: r)
                .frame(width: width)
        }
    }

    private func pillShape(selected i: Int) -> some View {
        Capsule().fill(pressed == i ? Brand.choc100Pressed : Brand.choc100)
            .overlay {
                Capsule().inset(by: 3.75)
                    .stroke(Brand.caramel.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            .frame(height: 48)
    }

    /// The pill is 14 + icon 24 + gap 7 + label + 14 wide, centred on its cell.
    private func edges(_ i: Int, cell: CGFloat) -> (l: CGFloat, r: CGFloat) {
        let centre = 8 + cell * (CGFloat(i) + 0.5)
        let half = (59 + Self.labelWidths[i]) / 2
        return (centre - half, centre + half)
    }

    // MARK: Tab cell

    private func tab(_ i: Int, cell: CGFloat) -> some View {
        let selected = selection == i
        let down = pressed == i
        let (title, kind) = Self.tabs[i]
        return Button {
            if selected {
                hops[i] += 1
                retap(i)
            } else {
                selection = i
            }
        } label: {
            HStack(spacing: 0) {
                TabIcon(kind: kind, filled: selected,
                        ink: down && !selected ? Brand.cream : Brand.liquorice400,
                        pill: down ? Brand.choc100Pressed : Brand.choc100)
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: bounces[i]) { v, s in v.scaleEffect(s) } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(0.7, duration: 0.07)
                            SpringKeyframe(1, duration: 0.6, spring: Spring(response: 0.38, dampingRatio: 0.45))
                        }
                    }
                    .keyframeAnimator(initialValue: CGFloat(0), trigger: reduceMotion ? 0 : hops[i]) { v, y in v.offset(y: y) } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(-5, duration: 0.08)
                            SpringKeyframe(0, duration: 0.5, spring: Spring(response: 0.30, dampingRatio: 0.45))
                        }
                    }
                Text(title)
                    .font(Font(Self.labelFont))
                    .foregroundStyle(Brand.cocoa)
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(selected ? 1 : 0)
                    .offset(x: selected || reduceMotion ? 0 : -6)
                    .animation(reduceMotion ? TabMotion.Reduced.label : selected ? TabMotion.labelIn : TabMotion.labelOut, value: selected)
                    .padding(.leading, 7)
                    .frame(width: selected ? 7 + Self.labelWidths[i] : 0, alignment: .leading)
                    .clipped()
            }
            // The label opening also slides the icon left, so the whole row follows the label's spring.
            .animation(reduceMotion ? nil : selected ? TabMotion.labelOpen : TabMotion.labelClose, value: selected)
            .scaleEffect(down && !reduceMotion ? TabMotion.pressScale : CGSize(width: 1, height: 1))
            .opacity(down && reduceMotion ? TabMotion.Reduced.pressDim : 1)
            .animation(reduceMotion ? (down ? TabMotion.Reduced.press : TabMotion.Reduced.release)
                                    : (down ? TabMotion.pressDown : TabMotion.pressUp), value: down)
            .frame(width: cell, height: 64)
            .background {
                Capsule().fill(Brand.cream.opacity(0.13))
                    .frame(width: 64, height: 48)
                    .opacity(down && !selected ? 1 : 0)
                    .animation(down ? TabMotion.haloIn : TabMotion.haloOut, value: down)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle { p in pressed = p ? i : (pressed == i ? nil : pressed) })
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A plain button that reports touch down and up, so the pill (a separate layer) can react to the press.
    private struct PressStyle: ButtonStyle {
        var onPress: (Bool) -> Void
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.onChange(of: configuration.isPressed) { _, p in onPress(p) }
        }
    }
}

/// The board's redrawn tab icons: 24 × 24, 2.25 stroke, round caps and joins. Idle is an outline; selected is filled
/// cocoa with its details cut out in the pill colour. The two cross-fade.
struct TabIcon: View {
    enum Kind { case home, history, profile }
    var kind: Kind
    var filled: Bool
    var ink: Color
    var pill: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let line = StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round)

    var body: some View {
        ZStack {
            outline.stroke(ink, style: Self.line).opacity(filled ? 0 : 1)
            solid.opacity(filled ? 1 : 0)
        }
        .frame(width: 24, height: 24)
        .animation(reduceMotion ? TabMotion.Reduced.iconSwap : TabMotion.iconSwap, value: filled)
        .animation(TabMotion.pressDown, value: ink)
    }

    private var outline: Path {
        switch kind {
        case .home: Path { p in house(&p); chimney(&p, closed: false); door(&p, to: 21, closed: false) }
        case .history: Path { p in clockRim(&p); clockArrow(&p); clockHands(&p) }
        case .profile: Path { p in head(&p); shoulders(&p, closed: false) }
        }
    }

    @ViewBuilder
    private var solid: some View {
        let cocoa = Brand.cocoa
        switch kind {
        case .home:
            let body = Path { p in house(&p); chimney(&p, closed: true) }
            ZStack {
                body.fill(cocoa)
                body.stroke(cocoa, style: Self.line)
                Path { door(&$0, to: 22.3, closed: true) }.fill(pill)
            }
        case .history:
            let rim = Path(ellipseIn: CGRect(x: 4, y: 4, width: 16, height: 16))
            ZStack {
                rim.fill(cocoa)
                rim.stroke(cocoa, style: Self.line)
                Path { p in p.move(to: CGPoint(x: 6.35, y: 6.34)); p.addLine(to: CGPoint(x: 4, y: 8.7)); clockArrow(&p) }
                    .stroke(cocoa, style: Self.line)
                Path { clockHands(&$0) }.stroke(pill, style: Self.line)
            }
        case .profile:
            let body = Path { p in head(&p); shoulders(&p, closed: true) }
            ZStack {
                body.fill(cocoa)
                body.stroke(cocoa, style: Self.line)
            }
        }
    }

    // SVG paths from the board, viewBox 0 0 24 24.

    /// M4 10.4 L12 4 l8 6.4 V19 a2 2 0 0 1-2 2 H6 a2 2 0 0 1-2-2 z
    private func house(_ p: inout Path) {
        p.move(to: CGPoint(x: 4, y: 10.4))
        p.addLine(to: CGPoint(x: 12, y: 4))
        p.addLine(to: CGPoint(x: 20, y: 10.4))
        p.addLine(to: CGPoint(x: 20, y: 19))
        p.addArc(tangent1End: CGPoint(x: 20, y: 21), tangent2End: CGPoint(x: 18, y: 21), radius: 2)
        p.addLine(to: CGPoint(x: 6, y: 21))
        p.addArc(tangent1End: CGPoint(x: 4, y: 21), tangent2End: CGPoint(x: 4, y: 19), radius: 2)
        p.closeSubpath()
    }

    /// M16.2 7.4 V4.8 h2.4 v4.5 (z when filled)
    private func chimney(_ p: inout Path, closed: Bool) {
        p.move(to: CGPoint(x: 16.2, y: 7.4))
        p.addLine(to: CGPoint(x: 16.2, y: 4.8))
        p.addLine(to: CGPoint(x: 18.6, y: 4.8))
        p.addLine(to: CGPoint(x: 18.6, y: 9.3))
        if closed { p.closeSubpath() }
    }

    /// M10 21 V17.4 a2 2 0 0 1 4 0 V21; the filled cut-out runs to 22.3 and closes.
    private func door(_ p: inout Path, to bottom: CGFloat, closed: Bool) {
        p.move(to: CGPoint(x: 10, y: bottom))
        p.addLine(to: CGPoint(x: 10, y: 17.4))
        p.addArc(center: CGPoint(x: 12, y: 17.4), radius: 2, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        p.addLine(to: CGPoint(x: 14, y: bottom))
        if closed { p.closeSubpath() }
    }

    /// M4 12 a8 8 0 1 0 2.35-5.66 L4 8.7
    private func clockRim(_ p: inout Path) {
        p.move(to: CGPoint(x: 4, y: 12))
        p.addArc(center: CGPoint(x: 12, y: 12), radius: 8, startAngle: .degrees(180), endAngle: .degrees(-135), clockwise: true)
        p.addLine(to: CGPoint(x: 4, y: 8.7))
    }

    /// M4 4.3 v4.4 h4.4
    private func clockArrow(_ p: inout Path) {
        p.move(to: CGPoint(x: 4, y: 4.3))
        p.addLine(to: CGPoint(x: 4, y: 8.7))
        p.addLine(to: CGPoint(x: 8.4, y: 8.7))
    }

    /// M12 8 v4 l2.8 1.8
    private func clockHands(_ p: inout Path) {
        p.move(to: CGPoint(x: 12, y: 8))
        p.addLine(to: CGPoint(x: 12, y: 12))
        p.addLine(to: CGPoint(x: 14.8, y: 13.8))
    }

    private func head(_ p: inout Path) {
        p.addEllipse(in: CGRect(x: 12 - 3.9, y: 8.2 - 3.9, width: 7.8, height: 7.8))
    }

    /// M4.8 20.2 c.9-3.7 3.8-5.9 7.2-5.9 s6.3 2.2 7.2 5.9; the filled one rounds the base and closes.
    private func shoulders(_ p: inout Path, closed: Bool) {
        p.move(to: CGPoint(x: 4.8, y: 20.2))
        p.addCurve(to: CGPoint(x: 12, y: 14.3), control1: CGPoint(x: 5.7, y: 16.5), control2: CGPoint(x: 8.6, y: 14.3))
        p.addCurve(to: CGPoint(x: 19.2, y: 20.2), control1: CGPoint(x: 15.4, y: 14.3), control2: CGPoint(x: 18.3, y: 16.5))
        guard closed else { return }
        p.addCurve(to: CGPoint(x: 18.4, y: 21.1), control1: CGPoint(x: 19.3, y: 20.7), control2: CGPoint(x: 18.9, y: 21.1))
        p.addLine(to: CGPoint(x: 5.6, y: 21.1))
        p.addCurve(to: CGPoint(x: 4.8, y: 20.2), control1: CGPoint(x: 5.1, y: 21.1), control2: CGPoint(x: 4.7, y: 20.7))
        p.closeSubpath()
    }
}

/// Re-tapping the selected tab scrolls its root to the top. Each tab root's ScrollView reads its tab's re-tap count.
extension EnvironmentValues {
    @Entry var tabRetap = 0
}

extension View {
    func scrollsToTopOnRetap() -> some View { modifier(RetapScroll()) }
}

private struct RetapScroll: ViewModifier {
    @Environment(\.tabRetap) private var retap
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = ScrollPosition(edge: .top)

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onChange(of: retap) {
                withAnimation(reduceMotion ? nil : TabMotion.scrollToTop) { position.scrollTo(edge: .top) }
            }
    }
}

/// Ataste tab bar motion, the board's constants file. Values match the prototype one to one.
enum TabMotion {
    // Press
    static let pressScale = CGSize(width: 1.08, height: 0.88)
    static let pillPressScale = CGSize(width: 1.04, height: 0.92)
    static let pressDown = Animation.spring(response: 0.20, dampingFraction: 0.75)
    static let pressUp = Animation.spring(response: 0.38, dampingFraction: 0.50)
    static let haloIn = Animation.easeOut(duration: 0.08)
    static let haloOut = Animation.easeOut(duration: 0.15)

    // Select: the pill's two edges animate separately so it stretches
    static let pillLead = Animation.spring(response: 0.30, dampingFraction: 0.78)
    static let pillTrail = Animation.spring(response: 0.44, dampingFraction: 0.82)
    static let iconSwap = Animation.easeOut(duration: 0.12)
    static let labelOpen = Animation.spring(response: 0.40, dampingFraction: 0.86).delay(0.04)
    static let labelIn = Animation.easeOut(duration: 0.18).delay(0.08)
    static let labelOut = Animation.easeIn(duration: 0.10)
    static let labelClose = Animation.spring(response: 0.32, dampingFraction: 1.0)
    static let screenSwap = Animation.easeOut(duration: 0.15)
    static let iconDip = Animation.easeOut(duration: 0.07)
    static let iconBounce = Animation.spring(response: 0.38, dampingFraction: 0.45)

    // Badge, disabled tap: on the board, not drawn by the bar yet (no badge, no disabled tab). `Motion` reuses them.
    static let badgeIn = Animation.spring(response: 0.32, dampingFraction: 0.50)
    static let badgeBump = Animation.spring(response: 0.30, dampingFraction: 0.60)
    static let badgeOut = Animation.easeIn(duration: 0.15)
    /// Offset x at each time in seconds, linear between.
    static let shake: [(x: CGFloat, at: Double)] = [(4, 0.05), (-3, 0.12), (2, 0.19), (-1, 0.26), (0, 0.32)]

    // Re-tap
    static let scrollToTop = Animation.spring(response: 0.50, dampingFraction: 1.0)

    // Visibility
    static let pushHide = Animation.spring(response: 0.32, dampingFraction: 1.0)
    static let popShow = Animation.spring(response: 0.42, dampingFraction: 0.72).delay(0.06)
    static let keyboardHide = Animation.easeIn(duration: 0.16)

    /// Reduce Motion: opacity only, no scale, travel or offset.
    enum Reduced {
        static let pressDim: Double = 0.6
        static let press = Animation.easeOut(duration: 0.10)
        static let release = Animation.easeOut(duration: 0.15)
        static let pill = Animation.easeInOut(duration: 0.20)
        static let iconSwap = Animation.easeInOut(duration: 0.15)
        static let label = Animation.easeInOut(duration: 0.20)
        static let pushHide = Animation.easeOut(duration: 0.15)
        static let keyboard = Animation.easeIn(duration: 0.12)
        static let show = Animation.easeOut(duration: 0.20).delay(0.06)
    }
}
