import SwiftUI
import CoreText
import UIKit

/// Every colour, font, size and radius in the app, from the Claude Design "Ataste Design System" page
/// (Bombon's language recoloured chocolate). Views use these roles; a `Color(hex:)` in a view is a bug.
enum Brand {
    // MARK: Colour (name · use · contrast from the design system)
    static let cocoa = Color(rgb: 0x2B1A12)        // primary text, dark surfaces · 15.2:1 on cream
    static let caramel = Color(rgb: 0x9D5C1D)      // brand, primary CTA, links, active tab · cream on it 4.8:1
    static let choc400 = Color(rgb: 0xF39E60)      // secondary accents, progress fill
    static let choc100 = Color(rgb: 0xF9CFAF)      // soft highlights, selected, Best seller
    static let cream = Color(rgb: 0xFBF3EA)        // app background
    static let card = Color.white                  // cards
    static let liquorice100 = Color(rgb: 0xEDE2E4) // chips, dividers, skeletons
    static let liquorice400 = Color(rgb: 0xD1B6BB) // borders, disabled (non-text)
    static let pink100 = Color(rgb: 0xF9B7D2)      // promo tags, split accents
    static let lime = Color(rgb: 0xE9FF83)         // success: unlocked, paid, delivered
    static let limeDeep = Color(rgb: 0xBCD947)     // success borders, timeline line
    static let destructive = Color(rgb: 0xE40014)  // remove, cancel, errors
    static let ink2 = Color(rgb: 0x5A4237)         // callout text
    static let ink3 = Color(rgb: 0x7A6257)         // footnotes, metadata
    static let ink4 = Color(rgb: 0xA08A80)         // upcoming timeline steps

    // Design-system states that have no role of their own (buttons' pressed and disabled cells, tags, mats).
    static let limeInk = Color(rgb: 0x5E7A00)          // "Open" dot, success text on white
    static let editsInk = Color(rgb: 0xB0005A)         // "Edits requested" dot
    static let cancelledFill = Color(rgb: 0xFDE3E5)    // "Cancelled" / "Declined" tag
    static let cancelledInk = Color(rgb: 0xB00010)
    static let destructiveSoft = Color(rgb: 0xF6C7CB)  // disabled destructive border
    static let trashFill = Color(rgb: 0xFBE0E3)        // stepper delete at quantity 1
    static let splitFill = Color(rgb: 0xFFF0F6)        // split block inside a row
    static let selectedFill = Color(rgb: 0xFDF5EE)     // selected choice card / saved place
    static let caramelPressed = Color(rgb: 0xB5773A)
    static let creamPressed = Color(rgb: 0xFDF8F2), choc100Pressed = Color(rgb: 0xFCE3D0)
    static let cocoaPressed = Color(rgb: 0x4A3329)
    static let limePressed = Color(rgb: 0xF2FFB8), limeDeepPressed = Color(rgb: 0xD3E886)
    static let destructivePressed = Color(rgb: 0xEE4D5B)
    static let stripe = Color(rgb: 0xF6AE78)           // second colour of the "close to Rp 200k" bar

    /// Avatar pastels, assigned in join order.
    static let people: [Color] = [choc400, pink100, lime, choc100, liquorice100, liquorice400]

    // MARK: Spacing and radii
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16, s5: CGFloat = 24, s6: CGFloat = 32, s7: CGFloat = 48
    static let rChip: CGFloat = 8, rField: CGFloat = 12, rSmall: CGFloat = 16, rCard: CGFloat = 24, rHero: CGFloat = 32

    // MARK: Type
    enum Style {
        case display, hero, title1, title2, accent, headline, body, callout, footnote, label

        var spec: (family: Family, size: CGFloat, weight: CGFloat, tracking: CGFloat) {
            switch self {
            case .display: (.roundo, 48, 700, -0.02)
            case .hero: (.roundo, 56, 700, -0.02)
            case .title1: (.roundo, 34, 700, -0.01)
            case .title2: (.roundo, 24, 700, 0)
            case .accent: (.shrikhand, 40, 400, 0)
            case .headline: (.manrope, 17, 700, 0)
            case .body: (.manrope, 16, 500, 0)
            case .callout: (.manrope, 14, 500, 0)
            case .footnote: (.manrope, 12, 500, 0)
            case .label: (.manrope, 12, 600, 0.03)
            }
        }
        var textStyle: Font.TextStyle {
            switch self {
            case .display, .hero, .title1: .largeTitle
            case .title2, .accent: .title2
            case .headline: .headline
            case .body: .body
            case .callout: .callout
            case .footnote, .label: .footnote
            }
        }
    }

    enum Family: String {
        case roundo = "Roundo Variable", manrope = "Manrope", shrikhand = "Shrikhand"
    }

    static func font(_ style: Style, size: CGFloat? = nil, weight: CGFloat? = nil) -> Font {
        let s = style.spec
        return Font(uiFont(s.family, size: size ?? s.size, weight: weight ?? s.weight, relativeTo: style.textStyle))
    }

    /// Variable fonts: pick the weight on the `wght` axis; scale with Dynamic Type relative to a system style.
    static func uiFont(_ family: Family, size: CGFloat, weight: CGFloat, relativeTo: Font.TextStyle = .body) -> UIFont {
        let wght = 0x7767_6874 // 'wght'
        var attrs: [UIFontDescriptor.AttributeName: Any] = [.family: family.rawValue]
        if family != .shrikhand {
            attrs[UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)] = [wght: weight]
        }
        let base = UIFont(descriptor: UIFontDescriptor(fontAttributes: attrs), size: size)
        return UIFontMetrics(forTextStyle: uiTextStyle(relativeTo)).scaledFont(for: base)
    }

    private static func uiTextStyle(_ s: Font.TextStyle) -> UIFont.TextStyle {
        switch s {
        case .largeTitle: .largeTitle
        case .title, .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .callout: .callout
        case .footnote: .footnote
        case .caption, .caption2: .caption1
        default: .body
        }
    }

    /// Registers the bundled fonts once at launch (variable Roundo and Manrope, Shrikhand).
    static func registerFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

extension View {
    /// Text in a design-system style, including its letter-spacing and the label's uppercase.
    func brand(_ style: Brand.Style, _ color: Color = Brand.cocoa) -> some View {
        let s = style.spec
        return self.font(Brand.font(style))
            .tracking(s.size * s.tracking)
            .textCase(style == .label ? .uppercase : nil)
            .foregroundStyle(color)
    }
}
