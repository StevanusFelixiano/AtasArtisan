import SwiftUI
import UIKit

// A group card on Home opening into the group (Motion board 09). The card's frame becomes the screen: its top,
// leading and trailing edges on Motion.doughLead and its bottom edge on Motion.doughTrail, so it stretches down,
// while its corners go from 32 pt to the display's and its fill turns cream. The card's content stays pinned at its
// size and fades out; the group screen is laid out full size from the start and the growing frame reveals it.
//
// NavigationStack has no custom push, so the opening is an overlay over a push without animation: a still of Home
// shows outside the growing frame until it fills the screen. Going back is the system zoom into the same card
// (`matchedTransitionSource` + `.zoom`), which is also what the interactive edge swipe follows. Groups opened any
// other way (a notification, a new group, ATASTE_OPEN) push as usual.

/// One opening in flight: the card's frame on screen, its fill, a still of Home and of the card.
struct CardOpening {
    var id: UUID
    var frame: CGRect
    var fill: Color
    var home: UIImage
    var card: UIImage?
}

/// Takes the still of a navigation stack's screen (without the tab bar, which is not in it).
final class ScreenStill {
    fileprivate weak var view: UIView?

    func capture() -> UIImage? {
        var r: UIResponder? = view
        while let next = r, !(next is UINavigationController) { r = next.next }
        guard let nav = (r as? UINavigationController)?.view, nav.bounds.width > 0 else { return nil }
        return UIGraphicsImageRenderer(bounds: nav.bounds).image { _ in nav.drawHierarchy(in: nav.bounds, afterScreenUpdates: false) }
    }

    /// The part of `image` under `rect` (points).
    static func crop(_ image: UIImage, to rect: CGRect) -> UIImage? {
        let s = image.scale
        guard let cg = image.cgImage?.cropping(to: CGRect(x: rect.minX * s, y: rect.minY * s, width: rect.width * s, height: rect.height * s)) else { return nil }
        return UIImage(cgImage: cg, scale: s, orientation: .up)
    }
}

/// Puts `still` on a view inside the navigation stack whose screen it captures.
struct ScreenStillProbe: UIViewRepresentable {
    var still: ScreenStill
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        still.view = v
        return v
    }
    func updateUIView(_ view: UIView, context: Context) { still.view = view }
}

/// A group screen opened from its card goes back into it with the system zoom.
struct ZoomBack: ViewModifier {
    var id: UUID
    var active: Bool
    var space: Namespace.ID
    func body(content: Content) -> some View {
        if active { content.navigationTransition(.zoom(sourceID: id, in: space)) } else { content }
    }
}

/// A value animated on its own, handed to `content` frame by frame.
private struct Progress<Content: View>: View, Animatable {
    var value: CGFloat
    @ViewBuilder var content: (CGFloat) -> Content
    var animatableData: CGFloat {
        get { value }
        set { value = newValue }
    }
    var body: some View { content(value) }
}

/// The opening, over the pushed group screen.
struct CardOpenOverlay: View {
    var opening: CardOpening
    var done: () -> Void
    /// Top, leading and trailing edges at the screen's.
    @State private var sides = false
    /// Bottom edge at the screen's.
    @State private var bottom = false
    @State private var cream = false
    @State private var cardOut = false
    @State private var screenIn = false
    @State private var springsAtRest = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let size = g.size
            let f = opening.frame
            ZStack(alignment: .topLeading) {
                // Home, outside the frame.
                Image(uiImage: opening.home).resizable().frame(width: size.width, height: size.height)
                    .mask {
                        // Reduce Motion has no frame: the whole still crossfades out.
                        Rectangle().overlay { if !reduceMotion { frame(size).blendMode(.destinationOut) } }.compositingGroup()
                    }
                    .opacity(reduceMotion && screenIn ? 0 : 1)
                if !reduceMotion {
                    // Inside it: the card's fill turning cream, fading as the group screen comes in under it.
                    frame(size).foregroundStyle(cream ? Brand.cream : opening.fill)
                        .opacity(screenIn ? 0 : 1)
                    // The card's content, pinned top-left at its own size, fading out.
                    if let card = opening.card {
                        Color.clear.frame(width: size.width, height: size.height)
                            .overlay(alignment: .topLeading) {
                                Image(uiImage: card).resizable().frame(width: f.width, height: f.height)
                                    .offset(x: f.minX, y: f.minY)
                            }
                            .opacity(cardOut ? 0 : 1)
                            .mask { frame(size) }
                    }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onAppear(perform: play)
        .accessibilityHidden(true)
    }

    /// The growing frame. Its corners are concentric with the display: 32 pt while the card is far from the screen's
    /// edges, the display's own radius once it fills the screen.
    private func frame(_ size: CGSize) -> some View {
        let f = opening.frame
        // The two springs each drive their own value, so the bottom edge can trail the other three.
        return Progress(value: sides ? 1 : 0) { s in Progress(value: bottom ? 1 : 0) { b in
            ConcentricRectangle(corners: .concentric(minimum: .fixed(CardMotion.cornerRadius)), isUniform: false)
                .padding(.leading, f.minX * (1 - s))
                .padding(.top, f.minY * (1 - s))
                .padding(.trailing, max(0, size.width - f.maxX) * (1 - s))
                .padding(.bottom, max(0, size.height - f.maxY) * (1 - b))
        } }
    }

    private func landed() {
        springsAtRest += 1
        if springsAtRest == 2 { done() }
    }

    private func play() {
        if reduceMotion {
            // The screen crossfades in at full size.
            withAnimation(Motion.Reduced.fade, completionCriteria: .logicallyComplete) { screenIn = true } completion: { done() }
            return
        }
        // The frame lands when both springs have come to rest; then the overlay goes.
        withAnimation(CardMotion.edges, completionCriteria: .removed) { sides = true } completion: { landed() }
        withAnimation(CardMotion.bottomEdge, completionCriteria: .removed) { bottom = true } completion: { landed() }
        withAnimation(Motion.fade.delay(CardMotion.colourDelay)) { cream = true }
        withAnimation(Motion.fadeOut) { cardOut = true }
        withAnimation(Motion.fade.delay(CardMotion.contentDelay)) { screenIn = true }
    }
}
