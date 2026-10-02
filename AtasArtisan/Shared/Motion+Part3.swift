import SwiftUI

// MARK: - Part 3 (ranks 16–22 + the onboarding ring). Additions only: part 1 and part 2 are unchanged.
// "Ataste Motion" board, part 3: sign-in, Send to WhatsApp and coming back, uploading a photo, marking paid, sharing
// an invite, the running-text band and empty states, plus the onboarding ring's settling turn. Values match the
// board's prototypes one to one.

extension Motion {
    /// The dashed onboarding ring (1-1, 1-4a). Replaces the 14 s linear loop:
    /// a quarter turn per real step on a slow critically damped spring, then still.
    static let ringTurn = Animation.spring(response: 1.2, dampingFraction: 1.0)
    static let ringStep = Angle.degrees(90)
}

enum SplashMotion {
    static let ringFrom = Angle.degrees(-90)
    static let mascotFrom: CGFloat = 0.9, mascotDelay: Double = 0.08
    static let logoOffset: CGFloat = -24, logoDelay: Double = 0.12
    static let captionDelay: Double = 0.30
    static let readyBump: CGFloat = 1.06, welcomeDelay: Double = 0.25
}

enum SignInMotion {
    static let card = CGSize(width: 354, height: 102), cardRadius: CGFloat = 32
    static let chip = CGSize(width: 236, height: 38)
    static let codeSize = (card: CGFloat(40), chip: CGFloat(15))
    static let mascotSize = (send: CGFloat(140), wait: CGFloat(206))
    static let waitInDelay: Double = 0.08
    static let codeLifetime: Double = 600
    static let newCodeDelay: Double = 0.32     // after the shake
    // Verified
    static let screenDelay: Double = 0.06
    static let sunburst = (tilt: Angle.degrees(-40), scale: CGFloat(0.8), delay: 0.06)
    static let discDelay: Double = 0.10
    static let mascot = (offset: CGFloat(60), delay: 0.16)
    static let headline = (scale: CGFloat(0.6), tilt: Angle.degrees(-6), delay: 0.24)
    static let lineDelay: Double = 0.32
    static let continueButton = (offset: CGFloat(40), delay: 0.38)
}

enum HandOffMotion {
    static let chipDelay: Double = 0.06
    static let cardOffset: CGFloat = 16, cardDelay: Double = 0.10
    static let mascotOffset: CGFloat = -30, mascotDelay: Double = 0.16
    static let totalsDelay: Double = 0.16
    static let buttonOffset: CGFloat = 40, buttonDelay: Double = 0.24
}

enum UploadMotion {
    static let thumbFrom: CGFloat = 0.9
    static let overlayOpacity: Double = 0.45   // Cocoa
    static let creepTo = AsyncMotion.creepTo   // 0.85
    static let doneDelay: Double = 0.20, retryDelay: Double = 0.10
    static let timeout: Double = 10
}

enum BoardMotion {
    static let buttonCollapseDelay: Double = 0.04
    static let barDelay: Double = 0.10
    static let nudgeBump: CGFloat = 1.15
}

enum ShareMotion {
    static let qrRevealDelay: Double = 0.18
    static let qrRevealRadius: CGFloat = 0.75  // of the QR tile, circle from the centre
}

enum BandMotion {
    /// The band's one flick waits this long after its screen appears. (Its speed and coast stay the `Marquee`'s own,
    /// by the user's call; the board's 800 pt/s and 0.998 per ms are not used.)
    static let flickDelay: Double = 0.30
}

enum EmptyMotion {
    static let frameOffset: CGFloat = -24
    static let frameTilt = (from: Angle.degrees(-6), to: Angle.degrees(-1.5))
    static let captionDelay: Double = 0.18
    static let copyOffset: CGFloat = 8, headlineDelay: Double = 0.12, bodyDelay: Double = 0.18
    static let buttonOffset: CGFloat = 24, primaryDelay: Double = 0.24, secondaryDelay: Double = 0.30
}

// MARK: Entrances

/// A part that enters when `shown` turns true: from `offset` (y), `scale` and `tilt` to rest on `spring` after
/// `delay`, its opacity 0 → 1 on `fade` (nil: the opacity rides on `spring`; `fades` false: it never fades). Turning
/// false hides it at once. Reduce Motion: it only fades in (`Motion.Reduced.fade`), or appears if it never fades.
struct Entrance: ViewModifier {
    var shown: Bool
    var offset: CGFloat = 0
    var scale: CGFloat = 1
    var tilt: Angle = .zero
    var anchor: UnitPoint = .center
    var spring: Animation
    var fade: Animation? = Motion.fade
    var fades = true
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let still = shown || reduceMotion
        content
            .scaleEffect(still ? 1 : scale, anchor: anchor)
            .rotationEffect(still ? .zero : tilt, anchor: anchor)
            .offset(y: still ? 0 : offset)
            .animation(shown && !reduceMotion ? spring.delay(delay) : nil, value: shown)
            .opacity(shown || !fades ? 1 : 0)
            .animation(shown ? (reduceMotion ? Motion.Reduced.fade : fade ?? spring).delay(delay) : nil, value: shown)
    }
}

extension View {
    func entrance(_ shown: Bool, offset: CGFloat = 0, scale: CGFloat = 1, tilt: Angle = .zero, anchor: UnitPoint = .center,
                  _ spring: Animation, fade: Animation? = Motion.fade, fades: Bool = true, delay: Double = 0) -> some View {
        modifier(Entrance(shown: shown, offset: offset, scale: scale, tilt: tilt, anchor: anchor, spring: spring, fade: fade,
                          fades: fades, delay: delay))
    }
}

// MARK: Empty states (22)

/// Empty states already seen this app session: only the first view of each plays its entrance.
@MainActor enum EmptySeen {
    static var ids: Set<String> = []
}

/// The parts of an empty state (2-2, 6-3), in the order they enter.
enum EmptyPart { case painting, caption, headline, body, primary, secondary }

/// One part of an empty state on its first view this session: the painting swings in from its top centre (offset y
/// −24 → 0, −6° → −1.5° on `Motion.bounce`, fading in), the caption fades in, the copy rises 8 pt and the buttons 24 pt
/// in order. Seen before, it is shown still. Reduce Motion fades the parts in. The painting is drawn untilted
/// (`tilt: 0`): its rest tilt (−1.5°) comes from here.
struct EmptyIntro: ViewModifier {
    var part: EmptyPart
    @State private var play: Bool
    @State private var on = false
    private let id: String

    init(_ part: EmptyPart, id: String) {
        self.part = part
        self.id = id
        _play = State(initialValue: !EmptySeen.ids.contains(id))
    }

    func body(content: Content) -> some View {
        let shown = on || !play
        Group {
            switch part {
            case .painting:
                content
                    .rotationEffect(EmptyMotion.frameTilt.to, anchor: .top)
                    .entrance(shown, offset: EmptyMotion.frameOffset,
                              tilt: .degrees(EmptyMotion.frameTilt.from.degrees - EmptyMotion.frameTilt.to.degrees), anchor: .top, Motion.bounce)
            case .caption:
                content.entrance(shown, Motion.fade, delay: EmptyMotion.captionDelay)
            case .headline:
                content.entrance(shown, offset: EmptyMotion.copyOffset, Motion.settle, delay: EmptyMotion.headlineDelay)
            case .body:
                content.entrance(shown, offset: EmptyMotion.copyOffset, Motion.settle, delay: EmptyMotion.bodyDelay)
            case .primary:
                content.entrance(shown, offset: EmptyMotion.buttonOffset, Motion.arrive, delay: EmptyMotion.primaryDelay)
            case .secondary:
                content.entrance(shown, offset: EmptyMotion.buttonOffset, Motion.arrive, delay: EmptyMotion.secondaryDelay)
            }
        }
        .onAppear {
            EmptySeen.ids.insert(id)
            if play { on = true }
        }
    }
}

extension View {
    func emptyIntro(_ part: EmptyPart, id: String) -> some View { modifier(EmptyIntro(part, id: id)) }
}

// MARK: Small part 3 pieces

/// One animated value handed to `content` frame by frame, so each edge of a moving shape can ride its own spring.
struct EdgeValue<Content: View>: View, Animatable {
    var value: CGFloat
    @ViewBuilder var content: (CGFloat) -> Content
    var animatableData: CGFloat {
        get { value }
        set { value = newValue }
    }
    var body: some View { content(value) }
}

/// A small button that folds away from its trailing edge (Mark paid once paid, Nudge once the member says paid):
/// opacity → 0 on `Motion.fadeOut` and width → 0 on `Motion.leave` 0.04 s later. Arriving, it opens from width 0 to
/// its fitted width on `Motion.settle`. Reduce Motion: it fades, then its width snaps.
struct Fold: Transition {
    var reduceMotion: Bool
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(FoldWidth(folded: !phase.isIdentity, reduceMotion: reduceMotion, leaving: phase == .didDisappear))
    }
}

private struct FoldWidth: ViewModifier {
    var folded: Bool
    var reduceMotion: Bool
    var leaving: Bool
    @State private var width: CGFloat?

    func body(content: Content) -> some View {
        let widthMotion: Animation? = reduceMotion ? nil : leaving ? Motion.leave.delay(BoardMotion.buttonCollapseDelay) : Motion.settle
        content
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .frame(width: folded ? 0 : width, alignment: .leading)
            .clipped()
            .animation(widthMotion, value: folded)
            .opacity(folded ? 0 : 1)
            .animation(reduceMotion ? Motion.Reduced.fade : leaving ? Motion.fadeOut : Motion.fade, value: folded)
    }
}

/// A tile revealed by a circle growing from its centre (the share sheet's QR): the clip's radius goes 0 → 75 % of the
/// tile's width on `Motion.settle` 0.18 s after it appears. Reduce Motion fades it in.
struct CircleReveal: ViewModifier {
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .mask {
                GeometryReader { g in
                    let r = reduceMotion || open ? g.size.width * ShareMotion.qrRevealRadius : 0
                    Circle().frame(width: r * 2, height: r * 2).position(x: g.size.width / 2, y: g.size.height / 2)
                }
            }
            .opacity(reduceMotion && !open ? 0 : 1)
            .onAppear {
                withAnimation((reduceMotion ? Motion.Reduced.fade : Motion.settle).delay(ShareMotion.qrRevealDelay)) { open = true }
            }
    }
}

// MARK: Upload (18)

/// A freshly picked photo scales in from 0.9 as it fades in (`Motion.settle`, `Motion.fade`); one that was already
/// there (`active` false) is still. Reduce Motion fades it in.
struct ThumbIn: ViewModifier {
    var active: Bool
    @State private var on = false
    func body(content: Content) -> some View {
        content.entrance(on || !active, scale: UploadMotion.thumbFrom, Motion.settle).onAppear { on = true }
    }
}

/// Where an upload stands, for the photo it covers.
enum UploadState: Equatable { case uploading, done, failed }

/// What sits over a photo being uploaded (the transfer receipt, the delivery photo on 5-12): a Cocoa 45 % layer and a
/// 56 pt Cream ring that creeps to 85 % and holds. Done: the ring fills, the layer fades and a lime check badge pops at
/// the top-right corner. Failed: the ring drains, the photo shakes and "Tap to retry" fades in. Reduce Motion: no
/// shake, and the ring, layer and badge crossfade.
struct UploadOverlay: ViewModifier {
    var state: UploadState?
    /// The photo's corner radius, which the layer follows.
    var radius: CGFloat
    /// Shows the check badge (a receipt that is up); the delivery photo hands off to its button instead.
    var badge = true
    @State private var ring: CGFloat = 0
    @State private var shakes = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Brand.cocoa.opacity(state == .uploading || state == .failed ? UploadMotion.overlayOpacity : 0))
                        .animation(reduceMotion ? Motion.Reduced.fade : Motion.fade, value: state)
                    // 56 pt across the outside of its 3 pt stroke. It fades with the layer once done, and gives way to
                    // "Tap to retry" once drained.
                    Circle().stroke(Brand.cream.opacity(0.3), lineWidth: 3)
                        .overlay {
                            Circle().trim(from: 0, to: ring)
                                .stroke(Brand.cream, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 53, height: 53)
                        .opacity(state == .uploading ? 1 : 0)
                        .animation((reduceMotion ? Motion.Reduced.fade : Motion.fade).delay(state == .failed ? UploadMotion.retryDelay : 0), value: state)
                    if state == .failed {
                        Label("Tap to retry", systemImage: "arrow.clockwise")
                            .labelStyle(IconLabel(spacing: 4, size: 11))
                            .font(Brand.font(.callout, size: 11, weight: 600))
                            .foregroundStyle(Brand.cream)
                            .multilineTextAlignment(.center)
                            .padding(4)
                            .transition(.opacity.animation((reduceMotion ? Motion.Reduced.fade : Motion.fade).delay(UploadMotion.retryDelay)))
                    }
                }
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                if badge && state == .done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Brand.cocoa)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Brand.lime))
                        .padding(3).background(Circle().fill(.white))
                        .offset(x: 8, y: -8)
                        .transition(reduceMotion ? AnyTransition.opacity.animation(Motion.Reduced.fade) : AnyTransition(PopIn()).animation(Motion.pop))
                        .accessibilityHidden(true)
                }
            }
            .shake(reduceMotion ? 0 : shakes)
            .onChange(of: state, initial: true) { old, new in
                switch new {
                case .uploading:
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { ring = 0 }
                    withAnimation(Motion.creep) { ring = UploadMotion.creepTo }
                case .done:
                    // Shown as it was when it opens already up.
                    if old == .uploading { withAnimation(reduceMotion ? Motion.Reduced.fill : Motion.doughLead) { ring = 1 } } else { ring = 1 }
                case .failed:
                    if old == .uploading { shakes += 1 }
                    withAnimation(reduceMotion ? Motion.Reduced.fade : Motion.leave) { ring = 0 }
                case nil:
                    ring = 0
                }
            }
    }
}
