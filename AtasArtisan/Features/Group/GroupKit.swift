import SwiftUI

// Small building blocks for the group screen (boards 3 to 6), sized from the design's CSS (1 px = 1 pt).

/// No network (6-8); ATASTE_OFFLINE fakes it for DEBUG screenshots.
var groupOffline: Bool { !Connectivity.shared.online || DebugScreens.value("ATASTE_OFFLINE") != nil }

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
    /// #F6FFD0, the replaced-item wash (no token yet).
    static let replaced = Brand.limeWash
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
/// 6-13: "Remove Burnt Cheesecake?", naming who loses a share when the item is split.
func removeItemConfirm(_ store: GroupStore, _ item: Item, action: @escaping () async throws -> Void) -> Confirm {
    let others = store.liveSplit(item).map { store.shares($0).map(\.user_id).filter { $0 != item.owner_id }.map(store.name) } ?? []
    let names = others.count > 1 ? others.dropLast().joined(separator: ", ") + " and " + others.last! : others.first ?? ""
    return Confirm(title: "Remove \(item.name)?",
                   message: others.isEmpty ? "It comes out of your order." : "It’s split with \(names). Removing it cancels the split and clears their shares.",
                   button: "Remove item", keep: "Keep it", delay: SheetMotion.rowAfterRemove, action: action)
}

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

/// The Liquid Glass action bar at the bottom of the group screen (`at-glass radius 36`, 12pt inset).
/// Offline (6-8), the buttons are disabled and a line under them says why.
struct GroupBar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        let offline = groupOffline
        VStack(spacing: 8) {
            // Bottom-aligned: an async pill's error line grows its column upwards.
            HStack(alignment: .bottom, spacing: 10) { content }.disabled(offline)
            if offline { Text("Reconnect to change your order").ui(GFont.manrope(13), Brand.ink2).padding(.bottom, 2) }
        }
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

/// Children side by side at fixed width ratios (CSS `flex: 1` / `flex: 1.2`).
struct FlexRow: Layout {
    var weights: [CGFloat]
    var spacing: CGFloat = 10

    private func widths(_ total: CGFloat, _ n: Int) -> [CGFloat] {
        let w = (0..<n).map { $0 < weights.count ? weights[$0] : 1 }
        let sum = w.reduce(0, +)
        let room = max(0, total - spacing * CGFloat(n - 1))
        return w.map { room * $0 / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 360
        let ws = widths(total, subviews.count)
        let h = zip(subviews, ws).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: proposal.height)).height }.max() ?? 0
        return CGSize(width: total, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (s, w) in zip(subviews, widths(bounds.width, subviews.count)) {
            s.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + spacing
        }
    }
}
