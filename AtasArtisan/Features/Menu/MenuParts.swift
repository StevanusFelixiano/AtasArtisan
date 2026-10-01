import SwiftUI

// Small pieces the menu, product and split screens share, on top of Shared/Components.swift.

/// Type at the exact sizes the boards use: Roundo 700 for prices and headings, Manrope for the rest.
enum MenuFont {
    static func roundo(_ size: CGFloat) -> Font { Brand.font(.title2, size: size, weight: 700) }
    static func manrope(_ size: CGFloat, _ weight: CGFloat = 500) -> Font { Brand.font(.body, size: size, weight: weight) }
}

/// Capsule stepper: 28 pt choc circles around a Roundo count (product sheet, cart, split rows).
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

    var body: some View {
        HStack(spacing: gap) {
            circle(minusSymbol, enabled: canMinus, label: minusLabel, action: minus)
            Text(value).font(MenuFont.roundo(countSize)).foregroundStyle(Brand.cocoa)
                .lineLimit(1).fixedSize()
                .frame(minWidth: minWidth).monospacedDigit()
                .contentTransition(.numericText())
            circle("plus", enabled: canPlus, label: plusLabel, action: plus)
        }
        .padding(pad)
        .background(Capsule().fill(fill))
        .accessibilityElement(children: .contain)
    }

    private func circle(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.cocoa)
                .frame(width: 28, height: 28).background(Circle().fill(Brand.choc100))
                .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}

/// Option pill with the price of that choice under it (3-16): cocoa when picked, white with a liquorice edge.
struct PricedOptionPill: View {
    var text: String
    var price: String?
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(text).font(MenuFont.manrope(14, 600))
                if let price { Text(price).font(MenuFont.manrope(11)).opacity(0.75) }
            }
            .foregroundStyle(selected ? Brand.cream : Brand.cocoa)
            .lineLimit(1)
            .padding(.horizontal, 18).padding(.vertical, price == nil ? 11 : 8)
            .background(Capsule().fill(selected ? Brand.cocoa : .white))
            .overlay(Capsule().strokeBorder(Brand.liquorice400, lineWidth: selected ? 0 : 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(price.map { "\(text), \($0)" } ?? text)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
