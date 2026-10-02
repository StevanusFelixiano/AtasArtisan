import SwiftUI

// Small pieces the menu, product and split screens share, on top of Shared/Components.swift.

/// Type at the exact sizes the boards use: Roundo 700 for prices and headings, Manrope for the rest.
enum MenuFont {
    static func roundo(_ size: CGFloat) -> Font { Brand.font(.title2, size: size, weight: 700) }
    static func manrope(_ size: CGFloat, _ weight: CGFloat = 500) -> Font { Brand.font(.body, size: size, weight: weight) }
}

/// Capsule stepper: 28 pt choc circles around a Roundo count (product sheet, cart, split rows, group item rows).
/// Each tap dips its button and plays .increase or .decrease; the count rolls up or down. At quantity 1 the minus
/// pops into a red trash (`minusSymbol: "trash"`), whose tap the caller confirms.
struct PillStepper: View {
    var value: String
    var fill: Color = .white
    var gap: CGFloat = 12
    var pad: CGFloat = 4
    var minWidth: CGFloat = 0
    var countSize: CGFloat = 17
    var minusSymbol = "minus"
    var canMinus = true
    var canPlus = true
    var minusLabel = "One less"
    var plusLabel = "One more"
    var minus: () -> Void
    var plus: () -> Void
    /// A tap on a disabled button, for a caller that answers it elsewhere (the split's total line shakes); without
    /// it the button itself shakes.
    var blocked: (() -> Void)? = nil
    @State private var down = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: gap) {
            StepButton(symbol: minusSymbol, enabled: canMinus, label: minusLabel, blocked: blocked) { down = true; minus() }
            Text(value).font(MenuFont.roundo(countSize)).foregroundStyle(Brand.cocoa)
                .lineLimit(1).fixedSize()
                .frame(minWidth: minWidth).monospacedDigit()
                .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: down))
                .animation(reduceMotion ? Motion.Reduced.fade : Motion.digits, value: value)
            StepButton(symbol: "plus", enabled: canPlus, label: plusLabel, blocked: blocked) { down = false; plus() }
        }
        .padding(pad)
        .background(Capsule().fill(fill))
        .accessibilityElement(children: .contain)
    }
}

/// One stepper circle. Plus and minus dip to 0.8 and bounce back on each tap with .increase / .decrease; the trash
/// pops in from 0 at −12° on Trash fill and ink (its tap plays nothing: the remove confirm follows).
private struct StepButton: View {
    var symbol: String
    var enabled: Bool
    var label: String
    var blocked: (() -> Void)?
    var action: () -> Void
    @State private var taps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let trash = symbol == "trash"
        Button {
            taps += 1
            action()
        } label: {
            PopSymbol(name: symbol, animation: Motion.pop.delay(StepperMotion.addCheckDelay))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(trash ? Brand.destructive : Brand.cocoa)
                .dip(reduceMotion || trash ? 0 : taps)
        }
        .buttonStyle(Style(trash: trash))
        .sensoryFeedback(trigger: taps) { _, _ in trash ? nil : symbol == "plus" ? Haptic.up : Haptic.down }
        .modifier(Blocked(enabled: enabled, blocked: blocked))
        .opacity(enabled ? 1 : SplitMotion.unavailableOpacity)
        .accessibilityLabel(label)
    }

    /// A disabled tap: the button shakes (`disabled(_:reason:)`), or `blocked` answers it.
    private struct Blocked: ViewModifier {
        var enabled: Bool
        var blocked: (() -> Void)?
        func body(content: Content) -> some View {
            if let blocked {
                content.disabled(!enabled)
                    .overlay { if !enabled { Color.clear.contentShape(Rectangle().inset(by: -8)).onTapGesture(perform: blocked) } }
            } else {
                content.disabled(!enabled, reason: nil)
            }
        }
    }

    private struct Style: ButtonStyle {
        var trash: Bool
        func makeBody(configuration: Configuration) -> some View {
            let p = configuration.isPressed
            configuration.label
                .frame(width: 28, height: 28)
                .background {
                    Circle().fill(trash ? Brand.trashFill : p ? Brand.choc100Pressed : Brand.choc100)
                        .pressTone(p)
                        .animation(Motion.quick.delay(StepperMotion.addCheckDelay), value: trash)
                }
                .contentShape(Rectangle().inset(by: -8))
                .doughPress(p, squash: Motion.pressIcon)
        }
    }
}

/// One option group's chips with the price each choice leads to under it (3-16), as the board layers them: white
/// chips with a 1.5 pt liquorice ring, the cocoa selection pill, then the labels. Picking another chip moves the
/// pill there, the edge in the direction of travel on `Motion.doughLead` and the other on `Motion.doughTrail`, while
/// the inks swap on `Motion.quick` (the new chip 0.04 s later). A press squashes the chip, and the pill if it sits
/// under it. Reduce Motion: the pill fades in at the new chip and a press dims.
struct OptionChips: View {
    struct Choice: Identifiable {
        var id: String
        var text: String
        var price: String?
        var allowed: Bool
    }
    var choices: [Choice]
    var selected: String?
    var pick: (String) -> Void
    @State private var frames: [String: CGRect] = [:]
    @State private var pressed: String?
    /// The selection pill's edges, each on its own spring (left, right, top, bottom).
    @State private var pl: CGFloat = 0
    @State private var pr: CGFloat = 0
    @State private var pt: CGFloat = 0
    @State private var pb: CGFloat = 0
    @State private var picks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FlowRow(spacing: 8) {
            ForEach(choices) { c in chip(c) }
        }
        .coordinateSpace(.named("chips"))
        .background { GeometryReader { g in layers(g.size) } }
        .sensoryFeedback(.selection, trigger: picks)
        // The first pick, or one another group's pick forced: place the pill, or send it over.
        .onChange(of: selected, initial: true) { old, new in
            guard let f = new.flatMap({ frames[$0] }), (pl, pr, pt, pb) != (f.minX, f.maxX, f.minY, f.maxY) else { return }
            if old == nil || pr == pl { still { (pl, pr, pt, pb) = (f.minX, f.maxX, f.minY, f.maxY) } } else { travel(f) }
        }
    }

    private func chip(_ c: Choice) -> some View {
        let on = selected == c.id
        return Button {
            guard !on else { return }
            if let to = frames[c.id] { travel(to) }
            picks += 1
            pick(c.id)
        } label: {
            VStack(spacing: 1) {
                Text(c.text).font(MenuFont.manrope(14, 600))
                if let price = c.price { Text(price).font(MenuFont.manrope(11)).opacity(0.75) }
            }
            .foregroundStyle(on ? Brand.cream : Brand.cocoa)
            .animation(reduceMotion ? Motion.Reduced.fade : on ? Motion.quick.delay(OptionMotion.inkDelay) : Motion.quick, value: on)
            .lineLimit(1)
            .padding(.horizontal, 18).padding(.vertical, c.price == nil ? 11 : 8)
            .contentShape(Capsule())
        }
        .buttonStyle(ChipPress(id: c.id, pressed: $pressed))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("chips")) } action: { f in
            still {
                frames[c.id] = f
                if selected == c.id { (pl, pr, pt, pb) = (f.minX, f.maxX, f.minY, f.maxY) }
            }
        }
        .disabled(!c.allowed)
        .opacity(c.allowed ? 1 : SplitMotion.unavailableOpacity)
        .accessibilityLabel(c.price.map { "\(c.text), \($0)" } ?? c.text)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The chip faces and the selection pill, under the labels.
    @ViewBuilder private func layers(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(choices) { c in
                if let f = frames[c.id] {
                    Capsule().fill(.white).overlay(Capsule().strokeBorder(Brand.liquorice400, lineWidth: 1.5))
                        .frame(width: f.width, height: f.height)
                        .modifier(Squash(on: pressed == c.id))
                        .offset(x: f.minX, y: f.minY)
                        .opacity(c.allowed ? 1 : SplitMotion.unavailableOpacity)
                }
            }
            if reduceMotion {
                ForEach(choices) { c in
                    if let f = frames[c.id] {
                        Capsule().fill(Brand.cocoa).frame(width: f.width, height: f.height).offset(x: f.minX, y: f.minY)
                            .opacity(selected == c.id ? 1 : 0)
                            .animation(Motion.Reduced.fade, value: selected)
                    }
                }
            } else if let s = selected, frames[s] != nil {
                // Each edge is its own animated value, so the edge that leads and the one that trails can run on
                // different springs.
                Edge(value: pl) { l in Edge(value: pr) { r in Edge(value: pt) { t in Edge(value: pb) { b in
                    Capsule().fill(Brand.cocoa)
                        .frame(width: max(0, r - l), height: max(0, b - t))
                        .scaleEffect(pressed == s ? Motion.pressCompact : CGSize(width: 1, height: 1))
                        .animation(pressed == s ? Motion.press : Motion.release, value: pressed == s)
                        .offset(x: l, y: t)
                } } } }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// The pill travels to `to`: the edge in the direction of travel on doughLead, the other on doughTrail.
    private func travel(_ to: CGRect) {
        let right = to.midX >= (pl + pr) / 2, down = to.midY >= (pt + pb) / 2
        withAnimation(right ? Motion.doughTrail : Motion.doughLead) { pl = to.minX }
        withAnimation(right ? Motion.doughLead : Motion.doughTrail) { pr = to.maxX }
        withAnimation(down ? Motion.doughTrail : Motion.doughLead) { pt = to.minY }
        withAnimation(down ? Motion.doughLead : Motion.doughTrail) { pb = to.maxY }
    }

    /// Layout changes (a chip measured) never animate the pill; only a pick does.
    private func still(_ change: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, change)
    }

    /// The label's press, reported so the face and the pill under it squash with it.
    private struct ChipPress: ButtonStyle {
        var id: String
        @Binding var pressed: String?
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .doughPress(configuration.isPressed, squash: Motion.pressCompact)
                .onChange(of: configuration.isPressed) { _, p in pressed = p ? id : (pressed == id ? nil : pressed) }
        }
    }

    /// One edge's position, animated on its own and handed to `content` frame by frame.
    private struct Edge<Content: View>: View, Animatable {
        var value: CGFloat
        @ViewBuilder var content: (CGFloat) -> Content
        var animatableData: CGFloat {
            get { value }
            set { value = newValue }
        }
        var body: some View { content(value) }
    }

    private struct Squash: ViewModifier {
        var on: Bool
        func body(content: Content) -> some View { content.doughPress(on, squash: Motion.pressCompact) }
    }
}

/// "1000gr" reads "1000 gr", the way the boards write weights.
func optionLabel(_ s: String) -> String {
    s.replacingOccurrences(of: #"(\d)(gr|g|kg|ml|cm)\b"#, with: "$1 $2", options: .regularExpression)
}

/// Atas's Indonesian option-group names in English.
func optionGroupLabel(_ s: String) -> String {
    switch s { case "Berat": "Weight"; case "Rasa": "Flavour"; case "Ukuran": "Size"; default: s }
}

/// Wrapping row of pills.
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += sz.width + spacing
            widest = max(widest, x - spacing)
            row = max(row, sz.height)
        }
        return CGSize(width: width == .infinity ? widest : width, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            row = max(row, sz.height)
        }
    }
}
