import SwiftUI

// The design system's building blocks (Claude Design "Ataste Design System"): pill buttons with a 4pt
// self-coloured border, pastel tags, white cards on cream, dashed photo circles, the Rp 200k bar,
// marquee bands, the giraffe in a pastel circle.

// MARK: Buttons

enum PillKind { case primary, secondary, dark, success, destructive }
enum PillSize { case large, medium, small }

struct PillStyle: ButtonStyle {
    var kind: PillKind = .primary
    var size: PillSize = .large
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let (fill, ink): (Color, Color) = switch kind {
        case .primary: (Brand.caramel, Brand.cream)
        case .secondary: (Brand.choc100, Brand.cocoa)
        case .dark: (Brand.cocoa, Brand.cream)
        case .success: (Brand.lime, Brand.cocoa)
        case .destructive: (Brand.destructive, .white)
        }
        let height: CGFloat = switch size { case .large: 60; case .medium: 52; case .small: 36 }
        configuration.label
            .font(Brand.font(.headline, size: size == .small ? 14 : 17, weight: 600))
            .lineLimit(1)
            .padding(.horizontal, size == .small ? 16 : 32)
            .frame(maxWidth: size == .large ? .infinity : nil, minHeight: height)
            .foregroundStyle(enabled ? ink : Brand.ink3)
            .background(Capsule().fill(enabled ? fill : Brand.liquorice100))
            .overlay(Capsule().stroke(enabled ? fill : Brand.liquorice400, lineWidth: size == .small ? 3 : 4))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .contentShape(Capsule())
            .frame(minHeight: 44)
    }
}

extension ButtonStyle where Self == PillStyle {
    static func pill(_ kind: PillKind = .primary, _ size: PillSize = .large) -> PillStyle { PillStyle(kind: kind, size: size) }
}

/// 28pt round icon button with a 44pt tap area.
struct IconCircle: View {
    var symbol: String
    var fill: Color = Brand.choc100
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.cocoa)
                .frame(width: 28, height: 28).background(Circle().fill(fill))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Tags and state

struct Tag: View {
    var text: String
    var fill: Color = Brand.choc100
    var ink: Color = Brand.cocoa
    var body: some View {
        Text(text).brand(.label, ink).padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(fill))
    }
}

struct StateTag: View {
    var state: GroupState
    var body: some View {
        let (bg, fg, dot): (Color, Color, Color) = switch state {
        case .open: (Brand.lime, Brand.cocoa, Color(rgb: 0x5E7A00))
        case .locked: (Brand.liquorice100, Brand.cocoa, Brand.cocoa)
        case .edits: (Brand.pink100, Brand.cocoa, Color(rgb: 0xB0005A))
        case .sent: (Brand.choc100, Brand.cocoa, Brand.caramel)
        case .confirmed: (Brand.caramel, Brand.cream, Brand.choc100)
        case .delivered: (Brand.cocoa, Brand.lime, Brand.lime)
        case .closed: (.white, Brand.ink3, Brand.liquorice400)
        case .cancelled: (Color(rgb: 0xFDE3E5), Color(rgb: 0xB00010), Brand.destructive)
        }
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(state.title).brand(.label, fg)
        }
        .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(bg))
        .accessibilityLabel("Status: \(state.title)")
    }
}

enum PayState {
    case unpaid, says, paid
    init(_ row: BillRow) { self = row.paid_at != nil ? .paid : row.proof_at != nil ? .says : .unpaid }
}

struct PayTag: View {
    var state: PayState
    var body: some View {
        switch state {
        case .unpaid: Tag(text: "Unpaid", fill: .white, ink: Brand.cocoa).overlay(Capsule().stroke(Brand.liquorice400))
        case .says: Tag(text: "Says paid", fill: Brand.choc100)
        case .paid: Tag(text: "Paid", fill: Brand.lime)
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
}

struct Avatar: View {
    var name: String
    var index: Int
    var host = false
    var size: CGFloat = 36
    var art: String? = nil
    var body: some View {
        ZStack {
            Circle().fill(Brand.people[index % Brand.people.count])
            if let art, Art.all.contains(art) {
                Image(art).resizable().scaledToFill()
                    .frame(width: size, height: size, alignment: art.hasPrefix("paint") ? .top : .bottom)
                    .clipShape(Circle())
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(Brand.font(.headline, size: size * 0.42))
                    .foregroundStyle(Brand.cocoa)
            }
        }
            .frame(width: size, height: size)
            .overlay(alignment: .bottom) {
                if host {
                    Text("HOST").font(Brand.font(.label, size: 7)).foregroundStyle(Brand.cream)
                        .padding(.horizontal, 3).background(Capsule().fill(Brand.cocoa)).offset(y: 5)
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
            Image(pose).resizable().scaledToFit().clipShape(Circle())
        }
        .frame(width: size, height: size)
        .overlay(Circle().inset(by: -7).strokeBorder(Brand.caramel.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5, 5])))
        .accessibilityHidden(true)
    }
}

/// Product photo on a pastel circle inside a dashed ring.
struct ProductPhoto: View {
    var url: URL?
    var size: CGFloat
    var fill: Color = Brand.choc100
    var body: some View {
        ZStack {
            Circle().fill(fill)
            AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
                .frame(width: size * 0.86, height: size * 0.86).clipShape(Circle())
        }
        .frame(width: size, height: size)
        .overlay(Circle().inset(by: -5).strokeBorder(Brand.caramel.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])))
        .accessibilityHidden(true)
    }
}

/// "Rp 45.000 more to unlock the ongkir discount" → sour-lime "Discount unlocked".
struct DiscountBar: View {
    var subtotal: Int
    static let goal = 200_000
    var body: some View {
        let done = subtotal >= Self.goal
        VStack(alignment: .leading, spacing: Brand.s2) {
            HStack {
                Text(Rupiah.format(subtotal)).brand(.title2)
                Text("/ 200.000").brand(.callout, Brand.ink3)
                Spacer()
                if done { Tag(text: "Discount unlocked", fill: Brand.lime) }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Brand.liquorice100)
                    Capsule().fill(done ? Brand.limeDeep : Brand.choc400)
                        .frame(width: g.size.width * min(1, CGFloat(subtotal) / CGFloat(Self.goal)))
                }
            }
            .frame(height: 12)
            Text(done ? "The ongkir discount is unlocked for this order."
                      : "\(Rupiah.format(Self.goal - subtotal)) more to unlock the ongkir discount")
                .brand(.callout, done ? Brand.cocoa : Brand.caramel)
        }
        .accessibilityElement(children: .combine)
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

struct LoaderView: View {
    var line = "Proofing the dough…"
    @State private var spin = false
    var body: some View {
        VStack(spacing: Brand.s5) {
            ZStack {
                Circle().strokeBorder(Brand.caramel, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                    .frame(width: 190, height: 190).rotationEffect(.degrees(spin ? 360 : 0))
                Mascot(pose: "pose-waiting", size: 160)
            }
            Text(line).brand(.title2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.cream.ignoresSafeArea())
        .onAppear { withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { spin = true } }
    }
}

struct EmptyStateView: View {
    var pose = "pose-sleeping"
    var title: String
    var message: String
    var body: some View {
        VStack(spacing: Brand.s4) {
            Mascot(pose: pose, size: 150, fill: Brand.liquorice100)
            Text(title).brand(.title2).multilineTextAlignment(.center)
            Text(message).brand(.body, Brand.ink2).multilineTextAlignment(.center)
        }
        .padding(Brand.s5)
        .frame(maxWidth: .infinity)
    }
}

struct ErrorBanner: View {
    var message: String
    var retry: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: Brand.s3) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Brand.destructive)
            Text(message).brand(.callout).frame(maxWidth: .infinity, alignment: .leading)
            if let retry { Button("Retry", action: retry).buttonStyle(.pill(.secondary, .small)) }
        }
        .card(Brand.rSmall, padding: Brand.s3)
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
