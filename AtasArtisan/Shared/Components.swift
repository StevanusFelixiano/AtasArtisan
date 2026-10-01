import SwiftUI

// The design system's building blocks (Claude Design "Ataste Design System"): pill buttons with a 4pt
// self-coloured border, pastel tags, white cards on cream, dashed photo circles, the Rp 200k bar,
// marquee bands, the giraffe in a pastel circle.

// MARK: Buttons

enum PillKind { case primary, secondary, dark, success, destructive }
enum PillSize { case large, medium, small }

/// Full pill with a border in the fill colour. Large: bottom action bar, 17pt, 60 tall, full width. Medium:
/// inline, 16pt, 52 tall. Small: rows and cards, 13pt, 3pt border, 36 tall (hit area 44). Pressed and disabled
/// colours are the design system's own cells, not an opacity.
struct PillStyle: ButtonStyle {
    var kind: PillKind = .primary
    var size: PillSize = .large
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
        let c = colors(pressed: configuration.isPressed)
        let small = size == .small
        configuration.label
            .labelStyle(PillLabel(spacing: small ? 6 : 8, icon: small ? 14 : 18))
            .font(Brand.font(.body, size: size == .large ? 17 : small ? 13 : 16, weight: 600))
            .lineLimit(1)
            .padding(.horizontal, small ? 16 : 32)
            .frame(maxWidth: size == .large ? .infinity : nil, minHeight: size == .large ? 60 : small ? 36 : 52)
            .foregroundStyle(c.ink)
            .background(Capsule().fill(c.fill))
            .overlay(Capsule().strokeBorder(c.border, lineWidth: small ? 3 : 4))
            .contentShape(Capsule())
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

extension ButtonStyle where Self == PillStyle {
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
        .buttonStyle(.plain)
    }
}

// MARK: Tags and state

enum TagSize { case regular, small, large }

/// `<at-tag>`: uppercase Manrope 600 with 0.03em tracking on a pastel capsule. Regular 11pt (cards, rows),
/// small 10pt, large 12pt (product tags). Optional leading dot (order state) or check (paid, accepted).
struct Tag: View {
    var text: String
    var fill: Color = Brand.choc100
    var ink: Color = Brand.cocoa
    var dot: Color? = nil
    var border: Color? = nil
    var check = false
    var size: TagSize = .regular

    var body: some View {
        let fs: CGFloat = switch size { case .regular: 11; case .small: 10; case .large: 12 }
        let side: CGFloat = switch size { case .regular: 14; case .small: 10; case .large: 16 }
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            if check { Image(systemName: "checkmark").font(.system(size: fs - 1, weight: .heavy)) }
            Text(text).font(Brand.font(.label, size: fs, weight: 600)).tracking(fs * 0.03).textCase(.uppercase)
        }
        .foregroundStyle(ink)
        .lineLimit(1)
        .padding(.vertical, size == .small ? 2 : 4)
        .padding(.leading, dot != nil || check ? (size == .small ? 8 : 10) : side)
        .padding(.trailing, side)
        .background(Capsule().fill(fill))
        .overlay { if let border { Capsule().strokeBorder(border, lineWidth: 1.5) } }
        .fixedSize()
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
            if let art, Art.all.contains(art) {
                Image(art).resizable().scaledToFill()
                    .frame(width: size, height: size, alignment: art.hasPrefix("paint") ? .top : .bottom)
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

/// Celebration rays (repeating 10° conic stripes) behind the "You're in!" and "Paid up!" moments.
struct Rays: View {
    var color: Color = Brand.lime
    var body: some View {
        let stops = (0..<36).flatMap { i -> [Gradient.Stop] in
            let a = Double(i) / 36, m = (Double(i) + 0.5) / 36
            return [.init(color: color, location: a), .init(color: color, location: m),
                    .init(color: .clear, location: m), .init(color: .clear, location: (Double(i) + 1) / 36)]
        }
        Circle().fill(AngularGradient(stops: stops, center: .center)).accessibilityHidden(true)
    }
}

/// The group screen's Rp 200k card, "the loudest element on the group screen" (3-1 / 3-3). Before the goal:
/// white card, Roundo 38 amount, 20pt bar (striped when close), "Rp X more" line. At the goal: lime card with
/// rays, the celebrating giraffe, Shrikhand "Discount unlocked!" and the DISCOUNT UNLOCKED band.
struct DiscountBar: View {
    var subtotal: Int
    var host = "the host"
    static let goal = 200_000

    var body: some View {
        if subtotal >= Self.goal { unlocked } else { progress }
    }

    private var fraction: CGFloat { min(1, CGFloat(subtotal) / CGFloat(Self.goal)) }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Rupiah.format(subtotal)).font(Font(Brand.uiFont(.roundo, size: 38, weight: 700)))
                Text("/ 200.000").font(Brand.font(.callout, weight: 600)).foregroundStyle(Brand.ink3)
            }
            bar(fill: fraction >= 0.75
                ? AnyShapeStyle(.linearGradient(stops: [.init(color: Brand.choc400, location: 0.5), .init(color: Brand.stripe, location: 0.5)],
                                               startPoint: .topLeading, endPoint: UnitPoint(x: 0.045, y: 0.045)))
                : AnyShapeStyle(Brand.choc400), width: fraction)
            (Text("\(Rupiah.format(Self.goal - subtotal)) more").foregroundStyle(Brand.caramel).fontWeight(.bold)
             + Text(" to unlock the ongkir discount"))
                .font(Brand.font(.body, size: 15, weight: 600))
        }
        .foregroundStyle(Brand.cocoa)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous).fill(Brand.card))
        .accessibilityElement(children: .combine)
    }

    private var unlocked: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Discount unlocked!").font(Font(Brand.uiFont(.shrikhand, size: 36, weight: 400)))
                    .frame(maxWidth: 200, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Rupiah.format(subtotal)).font(Font(Brand.uiFont(.roundo, size: 30, weight: 700)))
                    Text("/ 200.000").font(Brand.font(.footnote, size: 13, weight: 600))
                }
                Capsule().fill(Brand.cocoa).frame(height: 20)
                Text("Atas applies the ongkir discount when \(host) sends the order.")
                    .font(Brand.font(.callout, weight: 600))
            }
            .foregroundStyle(Brand.cocoa)
            .padding(EdgeInsets(top: 22, leading: 20, bottom: 18, trailing: 20))
            .frame(maxWidth: .infinity, alignment: .leading)
            Marquee(text: "DISCOUNT UNLOCKED • ONGKIR SORTED • KEEP ADDING • ", fill: Brand.cocoa, ink: Brand.lime, size: 13, speed: 18)
        }
        .background(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                Rays(color: .white).frame(width: 260, height: 260).opacity(0.7).offset(x: 60, y: -60)
                Mascot(pose: "pose-celebrating", size: 130, fill: .clear).offset(x: -6, y: 10)
            }
        }
        .background(Brand.lime)
        .clipShape(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous).strokeBorder(Brand.limeDeep, lineWidth: 2))
        .accessibilityElement(children: .combine)
    }

    private func bar(fill: AnyShapeStyle, width: CGFloat) -> some View {
        Capsule().fill(Brand.liquorice100).frame(height: 20)
            .overlay(alignment: .leading) {
                GeometryReader { g in Capsule().fill(fill).frame(width: g.size.width * width) }
            }
            .clipShape(Capsule())
    }
}

/// A slowly scrolling band of uppercase text.
/// Running text band, `<at-marquee>` in the design: Roundo 700 uppercase, 0.04em tracking, line height 1, vertical
/// padding 0.7 × size. One run is the text six times plus half an em; it travels its own width every `speed` seconds.
struct Marquee: View {
    var text = "FRESH FROM ATAS • GROUP UP • SAVE ON ONGKIR • "
    var fill = Brand.cocoa
    var ink = Brand.cream
    var size: CGFloat = 15
    var speed: Double = 30
    var reverse = false
    var tilt: Double = 0
    @State private var runWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                TimelineView(.animation(paused: reduceMotion)) { t in
                    let phase = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: speed) / speed
                    HStack(spacing: 0) { run; run }
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width / 2 } action: { runWidth = $0 }
                        .offset(x: -runWidth * (reverse ? 1 - phase : phase))
                }
            }
            .padding(.vertical, (size * 0.7).rounded())
        .background(fill)
        .clipped()
        .rotationEffect(.degrees(tilt))
        .padding(.horizontal, tilt == 0 ? 0 : -12)
        .accessibilityHidden(true)
    }
}

/// The design system's toast ("Link copied", "Account number copied"): cocoa pill, lime check, Manrope 600 14.
struct Toast: View {
    var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Brand.lime)
            Text(text).font(Brand.font(.callout, weight: 600)).foregroundStyle(Brand.cream)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(Capsule().fill(Brand.cocoa))
        .shadow(color: Brand.cocoa.opacity(0.25), radius: 12, y: 8)
    }
}

extension View {
    /// Shows the toast for 1.6 s, `above` points over the bottom safe area, with a success haptic.
    func toast(_ text: Binding<String?>, above: CGFloat = 8) -> some View {
        overlay(alignment: .bottom) {
            if let t = text.wrappedValue {
                Toast(text: t)
                    .padding(.bottom, above)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: t) {
                        try? await Task.sleep(for: .seconds(1.6))
                        text.wrappedValue = nil
                    }
            }
        }
        .animation(.spring(duration: 0.3), value: text.wrappedValue)
        .sensoryFeedback(.success, trigger: text.wrappedValue) { _, new in new != nil }
    }
}

/// Copy with feedback: `copy(link, "Link copied", $toast)` on a view that has `.toast($toast)`.
func copy(_ value: String, _ message: String, _ toast: Binding<String?>) {
    UIPasteboard.general.string = value
    toast.wrappedValue = message
}

// MARK: States

/// "Proofing the dough…": a dashed caramel ring turning every 14 s around the neutral giraffe (`<at-spin>`).
struct LoaderView: View {
    var line = "Proofing the dough…"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                TimelineView(.animation(paused: reduceMotion)) { t in
                    Circle().strokeBorder(Brand.caramel, style: StrokeStyle(lineWidth: 1.2, dash: [5.4, 5.4]))
                        .rotationEffect(.degrees(t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 14) / 14 * 360))
                }
                .frame(width: 180, height: 180)
                Mascot(pose: "pose-neutral", size: 144)
            }
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
            .background(shape.fill(selected ? Brand.selectedFill : Brand.cream))
            .overlay(shape.strokeBorder(selected ? Brand.caramel : Brand.liquorice100, lineWidth: selected ? 2.5 : 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Segmented control: white thumb on a liquorice capsule, 14pt semibold.
struct Segmented: View {
    var options: [String]
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                Button { withAnimation(.snappy) { selection = i } } label: {
                    Text(options[i]).font(Brand.font(.callout, weight: 600))
                        .foregroundStyle(selection == i ? Brand.cocoa : Brand.ink2)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background { if selection == i { Capsule().fill(.white).shadow(color: Brand.cocoa.opacity(0.12), radius: 1.5, y: 1) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == i ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Brand.liquorice100))
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
                    .frame(width: 36, height: 36).background(Circle().fill(detail == nil ? Brand.liquorice100 : Brand.choc100))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Brand.font(.body, size: 15, weight: detail == nil ? 600 : 700))
                    if let detail { Text(detail).font(Brand.font(.callout, size: 13)).foregroundStyle(Brand.ink2).lineLimit(1) }
                }
                Spacer(minLength: 0)
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
