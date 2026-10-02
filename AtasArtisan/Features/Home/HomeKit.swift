import SwiftUI

// Pieces the Home, create, share and join screens (board 2) share: sized type, form fields, the cream
// outline pill, painting frames, the WhatsApp glyph and the "1h 24m" countdown.

extension View {
    /// A design-system style at an explicit size (the board uses 11/13/15/20/22/26/28/40 beside the base sizes).
    func styled(_ style: Brand.Style, _ size: CGFloat, weight: CGFloat? = nil, _ color: Color = Brand.cocoa) -> some View {
        let s = style.spec
        return self.font(Brand.font(style, size: size, weight: weight))
            .tracking(size * s.tracking)
            .textCase(style == .label ? .uppercase : nil)
            .foregroundStyle(color)
    }

    /// A tappable field (date, time, area menu) drawn like `BrandField`: 52 tall, radius 12, cream with a
    /// liquorice edge; white with a 2pt red edge on error.
    func fieldBox(error: Bool = false, fill: Color = Brand.cream) -> some View {
        let shape = RoundedRectangle(cornerRadius: Brand.rField, style: .continuous)
        return self.padding(.horizontal, Brand.s4)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(shape.fill(error ? Brand.card : fill))
            .overlay(shape.strokeBorder(error ? Brand.destructive : Brand.liquorice100, lineWidth: error ? 2 : 1.5))
    }
}

/// "GROUP NAME" above a field: Manrope 600 12 uppercase, 4pt in from the field edge.
struct FieldLabel: View {
    var text: String
    var color = Brand.cocoa
    init(_ text: String, color: Color = Brand.cocoa) { self.text = text; self.color = color }
    var body: some View { Text(text).brand(.label, color) }
}

/// A painting in the shared caramel frame with "Title · oil on canvas" under it.
struct CaptionedPainting: View {
    var art: String
    var title: String
    var width: CGFloat
    var height: CGFloat
    var tilt: Double
    var body: some View {
        VStack(spacing: Brand.s2) {
            PaintingFrame(art: art, width: width, height: height, tilt: tilt)
            Text("\(Text(title).italic()) · oil on canvas").brand(.footnote, Brand.ink3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), a giraffe painting")
    }
}

/// The WhatsApp mark the board draws (`at-icon name="wa"`): a round speech bubble with a tail and a handset,
/// stroked on a 24-unit grid.
struct WAGlyph: View {
    var size: CGFloat = 20
    var body: some View {
        WAShape().stroke(style: StrokeStyle(lineWidth: 2 * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private struct WAShape: Shape {
        func path(in rect: CGRect) -> Path {
            let k = rect.width / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
            var path = Path()
            // Bubble: from (7.9, 20) the long way round the r=9 circle to (4, 16.1), then the tail to (2, 22).
            path.move(to: p(7.9, 20))
            path.addArc(center: p(12, 12), radius: 9 * k, startAngle: .degrees(117.1), endAngle: .degrees(152.9), clockwise: true)
            path.addLine(to: p(2, 22))
            path.closeSubpath()
            // Handset.
            path.move(to: p(9, 9.2))
            path.addCurve(to: p(14.8, 15), control1: p(9.2, 11.8), control2: p(12, 14.6))
            path.addLine(to: p(16, 13.6))
            path.addLine(to: p(14.1, 12.6))
            path.addLine(to: p(13.2, 13.3))
            path.addCurve(to: p(11.2, 11.3), control1: p(12.3, 12.9), control2: p(11.6, 12.2))
            path.addLine(to: p(11.9, 10.4))
            path.addLine(to: p(10.9, 8.5))
            path.closeSubpath()
            return path
        }
    }
}

/// "1h 24m", "35m", "2d 3h" until a moment.
nonisolated enum Countdown {
    static func text(to date: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let hours = minutes / 60, days = hours / 24
        if days > 0 { return "\(days)d \(hours % 24)h" }
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    /// "Locks in 1h 24m", or "Locking now" once the cutoff has passed.
    static func locks(_ cutoff: Date, now: Date = Date()) -> String {
        cutoff <= now ? "Locking now" : "Locks in \(text(to: cutoff, now: now))"
    }
}

/// A DEBUG-only screenshot hook for this board's screens: `ATASTE_HOME` = empty | paste | create | personal |
/// nopay | late | payment | address | born | login, `ATASTE_JOIN` = a join code.
enum HomeDebug {
    static var screen: String? { DebugScreens.value("ATASTE_HOME") }
}
