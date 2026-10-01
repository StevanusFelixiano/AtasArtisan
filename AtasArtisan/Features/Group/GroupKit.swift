import SwiftUI

// Small building blocks for the group screen (boards 3 to 6), sized from the design's CSS (1 px = 1 pt).

enum GFont {
    /// Roundo 700 at a design size ("font:700 32px Roundo").
    static func roundo(_ size: CGFloat) -> Font { Brand.font(.title2, size: size, weight: 700) }
    /// Manrope at a design size and weight ("font:600 14px Manrope").
    static func manrope(_ size: CGFloat, _ weight: CGFloat = 500) -> Font { Brand.font(.body, size: size, weight: weight) }
    /// Shrikhand display ("font:400 30px Shrikhand").
    static func shrikhand(_ size: CGFloat) -> Font { Brand.font(.accent, size: size) }
}

/// Tints the design uses that have no token of their own: a token at an opacity over white.
enum GTint {
    /// #FFF0F6, the flagged-item wash.
    static let flagged = Brand.pink100.opacity(0.2)
    /// #F6FFD0, the replaced-item wash.
    static let replaced = Brand.lime.opacity(0.3)
    /// #F6C7CB, the Remove pill's ring.
    static let removeRing = Brand.destructive.opacity(0.22)
}

extension View {
    func ui(_ font: Font, _ color: Color = Brand.cocoa) -> some View {
        self.font(font).foregroundStyle(color)
    }

    /// White surface with the design's radius and padding (cards on board 3 to 6 use 24, 28 or 32).
    func surface(_ radius: CGFloat = 32, padding: EdgeInsets = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18), fill: Color = Brand.card) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
    }
}

func edges(_ v: CGFloat, _ h: CGFloat) -> EdgeInsets { EdgeInsets(top: v, leading: h, bottom: v, trailing: h) }

/// "2 Pain Au Chocolate", "2 Pain Au Chocolate and 1 Brioche Bun".
func itemPhrase(_ items: [Item]) -> String {
    let parts = items.map { "\($0.qty) \($0.name)" }
    switch parts.count {
    case 0: return ""
    case 1: return parts[0]
    default: return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    }
}

/// "Rp 24.000" → "24.000", the review list's bare amounts.
func bareRupiah(_ n: Int) -> String { String(Rupiah.format(n).dropFirst(3)) }

/// ¼, ½, ¾, ⅓, ⅔ for a split share, else "25%".
func shareGlyph(_ pct: Double) -> String {
    switch Int(pct.rounded()) {
    case 25: "¼"
    case 50: "½"
    case 75: "¾"
    case 33: "⅓"
    case 67: "⅔"
    case 20: "⅕"
    default: "\(Int(pct.rounded()))%"
    }
}

/// The design's WhatsApp glyph (`at-icon name="wa"`): a round bubble with a tail and a handset, on a 24 grid.
struct WhatsAppGlyph: View {
    var size: CGFloat = 15
    var color: Color = Brand.cocoa
    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 24
            var bubble = Path()
            bubble.move(to: CGPoint(x: 7.9 * k, y: 20 * k))
            bubble.addArc(center: CGPoint(x: 12 * k, y: 12 * k), radius: 9 * k, startAngle: .degrees(117.1), endAngle: .degrees(152.9), clockwise: true)
            bubble.addLine(to: CGPoint(x: 2 * k, y: 22 * k))
            bubble.closeSubpath()
            var phone = Path()
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
            phone.move(to: p(9, 9.2))
            phone.addCurve(to: p(14.8, 15), control1: p(9.2, 11.8), control2: p(12, 14.6))
            phone.addLine(to: p(16, 13.6))
            phone.addLine(to: p(14.1, 12.6))
            phone.addLine(to: p(13.2, 13.3))
            phone.addCurve(to: p(11.2, 11.3), control1: p(12.3, 12.9), control2: p(11.6, 12.2))
            phone.addLine(to: p(11.9, 10.4))
            phone.addLine(to: p(10.9, 8.5))
            phone.closeSubpath()
            let style = StrokeStyle(lineWidth: 2 * k, lineCap: .round, lineJoin: .round)
            ctx.stroke(bubble, with: .color(color), style: style)
            ctx.stroke(phone, with: .color(color), style: style)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 28pt pastel circle holding a glyph, with a 44pt tap area (the member rows' pie and WhatsApp buttons).
struct RoundIcon<Glyph: View>: View {
    var fill: Color
    var size: CGFloat = 28
    @ViewBuilder var glyph: Glyph
    var body: some View {
        glyph.frame(width: size, height: size).background(Circle().fill(fill))
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }
}

/// An SF Symbol drawn at the design's icon size and stroke weight.
func icon(_ name: String, _ size: CGFloat, _ color: Color = Brand.cocoa, weight: Font.Weight = .semibold) -> some View {
    Image(systemName: name).font(.system(size: size * 0.85, weight: weight)).foregroundStyle(color)
        .frame(width: size, height: size)
}

/// Icon + title inside a pill.
struct PillLabel: View {
    var title: String
    var symbol: String?
    var body: some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol).font(.system(size: 16, weight: .semibold)) }
            Text(title)
        }
    }
}

/// Cream pill with a 4pt choc-100 ring: the bar's "+", "Request edits", "Open the Atas chat".
struct OutlinePillStyle: ButtonStyle {
    var size: CGFloat = 15
    var height: CGFloat = 52
    var expand = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GFont.manrope(size, 600))
            .lineLimit(1)
            .foregroundStyle(enabled ? Brand.cocoa : Brand.ink3)
            .padding(.horizontal, expand ? 16 : 0)
            .frame(maxWidth: expand ? .infinity : nil, minHeight: height)
            .background(Capsule().fill(Brand.cream))
            .overlay(Capsule().strokeBorder(Brand.choc100, lineWidth: 4))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .contentShape(Capsule())
    }
}

/// The Liquid Glass action bar at the bottom of the group screen (`at-glass radius 36`, 12pt inset).
struct GlassBar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 10) { content }
            .padding(12)
            .glassEffect(.regular.tint(Brand.cream.opacity(0.4)), in: .rect(cornerRadius: 36))
            .padding(.horizontal, 12)
    }
}

/// Skeleton block (#EDE2E4).
struct Bone: View {
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat = 999
    var body: some View {
        RoundedRectangle(cornerRadius: min(radius, height / 2 + 0.5), style: .continuous).fill(Brand.liquorice100)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// 3-7 Group · loading.
struct GroupSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Bone(width: 80, height: 24)
                    Bone(width: 290, height: 30, radius: 10)
                    Bone(width: 200, height: 30, radius: 10)
                }
                .padding(.horizontal, 4)
                VStack(alignment: .leading, spacing: 14) {
                    Bone(width: 180, height: 34, radius: 10)
                    Bone(height: 20)
                    Bone(width: 240, height: 14)
                }
                .surface(32, padding: edges(20, 20))
                VStack(spacing: 0) {
                    ForEach([0.6, 0.45, 0.55], id: \.self) { w in
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(Brand.liquorice100).frame(width: 40, height: 40)
                            GeometryReader { g in
                                VStack(alignment: .leading, spacing: 8) {
                                    Bone(width: g.size.width * w, height: 14)
                                    Bone(width: g.size.width * (w + 0.3 > 1 ? 1 : w + 0.3), height: 12)
                                }
                            }
                            .frame(height: 34)
                        }
                        .padding(.vertical, 14)
                        if w != 0.55 { Rectangle().fill(Brand.liquorice100).frame(height: 1) }
                    }
                }
                .surface(32, padding: edges(6, 18))
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .scrollDisabled(true)
        .screen()
        .accessibilityLabel("Loading the order")
    }
}
