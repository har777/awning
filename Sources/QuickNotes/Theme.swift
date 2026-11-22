import AppKit

/// All colours are dynamic: they resolve against the view's appearance at draw time, so the
/// visor switches between light and dark without rebuilding anything.
enum Theme {
    static let accent = dynamic(light: rgb(0.09, 0.54, 0.31), dark: rgb(0.42, 0.88, 0.62))
    static let amber = dynamic(light: rgb(0.70, 0.43, 0.00), dark: rgb(0.98, 0.77, 0.36))
    static let red = dynamic(light: rgb(0.80, 0.20, 0.20), dark: rgb(0.98, 0.48, 0.48))
    static let text = dynamic(light: rgb(0.13, 0.14, 0.16), dark: rgb(0.87, 0.89, 0.92))
    static let heading = dynamic(light: .black, dark: .white)
    static let dim = dynamic(light: NSColor(white: 0.42, alpha: 1), dark: NSColor(white: 0.56, alpha: 1))
    static let faint = dynamic(light: NSColor(white: 0.58, alpha: 1), dark: NSColor(white: 0.40, alpha: 1))
    static let code = dynamic(light: rgb(0.70, 0.33, 0.08), dark: rgb(0.95, 0.70, 0.50))
    static let background = dynamic(light: rgb(0.985, 0.983, 0.975, 0.93), dark: rgb(0.055, 0.063, 0.08, 0.90))
    static let hairline = dynamic(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.07))
    static let border = dynamic(light: NSColor(white: 0, alpha: 0.14), dark: NSColor(white: 1, alpha: 0.12))
    static let hover = dynamic(light: NSColor(white: 0, alpha: 0.06), dark: NSColor(white: 1, alpha: 0.08))
    static let grip = dynamic(light: NSColor(white: 0, alpha: 0.22), dark: NSColor(white: 1, alpha: 0.28))
    static let selection = dynamic(light: rgb(0.09, 0.54, 0.31, 0.18), dark: rgb(0.42, 0.88, 0.62, 0.25))

    static let cornerRadius: CGFloat = 12

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

/// Light / dark / follow the system.
enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}
