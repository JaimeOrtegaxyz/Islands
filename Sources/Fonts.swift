import AppKit

extension NSFont {
    /// Returns Quicksand at the requested weight, falling back to the system
    /// font if the bundled font fails to load. Glyphs that Quicksand doesn't
    /// ship (e.g. ⌃⌥⌘⇧) are filled in by the system's automatic font cascade.
    static func quicksand(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let postscriptName: String
        switch weight {
        case .ultraLight, .thin, .light:
            postscriptName = "Quicksand-Light"
        case .medium:
            postscriptName = "Quicksand-Medium"
        case .semibold:
            postscriptName = "Quicksand-SemiBold"
        case .bold, .heavy, .black:
            postscriptName = "Quicksand-Bold"
        default:
            postscriptName = "Quicksand-Regular"
        }
        return NSFont(name: postscriptName, size: size)
            ?? .systemFont(ofSize: size, weight: weight)
    }
}
