import SwiftUI

// Sheets and confirms (Motion board 07): the remove and leave confirms, Request an edit and Propose a split.
// They rise from below on `Motion.arrive`; the overshoot stretches the sheet instead of lifting it. A drag follows
// the finger, an upward drag rubber-bands, and a release past 30 % of the height or faster than 800 pt/s downward
// dismisses on `Motion.leave` from the finger's speed. Reduce Motion fades them in and out. System alerts stay
// system alerts.

extension View {
    /// Presents `content` in the Ataste bottom sheet while `item` is set. `title` makes it a full sheet (62 pt from
    /// the top, a Cancel and title row); without it the sheet is a confirm sized to its content. `insets` replaces the
    /// sheet's padding (the share sheet's 10 / 18 / 24). The content closes it with `@Environment(\.closeSheet)`;
    /// setting `item` to nil closes it too, with the same motion.
    func doughSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>, title: String? = nil, insets: EdgeInsets? = nil,
                                                     @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        modifier(DoughSheetHost(item: item, title: title, insets: insets, sheet: content))
    }

    /// A full Ataste sheet whose title follows the item it shows ("Ask Dimas to share"). The title is read from the
    /// item on show, so it stays put while the sheet leaves.
    func doughSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>, titled: @escaping (Item) -> String,
                                                     @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        modifier(DoughSheetHost(item: item, title: nil, titled: titled, insets: nil, sheet: content))
    }
}

/// Closes the sheet the view sits in, with the sheet's leave motion.
struct CloseSheet {
    let run: () -> Void
    func callAsFunction() { run() }
}

extension EnvironmentValues {
    @Entry var closeSheet: CloseSheet? = nil
}

/// Changes that must not animate: the cover that hosts the sheet appears and goes without the system's slide.
private func still(_ change: () -> Void) {
    var t = Transaction()
    t.disablesAnimations = true
    withTransaction(t, change)
}

private struct DoughSheetHost<Item: Identifiable, Sheet: View>: ViewModifier {
    @Binding var item: Item?
    var title: String?
    var titled: ((Item) -> String)? = nil
    var insets: EdgeInsets?
    var sheet: (Item) -> Sheet
    /// What the cover shows; it outlives `item` while the sheet leaves.
    @State private var shown: Item?
    @State private var leaving = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $shown) { i in
                SheetFrame(title: titled?(i) ?? title, insets: insets, leaving: leaving, gone: finish) { sheet(i) }
                    .presentationBackground(.clear)
            }
            .onChange(of: item?.id, initial: true) { _, id in
                if let id, id != shown?.id {
                    leaving = false
                    still { shown = item }
                } else if id == nil, shown != nil {
                    leaving = true
                }
            }
    }

    private func finish() {
        still { shown = nil }
        leaving = false
        if item != nil { item = nil }
    }
}

private struct SheetFrame<Content: View>: View {
    var title: String?
    var insets: EdgeInsets?
    var leaving: Bool
    var gone: () -> Void
    @ViewBuilder var content: Content
    /// Down from the resting place; below zero the sheet stretches instead (only its bottom padding grows).
    @State private var offset: CGFloat = 10_000
    @State private var height: CGFloat = 0
    @State private var opacity = 1.0
    @State private var closing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let fullHeight = g.size.height - 62 - 8
            SheetStage(offset: offset, height: height, fullHeight: title == nil ? nil : fullHeight, insets: insets,
                       scrimTap: { dismiss(velocity: 0) }, drag: drag) {
                VStack(spacing: 0) {
                    if let title { header(title) }
                    content
                }
                .environment(\.closeSheet, CloseSheet { dismiss(velocity: 0) })
            } measured: { h in
                let first = height == 0
                height = title == nil ? h : fullHeight
                if first { present() }
            }
            .opacity(opacity)
        }
        .ignoresSafeArea(.container)
        .onChange(of: leaving) { _, l in if l { dismiss(velocity: 0) } }
    }

    /// Cancel and the title, over the grabber; the drag area of a full sheet.
    private func header(_ title: String) -> some View {
        ZStack {
            Text(title).font(GFont.manrope(17, 700)).foregroundStyle(Brand.cocoa).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button("Cancel") { dismiss(velocity: 0) }
                    .font(GFont.manrope(16, 600)).foregroundStyle(Brand.caramel)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .gesture(drag)
    }

    private func present() {
        if reduceMotion {
            still { offset = 0; opacity = 0 }
            withAnimation(Motion.Reduced.fade) { opacity = 1 }
            return
        }
        still { offset = height + SheetMotion.offscreenExtra }
        DispatchQueue.main.async { withAnimation(SheetMotion.present) { offset = 0 } }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { v in
                guard !closing else { return }
                let t = v.translation.height
                still { offset = t >= 0 ? t : -Motion.rubberBand(-t, limit: max(1, height)) }
            }
            .onEnded { v in
                guard !closing else { return }
                let vy = v.velocity.height
                if offset > height * SheetMotion.dismissFraction || vy > SheetMotion.dismissVelocity {
                    dismiss(velocity: vy)
                } else {
                    withAnimation(reduceMotion ? SheetMotion.dismiss : Motion.flung(Motion.Keyframe.arrive, velocity: vy, distance: -offset)) { offset = 0 }
                }
            }
    }

    private func dismiss(velocity: CGFloat) {
        guard !closing else { return }
        closing = true
        if reduceMotion {
            withAnimation(Motion.Reduced.fade, completionCriteria: .logicallyComplete) { opacity = 0 } completion: { gone() }
            return
        }
        let target = height + SheetMotion.offscreenExtra
        withAnimation(Motion.flung(Motion.Keyframe.leave, velocity: velocity, distance: target - offset), completionCriteria: .logicallyComplete) {
            offset = target
        } completion: { gone() }
    }
}

/// The scrim and the sheet at one offset, so the scrim's opacity (1 − offset / height) and the stretch follow the
/// sheet frame by frame.
private struct SheetStage<Content: View, Drag: Gesture>: View, Animatable {
    var offset: CGFloat
    var height: CGFloat
    /// A full sheet's resting height; nil for a confirm, which takes its content's height.
    var fullHeight: CGFloat?
    var insets: EdgeInsets?
    var scrimTap: () -> Void
    var drag: Drag
    @ViewBuilder var content: Content
    var measured: (CGFloat) -> Void

    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }

    var body: some View {
        let lift = max(0, offset)
        let stretch = max(0, -offset)
        let progress = height > 0 ? max(0, min(1, 1 - lift / height)) : 0
        let full = fullHeight != nil
        let shape = RoundedRectangle(cornerRadius: 40, style: .continuous)
        ZStack(alignment: .bottom) {
            Brand.cocoa.opacity(SheetMotion.scrimOpacity * progress)
                .contentShape(Rectangle())
                .onTapGesture(perform: scrimTap)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Close")
            VStack(spacing: 0) {
                // The grabber, 14 pt above the content (3-6).
                RoundedRectangle(cornerRadius: 3).fill(Brand.liquorice400).frame(width: 36, height: 5)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(drag)
                    .accessibilityHidden(true)
                content
                    .frame(maxHeight: full ? .infinity : nil, alignment: .top)
            }
            .padding(insets ?? EdgeInsets(top: 10, leading: full ? 18 : 20, bottom: full ? 26 : 36, trailing: full ? 18 : 20))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if stretch == 0 { measured($0) } }
            .frame(height: fullHeight)
            // The stretch: the content stays pinned to the top and only the bottom padding grows.
            .padding(.bottom, stretch)
            .background { shape.fill(Color.clear).glassEffect(.regular.tint(Brand.cream.opacity(0.62)), in: shape) }
            .contentShape(shape)
            .modifier(SheetDrag(on: !full, drag: drag))
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .offset(y: lift)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// A confirm drags from anywhere on it; a full sheet only from its grabber and header (its content scrolls).
private struct SheetDrag<Drag: Gesture>: ViewModifier {
    var on: Bool
    var drag: Drag
    func body(content: Content) -> some View {
        if on { content.gesture(drag) } else { content }
    }
}

// MARK: Confirm

/// The remove-item and leave-group questions (built like 3-6 Leave group): Roundo title, the why, then Keep and the
/// red action as two half-width pills. Keep gives a light tap and closes; the action gives a medium tap, closes, and
/// runs `act` after `delay` (the removed row collapses 0.12 s into the sheet's exit).
struct ConfirmSheet: View {
    var confirm: Confirm
    var delay: Double = 0
    var act: () -> Void
    @Environment(\.closeSheet) private var close

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(confirm.title).font(Font(Brand.uiFont(.roundo, size: 24, weight: 700))).foregroundStyle(Brand.cocoa)
                .fixedSize(horizontal: false, vertical: true)
            Text(confirm.message).font(GFont.manrope(15, 500)).lineSpacing(2).foregroundStyle(Brand.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            HStack(spacing: 10) {
                Button(confirm.keep) { close?() }.buttonStyle(ConfirmPillStyle(destructive: false))
                Button(confirm.button) {
                    close?()
                    Task {
                        try? await Task.sleep(for: .seconds(delay))
                        act()
                    }
                }
                .buttonStyle(ConfirmPillStyle(destructive: true))
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Keep (Cream, #EDE2E4 ring) and the red action: half-width pills, 13 pt vertical padding inside a 4 pt ring,
/// compact squash.
private struct ConfirmPillStyle: PrimitiveButtonStyle {
    var destructive: Bool
    func makeBody(configuration: Configuration) -> some View {
        CommitButton(configuration: configuration, face: Face(destructive: destructive), haptic: destructive ? Haptic.heavy : Haptic.tap)
    }

    private struct Face: ButtonStyle {
        var destructive: Bool
        func makeBody(configuration: Configuration) -> some View {
            let p = configuration.isPressed
            let fill = destructive ? (p ? Brand.destructivePressed : Brand.destructive) : (p ? Brand.creamPressed : Brand.cream)
            let border = destructive ? fill : Brand.liquorice100
            configuration.label
                .font(GFont.manrope(16, 600))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(destructive ? Color.white : Brand.cocoa)
                .padding(.horizontal, 12)
                .padding(.vertical, 13 + 4)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(fill).pressTone(p))
                .overlay(Capsule().strokeBorder(border, lineWidth: 4).pressTone(p))
                .contentShape(Capsule())
                .doughPress(p, squash: Motion.pressCompact)
        }
    }
}
