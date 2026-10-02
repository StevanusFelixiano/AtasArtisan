import SwiftUI

/// Ataste app motion, the "Ataste Motion" board's constants file (part 1: buttons, adding and the stepper, the
/// Rp 200.000 bar, async buttons, copy and the toast, status chips and the timeline). It extends `TabMotion` (Tab Bar
/// board): the shared springs are TabMotion values under names that say what they're for. Values match the board's
/// prototypes one to one. Every interaction has a Reduce Motion version (opacity only, haptics unchanged), and
/// nothing loops.
enum Motion {
    // Springs
    static let press = TabMotion.pressDown        // (0.20 / 0.75) finger down
    static let release = TabMotion.pressUp        // (0.38 / 0.50) finger up, the dough bounce
    static let pop = TabMotion.badgeIn            // (0.32 / 0.50) something new appears
    static let bump = TabMotion.badgeBump         // (0.30 / 0.60) something there changes
    static let bounce = TabMotion.iconBounce      // (0.38 / 0.45) after a dip; mascot landing
    static let doughLead = TabMotion.pillLead     // (0.30 / 0.78) leading edge of a growing thing
    static let doughTrail = TabMotion.pillTrail   // (0.44 / 0.82) trailing edge, progress fill
    static let settle = Animation.spring(response: 0.40, dampingFraction: 0.86)  // TabMotion.labelOpen, no delay
    static let arrive = Animation.spring(response: 0.42, dampingFraction: 0.72)  // TabMotion.popShow, no delay
    static let leave = TabMotion.pushHide         // (0.32 / 1.0) collapses and exits
    static let glide = TabMotion.scrollToTop      // (0.50 / 1.0) counting, long travel

    // Curves
    static let quickIn = TabMotion.haloIn         // .easeOut(0.08) pressed tone on
    static let quick = TabMotion.iconSwap         // .easeOut(0.12) colours inside a control
    static let digits = Animation.easeOut(duration: 0.18)  // numericText rolls
    static let fade = Animation.easeOut(duration: 0.20)
    static let fadeOut = TabMotion.badgeOut       // .easeIn(0.15)
    static let dip = TabMotion.iconDip            // .easeOut(0.07), scale → 0.8 before bounce
    static let shake = TabMotion.shake
    static let creep = Animation.easeOut(duration: 2.4)    // async fill 0 → 0.85, then holds

    // Press scales
    static let pressWide = CGSize(width: 1.02, height: 0.92)  // full-width pills
    static let pressCompact = TabMotion.pillPressScale        // 1.04 × 0.92
    static let pressIcon = TabMotion.pressScale               // 1.08 × 0.88

    /// The same springs as `Spring`, for keyframe tracks (a keyframe takes a Spring, not an Animation).
    enum Keyframe {
        static let pop = Spring(response: 0.32, dampingRatio: 0.50)
        static let bump = Spring(response: 0.30, dampingRatio: 0.60)
        static let bounce = Spring(response: 0.38, dampingRatio: 0.45)
        static let dip: Double = 0.07
    }

    /// @Environment(\.accessibilityReduceMotion): opacity only. Haptics unchanged.
    enum Reduced {
        static let pressDim = TabMotion.Reduced.pressDim  // 0.6
        static let press = TabMotion.Reduced.press
        static let release = TabMotion.Reduced.release
        static let fade = TabMotion.Reduced.pill          // .easeInOut(0.20)
        static let fill = Animation.easeInOut(duration: 0.25)
    }
}

enum Haptic {
    static let tap: SensoryFeedback = .impact(weight: .light)
    static let heavy: SensoryFeedback = .impact(weight: .medium)
    static let blocked: SensoryFeedback = .impact(weight: .light, intensity: 0.5)
    static let up: SensoryFeedback = .increase
    static let down: SensoryFeedback = .decrease
    static let done: SensoryFeedback = .success
    static let warn: SensoryFeedback = .warning
    static let fail: SensoryFeedback = .error
}

enum ButtonMotion {
    static let reasonOffset: CGFloat = -4
    static let reasonHold: Double = 2.4
}

enum StepperMotion {
    static let addCheckDelay: Double = 0.04
    static let iconTilt: Angle = .degrees(-12)   // check and trash pop in from this
    static let dipScale: CGFloat = 0.8
    static let againBump: CGFloat = 1.2
}

enum BasketMotion {
    static let bumpFrom: CGFloat = 1.06
    static let hiddenOffset: CGFloat = 90
    static let roundTo = 500                    // Rp, while counting
}

enum UnlockMotion {
    static let threshold = 200_000
    static let cardDelay: Double = 0.18         // the fill arrives first
    static let headlineFrom = (scale: CGFloat(0.6), tilt: Angle.degrees(-6), delay: 0.26)
    static let totalSize = (from: CGFloat(38), to: CGFloat(30))
    static let messageDelay: Double = 0.28
    static let sunburst = (tilt: Angle.degrees(-40), opacity: 0.7, delay: 0.26)
    static let mascot = (offset: CGFloat(60), scale: CGFloat(0.8), delay: 0.32)
    static let band = (height: CGFloat(31), delay: 0.38)
}

enum AsyncMotion {
    static let creepTo: CGFloat = 0.85
    static let successDelay: Double = 0.10      // colour, bump, check
    static let checkDelay: Double = 0.12
    static let successBump: CGFloat = 1.05
    static let handOff: Double = 0.8
    static let timeout: Double = 10
}

enum ToastMotion {
    static let enter = (offset: CGFloat(24), scale: CGFloat(0.96))
    static let exitOffset: CGFloat = 8
    static let hold: Double = 1.8
    static let iconHold: Double = 1.6
    static let repeatBump: CGFloat = 1.06
}

enum StatusMotion {
    static let bumpFrom: CGFloat = 1.08, bumpDelay: Double = 0.06
    static let labelOffset: CGFloat = 8
    static let doneDelay: Double = 0.08, nowDelay: Double = 0.20, timeDelay: Double = 0.28
    static let nowFrom: CGFloat = 0.6
}

extension GroupState {
    /// What someone watching the order feels when it moves here; nil for Open, Locked, Sent, Closed. Whoever caused
    /// the change already felt their own button.
    var watcherHaptic: SensoryFeedback? {
        switch self {
        case .confirmed, .delivered: Haptic.done
        case .edits: Haptic.warn
        case .cancelled: Haptic.fail
        case .open, .locked, .sent, .closed: nil
        }
    }
}

// MARK: Buttons

extension View {
    /// The press every button face shares: squash on touch down (`Motion.press`), dough bounce back on release
    /// (`Motion.release`). Reduce Motion dims to 0.6 instead of squashing. The face's own fill and border change to
    /// their pressed tokens with `pressTone`.
    func doughPress(_ pressed: Bool, squash: CGSize) -> some View {
        modifier(DoughPress(pressed: pressed, squash: squash))
    }

    /// The pressed tone's curves: in fast, out slower.
    func pressTone(_ pressed: Bool) -> some View {
        animation(pressed ? Motion.quickIn : Motion.fadeOut, value: pressed)
    }

    /// `.disabled(off)` that still answers a tap: the button shakes, a soft tap plays, and `reason` shows under it for
    /// 2.4 s. A touch down does nothing. Reduce Motion: no shake, the reason fades in and out.
    func disabled(_ off: Bool, reason: String?) -> some View {
        modifier(BlockedTap(off: off, reason: reason))
    }
}

private struct DoughPress: ViewModifier {
    var pressed: Bool
    var squash: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && !reduceMotion ? squash : CGSize(width: 1, height: 1))
            .opacity(pressed && reduceMotion ? Motion.Reduced.pressDim : 1)
            .animation(reduceMotion ? (pressed ? Motion.Reduced.press : Motion.Reduced.release)
                                    : (pressed ? Motion.press : Motion.release), value: pressed)
    }
}

/// The button a style draws: `face` draws it and its press, and the tap that runs the action plays `haptic` (a press
/// that slides off plays nothing). The button styles (pill, bar pill, wide pill, chip, dough) are made of this.
struct CommitButton<Face: ButtonStyle>: View {
    let configuration: PrimitiveButtonStyleConfiguration
    var face: Face
    var haptic: SensoryFeedback?
    @State private var commits = 0

    var body: some View {
        Button(role: configuration.role) {
            commits += 1
            configuration.trigger()
        } label: {
            configuration.label
        }
        .buttonStyle(face)
        .sensoryFeedback(trigger: commits) { _, _ in haptic }
    }
}

/// For buttons that draw their own face: the shared press without a pressed colour, and the commit tap.
struct DoughStyle: PrimitiveButtonStyle {
    var squash = Motion.pressIcon
    var haptic: SensoryFeedback? = Haptic.tap
    func makeBody(configuration: Configuration) -> some View {
        CommitButton(configuration: configuration, face: Face(squash: squash), haptic: haptic)
    }

    private struct Face: ButtonStyle {
        var squash: CGSize
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.doughPress(configuration.isPressed, squash: squash)
        }
    }
}

private struct BlockedTap: ViewModifier {
    var off: Bool
    var reason: String?
    @State private var taps = 0
    @State private var showing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .disabled(off)
            .overlay {
                if off { Color.clear.contentShape(Rectangle()).onTapGesture { taps += 1 } }
            }
            .shake(reduceMotion ? 0 : taps)
            .overlay(alignment: .bottom) {
                if showing, let reason {
                    Text(reason).font(Brand.font(.callout, size: 13)).foregroundStyle(Brand.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .alignmentGuide(.bottom) { $0[.top] - 6 }
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: ButtonMotion.reasonOffset)))
                        .allowsHitTesting(false)
                }
            }
            .sensoryFeedback(Haptic.blocked, trigger: taps)
            .task(id: taps) {
                guard taps > 0, reason != nil else { return }
                withAnimation(reduceMotion ? Motion.Reduced.fade : Motion.settle) { showing = true }
                do { try await Task.sleep(for: .seconds(ButtonMotion.reasonHold)) } catch { return }
                withAnimation(reduceMotion ? Motion.Reduced.fade : Motion.fadeOut) { showing = false }
            }
    }
}

// MARK: Small motions

extension View {
    /// The disabled-tap shake on offset x (`Motion.shake`), each time `trigger` changes.
    func shake(_ trigger: Int) -> some View {
        keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { v, x in v.offset(x: x) } keyframes: { _ in
            let s = Motion.shake
            KeyframeTrack {
                LinearKeyframe(s[0].x, duration: s[0].at)
                LinearKeyframe(s[1].x, duration: s[1].at - s[0].at)
                LinearKeyframe(s[2].x, duration: s[2].at - s[1].at)
                LinearKeyframe(s[3].x, duration: s[3].at - s[2].at)
                LinearKeyframe(s[4].x, duration: s[4].at - s[3].at)
            }
        }
    }

    /// Jumps to `from` after `delay` and springs back to 1, each time `trigger` changes (the bumps: 1.2, 1.08, 1.06,
    /// 1.05; the timeline's new step from 0.6). Callers pass a constant trigger under Reduce Motion. The in-app banner
    /// bumps from its top centre (`anchor`).
    func kick(_ trigger: Int, from: CGFloat, delay: Double = 0, spring: Spring = Motion.Keyframe.bump, anchor: UnitPoint = .center) -> some View {
        keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { v, s in v.scaleEffect(s, anchor: anchor) } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(1, duration: delay)
                MoveKeyframe(from)
                SpringKeyframe(1, spring: spring)
            }
        }
    }

    /// The stepper buttons' tap: scale 1 → 0.8 (`Motion.dip`), then `Motion.bounce` back.
    func dip(_ trigger: Int) -> some View {
        keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { v, s in v.scaleEffect(s) } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(StepperMotion.dipScale, duration: Motion.Keyframe.dip)
                SpringKeyframe(1, spring: Motion.Keyframe.bounce)
            }
        }
    }
}

/// New icons pop in from scale 0 at −12° (the add and copy checks, the trash); the old one shrinks away.
struct PopIn: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase.isIdentity ? 1 : 0.01)
            .rotationEffect(phase == .willAppear ? StepperMotion.iconTilt : .zero)
    }
}

/// Labels roll: the new one comes up from `distance` below, the old one leaves upwards.
struct Roll: Transition {
    var distance: CGFloat = StatusMotion.labelOffset
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .offset(y: phase == .willAppear ? distance : phase == .didDisappear ? -distance : 0)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

extension AnyTransition {
    /// `Roll`, or a crossfade under Reduce Motion.
    static func roll(_ reduceMotion: Bool) -> AnyTransition { reduceMotion ? .opacity : AnyTransition(Roll()) }
}

/// An SF Symbol that pops when it changes: the new symbol from scale 0 at −12° on `animation` (Motion.pop by
/// default), the old one shrinking. Reduce Motion crossfades. Font and colour come from the caller. The animation
/// rides on the transition only, so the symbol still moves with its row.
struct PopSymbol: View {
    var name: String
    var animation: Animation = Motion.pop
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Image(systemName: name).id(name)
                .transition(reduceMotion ? AnyTransition.opacity.animation(Motion.Reduced.fade) : AnyTransition(PopIn()).animation(animation))
        }
    }
}

/// An amount that counts from the old value to the new one on `Motion.glide`, shown to the nearest Rp 500 while it
/// moves. Reduce Motion crossfades to the new value. Its frame follows its parent's animation (`geometryGroup`), so
/// only the digits are on `glide`.
struct CountUp<Shown: View>: View {
    var amount: Int
    /// Seconds before the count starts (the bill's total waits 0.24 s for the lines above it).
    var delay: Double = 0
    @ViewBuilder var content: (Int) -> Shown
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                content(amount).contentTransition(.opacity).animation(Motion.Reduced.fade.delay(delay), value: amount)
            } else {
                Counting(value: Double(amount), target: amount, content: content).animation(Motion.glide.delay(delay), value: amount)
            }
        }
        .geometryGroup()
    }

    private struct Counting: View, Animatable {
        var value: Double
        var target: Int
        var content: (Int) -> Shown
        var animatableData: Double {
            get { value }
            set { value = newValue }
        }
        var body: some View {
            let step = Double(BasketMotion.roundTo)
            content(abs(value - Double(target)) < 1 ? target : Int((value / step).rounded() * step))
        }
    }
}

/// Children stacked in one spot, the layout sized by the `active` one (the Rp 200k card's two messages crossfade
/// in place).
struct OneSpot: Layout {
    var active: Int
    /// The active child's height across the full width offered, so the others wrap the same way.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.indices.contains(active) else { return .zero }
        let size = subviews[active].sizeThatFits(proposal)
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for s in subviews { s.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil)) }
    }
}

/// Roundo 700 at a size that animates (the Rp 200k total, 38 → 30 when the discount unlocks).
struct RoundoSize: ViewModifier, Animatable {
    var size: CGFloat
    var animatableData: CGFloat {
        get { size }
        set { size = newValue }
    }
    func body(content: Content) -> some View {
        content.font(Font(Brand.uiFont(.roundo, size: size, weight: 700)))
    }
}

// MARK: Async buttons

/// A large pill whose action waits on the server (Lock order, Lock again, Send to Atas, Mark paid, Confirm
/// delivered). No spinner: while it waits, a cream fill creeps across the face to 85 % and holds until the reply.
/// Success turns it lime with a check and the done text, and `then` runs 0.8 s later (the next state takes over).
/// Failure keeps its colours, shakes, says "Try again", and shows why in a line above it, inside the bar.
/// The request is never cancelled: these are writes, and the server may finish them anyway. With no reply after 10 s
/// the pill `refresh`es and asks `reached` whether the order is already where the button takes it; if so that is the
/// success, if not it shows the failure while the request carries on. A late reply then settles it (success, or
/// the real reason), and Try again waits on that same request instead of sending a second one.
/// `holding` is true from the tap until the hand-off, so the screen can keep showing the state the button acts on.
struct AsyncPill<Idle: View>: View {
    var busyTitle: String
    var doneTitle: String
    var failTitle: String
    var kind: PillKind = .primary
    /// 12 pt side padding instead of 32, for a pill that shares its row.
    var tight = false
    var holding: Binding<Bool>? = nil
    /// Reloads what `reached` reads.
    var refresh: () async -> Void
    /// The order is already in the state the action aims for (checked after `refresh`).
    var reached: () -> Bool
    var action: () async throws -> Void
    var then: () -> Void
    /// The label at rest, e.g. lock + "Lock order".
    @ViewBuilder var idle: Idle

    private enum Phase { case idle, busy, done, failed }
    private enum Reply { case answer(String?), timeout }
    @State private var phase = Phase.idle
    @State private var fill: CGFloat = 0
    @State private var fillOpacity = 1.0
    @State private var checked = false
    @State private var error: String?
    @State private var successes = 0
    @State private var failures = 0
    /// The request still in flight after a timeout; Try again waits on it rather than sending another.
    @State private var pending: Task<String?, Never>?
    /// Bumped by each tap, so a late reply only settles the attempt that is still showing.
    @State private var attempt = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The error line is part of the layout, so the bar it sits in grows to hold it (as for the offline line).
        VStack(spacing: 8) {
            if let error {
                Label { Text(error) } icon: { Image(systemName: "exclamationmark.circle") }
                    .labelStyle(IconLabel(spacing: 6, size: 15))
                    .font(Brand.font(.callout, size: 13))
                    .foregroundStyle(Brand.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: ButtonMotion.reasonOffset)))
            }
            Button { run() } label: {
                ZStack { label.id(phase).transition(labelTransition) }
            }
            .buttonStyle(PillStyle(kind: phase == .done ? .success : kind, size: .large, tight: tight, loading: (fill, fillOpacity)))
            .allowsHitTesting(phase == .idle || phase == .failed)
            .shake(reduceMotion ? 0 : failures)
            .kick(reduceMotion ? 0 : successes, from: AsyncMotion.successBump, delay: AsyncMotion.successDelay)
        }
        .sensoryFeedback(Haptic.done, trigger: successes)
        .sensoryFeedback(Haptic.fail, trigger: failures)
    }

    @ViewBuilder private var label: some View {
        switch phase {
        case .idle:
            idle
        case .busy:
            Text(busyTitle)
        case .done:
            Label {
                Text(doneTitle)
            } icon: {
                Image(systemName: "checkmark").font(.system(size: 18, weight: .heavy))
                    .scaleEffect(checked || reduceMotion ? 1 : 0.01)
                    .rotationEffect(checked || reduceMotion ? .zero : StepperMotion.iconTilt)
            }
        case .failed:
            Label("Try again", systemImage: "arrow.clockwise")
        }
    }

    /// The old label leaves upwards on `Motion.quick`, the new one comes up on `Motion.settle`.
    private var labelTransition: AnyTransition {
        reduceMotion ? AnyTransition.opacity.animation(Motion.Reduced.fade)
            : .asymmetric(insertion: AnyTransition(Roll()).animation(Motion.settle), removal: AnyTransition(Roll()).animation(Motion.quick))
    }

    private func run() {
        guard phase == .idle || phase == .failed else { return }
        attempt += 1
        let mine = attempt
        holding?.wrappedValue = true
        withAnimation(Motion.fadeOut) { error = nil }
        withAnimation(reduceMotion ? Motion.Reduced.fade : Motion.quick) { phase = .busy }
        withAnimation(Motion.creep) { fill = AsyncMotion.creepTo }
        let work = pending ?? Task { () -> String? in
            do {
                try await action()
                return nil
            } catch {
                return "\(failTitle). \(readable(error))"
            }
        }
        pending = work
        Task {
            let (replies, reply) = AsyncStream.makeStream(of: Reply.self)
            Task {
                reply.yield(.answer(await work.value))
                reply.finish()
            }
            Task {
                try? await Task.sleep(for: .seconds(AsyncMotion.timeout))
                reply.yield(.timeout)
            }
            var first = replies.makeAsyncIterator()
            if case .answer(let message)? = await first.next() {
                pending = nil
                if let message { fail(message) } else { await succeed() }
                return
            }
            // No reply yet. The write may have landed anyway.
            await refresh()
            guard mine == attempt else { return }
            if reached() {
                pending = nil
                await succeed()
                return
            }
            fail("\(failTitle). No answer from the server yet.")
            let late = await work.value
            // A Try again tap since then waits on this same request and settles it itself.
            guard mine == attempt, phase == .failed else { return }
            pending = nil
            if let late {
                withAnimation(reduceMotion ? Motion.Reduced.fade : Motion.settle) { error = late }
            } else {
                withAnimation(Motion.fadeOut) { error = nil }
                await succeed()
            }
        }
    }

    private func fail(_ message: String) {
        failures += 1
        holding?.wrappedValue = false
        withAnimation(reduceMotion ? Motion.Reduced.fade : Motion.leave) { fill = 0 }
        withAnimation(reduceMotion ? Motion.Reduced.fade : Motion.settle) {
            phase = .failed
            error = message
        }
    }

    private func succeed() async {
        successes += 1
        withAnimation(reduceMotion ? Motion.Reduced.fill : Motion.doughLead) { fill = 1 }
        try? await Task.sleep(for: .seconds(AsyncMotion.successDelay))
        withAnimation(reduceMotion ? Motion.Reduced.fade : Motion.fade) {
            fillOpacity = 0
            phase = .done
        }
        withAnimation(Motion.pop.delay(AsyncMotion.checkDelay - AsyncMotion.successDelay)) { checked = true }
        try? await Task.sleep(for: .seconds(AsyncMotion.handOff - AsyncMotion.successDelay))
        then()
        holding?.wrappedValue = false
        // Ready for the next use, if the button is still there.
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            phase = .idle
            fill = 0
            fillOpacity = 1
            checked = false
        }
    }
}

extension AsyncPill where Idle == Label<Text, Image> {
    init(title: String, icon: String, busyTitle: String, doneTitle: String, failTitle: String, kind: PillKind = .primary,
         tight: Bool = false, holding: Binding<Bool>? = nil, refresh: @escaping () async -> Void, reached: @escaping () -> Bool,
         action: @escaping () async throws -> Void, then: @escaping () -> Void = {}) {
        self.init(busyTitle: busyTitle, doneTitle: doneTitle, failTitle: failTitle, kind: kind, tight: tight, holding: holding,
                  refresh: refresh, reached: reached, action: action, then: then) { Label(title, systemImage: icon) }
    }
}

// MARK: Item rows

extension View {
    /// A list whose rows come and go (My items, My order): an added row opens on `Motion.settle`, a removed one closes
    /// on `Motion.leave`. Rows carry `.transition(.itemRow)`. Reduce Motion: heights snap, contents fade.
    func rowMotion<ID: Hashable>(_ ids: [ID]) -> some View { modifier(RowMotion(ids: ids)) }
}

private struct RowMotion<ID: Hashable>: ViewModifier {
    var ids: [ID]
    @State private var count: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // `count` is still the old length while the new ids render.
        let opening = ids.count >= (count ?? ids.count)
        content
            .animation(reduceMotion ? nil : opening ? Motion.settle : Motion.leave, value: ids)
            .onChange(of: ids, initial: true) { count = ids.count }
    }
}

extension AnyTransition {
    /// A row's contents: in with `Motion.fade` after 0.06 s, out with `Motion.fadeOut`.
    static var itemRow: AnyTransition {
        .asymmetric(insertion: .opacity.animation(Motion.fade.delay(0.06)), removal: .opacity.animation(Motion.fadeOut))
    }
}
