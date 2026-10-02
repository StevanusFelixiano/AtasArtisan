import SwiftUI

// MARK: - Part 2 (ranks 7–15). Additions only: part 1 names and values are unchanged.
// "Ataste Motion" board, part 2: sheets and confirms, in-app notifications, cards opening into the group, the split,
// members joining, the bill settling, option chips, skeleton rows and pull to refresh. Values match the board's
// prototypes one to one.

extension Motion {
    static let pressCard = CGSize(width: 1.015, height: 0.97)   // big cards, banners
    /// UIScrollView-style rubber band for over-drag: sheets, banners, pull to refresh.
    static func rubberBand(_ offset: CGFloat, limit: CGFloat, c: CGFloat = 0.55) -> CGFloat {
        (1 - 1 / (offset * c / limit + 1)) * limit
    }

    /// `spring` started at the finger's release `velocity` (pt/s) for a travel of `distance` pt. SwiftUI reads a
    /// spring's initial velocity in travels per second.
    static func flung(_ spring: Spring, velocity: CGFloat, distance: CGFloat) -> Animation {
        .interpolatingSpring(spring, initialVelocity: abs(distance) < 1 ? 0 : Double(velocity / distance))
    }
}

extension Motion.Keyframe {
    static let arrive = Spring(response: 0.42, dampingRatio: 0.72)   // Motion.arrive
    static let leave = Spring(response: 0.32, dampingRatio: 1.0)     // Motion.leave
}

enum SheetMotion {
    static let present  = Motion.arrive              // overshoot stretches the sheet, it doesn't lift
    static let snapBack = Motion.arrive
    static let dismiss  = Motion.leave
    static let offscreenExtra: CGFloat = 16
    static let dismissFraction: CGFloat = 0.3
    static let dismissVelocity: CGFloat = 800        // pt/s, downward
    static let scrimOpacity: Double = 0.3            // Cocoa
    static let rowAfterRemove: Double = 0.12         // remove confirm → row collapse
}

enum BannerMotion {
    static let hiddenExtra: CGFloat = 70             // hidden offset = −(height + 70)
    static let hold: Double = 4
    static let dismissDistance: CGFloat = 24, dismissVelocity: CGFloat = 300   // upward
    static let tapSlop: CGFloat = 6
    static let stretchLimit: CGFloat = 120
    static let repeatBump: CGFloat = 1.06
}

enum CardMotion {
    static let edges      = Motion.doughLead         // top, leading, trailing
    static let bottomEdge = Motion.doughTrail
    static let colourDelay: Double = 0.06, contentDelay: Double = 0.12, closeContentDelay: Double = 0.06
    static let cornerRadius: CGFloat = 32
}

enum SplitMotion {
    static let slices = 12
    static let segmentGap: CGFloat = 2
    static let rowDelay: Double = 0.04
    static let unavailableOpacity: Double = 0.4
}

enum MembersMotion {
    static let stackStep: CGFloat = 30               // 40pt avatars overlapping 10
    static let rowHeight: CGFloat = 69
    static let rowDelay: Double = 0.06
}

enum BillMotion {
    static let lineStart: Double = 0.10, lineStep: Double = 0.04
    static let discountDelay: Double = 0.18
    static let totalDelay: Double = 0.24
    static let totalSize = (from: CGFloat(46), to: CGFloat(52))
    static let waitingDelay: Double = 0.30
    static let payDelay: Double = 0.40, payBump: CGFloat = 1.05
}

enum OptionMotion {
    static let inkDelay: Double = 0.04
}

enum SkeletonMotion {
    static let minimumShow: Double = 0.3
    static let skipIfFasterThan: Double = 0.15
    static let stagger: Double = 0.04, maxStagger: Double = 0.32
    static let contentOffset: CGFloat = 6
    static let monthLabelHeight: CGFloat = 30
}

enum RefreshMotion {
    static let threshold: CGFloat = 72
    static let hold: CGFloat = 64
    static let mascotFrom: CGFloat = 0.6, mascotFadeDistance: CGFloat = 40
    static let thresholdBump: CGFloat = 1.12
    static let returnDelay: Double = 0.20
    static let timeout: Double = 10
}

// MARK: Skeleton timing

/// When a loading screen shows its skeleton (14 Skeleton → content): nothing for the first 0.15 s, so a fast load
/// shows its content still; once shown, the skeleton stays at least 0.3 s, then the content arrives over it. The
/// skeleton itself is still: no shimmer, no pulse.
@MainActor @Observable
final class SkeletonGate {
    private(set) var skeleton = false
    private(set) var revealed = false
    /// The skeleton was on screen, so the content arrives (rather than showing still).
    private(set) var animated = false
    private var shownAt: Date?

    /// Runs the first load under the gate; later loads run `work` straight away.
    func load(_ work: () async -> Void) async {
        guard !revealed else { return await work() }
        let timer = Task {
            try? await Task.sleep(for: .seconds(SkeletonMotion.skipIfFasterThan))
            guard !Task.isCancelled, !revealed else { return }
            skeleton = true
            shownAt = .now
        }
        await work()
        timer.cancel()
        if let shownAt {
            try? await Task.sleep(for: .seconds(max(0, SkeletonMotion.minimumShow - Date.now.timeIntervalSince(shownAt))))
            animated = true
        }
        revealed = true
    }

    /// A row's place in the arrival: 0.04 s per row, capped at 0.32 s.
    static func delay(_ index: Int) -> Double { min(Double(index) * SkeletonMotion.stagger, SkeletonMotion.maxStagger) }
}

/// Content arriving over its skeleton: offset y 6 → 0 on `Motion.settle` and opacity 0 → 1 on `Motion.fade`, after
/// the row's stagger. Reduce Motion crossfades in place. Still when `animate` is false (a fast load, a later load).
struct Arrival: ViewModifier {
    var index = 0
    var animate: Bool
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let on = shown || !animate
        let delay = SkeletonGate.delay(index)
        content
            .offset(y: on || reduceMotion ? 0 : SkeletonMotion.contentOffset)
            .animation(Motion.settle.delay(delay), value: on)
            .opacity(on ? 1 : 0)
            .animation((reduceMotion ? Motion.Reduced.fade : Motion.fade).delay(delay), value: on)
            .onAppear { if animate { shown = true } }
    }
}

// MARK: Small part 2 pieces

/// A label that rolls to a new text (`Motion.digits`, `Roll`), or crossfades under Reduce Motion: the split total
/// line, the bill's ongkir share.
struct RollText<Shown: View>: View {
    var key: String
    var delay: Double = 0
    @ViewBuilder var content: Shown
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            content.id(key).transition(AnyTransition.roll(reduceMotion).animation((reduceMotion ? Motion.Reduced.fade : Motion.digits).delay(delay)))
        }
    }
}

/// A new member's avatar pops from its centre, slightly below the middle: scale 0 → 1, rotation −12° → 0°
/// (`Motion.pop` after `delay`). Reduce Motion fades it in. Shown still when `active` is false (on appear).
struct PopOnAppear: ViewModifier {
    var active: Bool
    var delay: Double = 0
    @State private var popped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let anchor = UnitPoint(x: 0.5, y: 0.6)
        let still = !active || popped
        content
            .scaleEffect(still || reduceMotion ? 1 : 0.01, anchor: anchor)
            .rotationEffect(still || reduceMotion ? .zero : StepperMotion.iconTilt, anchor: anchor)
            .opacity(still || !reduceMotion ? 1 : 0)
            .onAppear {
                guard active else { return }
                withAnimation((reduceMotion ? Motion.Reduced.fade : Motion.pop).delay(delay)) { popped = true }
            }
    }
}
