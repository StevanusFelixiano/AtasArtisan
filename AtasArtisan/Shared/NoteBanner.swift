import SwiftUI
import UIKit

// In-app notifications (Motion board 08). A push that arrives while Ataste is open shows as the Ataste banner
// instead of the system one, unless it is about the group on screen: that screen's own change plays instead. The
// banner drops in from above on `Motion.arrive` (the overshoot stretches it downwards), holds 4 s (paused while a
// finger is on it), and leaves upwards. A newer event rolls its text in and bumps it; banners never stack. A swipe
// up sends it away, a pull down rubber-bands it, a tap opens the group. Reduce Motion fades it in and out.

/// An order event that arrived while the app was open (a push in the foreground: `kind` and `group` from the push
/// payload, title and body from its alert).
struct InAppNote: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var body: String
    var kind: String
    var group: UUID?

    /// The event's haptic: an edit request warns, a final bill or a confirmed payment succeeds, someone joining
    /// (the host's event) taps; reminders and the rest are silent.
    var haptic: SensoryFeedback? {
        switch kind {
        case "edit_requested": Haptic.warn
        case "bill_final", "payment_confirmed": Haptic.done
        case "joined": Haptic.tap
        default: nil
        }
    }
}

extension View {
    /// Marks the group screen on show, so an event about it plays on the screen rather than as a banner.
    func marksScreen(group: UUID) -> some View { modifier(ScreenMark(id: group)) }
}

extension EnvironmentValues {
    /// The tab this view sits in is the one on show (all three tab stacks stay alive behind the tab bar).
    @Entry var pageShown = true
}

private struct ScreenMark: ViewModifier {
    var id: UUID
    @Environment(\.pageShown) private var pageShown
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .onAppear { appeared = true; mark() }
            .onDisappear { appeared = false; mark() }
            .onChange(of: pageShown) { mark() }
    }

    private func mark() {
        let app = AppModel.shared
        if appeared && pageShown { app.screenGroup = id } else if app.screenGroup == id { app.screenGroup = nil }
    }
}

// MARK: Window

/// The banner's own window over the app's, so it shows above sheets and covers too. Touches outside the banner
/// fall through to the app.
final class BannerWindow: UIWindow {
    static var current: BannerWindow?
    /// The banner's frame; empty while there is none.
    var hitRect: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        hitRect.contains(point) ? super.hitTest(point, with: event) : nil
    }
}

/// Puts the banner window on the scene once, from the root view.
struct BannerWindowInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { let p = Probe(); p.isUserInteractionEnabled = false; return p }
    func updateUIView(_ view: UIView, context: Context) {}

    final class Probe: UIView {
        override func didMoveToWindow() {
            guard BannerWindow.current == nil, let scene = window?.windowScene else { return }
            let w = BannerWindow(windowScene: scene)
            let host = UIHostingController(rootView: NoteBanner().environment(AppModel.shared))
            host.view.backgroundColor = .clear
            w.rootViewController = host
            w.windowLevel = .normal + 1
            w.backgroundColor = .clear
            w.isHidden = false
            BannerWindow.current = w
        }
    }
}

// MARK: Banner

struct NoteBanner: View {
    @Environment(AppModel.self) private var app
    @State private var shown: InAppNote?
    /// Below 0 the banner is up out of view; above 0 it stretches (its bottom padding grows).
    @State private var y: CGFloat = -1000
    @State private var height: CGFloat = 0
    @State private var opacity = 1.0
    @State private var pressed = false
    @State private var touching = false
    @State private var dragging = false
    @State private var leaving = false
    @State private var bumps = 0
    /// The leave in flight; a new event during it cancels it.
    @State private var leaveToken: UUID?
    /// Seconds of the 4 s hold still to run; a finger on the banner pauses it.
    @State private var holdLeft = BannerMotion.hold
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if let shown {
                BannerStage(y: y) { stretch in card(shown, stretch: stretch) }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { BannerWindow.current?.hitRect = $0 }
                    .opacity(opacity)
                    .padding(.top, 54)
                    .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .onChange(of: app.note) { _, note in if let note { arrive(note) } }
        .sensoryFeedback(trigger: app.note?.id) { _, _ in app.note?.haptic }
        .task(id: "\(shown?.id.uuidString ?? "")|\(touching)|\(leaving)") { await holdThenLeave() }
    }

    private func card(_ note: InAppNote, stretch: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return HStack(alignment: .top, spacing: 10) {
            // The app icon as N-3 draws it: the giraffe's head over a cream band, on caramel.
            ZStack(alignment: .topLeading) {
                Brand.caramel
                Image("icon-head").resizable().scaledToFill().frame(width: 26, height: 26).offset(x: 6, y: 3)
                RoundedRectangle(cornerRadius: 5).fill(Brand.cream).frame(width: 28, height: 7)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Brand.cocoa).offset(y: 1.5))
                    .offset(x: 5, y: 27)
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            // A newer event rolls in over the old one.
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(note.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text("now").font(.system(size: 13)).foregroundStyle(Brand.bannerMeta)
                    }
                    Text(note.body).font(.system(size: 15)).lineLimit(3)
                }
                .lineSpacing(1.5)
                .foregroundStyle(Brand.cocoa)
                .id(note.id)
                .transition(AnyTransition.roll(reduceMotion).animation(reduceMotion ? Motion.Reduced.fade : Motion.digits))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
            let first = height == 0
            height = h
            if first { present() }
        }
        .padding(.bottom, stretch)
        // Cream at 82 % over a blur, a 1 pt light edge at the top, and a soft cocoa shadow (N-3).
        .background { shape.fill(Brand.cream.opacity(0.82)).background(.ultraThinMaterial, in: shape) }
        .overlay {
            shape.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.9), location: 0), .init(color: .white.opacity(0), location: 0.06)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .shadow(color: Brand.cocoa.opacity(0.22), radius: 15, y: 12)
        .contentShape(shape)
        // Presses and bumps scale from the top centre.
        .scaleEffect(pressed && !reduceMotion ? Motion.pressCard : CGSize(width: 1, height: 1), anchor: .top)
        .opacity(pressed && reduceMotion ? Motion.Reduced.pressDim : 1)
        .animation(reduceMotion ? (pressed ? Motion.Reduced.press : Motion.Reduced.release) : (pressed ? Motion.press : Motion.release), value: pressed)
        .kick(reduceMotion ? 0 : bumps, from: BannerMotion.repeatBump, anchor: .top)
        .gesture(touch)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
    }

    private var touch: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                guard !leaving else { return }
                if !touching { touching = true; pressed = true }
                let t = v.translation
                if !dragging, hypot(t.width, t.height) > BannerMotion.tapSlop { dragging = true; pressed = false }
                guard dragging else { return }
                still { y = t.height < 0 ? t.height : Motion.rubberBand(t.height, limit: BannerMotion.stretchLimit) }
            }
            .onEnded { v in
                guard !leaving else { return }
                touching = false
                pressed = false
                guard dragging else { return open() }
                dragging = false
                let vy = v.velocity.height
                if v.translation.height < -BannerMotion.dismissDistance || vy < -BannerMotion.dismissVelocity {
                    leave(velocity: vy)
                } else {
                    withAnimation(reduceMotion ? Motion.leave : Motion.flung(Motion.Keyframe.arrive, velocity: vy, distance: -y)) { y = 0 }
                }
            }
    }

    private var hidden: CGFloat { -(height + BannerMotion.hiddenExtra) }

    private func arrive(_ note: InAppNote) {
        holdLeft = BannerMotion.hold
        AccessibilityNotification.Announcement("\(note.title). \(note.body)").post()
        if shown != nil, !leaving {
            // Never stacks: the text rolls to the new event and the banner bumps.
            shown = note
            if !reduceMotion { bumps += 1 }
            return
        }
        leaving = false
        leaveToken = nil
        if shown == nil { height = 0 }
        shown = note
        if height > 0 { present() }
    }

    private func present() {
        if reduceMotion {
            still { y = 0; opacity = 0 }
            withAnimation(Motion.Reduced.fade) { opacity = 1 }
            return
        }
        if y < hidden || y == -1000 { still { y = hidden } }
        DispatchQueue.main.async { withAnimation(Motion.arrive) { y = 0 } }
    }

    private func holdThenLeave() async {
        guard shown != nil, !touching, !leaving else { return }
        let start = Date.now
        do { try await Task.sleep(for: .seconds(holdLeft)) } catch {
            holdLeft = max(0, holdLeft - Date.now.timeIntervalSince(start))
            return
        }
        leave(velocity: 0)
    }

    /// Tap: the banner leaves and its group opens.
    private func open() {
        let group = shown?.group
        leave(velocity: 0)
        if let group { app.openGroup = group }
    }

    private func leave(velocity: CGFloat) {
        guard shown != nil, !leaving else { return }
        leaving = true
        let token = UUID()
        leaveToken = token
        let done = {
            guard leaveToken == token else { return }
            leaveToken = nil
            still {
                shown = nil
                y = -1000
                opacity = 1
                leaving = false
            }
            BannerWindow.current?.hitRect = .zero
            app.note = nil
        }
        if reduceMotion {
            withAnimation(Motion.fadeOut, completionCriteria: .logicallyComplete) { opacity = 0 } completion: { done() }
        } else {
            withAnimation(Motion.flung(Motion.Keyframe.leave, velocity: velocity, distance: hidden - y), completionCriteria: .logicallyComplete) {
                y = hidden
            } completion: { done() }
        }
    }

    private func still(_ change: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, change)
    }
}

/// The banner at one position, frame by frame: up out of view below 0, stretched (taller at the bottom) above 0.
private struct BannerStage<Card: View>: View, Animatable {
    var y: CGFloat
    @ViewBuilder var card: (CGFloat) -> Card

    var animatableData: CGFloat {
        get { y }
        set { y = newValue }
    }

    var body: some View {
        card(max(0, y)).offset(y: min(0, y))
    }
}
