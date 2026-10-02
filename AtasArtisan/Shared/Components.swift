import SwiftUI

// The design system's building blocks (Claude Design "Ataste Design System"): pill buttons with a 4pt
// self-coloured border, pastel tags, white cards on cream, dashed photo circles, the Rp 200k bar,
// marquee bands, the giraffe in a pastel circle.

// MARK: Buttons

enum PillKind { case primary, secondary, dark, success, destructive }
enum PillSize { case large, medium, small }

/// Full pill with a border in the fill colour. Large: bottom action bar, 17pt, 60 tall, full width. Medium:
/// inline, 16pt, 52 tall. Small: rows and cards, 13pt, 3pt border, 36 tall (hit area 44). Pressed and disabled
/// colours are the design system's own cells, not an opacity. Every pill squashes on press (wide for large,
/// compact for medium and small) and gives a light tap when it commits, a medium one for destructive.
struct PillStyle: PrimitiveButtonStyle {
    var kind: PillKind = .primary
    var size: PillSize = .large
    /// 12 pt side padding instead of 32, for a large pill that shares its row.
    var tight = false
    /// `AsyncPill`'s loading fill: the share of the face's width and its opacity.
    var loading: (width: CGFloat, opacity: Double)? = nil

    func makeBody(configuration: Configuration) -> some View {
        CommitButton(configuration: configuration, face: PillFace(kind: kind, size: size, tight: tight, loading: loading),
                     haptic: kind == .destructive ? Haptic.heavy : Haptic.tap)
    }
}

/// The pill itself: colours for its kind and state, the loading fill, the press.
private struct PillFace: ButtonStyle {
    var kind: PillKind
    var size: PillSize
    var tight: Bool
    var loading: (width: CGFloat, opacity: Double)?
    @Environment(\.isEnabled) private var enabled

    private func colors(pressed: Bool) -> (fill: Color, border: Color, ink: Color) {
        switch (kind, enabled, pressed) {
        case (.primary, false, _): (Brand.liquorice400, Brand.liquorice400, Brand.cream)
        case (.primary, true, true): (Brand.caramelPressed, Brand.caramelPressed, Brand.cream)
        case (.primary, true, false): (Brand.caramel, Brand.caramel, Brand.cream)
        case (.secondary, false, _): (Brand.cream, Brand.liquorice100, Brand.liquorice400)
        case (.secondary, true, true): (Brand.creamPressed, Brand.choc100Pressed, Brand.cocoa)
        case (.secondary, true, false): (Brand.cream, Brand.choc100, Brand.cocoa)
        case (.dark, false, _): (Brand.liquorice400, Brand.liquorice400, Brand.cream)
        case (.dark, true, true): (Brand.cocoaPressed, Brand.cocoaPressed, Brand.cream)
        case (.dark, true, false): (Brand.cocoa, Brand.cocoa, Brand.cream)
        case (.success, false, _): (Brand.liquorice100, Brand.liquorice100, Brand.liquorice400)
        case (.success, true, true): (Brand.limePressed, Brand.limeDeepPressed, Brand.cocoa)
        case (.success, true, false): (Brand.lime, Brand.limeDeep, Brand.cocoa)
        case (.destructive, false, _): (.white, Brand.destructiveSoft, Brand.destructive)
        case (.destructive, true, true): (Brand.destructivePressed, Brand.destructivePressed, .white)
        case (.destructive, true, false): (Brand.destructive, Brand.destructive, .white)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let c = colors(pressed: pressed)
        let small = size == .small
        configuration.label
            .labelStyle(PillLabel(spacing: small ? 6 : 8, icon: small ? 14 : 18))
            .font(Brand.font(.body, size: size == .large ? 17 : small ? 13 : 16, weight: 600))
            .lineLimit(1)
            .minimumScaleFactor(tight ? 0.85 : 1)
            .padding(.horizontal, tight ? 12 : small ? 16 : 32)
            .frame(maxWidth: size == .large ? .infinity : nil, minHeight: size == .large ? 60 : small ? 36 : 52)
            .foregroundStyle(c.ink)
            .background {
                Capsule().fill(c.fill)
                    .overlay(alignment: .leading) {
                        // Cream at 24 % from the left edge, under the label; the face's capsule clips its leading end.
                        if let loading {
                            GeometryReader { g in Rectangle().fill(Brand.cream.opacity(0.24)).frame(width: g.size.width * loading.width) }
                                .opacity(loading.opacity)
                        }
                    }
                    .clipShape(Capsule())
                    .pressTone(pressed)
            }
            .overlay(Capsule().strokeBorder(c.border, lineWidth: small ? 3 : 4).pressTone(pressed))
            .contentShape(Capsule())
            .doughPress(pressed, squash: size == .large ? Motion.pressWide : Motion.pressCompact)
            .frame(minHeight: 44)
    }
}

private struct PillLabel: LabelStyle {
    var spacing: CGFloat
    var icon: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon.font(.system(size: icon, weight: .semibold))
            configuration.title
        }
    }
}

extension PrimitiveButtonStyle where Self == PillStyle {
    static func pill(_ kind: PillKind = .primary, _ size: PillSize = .large) -> PillStyle { PillStyle(kind: kind, size: size) }
}

/// 28pt round icon button with a 44pt tap area.
struct IconCircle: View {
    var symbol: String
    var fill: Color = Brand.choc100
    var ink: Color = Brand.cocoa
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(ink)
                .frame(width: 28, height: 28).background(Circle().fill(fill))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(DoughStyle())
    }
}

// MARK: Icons

/// The design's `wa` icon (speech bubble with a handset), stroked like the other line icons.
struct WhatsAppGlyph: View {
    var size: CGFloat = 20
    var color: Color? = nil
    var lineWidth: CGFloat = 2
    var body: some View {
        let shape = WhatsAppShape().stroke(style: StrokeStyle(lineWidth: lineWidth * size / 24, lineCap: .round, lineJoin: .round))
        Group { if let color { shape.foregroundStyle(color) } else { shape } }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct WhatsAppShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        // Bubble: a circle r 9 around (12, 12) from the tail's lower edge round to its upper edge, tail at (2, 22).
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

// MARK: Tags and state

enum TagSize { case regular, small, large }

/// `<at-tag>`: uppercase Manrope 600 with 0.03em tracking on a pastel capsule. Regular 11pt (cards, rows),
/// small 10pt, large 12pt (product tags). Optional leading dot (order state) or check (paid, accepted).
/// A tag whose text changes on screen (order or payment state) moves to the new one: the width grows from the leading
/// edge, the colours change, the old label rolls up and out as the new one rolls in, then the tag bumps. Reduce
/// Motion crossfades. Appearing, it is still.
struct Tag: View {
    var text: String
    var fill: Color = Brand.choc100
    var ink: Color = Brand.cocoa
    var dot: Color? = nil
    var border: Color? = nil
    var check = false
    var size: TagSize = .regular
    @State private var labelWidth: CGFloat?
    @State private var changes = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fs: CGFloat = switch size { case .regular: 11; case .small: 10; case .large: 12 }
        let side: CGFloat = switch size { case .regular: 14; case .small: 10; case .large: 16 }
        let label = { (t: String) in Text(t).font(Brand.font(.label, size: fs, weight: 600)).tracking(fs * 0.03).textCase(.uppercase) }
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            if check { Image(systemName: "checkmark").font(.system(size: fs - 1, weight: .heavy)) }
            ZStack(alignment: .leading) {
                label(text).fixedSize().id(text).transition(AnyTransition.roll(reduceMotion).animation(reduceMotion ? Motion.Reduced.fade : Motion.digits))
            }
            .frame(width: labelWidth, alignment: .leading)
            .background {
                label(text).fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
                        if labelWidth == nil || reduceMotion { labelWidth = w } else { withAnimation(Motion.doughLead) { labelWidth = w } }
                    }
            }
        }
        .lineLimit(1)
        .padding(.vertical, size == .small ? 2 : 4)
        .padding(.leading, dot != nil || check ? (size == .small ? 8 : 10) : side)
        .padding(.trailing, side)
        .foregroundStyle(ink)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(border ?? .clear, lineWidth: 1.5))
        .animation(reduceMotion ? Motion.Reduced.fade : Motion.quick, value: text)
        .clipShape(Capsule())
        .geometryGroup()
        .kick(reduceMotion ? 0 : changes, from: StatusMotion.bumpFrom, delay: StatusMotion.bumpDelay)
        .fixedSize()
        .onChange(of: text) { changes += 1 }
    }
}

struct StateTag: View {
    var state: GroupState
    var size: TagSize = .regular
    var body: some View {
        let (bg, fg, dot): (Color, Color, Color) = switch state {
        case .open: (Brand.lime, Brand.cocoa, Brand.limeInk)
        case .locked: (Brand.liquorice100, Brand.cocoa, Brand.cocoa)
        case .edits: (Brand.pink100, Brand.cocoa, Brand.editsInk)
        case .sent: (Brand.choc100, Brand.cocoa, Brand.caramel)
        case .confirmed: (Brand.caramel, Brand.cream, Brand.choc100)
        case .delivered: (Brand.cocoa, Brand.lime, Brand.lime)
        case .closed: (.white, Brand.ink3, Brand.liquorice400)
        case .cancelled: (Brand.cancelledFill, Brand.cancelledInk, Brand.destructive)
        }
        Tag(text: state.title, fill: bg, ink: fg, dot: dot, size: size)
            .accessibilityLabel("Status: \(state.title)")
    }
}

enum PayState {
    case unpaid, says, paid
    init(_ row: BillRow) { self = row.paid_at != nil ? .paid : row.proof_at != nil ? .says : .unpaid }
}

struct PayTag: View {
    var state: PayState
    var size: TagSize = .regular
    var body: some View {
        switch state {
        case .unpaid: Tag(text: "Unpaid", fill: .white, border: Brand.liquorice400, size: size)
        case .says: Tag(text: "Says paid", fill: Brand.choc100, size: size)
        case .paid: Tag(text: "Paid", fill: Brand.lime, border: Brand.limeDeep, check: true, size: size)
        }
    }
}

// MARK: Surfaces

extension View {
    func card(_ radius: CGFloat = Brand.rCard, padding: CGFloat = Brand.s4) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Brand.card))
    }

    /// A full screen on cream. The frame comes first: a narrow view (a spinner while loading) must still paint
    /// the whole screen, or the black window shows on both sides.
    func screen() -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.cream.ignoresSafeArea())
            .toolbarBackground(Brand.cream, for: .navigationBar)
    }
}

/// The art people can pick as their profile picture (Ataste's own, never an upload).
enum Art {
    static let poses = ["pose-neutral", "pose-waving", "pose-cakebox", "pose-waiting", "pose-celebrating",
                        "pose-confused", "pose-sleeping", "pose-delivery", "pose-phone", "pose-splitting"]
    static let paintings = ["paint-monalisa", "paint-croissant", "paint-scream", "paint-gothic", "paint-brioche",
                            "paint-sonofbun", "paint-vangogh", "paint-supper", "paint-creation"]
    static var all: [String] { poses + paintings }

    /// Background swatches for the profile picture (design 6-5b): key stored in `profiles.avatar_bg`, colour, name.
    /// No cream: the app background is cream, so the picture would vanish.
    static let backgrounds: [(key: String, color: Color, name: String)] = [
        ("choc100", Brand.choc100, "Chocolate 100"), ("choc400", Brand.choc400, "Chocolate 400"),
        ("pink100", Brand.pink100, "Pink 100"), ("lime", Brand.lime, "Sour lime"),
        ("liquorice100", Brand.liquorice100, "Liquorice 100"), ("liquorice400", Brand.liquorice400, "Liquorice 400"),
        ("caramel", Brand.caramel, "Caramel"),
    ]
    static func background(_ key: String?) -> Color? { backgrounds.first { $0.key == key }?.color }

    /// How each painting sits in a round avatar (design `ataste-art.js` ART table): image size, the face centre as a
    /// fraction of the image (cx, cy), and how much of the image width the circle shows (cw).
    static let paintingCrop: [String: (w: CGFloat, h: CGFloat, cx: CGFloat, cy: CGFloat, cw: CGFloat)] = [
        "paint-croissant": (716, 1113, 0.42, 0.3, 1.00),
        "paint-creation":  (1140, 735, 0.5, 0.5, 0.65),
        "paint-brioche":   (900, 1117, 0.52, 0.3, 1.00),
        "paint-monalisa":  (900, 1117, 0.52, 0.26, 0.95),
        "paint-scream":    (900, 1117, 0.52, 0.3, 0.95),
        "paint-gothic":    (900, 1117, 0.5, 0.3, 1.00),
        "paint-sonofbun":  (900, 1117, 0.5, 0.28, 0.95),
        "paint-vangogh":   (900, 1117, 0.47, 0.28, 0.90),
        "paint-supper":    (1400, 781, 0.5, 0.4, 0.58),
    ]
}

/// `<at-avatar>`: initial in Roundo 700 at 0.4 × size on a pastel (join order), or the person's chosen art.
/// Host gets a cocoa "HOST" badge with a white edge at the bottom right; `ring` draws a border inside.
struct Avatar: View {
    var name: String
    var index: Int
    var host = false
    var size: CGFloat = 36
    var art: String? = nil
    /// The person's chosen background (`profiles.avatar_bg`); nil keeps the join-order pastel.
    var bg: String? = nil
    var ring: Color? = nil
    var body: some View {
        let fill = Art.background(bg) ?? Brand.people[index % Brand.people.count]
        ZStack {
            Circle().fill(fill)
            if let art, let c = Art.paintingCrop[art] {
                // Centre the face, keep the image covering the circle (the design's artBg()).
                let bw = size / c.cw, bh = bw * c.h / c.w
                let x = min(0, max(size - bw, size / 2 - c.cx * bw)), y = min(0, max(size - bh, size / 2 - c.cy * bh))
                Image(art).resizable().frame(width: bw, height: bh)
                    .offset(x: x + (bw - size) / 2, y: y + (bh - size) / 2)
                    .frame(width: size, height: size).clipShape(Circle())
            } else if let art, Art.all.contains(art) {
                Image(art).resizable().scaledToFill()
                    .frame(width: size, height: size, alignment: .bottom)
                    .clipShape(Circle())
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(Font(Brand.uiFont(.roundo, size: size * 0.4, weight: 700)))
                    .foregroundStyle(bg == "caramel" ? Brand.cream : Brand.cocoa)
            }
            if let ring { Circle().strokeBorder(ring, lineWidth: max(2, size / 14)) }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if host {
                Text("HOST").font(Brand.font(.label, size: 8, weight: 700)).tracking(0.32).foregroundStyle(Brand.cream)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Brand.cocoa))
                    .padding(2).background(Capsule().fill(.white))
                    .fixedSize()
                    .offset(x: 6, y: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The giraffe on a pastel circle (bust bottom-anchored, clipped by the circle).
struct Mascot: View {
    var pose: String
    var size: CGFloat = 160
    var fill: Color = Brand.choc100
    var body: some View {
        ZStack {
            Circle().fill(fill)
            Image(pose).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// `<at-photo>`: a dashed caramel ring at the edge, the photo on a pastel circle inset by 5.5% (at least 4).
struct ProductPhoto: View {
    var url: URL?
    var size: CGFloat
    var fill: Color = Brand.choc100
    var ring = true
    var body: some View {
        let pad = max(4, (size * 0.055).rounded())
        ZStack {
            if ring { Circle().strokeBorder(Brand.caramel.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4.5, 3])) }
            Circle().fill(fill).padding(pad)
            AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
                .frame(width: size - pad * 2, height: size - pad * 2).clipShape(Circle())
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A painting parody in its caramel frame with the dashed cream mat (brand board). `frame` 10 and `mat` 5 on
/// screens, 16 and 8 on the brand board; `tilt` in degrees.
struct PaintingFrame: View {
    var art: String
    var width: CGFloat
    var height: CGFloat
    var frame: CGFloat = 10
    var mat: CGFloat = 5
    var tilt: Double = 0
    var body: some View {
        Image(art).resizable().scaledToFill()
            .frame(width: width, height: height).clipped()
            .padding(mat)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.cream.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .padding(frame)
            .background(RoundedRectangle(cornerRadius: frame >= 16 ? 12 : 10).fill(Brand.caramel))
            .shadow(color: Brand.cocoa.opacity(0.25), radius: 15, y: 14)
            .rotationEffect(.degrees(tilt))
            .accessibilityHidden(true)
    }
}

/// Celebration rays (CSS `repeating-conic-gradient(colour 0 width, transparent width period)`): wedges of `width`
/// degrees every `period` degrees, starting at 12 o'clock, clipped to a circle. Design system: 10 in 20; 5-8 Paid: 9 in 18.
struct Rays: View {
    var color: Color = Brand.lime
    var width: Double = 10
    var period: Double = 20
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2), r = max(size.width, size.height)
            var wedges = Path()
            var a = -90.0
            while a < 270 {
                wedges.move(to: c)
                wedges.addArc(center: c, radius: r, startAngle: .degrees(a), endAngle: .degrees(a + width), clockwise: false)
                wedges.closeSubpath()
                a += period
            }
            ctx.clip(to: Path(ellipseIn: CGRect(origin: .zero, size: size)))
            ctx.fill(wedges, with: .color(color))
        }
        .accessibilityHidden(true)
    }
}

/// The group screen's Rp 200k card, "the loudest element on the group screen" (3-1 / 3-3). Before the goal:
/// white card, Roundo 38 amount, 20pt bar (striped when close), "Rp X more" line. At the goal: lime card with
/// rays, the celebrating giraffe, Shrikhand "Discount unlocked!" and the DISCOUNT UNLOCKED band.
/// One card for both: while the screen is open the bar fills, the numbers count, and crossing the goal plays the
/// unlock in order (fill, card, headline, message, sunburst, giraffe, band); dropping back plays it out. A card that
/// appears already unlocked is still. Layers on their own timing sit in a `geometryGroup`, so where they are still
/// follows the card.
struct DiscountBar: View {
    var subtotal: Int
    var host = "the host"
    /// Personal order (3-8): "Rp X more for the ongkir discount".
    var personal = false
    static let goal = UnlockMotion.threshold
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var unlocked: Bool { subtotal >= Self.goal }
    private var fraction: CGFloat { min(1, CGFloat(subtotal) / CGFloat(Self.goal)) }

    /// The unlock's step at its delay, or `off` when it re-locks.
    private func step(_ a: Animation, _ delay: Double, off: Animation = Motion.fadeOut) -> Animation {
        unlocked ? a.delay(delay) : off
    }
    /// Rows that open or close: the unlock's `Motion.settle`, the re-lock's `Motion.leave`; Reduce Motion snaps them.
    private func row(_ delay: Double) -> Animation? {
        reduceMotion ? nil : step(Motion.settle, delay, off: Motion.leave)
    }
    /// Layers that only fade under Reduce Motion.
    private func layer(_ a: Animation, _ delay: Double) -> Animation {
        step(reduceMotion ? Motion.Reduced.fade : a, delay)
    }

    var body: some View {
        let u = unlocked
        let card = UnlockMotion.cardDelay
        let shape = RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                headline
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CountUp(amount: subtotal) { Text(Rupiah.format($0)) }
                        .modifier(RoundoSize(size: u ? UnlockMotion.totalSize.to : UnlockMotion.totalSize.from))
                    Text("/ 200.000").font(u ? Brand.font(.footnote, size: 13, weight: 600) : Brand.font(.callout, weight: 600))
                        .foregroundStyle(u ? Brand.cocoa : Brand.ink3)
                }
                bar
                OneSpot(active: u ? 1 : 0) {
                    CountUp(amount: max(0, Self.goal - subtotal)) { n in
                        Text("\(Rupiah.format(n)) more").foregroundStyle(Brand.caramel).fontWeight(.bold)
                            + Text(personal ? " for the ongkir discount" : " to unlock the ongkir discount")
                    }
                    .font(Brand.font(.body, size: 15, weight: 600))
                    .opacity(u ? 0 : 1)
                    .animation(u ? Motion.fadeOut.delay(card) : Motion.fade, value: u)
                    .geometryGroup()
                    Text("Atas applies the ongkir discount when \(host) sends the order.")
                        .font(Brand.font(.callout, weight: 600))
                        .opacity(u ? 1 : 0)
                        .animation(step(Motion.fade, UnlockMotion.messageDelay), value: u)
                        .geometryGroup()
                }
            }
            .foregroundStyle(Brand.cocoa)
            // 3-3's padding when unlocked, 20 all round before.
            .padding(u ? EdgeInsets(top: 22, leading: 20, bottom: 18, trailing: 20) : EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))
            .frame(maxWidth: .infinity, alignment: .leading)
            band
        }
        .background(alignment: .topTrailing) { celebration }
        .background {
            ZStack {
                shape.fill(Brand.card)
                shape.fill(Brand.lime).opacity(u ? 1 : 0).animation(step(Motion.fade, card), value: u).geometryGroup()
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Brand.limeDeep, lineWidth: 2)
                .opacity(u ? 1 : 0).animation(step(Motion.fade, card), value: u).geometryGroup()
        }
        .animation(row(card), value: u)
        .accessibilityElement(children: .combine)
        .sensoryFeedback(Haptic.done, trigger: u) { !$0 && $1 }
    }

    /// "Discount unlocked!": the column's first row, opening from 0 (its 12 pt gap opens with it) while the words
    /// scale up from 0.6 and turn from −6° about a point 10 % across, 80 % down.
    private var headline: some View {
        let u = unlocked
        let from = UnlockMotion.headlineFrom
        let anchor = UnitPoint(x: 0.1, y: 0.8)
        let still = u || reduceMotion
        return Text("Discount unlocked!").font(Font(Brand.uiFont(.shrikhand, size: 36, weight: 400)))
            .frame(maxWidth: 200, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(still ? 1 : from.scale, anchor: anchor)
            .rotationEffect(still ? .zero : from.tilt, anchor: anchor)
            .opacity(u ? 1 : 0)
            .animation(layer(Motion.pop, from.delay), value: u)
            .geometryGroup()
            .frame(height: u ? nil : 0, alignment: .top)
            .clipped()
            .padding(.bottom, u ? 0 : -12)
    }

    private var bar: some View {
        let u = unlocked
        let close = fraction >= 0.75
        return Capsule().fill(Brand.liquorice100).frame(height: 20)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Capsule()
                        .fill(close ? AnyShapeStyle(.linearGradient(stops: [.init(color: Brand.choc400, location: 0.5), .init(color: Brand.stripe, location: 0.5)],
                                                                   startPoint: .topLeading, endPoint: UnitPoint(x: 0.045, y: 0.045)))
                                    : AnyShapeStyle(Brand.choc400))
                        // At the goal a cocoa layer fades in over the full fill.
                        .overlay(Capsule().fill(Brand.cocoa).opacity(u ? 1 : 0).animation(step(Motion.quick, UnlockMotion.cardDelay), value: u))
                        .frame(width: g.size.width * fraction)
                        .animation(reduceMotion ? Motion.Reduced.fill : Motion.doughTrail, value: fraction)
                }
            }
            .clipShape(Capsule())
            .geometryGroup()
    }

    /// The band row under the column, full card width. The card makes room with the rest of the unlock; the band
    /// opens into it from the top after 0.38 s. Reduce Motion: it appears without the opening.
    private var band: some View {
        let u = unlocked
        let height = UnlockMotion.band.height
        return ZStack(alignment: .top) {
            if u {
                Marquee(text: "DISCOUNT UNLOCKED • ONGKIR SORTED • KEEP ADDING • ", fill: Brand.cocoa, ink: Brand.lime, size: 13)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }
        }
        .frame(height: u ? height : 0, alignment: .top)
        .mask(alignment: .top) {
            Rectangle().frame(height: u ? height : 0)
                .animation(reduceMotion ? nil : step(Motion.settle, UnlockMotion.band.delay, off: Motion.leave), value: u)
        }
    }

    /// The sunburst behind everything and the celebrating giraffe; there only once unlocked.
    private var celebration: some View {
        let u = unlocked
        let sun = UnlockMotion.sunburst, giraffe = UnlockMotion.mascot
        let still = u || reduceMotion
        return ZStack(alignment: .topTrailing) {
            Rays(color: .white).frame(width: 260, height: 260)
                .rotationEffect(still ? .zero : sun.tilt)
                .animation(reduceMotion ? nil : step(Motion.glide, sun.delay), value: u)
                .opacity(u ? sun.opacity : 0)
                .animation(layer(Motion.fade, sun.delay), value: u)
                .offset(x: 60, y: -60)
            Mascot(pose: "pose-celebrating", size: 130, fill: .clear)
                .scaleEffect(still ? 1 : giraffe.scale)
                .offset(y: still ? 0 : giraffe.offset)
                .opacity(u ? 1 : 0)
                .animation(layer(Motion.bounce, giraffe.delay), value: u)
                .offset(x: -6, y: 10)
        }
        .allowsHitTesting(false)
    }
}

/// Running text band, `<at-marquee>` in the design: Roundo 700 uppercase, 0.04em tracking, line height 1, vertical
/// padding 0.7 × size. One run is the text six times plus half an em, and the track wraps every run.
/// It does not run on its own: 0.3 s after it appears it is flicked once and coasts to a stop, and a horizontal drag scrolls it and
/// coasts on release, like a scroll view's deceleration. Reduce Motion skips the flick on appear.
struct Marquee: View {
    var text = "FRESH FROM ATAS • GROUP UP • SAVE ON ONGKIR • "
    var fill = Brand.cocoa
    var ink = Brand.cream
    var size: CGFloat = 15
    var reverse = false
    var tilt: Double = 0
    @State private var runWidth: CGFloat = 0
    @State private var coast = Coast(from: 0, velocity: 0, start: .now)
    /// Track position the current drag started from (minus the translation at the moment it locked horizontal).
    @State private var dragFrom: CGFloat?
    @State private var dragX: CGFloat = 0
    /// nil until a drag has moved far enough to pick an axis; a vertical drag is left to the enclosing scroll view.
    @State private var horizontal: Bool?
    @State private var moving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Exponential decay: x(t) = from + v/k·(1 − e^(−k·t)), so the speed falls smoothly to zero.
    struct Coast {
        var from: CGFloat, velocity: CGFloat, start: Date
        static let friction = 2.5  // 1/s; a flick travels velocity / friction points
        /// When the speed has fallen under 0.5 pt/s; x is held there, so a later redraw never jumps.
        var end: Date { start + log(max(abs(velocity), 0.5) / 0.5) / Self.friction }
        func x(_ t: Date) -> CGFloat {
            let dt = min(t, end).timeIntervalSince(start)
            return from + velocity / Self.friction * (1 - exp(-Self.friction * max(0, dt)))
        }
    }

    /// Where the track is now, in points, unwrapped.
    private var x: CGFloat { dragFrom.map { $0 + dragX } ?? coast.x(.now) }

    private func wrapped(_ x: CGFloat) -> CGFloat {
        guard runWidth > 0 else { return 0 }
        let m = x.truncatingRemainder(dividingBy: runWidth)
        return m > 0 ? m - runWidth : m
    }

    var body: some View {
        let run = Text(String(repeating: text + " ", count: 6))
            .font(Font(Brand.uiFont(.roundo, size: size, weight: 700)))
            .tracking(size * 0.04)
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.trailing, size / 2)
        // The track is far wider than the screen, so it lives in an overlay and never sizes the layout.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: size)
            .overlay(alignment: .leading) {
                TimelineView(.animation(paused: !moving || dragFrom != nil)) { t in
                    HStack(spacing: 0) { run; run }
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width / 2 } action: { runWidth = $0 }
                        .offset(x: wrapped(dragFrom.map { $0 + dragX } ?? coast.x(t.date)))
                }
            }
            .padding(.vertical, (size * 0.7).rounded())
        .background(fill)
        .clipped()
        .contentShape(Rectangle())
        // Simultaneous, so a vertical drag that starts on the band still scrolls the screen.
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { v in
                    if horizontal == nil {
                        horizontal = abs(v.translation.width) > abs(v.translation.height)
                        if horizontal == true { dragFrom = x - v.translation.width }
                    }
                    if horizontal == true { dragX = v.translation.width }
                }
                .onEnded { v in
                    if let from = dragFrom {
                        coast = Coast(from: from + v.translation.width, velocity: v.velocity.width, start: .now)
                    }
                    dragFrom = nil
                    horizontal = nil
                }
        )
        .onAppear {
            guard !reduceMotion else { return }
            // The flick waits 0.3 s after the screen appears (Motion board 21); a coast that starts later holds still.
            coast = Coast(from: x, velocity: reverse ? 1200 : -1200, start: .now + BandMotion.flickDelay)
        }
        // Run the timeline only while a coast is moving.
        .task(id: coast.start) {
            moving = true
            do { try await Task.sleep(for: .seconds(max(0, coast.end.timeIntervalSinceNow))); moving = false } catch {}
        }
        .rotationEffect(.degrees(tilt))
        .padding(.horizontal, tilt == 0 ? 0 : -12)
        .accessibilityHidden(true)
    }
}

/// The design system's toast ("Link copied", "Account number copied"): cocoa pill, lime check, Manrope 600 14.
/// A new message rolls in over the old one.
struct Toast: View {
    var text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Brand.lime)
            ZStack {
                Text(text).font(Brand.font(.callout, weight: 600)).foregroundStyle(Brand.cream).id(text).transition(.roll(reduceMotion))
            }
            .animation(reduceMotion ? Motion.Reduced.fade : Motion.digits, value: text)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(Capsule().fill(Brand.cocoa))
        .shadow(color: Brand.cocoa.opacity(0.25), radius: 12, y: 8)
    }
}

/// One toast's message. Each copy makes a new one, so copying the same thing again restarts the timer.
struct ToastNote: Equatable {
    var text: String
    var id = UUID()
}

extension View {
    /// Shows the toast `above` points over the bottom safe area for 1.8 s after the last copy, or until it is swiped
    /// down. It rises in from 24 pt below; a copy while it shows rolls the text and bumps it. Never more than one.
    func toast(_ note: Binding<ToastNote?>, above: CGFloat = 8) -> some View {
        modifier(ToastHost(note: note, above: above))
    }
}

private struct ToastHost: ViewModifier {
    @Binding var note: ToastNote?
    var above: CGFloat
    @State private var bumps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                ZStack {
                    if let n = note {
                        Toast(text: n.text)
                            .kick(reduceMotion ? 0 : bumps, from: ToastMotion.repeatBump)
                            .padding(.bottom, above)
                            .transition(transition)
                            .gesture(DragGesture(minimumDistance: 8).onEnded { if $0.translation.height > 0 { note = nil } })
                            .task(id: n.id) {
                                do { try await Task.sleep(for: .seconds(ToastMotion.hold)) } catch { return }
                                note = nil
                            }
                    }
                }
            }
            .onChange(of: note) { old, new in if old != nil && new != nil { bumps += 1 } }
    }

    /// In: up from 24 pt below at 0.96 (`Motion.arrive`) while it fades in (`Motion.fade`). Out: 8 pt down as it fades.
    private var transition: AnyTransition {
        if reduceMotion {
            return .asymmetric(insertion: .opacity.animation(Motion.Reduced.fade), removal: .opacity.animation(Motion.fadeOut))
        }
        let enter = ToastMotion.enter
        return .asymmetric(
            insertion: AnyTransition.offset(y: enter.offset).combined(with: .scale(scale: enter.scale)).animation(Motion.arrive)
                .combined(with: .opacity.animation(Motion.fade)),
            removal: AnyTransition.offset(y: ToastMotion.exitOffset).combined(with: .opacity).animation(Motion.fadeOut))
    }
}

/// Copy with feedback: `copy(link, "Link copied", $toast)` on a view that has `.toast($toast)`.
func copy(_ value: String, _ message: String, _ toast: Binding<ToastNote?>) {
    UIPasteboard.general.string = value
    toast.wrappedValue = ToastNote(text: message)
}

/// A copy button (account name and number, the invite link): its copy icon gives way to a check that pops in,
/// and comes back 1.6 s after the last copy. `face` draws the button around the icon it is given.
struct CopyButton<Face: View>: View {
    var value: String
    var message: String
    @Binding var toast: ToastNote?
    var symbol = "square.on.square"
    var squash = Motion.pressIcon
    @ViewBuilder var face: (PopSymbol) -> Face
    @State private var copies = 0

    var body: some View {
        let copied = copies > 0
        Button {
            copy(value, message, $toast)
            copies += 1
        } label: {
            face(PopSymbol(name: copied ? "checkmark" : symbol, animation: copied ? Motion.pop : Motion.fade))
        }
        .buttonStyle(DoughStyle(squash: squash))
        .task(id: copies) {
            guard copies > 0 else { return }
            do { try await Task.sleep(for: .seconds(ToastMotion.iconHold)) } catch { return }
            copies = 0
        }
    }
}

// MARK: States

/// "Proofing the dough…": the dashed caramel ring around the neutral giraffe (`<at-spin>`). Like the splash's, it turns
/// a quarter into place as it appears and then stays still while it waits.
struct LoaderView: View {
    var line = "Proofing the dough…"
    @State private var shown = false
    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                ObRing(size: 180, turns: shown ? 1 : 0, from: SplashMotion.ringFrom)
                Mascot(pose: "pose-neutral", size: 144)
            }
            .onAppear { shown = true }
            Text(line).font(Font(Brand.uiFont(.roundo, size: 20, weight: 700))).foregroundStyle(Brand.cocoa)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.cream.ignoresSafeArea())
    }
}

/// Empty and error states: art on a pastel circle, Roundo 24 title, callout message, optional action
/// ("The oven didn't answer." + Try again).
struct EmptyStateView: View {
    var pose = "pose-sleeping"
    var fill: Color = Brand.liquorice100
    var size: CGFloat = 140
    var title: String
    var message: String
    var actionTitle: String? = nil
    var actionIcon = "arrow.clockwise"
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 14) {
            Mascot(pose: pose, size: size, fill: fill)
            Text(title).font(Font(Brand.uiFont(.roundo, size: 24, weight: 700))).foregroundStyle(Brand.cocoa)
            Text(message).font(Brand.font(.callout)).foregroundStyle(Brand.ink2)
            if let actionTitle, let action {
                Button(action: action) { Label(actionTitle, systemImage: actionIcon) }.buttonStyle(.pill(.primary, .medium))
            }
        }
        .multilineTextAlignment(.center)
        .padding(Brand.s5)
        .frame(maxWidth: .infinity)
    }
}

/// Offline and stale-menu banner: icon, 13pt semibold line, a white Retry/Refresh pill, radius 16.
struct NoticeBanner: View {
    var icon: String
    var text: String
    var fill: Color = Brand.liquorice100
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
            Text(text).font(Brand.font(.callout, size: 13, weight: 600)).frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(Brand.font(.callout, size: 13, weight: 600))
                        .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Brand.cocoa)
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 10))
        .background(RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous).fill(fill))
    }
}

struct ErrorBanner: View {
    var message: String
    var retry: (() -> Void)?
    var body: some View {
        NoticeBanner(icon: "exclamationmark.triangle", text: message, fill: Brand.choc100, actionTitle: retry == nil ? nil : "Retry", action: retry)
    }
}

// MARK: Fields and choices

/// Text field: label above, 52 tall, radius 12, cream with a liquorice edge. Focused: white, caramel edge and a
/// choc-100 halo. Error: 2pt red edge and the message below with an alert icon.
struct BrandField: View {
    var label: String? = nil
    var placeholder: String
    @Binding var text: String
    var error: String? = nil
    var multiline = false
    var keyboard: UIKeyboardType = .default
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Brand.rField, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            if let label { Text(label).brand(.label) }
            TextField(label ?? placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(Brand.ink4),
                      axis: multiline ? .vertical : .horizontal)
                .font(Brand.font(.body))
                .foregroundStyle(Brand.cocoa)
                .tint(Brand.caramel)
                .keyboardType(keyboard)
                .focused($focused)
                .lineLimit(multiline ? 2...6 : 1...1)
                .padding(.horizontal, 16)
                .padding(.vertical, multiline ? 14 : 0)
                .frame(minHeight: multiline ? 76 : 52, alignment: multiline ? .topLeading : .leading)
                .background(shape.fill(focused || error != nil ? Color.white : Brand.cream))
                .overlay(shape.strokeBorder(error != nil ? Brand.destructive : focused ? Brand.caramel : Brand.liquorice100,
                                            lineWidth: error != nil || focused ? 2 : 1.5))
                .background(RoundedRectangle(cornerRadius: Brand.rField + 4, style: .continuous).fill(Brand.choc100)
                    .padding(-4).opacity(focused && error == nil ? 1 : 0))
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").font(Brand.font(.callout, size: 13)).foregroundStyle(Brand.destructive)
            }
        }
    }
}

/// Choice card (payment rule): round check, bold title, callout detail; selected is caramel-edged warm cream.
struct ChoiceCard: View {
    var title: String
    var detail: String
    var selected: Bool
    var action: () -> Void
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous)
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    if selected {
                        Circle().fill(Brand.caramel)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                    } else {
                        Circle().strokeBorder(Brand.liquorice400, lineWidth: 2)
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Brand.font(.body, size: 16, weight: 700))
                    Text(detail).font(Brand.font(.callout, size: 13)).foregroundStyle(Brand.ink2)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Brand.cocoa)
            .multilineTextAlignment(.leading)
            .padding(16)
            .background(shape.fill(selected ? Brand.selectedFill : .white))
            .overlay(shape.strokeBorder(selected ? Brand.caramel : Brand.liquorice100, lineWidth: selected ? 2.5 : 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Segmented control: white thumb on a liquorice capsule, 14pt semibold. Picking the other segment sends the thumb
/// there like the option chips' pill (Motion board 13): the edge in the direction of travel on `Motion.doughLead`, the
/// other on `Motion.doughTrail`, the inks swapping on `Motion.quick` (the new one 0.04 s later), with a selection tick.
/// A press squashes the segment and the thumb under it; a tap on the picked segment only presses. A selection set from
/// outside moves the thumb still. Reduce Motion: the thumb fades across and a press dims.
struct Segmented: View {
    var options: [String]
    @Binding var selection: Int
    /// The thumb's edges as fractions of the track.
    @State private var left: CGFloat = 0
    @State private var right: CGFloat = 0
    @State private var pressed: Int?
    @State private var picks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let on = selection == i
                Button { pick(i) } label: {
                    Text(options[i]).font(Brand.font(.callout, weight: 600))
                        .foregroundStyle(on ? Brand.cocoa : Brand.ink2)
                        .animation(reduceMotion ? Motion.Reduced.fade : on ? Motion.quick.delay(OptionMotion.inkDelay) : Motion.quick, value: on)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .contentShape(Capsule())
                }
                .buttonStyle(SegmentPress(index: i, pressed: $pressed))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .background { thumb }
        .padding(4)
        .background(Capsule().fill(Brand.liquorice100))
        .sensoryFeedback(.selection, trigger: picks)
        .onChange(of: selection, initial: true) { _, s in
            if (left, right) != edges(s) { still { (left, right) = edges(s) } }
        }
    }

    /// The white thumb, shadow 0 1 3 Cocoa at 15 %.
    private func face(squashed: Bool = false) -> some View {
        Capsule().fill(.white).shadow(color: Brand.cocoa.opacity(0.15), radius: 1.5, y: 1)
            .scaleEffect(squashed ? Motion.pressCompact : CGSize(width: 1, height: 1))
            .animation(squashed ? Motion.press : Motion.release, value: squashed)
    }

    private var thumb: some View {
        GeometryReader { g in
            if reduceMotion {
                ForEach(options.indices, id: \.self) { i in
                    face()
                        .frame(width: g.size.width / CGFloat(options.count))
                        .offset(x: g.size.width * CGFloat(i) / CGFloat(options.count))
                        .opacity(selection == i ? 1 : 0)
                        .animation(Motion.Reduced.fade, value: selection)
                }
            } else {
                EdgeValue(value: left) { l in EdgeValue(value: right) { r in
                    face(squashed: pressed == selection)
                        .frame(width: max(0, r - l) * g.size.width)
                        .offset(x: l * g.size.width)
                } }
            }
        }
    }

    private func edges(_ i: Int) -> (CGFloat, CGFloat) {
        let n = CGFloat(max(1, options.count))
        return (CGFloat(i) / n, CGFloat(i + 1) / n)
    }

    private func pick(_ i: Int) {
        guard i != selection else { return }
        let (l, r) = edges(i)
        let right = l > left
        withAnimation(right ? Motion.doughTrail : Motion.doughLead) { left = l }
        withAnimation(right ? Motion.doughLead : Motion.doughTrail) { self.right = r }
        picks += 1
        selection = i
    }

    private func still(_ change: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, change)
    }

    /// The segment's press, reported so the thumb under it squashes with it.
    private struct SegmentPress: ButtonStyle {
        var index: Int
        @Binding var pressed: Int?
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .doughPress(configuration.isPressed, squash: Motion.pressCompact)
                .onChange(of: configuration.isPressed) { _, p in pressed = p ? index : (pressed == index ? nil : pressed) }
        }
    }
}

/// Option pill, one choice per option group: cocoa when picked, white with a liquorice edge otherwise.
struct OptionPill: View {
    var text: String
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(Brand.font(.callout, weight: 600))
                .foregroundStyle(selected ? Brand.cream : Brand.cocoa)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(selected ? Brand.cocoa : .white))
                .overlay(Capsule().strokeBorder(Brand.liquorice400, lineWidth: selected ? 0 : 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Saved place row (and "Add new address" with `icon: "plus"` and no detail). Selected: caramel edge.
struct PlaceRow: View {
    var title: String
    var detail: String? = nil
    var icon = "mappin"
    var selected = false
    var action: () -> Void
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Brand.rSmall, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(detail == nil ? Color.white : Brand.choc100))
                    .overlay { if detail == nil { Circle().strokeBorder(Brand.liquorice400, lineWidth: 1.5) } }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Brand.font(.body, size: 15, weight: detail == nil ? 600 : 700))
                    if let detail { Text(detail).font(Brand.font(.callout, size: 13)).foregroundStyle(Brand.ink2).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(Circle().fill(Brand.caramel))
                }
            }
            .foregroundStyle(Brand.cocoa)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(shape.fill(selected ? Brand.selectedFill : Brand.cream))
            .overlay { if selected { shape.strokeBorder(Brand.caramel, lineWidth: 2) } }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The host's bank or e-wallet on cocoa: bank chip, account name, number in Roundo, copy button.
struct PayoutCard: View {
    var account: PayoutAccount
    var copy: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(account.label.uppercased()).font(Brand.font(.label, size: 11, weight: 600)).tracking(0.33)
                    .foregroundStyle(Brand.cocoa).padding(.horizontal, 12).padding(.vertical, 3)
                    .background(Capsule().fill(Brand.choc400))
                Spacer()
                Text(account.account_name).font(Brand.font(.footnote)).foregroundStyle(Brand.liquorice400)
            }
            HStack {
                Text(Self.grouped(account.number)).font(Font(Brand.uiFont(.roundo, size: 24, weight: 700))).tracking(0.96)
                    .foregroundStyle(Brand.cream).textSelection(.enabled)
                Spacer()
                if let copy {
                    IconCircle(symbol: "doc.on.doc", action: copy).padding(-8).accessibilityLabel("Copy account number")
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: Brand.rCard, style: .continuous).fill(Brand.cocoa))
    }

    /// "5271009934" → "5271 0099 34"; anything with letters or spaces is left as typed.
    static func grouped(_ n: String) -> String {
        guard n.allSatisfy(\.isNumber) else { return n }
        return stride(from: 0, to: n.count, by: 4).map { i in
            String(n.dropFirst(i).prefix(4))
        }.joined(separator: " ")
    }
}

/// One alert for every "Couldn't…" message, per the iOS guide (.alert only).
struct Problem: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

extension View {
    func problemAlert(_ problem: Binding<Problem?>) -> some View {
        alert(problem.wrappedValue?.title ?? "", isPresented: Binding(get: { problem.wrappedValue != nil }, set: { if !$0 { problem.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(problem.wrappedValue?.message ?? "") }
    }
}

/// Runs an async action, turning a failure into a Problem.
@MainActor
func attempt(_ problem: Binding<Problem?>, _ title: String, _ work: @escaping () async throws -> Void) async {
    do { try await work() } catch where isCancellation(error) {} catch { problem.wrappedValue = Problem(title: title, message: readable(error)) }
}

/// Presents the system share sheet (ShareLink never sits in a Menu; see the iOS guide).
func presentShare(_ items: [Any]) {
    let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
    guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
    var top = root
    while let p = top.presentedViewController { top = p }
    top.present(vc, animated: true)
}
