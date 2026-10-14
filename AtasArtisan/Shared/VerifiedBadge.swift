import SwiftUI

// Board 9 "Verified badge" (`<at-verified>`): a small version of the sticker-pill logo. It means one thing: this person
// proved they own the WhatsApp number on their account (`profiles.phone`). Sentence case, so it never reads as one of the
// uppercase state tags (PAID, TAKEN, READY), and a phone-with-a-tick glyph, so it never reads as Apple's or Meta's check.

/// Whose badge it is: the explainer (9-10b) names them and shows their picture.
struct VerifiedPerson: Identifiable, Hashable {
    var name: String
    var avatar: String? = nil
    var bg: String? = nil
    var index = 0
    var id: String { name }

    init(name: String, avatar: String? = nil, bg: String? = nil, index: Int = 0) {
        self.name = name.isEmpty ? "Someone" : name
        self.avatar = avatar
        self.bg = bg
        self.index = index
    }

    init(_ p: Profile, index: Int = 0) {
        self.init(name: p.name, avatar: p.avatar, bg: p.avatar_bg, index: index)
    }
}

/// S (20 pt) sits 6 pt after a name, before any role ("· host"); L (26 pt) in the profile header and on 9-5; the dot
/// (22 × 16) on an avatar's corner where a name line has no room. Light: Caramel, Cream ink, the logo's cocoa drop.
/// Dark (on Cocoa): Chocolate 400, Cocoa ink, no drop. With a `person` it is a button that opens "What Verified means".
struct VerifiedBadge: View {
    enum Size { case s, l, dot }
    var size: Size = .s
    var dark = false
    var person: VerifiedPerson? = nil
    /// The dot's 2 pt ring, the surface it sits on.
    var ring: Color = Brand.card
    @State private var explaining: VerifiedPerson?

    var body: some View {
        if let person {
            Button { explaining = person } label: { face }
                .buttonStyle(.plain)
                // A 20 pt badge in a name line: the tap area grows past it without moving anything.
                .contentShape(Rectangle().inset(by: -10))
                .accessibilityLabel("Verified")
                .accessibilityHint("Explains what Verified means")
                .doughSheet(item: $explaining) { p in VerifiedMeaning(person: p) }
        } else {
            face.accessibilityElement().accessibilityLabel("Verified")
        }
    }

    @ViewBuilder private var face: some View {
        let fill = dark ? Brand.choc400 : Brand.caramel
        let ink = dark ? Brand.cocoa : Brand.cream
        switch size {
        case .dot:
            VerifiedGlyph(size: 11)
                .foregroundStyle(ink)
                .frame(width: 22, height: 16)
                .background(Capsule().fill(fill))
                .background(Capsule().fill(ring).padding(-2))
        case .s, .l:
            let l = size == .l
            HStack(spacing: l ? 5 : 4) {
                VerifiedGlyph(size: l ? 15 : 12)
                Text("Verified").font(Brand.font(.label, size: l ? 13 : 11, weight: 700))
            }
            .foregroundStyle(ink)
            .padding(.leading, l ? 9 : 6).padding(.trailing, l ? 12 : 8)
            .frame(minHeight: l ? 26 : 20)
            .background(Capsule().fill(fill))
            .background(Capsule().fill(Brand.cocoa).offset(y: l ? 2 : 1.5).opacity(dark ? 0 : 1))
            .fixedSize()
        }
    }
}

/// The badge's glyph: a phone with a tick on its screen (board: rect 5.5,2 13×20 r3.5, tick 9,11.6 → 11.2,13.8 → 15,10).
struct VerifiedGlyph: View {
    var size: CGFloat
    var body: some View {
        VerifiedShape()
            .stroke(style: StrokeStyle(lineWidth: 2.4 * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct VerifiedShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path(roundedRect: CGRect(origin: p(5.5, 2), size: CGSize(width: 13 * s, height: 20 * s)), cornerRadius: 3.5 * s)
        path.move(to: p(9, 11.6))
        path.addLine(to: p(11.2, 13.8))
        path.addLine(to: p(15, 10))
        return path
    }
}

/// A name in a row, then the badge 6 pt after it (when `person` is verified) and `tail` ("· you", "· not verified").
/// On one line when it fits; in a narrow row the badge and tail go under the name instead of the name being cut short.
struct BadgedName<Tail: View>: View {
    var name: String
    var font: Font
    /// Nil: no badge (not verified).
    var person: VerifiedPerson?
    @ViewBuilder var tail: Tail

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                text.lineLimit(1)
                marks
            }
            VStack(alignment: .leading, spacing: 4) {
                text
                HStack(spacing: 6) { marks }
            }
        }
    }

    private var text: some View { Text(name).font(font).foregroundStyle(Brand.cocoa) }

    @ViewBuilder private var marks: some View {
        if let person { VerifiedBadge(person: person) }
        tail
    }
}

/// "· not verified" after a name, only in the host's member list and payment board: that is where a WhatsApp button is
/// missing for them. Manrope 12, Ink 3.
struct NotVerifiedNote: View {
    var body: some View {
        Text("· not verified").font(GFont.manrope(12)).foregroundStyle(Brand.ink3).fixedSize()
    }
}

// MARK: What Verified means (9-10b)

/// Opened by tapping any badge: who, what the badge proves, and what it doesn't.
struct VerifiedMeaning: View {
    var person: VerifiedPerson
    @Environment(\.closeSheet) private var close

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Avatar(name: person.name, index: person.index, size: 48, art: person.avatar, bg: person.bg)
                HStack(spacing: 8) {
                    Text(person.name).font(GFont.roundo(24)).foregroundStyle(Brand.cocoa).lineLimit(1)
                    VerifiedBadge(size: .l)
                }
            }
            Text("What Verified means").font(GFont.roundo(20)).foregroundStyle(Brand.cocoa)
                .accessibilityAddTraits(.isHeader)
            Text("\(person.name) sent us a WhatsApp message from the number on this account, so we know the number really belongs to \(person.name).")
                .font(GFont.manrope(15)).lineSpacing(3).foregroundStyle(Brand.cocoa)
                .fixedSize(horizontal: false, vertical: true)
            Text("It doesn’t check a bank account or rate anyone’s orders. You’ll see the number once you’re in the group.")
                .font(GFont.manrope(14)).lineSpacing(3).foregroundStyle(Brand.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button { close?() } label: { Text("Got it").frame(maxWidth: .infinity) }
                .buttonStyle(.pill(.secondary, .medium))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
