import CoreGraphics
import Testing
@testable import IslandsCore

/// Fraction-level tolerance. The tables are built from dyadic fractions where
/// possible, but sixths/thirds aren't exactly representable, so compare with slack.
let fractionAccuracy: CGFloat = 1e-9

func isClose(_ a: CGFloat, _ b: CGFloat, _ accuracy: CGFloat = fractionAccuracy) -> Bool {
    abs(a - b) <= accuracy
}

func expectEntry(
    _ entry: PositionEntry,
    offset: CGFloat,
    size: CGFloat,
    _ label: String = "",
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(isClose(entry.offset, offset), "offset \(label)", sourceLocation: sourceLocation)
    #expect(isClose(entry.size, size), "size \(label)", sourceLocation: sourceLocation)
}

func expectRect(
    _ rect: CGRect,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    _ label: String = "",
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(isClose(rect.origin.x, x), "x \(label)", sourceLocation: sourceLocation)
    #expect(isClose(rect.origin.y, y), "y \(label)", sourceLocation: sourceLocation)
    #expect(isClose(rect.size.width, width), "width \(label)", sourceLocation: sourceLocation)
    #expect(isClose(rect.size.height, height), "height \(label)", sourceLocation: sourceLocation)
}
