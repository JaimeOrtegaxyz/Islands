import CoreGraphics

/// The set of snap fractions the user has chosen. Drives `AxisLayout.make`.
public enum SnapProfile: Int, CaseIterable {
    case quarters
    case sixths
    case both

    public var displayName: String {
        switch self {
        case .quarters: return "Quarters"
        case .sixths: return "Sixths"
        case .both: return "Quarters + Sixths"
        }
    }

    /// Snap sizes as fractions of the screen, strictly increasing within `(0, 1)`.
    /// `AxisLayout.make` relies on these being unique and ordered.
    public var availableFractions: [CGFloat] {
        switch self {
        case .quarters:
            return [1.0 / 4, 1.0 / 2, 3.0 / 4]
        case .sixths:
            return [1.0 / 6, 2.0 / 6, 3.0 / 6, 4.0 / 6, 5.0 / 6]
        case .both:
            return [1.0 / 6, 1.0 / 4, 1.0 / 3, 1.0 / 2, 2.0 / 3, 3.0 / 4, 5.0 / 6]
        }
    }
}

public enum PeekSizePreset: Int, CaseIterable {
    case small
    case medium
    case large

    public var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// Height of the peek strip revealed for stacked (accordion) windows, in points.
    public var points: CGFloat {
        switch self {
        case .small: return 4
        case .medium: return 8
        case .large: return 12
        }
    }
}
