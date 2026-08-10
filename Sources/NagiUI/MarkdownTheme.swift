import AppKit
import NagiCore

/// Colours for the body editor.
///
/// Light and dark live inside a single `NSColor` each, so nothing downstream has
/// to know which appearance it is drawing in — including the text storage, which
/// is written once and re-resolved by AppKit when the system theme flips.
///
/// `@MainActor` because these are stored `NSColor` / `NSFont` values, which are
/// not `Sendable`; the editor only ever touches them from the main actor anyway.
@MainActor
enum MarkdownTheme {
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    static let bodyColor = dynamic(light: 0x1C1C1E, dark: 0xE4E4E6)

    /// Punctuation is deliberately low-contrast: its job is to recede. The body
    /// text is what has to stay readable.
    private static let markerColor = dynamic(light: 0x8A8F98, dark: 0x8D939C)
    private static let headingColor = dynamic(light: 0x0A58CA, dark: 0x6FA8FF)
    private static let codeColor = dynamic(light: 0x1F7A3D, dark: 0x7FCE8F)
    private static let linkColor = dynamic(light: 0x7A34C4, dark: 0xC08CF0)
    // Light is 0x666B72, not the 0x6C7178 the design table first carried: on the
    // measured editor background that only reached 4.47:1. See specs/contrast.py.
    private static let quoteColor = dynamic(light: 0x666B72, dark: 0x9AA0A8)

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: bodyColor]
    }

    static func color(for token: MarkdownToken) -> NSColor {
        switch token {
        case .heading:              return headingColor
        case .marker:               return markerColor
        case .code:                 return codeColor
        case .quoteText:            return quoteColor
        case .linkText, .linkURL:   return linkColor
        }
    }

    static func attributes(for token: MarkdownToken) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color(for: token)]
        if token == .linkText {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    private static func dynamic(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        }
    }
}

private extension NSColor {
    convenience init(rgb: Int) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
