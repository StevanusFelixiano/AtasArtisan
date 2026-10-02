import SwiftUI

// Pull to refresh (Motion board 15). The list itself moves: UIScrollView's own over-scroll is the board's
// Motion.rubberBand(drag, limit: list height). The waiting giraffe fades in over the first 40 pt and grows from 0.6
// to full size by 72 pt; crossing 72 pt bumps it with a light tap. Released past 72 pt, the list holds 64 pt down
// while a caramel ring creeps round the giraffe to 85 %; the reply fills it and the list returns 0.2 s later. A
// failure or a 10 s wait drains the ring, shakes the giraffe and returns the list. Reduce Motion: opacity only.

extension View {
    /// Ataste pull to refresh on a ScrollView, in place of `.refreshable`. `action` reloads and says whether it
    /// worked. `below` is the height of a title at the top of the list that stays put while the list is pulled (it
    /// reads `pullOffset`); the giraffe sits in the gap under it.
    func pullToRefresh(below: CGFloat = 0, _ action: @escaping () async -> Bool) -> some View {
        modifier(PullRefresh(below: below, action: action))
    }

    /// A title inside a pull-to-refresh list that stays put while the list under it moves.
    func staysPutOnPull() -> some View { modifier(StaysPut()) }
}

extension EnvironmentValues {
    /// How far a pull-to-refresh list is down from its rest: the pull plus the 64 pt hold while it refreshes.
    @Entry var pullOffset: CGFloat = 0
}

private struct StaysPut: ViewModifier {
    @Environment(\.pullOffset) private var pull
    func body(content: Content) -> some View { content.offset(y: -pull) }
}

private struct PullRefresh: ViewModifier {
    var below: CGFloat
    var action: () async -> Bool

    private enum Phase { case idle, refreshing, done, failed }
    @State private var phase = Phase.idle
    /// Over-scroll past the top, from the scroll view.
    @State private var pull: CGFloat = 0
    @State private var dragging = false
    /// The list's hold while refreshing (0 or 64), animated; it shows only where it exceeds the pull.
    @State private var hold: CGFloat = 0
    @State private var ring: CGFloat = 0
    @State private var fade = 1.0
    @State private var bumps = 0
    @State private var shakes = 0
    @State private var fails = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(.always, axes: .vertical)
            .scrollClipDisabled()
            .onScrollGeometryChange(for: CGFloat.self) { max(0, -($0.contentOffset.y + $0.contentInsets.top)) } action: { _, p in pull = p }
            .onScrollPhaseChange { old, new in
                dragging = new == .interacting
                if old == .interacting, new != .interacting, phase == .idle, pull >= RefreshMotion.threshold { start() }
            }
            .modifier(Held(hold: hold, pull: pull, below: below) { gap in indicator(gap) })
            .onChange(of: dragging && pull >= RefreshMotion.threshold && phase == .idle) { _, armed in if armed { bumps += 1 } }
            .sensoryFeedback(.impact(weight: .light), trigger: bumps)
            .sensoryFeedback(Haptic.fail, trigger: fails)
            // VoiceOver has no pull: a Refresh button comes first in the list and runs the same refresh, which says
            // how it went. It is there only while VoiceOver runs, and takes no room.
            .overlay(alignment: .top) {
                if voiceOver {
                    Button("Refresh") { start() }
                        .disabled(phase != .idle)
                        .font(.system(size: 1))
                        .foregroundStyle(Color.clear)
                        .frame(maxWidth: .infinity, maxHeight: 1)
                        .clipped()
                        .accessibilitySortPriority(1)
                }
            }
            .accessibilityElement(children: .contain)
    }

    /// The giraffe in its white circle inside the ring, sized and faded by how far the list is down.
    private func indicator(_ gap: CGFloat) -> some View {
        let refreshing = phase != .idle
        let shown = refreshing ? 1 : min(1, gap / RefreshMotion.mascotFadeDistance)
        let grown = refreshing || reduceMotion ? 1 : RefreshMotion.mascotFrom + (1 - RefreshMotion.mascotFrom) * min(1, gap / RefreshMotion.threshold)
        return ZStack {
            Circle().stroke(Brand.liquorice100, lineWidth: 3).frame(width: 56, height: 56)
            Circle().trim(from: 0, to: ring)
                .stroke(Brand.caramel, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 56, height: 56)
            Mascot(pose: "pose-waiting", size: 48, fill: .white)
        }
        .frame(width: 60, height: 60)
        .scaleEffect(grown)
        .kick(reduceMotion ? 0 : bumps, from: RefreshMotion.thresholdBump)
        .shake(reduceMotion ? 0 : shakes)
        .opacity(shown * fade)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func start() {
        phase = .refreshing
        AccessibilityNotification.Announcement("Refreshing").post()
        withAnimation(reduceMotion ? Motion.Reduced.fade : Motion.settle) { hold = RefreshMotion.hold }
        withAnimation(Motion.creep) { ring = AsyncMotion.creepTo }
        Task {
            // Whichever comes first: the reply, or 10 s (the reload carries on and lands when it lands).
            let (replies, reply) = AsyncStream.makeStream(of: Bool.self)
            Task {
                reply.yield(await action())
                reply.finish()
            }
            let timeout = Task {
                try? await Task.sleep(for: .seconds(RefreshMotion.timeout))
                reply.yield(false)
                reply.finish()
            }
            var first = replies.makeAsyncIterator()
            let ok = await first.next() ?? false
            timeout.cancel()
            if ok { await finish() } else { await fail() }
        }
    }

    private func finish() async {
        phase = .done
        AccessibilityNotification.Announcement("Refreshed").post()
        withAnimation(reduceMotion ? Motion.Reduced.fill : Motion.doughLead) { ring = 1 }
        try? await Task.sleep(for: .seconds(RefreshMotion.returnDelay))
        withAnimation(Motion.fadeOut) { fade = 0 }
        withAnimation(reduceMotion ? Motion.leave : Motion.arrive, completionCriteria: .logicallyComplete) { hold = 0 } completion: { reset() }
    }

    private func fail() async {
        phase = .failed
        AccessibilityNotification.Announcement("Couldn’t refresh. Try again in a moment.").post()
        fails += 1
        shakes += 1
        withAnimation(reduceMotion ? Motion.Reduced.fade : Motion.leave) { ring = 0 }
        try? await Task.sleep(for: .seconds(0.32))
        withAnimation(Motion.fadeOut) { fade = 0 }
        withAnimation(Motion.leave, completionCriteria: .logicallyComplete) { hold = 0 } completion: { reset() }
    }

    private func reset() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            phase = .idle
            ring = 0
            fade = 1
        }
    }
}

/// Moves the list down by whatever of the hold the over-scroll doesn't already give, frame by frame (only `hold`
/// animates; the pull follows the finger and the scroll view's own bounce), and places the indicator in the gap.
private struct Held<Indicator: View>: ViewModifier, Animatable {
    var hold: CGFloat
    var pull: CGFloat
    var below: CGFloat
    @ViewBuilder var indicator: (CGFloat) -> Indicator

    var animatableData: CGFloat {
        get { hold }
        set { hold = newValue }
    }

    func body(content: Content) -> some View {
        let extra = max(0, hold - pull)
        let gap = pull + extra
        content
            .offset(y: extra)
            .environment(\.pullOffset, gap)
            .overlay(alignment: .top) {
                indicator(gap).offset(y: below + gap / 2 - 30)
            }
    }
}
