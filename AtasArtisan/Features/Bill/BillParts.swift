import SwiftUI
import Supabase

// Pieces the board-5 screens (send, final bill, bill, payments, receipt, delivery) draw the same way.
// Sizes are the design's CSS px, 1 px = 1 pt.

enum Type5 {
    /// Manrope at a design size and weight.
    static func manrope(_ size: CGFloat, _ weight: CGFloat = 500) -> Font { Brand.font(.body, size: size, weight: weight) }
    /// Roundo 700 at a design size.
    static func roundo(_ size: CGFloat) -> Font { Brand.font(.title2, size: size, weight: 700) }
}

extension Rupiah {
    /// "481.000": the amount without "Rp ".
    static func bare(_ n: Int) -> String { String(format(n).dropFirst(3)) }
}

/// "Rani", "Rani and Kevin", "Rani, Dimas and Kevin".
func joinedNames(_ names: [String]) -> String {
    guard names.count > 1 else { return names.first ?? "" }
    return names.dropLast().joined(separator: ", ") + " and " + names.last!
}

// MARK: Icons

/// Final / not final, the bill's own `at-tag` kinds (pay states are the shared `PayTag`).
func finalTag(_ final: Bool) -> Tag {
    final ? Tag(text: "Final", fill: Brand.lime, border: Brand.limeDeep) : Tag(text: "Not final yet", fill: Brand.liquorice100)
}

// MARK: Buttons

/// Full-width pill for the cells the shared `.pill` sizes don't cover: the translucent "Not received" on the
/// dark receipt screen and the 15 pt "Try again" inside the upload-failed card.
struct WidePill: ButtonStyle {
    var fill: Color
    var ink: Color
    var border: Color? = nil
    var size: CGFloat = 16
    /// Vertical padding inside the 4 pt border (the design's 14 px padding + 4 px border = 18).
    var padding: CGFloat = 18
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(IconLabel(spacing: 8, size: size - 1))
            .font(Type5.manrope(size, 600))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .padding(.vertical, padding)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(border ?? fill, lineWidth: 4))
            .opacity(enabled ? 1 : 0.5)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .contentShape(Capsule())
            .frame(minHeight: 44)
    }
}

struct IconLabel: LabelStyle {
    var spacing: CGFloat
    var size: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) { configuration.icon.font(.system(size: size, weight: .semibold)); configuration.title }
    }
}

/// Small action chip on the payment board: "Nudge", "Mark paid". 12 pt, 5/12 padding, 44 pt tap area.
struct ChipStyle: ButtonStyle {
    var fill: Color
    var ring: Color?
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(IconLabel(spacing: 5, size: 12))
            .font(Type5.manrope(12, 600))
            .foregroundStyle(Brand.cocoa)
            .padding(.vertical, 5).padding(.horizontal, 12)
            .background(Capsule().fill(fill))
            .overlay { if let ring { Capsule().strokeBorder(ring, lineWidth: 1.5) } }
            .opacity(configuration.isPressed ? 0.82 : 1)
            .contentShape(Rectangle().inset(by: -9))
    }
}

/// The design's bottom `at-glass` bar: 12 pt in from the sides, radius 36, 12 pt padding.
struct GlassBar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(12)
            .glassEffect(.regular.tint(Brand.cream.opacity(0.4)), in: .rect(cornerRadius: 36))
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
    }
}

// MARK: Surfaces

/// Mascot banner under the bill: pose-waiting on a 56 pt circle, 14/600 text, radius 24.
struct BillBanner: View {
    var text: String
    var fill: Color
    var circle: Color
    var body: some View {
        HStack(spacing: 12) {
            Mascot(pose: "pose-waiting", size: 56, fill: circle)
            Text(text).font(Type5.manrope(14, 600)).lineSpacing(1).foregroundStyle(Brand.cocoa)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(fill))
    }
}

/// 6-9: an upload that failed. The picked photo stays (faded) next to the reason, and "Try again" resends the
/// same JPEG. Supabase storage uploads report no progress, so the line names no percentage.
struct UploadFailedCard: View {
    var image: UIImage?
    var retry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Brand.liquorice100
                    Hatching(ink: Brand.cocoa.opacity(0.08), band: 5)
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                }
                .frame(width: 56, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(0.6)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Label("Upload didn’t go through", systemImage: "exclamationmark.triangle")
                        .labelStyle(IconLabel(spacing: 6, size: 14))
                        .font(Type5.manrope(15, 700)).foregroundStyle(Brand.destructive)
                    Text("The connection dropped. Your photo is still here.")
                        .font(Type5.manrope(13)).lineSpacing(1).foregroundStyle(Brand.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: retry) { Label("Try again", systemImage: "arrow.clockwise") }
                .buttonStyle(WidePill(fill: Brand.cocoa, ink: Brand.cream, size: 15, padding: 15))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Brand.card))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Brand.destructive, lineWidth: 2))
    }
}

/// Diagonal stripes behind a photo that hasn't loaded (the design's placeholder hatching).
struct Hatching: View {
    var ink: Color
    var band: CGFloat = 8
    var body: some View {
        Canvas { ctx, size in
            let w = band * 1.414
            var x: CGFloat = -size.height
            while x < size.width {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                p.addLine(to: CGPoint(x: x + size.height + w, y: 0))
                p.addLine(to: CGPoint(x: x + w, y: size.height))
                p.closeSubpath()
                ctx.fill(p, with: .color(ink))
                x += w * 2
            }
        }
        .accessibilityHidden(true)
    }
}

/// A signed-URL photo over the hatched placeholder.
struct HatchedPhoto: View {
    var url: URL?
    var fill: Color
    var ink: Color
    var band: CGFloat = 8
    var body: some View {
        ZStack {
            fill
            Hatching(ink: ink, band: band)
            if let url {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }
        .clipped()
    }
}

/// A 1 pt dashed rule.
struct DashedRule: View {
    var color: Color
    var body: some View {
        Line().stroke(color, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(height: 1)
    }
    struct Line: Shape {
        func path(in r: CGRect) -> Path { Path { $0.move(to: CGPoint(x: r.minX, y: r.midY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
    }
}

// MARK: Receipts

/// Receipts live at `receipts/<group>/<user>.jpg`. Listing the folder returns only what the caller may read
/// (their own, or every member's for the host), with the upload time.
enum Receipts {
    static func path(_ group: UUID, _ user: UUID) -> String { "\(group.uuidString.lowercased())/\(user.uuidString.lowercased()).jpg" }

    /// user → upload time, for the receipts the caller can see in this group.
    static func list(_ group: UUID) async -> [UUID: Date] {
        let files = (try? await supabase.storage.from("receipts").list(path: group.uuidString.lowercased())) ?? []
        var out: [UUID: Date] = [:]
        for f in files {
            guard f.name.hasSuffix(".jpg"), let u = UUID(uuidString: String(f.name.dropLast(4))) else { continue }
            out[u] = f.updatedAt ?? f.createdAt ?? .distantPast
        }
        return out
    }

    static func url(_ group: UUID, _ user: UUID) async -> URL? {
        try? await supabase.storage.from("receipts").createSignedURL(path: path(group, user), expiresIn: 600)
    }
}
