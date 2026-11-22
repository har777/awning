import AppKit

enum Theme {
    static let accent = NSColor(srgbRed: 0.42, green: 0.88, blue: 0.62, alpha: 1)
    static let amber = NSColor(srgbRed: 0.98, green: 0.77, blue: 0.36, alpha: 1)
    static let red = NSColor(srgbRed: 0.98, green: 0.48, blue: 0.48, alpha: 1)
    static let text = NSColor(srgbRed: 0.87, green: 0.89, blue: 0.92, alpha: 1)
    static let heading = NSColor.white
    static let dim = NSColor(white: 0.56, alpha: 1)
    static let faint = NSColor(white: 0.40, alpha: 1)
    static let code = NSColor(srgbRed: 0.95, green: 0.70, blue: 0.50, alpha: 1)
    static let background = NSColor(srgbRed: 0.055, green: 0.063, blue: 0.08, alpha: 0.90)
    static let hairline = NSColor(white: 1, alpha: 0.07)
    static let border = NSColor(white: 1, alpha: 0.12)
    static let hover = NSColor(white: 1, alpha: 0.08)
    static let selection = accent.withAlphaComponent(0.25)

    static let cornerRadius: CGFloat = 12

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }
}
