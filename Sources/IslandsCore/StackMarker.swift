import CoreGraphics

/// How a stack (windows sharing one zone) marks itself. Every stacked window gives up
/// `bandHeight` points at the top of its slot, and Islands draws the marker in that band —
/// beside the windows, never over them, so nothing has to fight the window server for
/// z-order.
public enum StackMarkerStyle: Int, CaseIterable {
    /// A tab per window: app icon and title, the front one highlighted.
    case tabs
    /// A short row of dashes, the front one in its app's colour.
    case slim

    public var displayName: String {
        switch self {
        case .tabs: return "Tabs"
        case .slim: return "Slim"
        }
    }

    /// Height of the band reserved above a stack, in points.
    public var bandHeight: CGFloat {
        switch self {
        case .tabs: return 20
        case .slim: return StackMarkerLayout.dashHeight + 6
        }
    }
}

/// Pure geometry for the stack markers, in points. Both markers sit at the stack's
/// top-left and stop growing at a cap, so a stack spanning a whole display still gets
/// a compact marker rather than a strip from edge to edge.
public enum StackMarkerLayout {

    // MARK: Tabs

    /// Gap between the stack's left edge and the tab strip.
    public static let tabStripInset: CGFloat = 4
    /// Padding inside the strip, around the tabs.
    public static let tabStripPadding: CGFloat = 1
    /// No tab grows wider than this, however wide the stack.
    public static let tabMaxWidth: CGFloat = 200
    /// Below this a tab shows only its icon.
    public static let tabTitleMinWidth: CGFloat = 72

    /// Width of each tab in a stack of `count` windows `stackWidth` points wide: an equal
    /// share of the strip, capped at `tabMaxWidth`.
    public static func tabWidth(count: Int, stackWidth: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let available = stackWidth - 2 * tabStripInset - 2 * tabStripPadding
        return max(0, min(tabMaxWidth, available / CGFloat(count)))
    }

    /// Whole strip width for `count` tabs of `tabWidth` — the strip hugs its tabs.
    public static func tabStripWidth(count: Int, tabWidth: CGFloat) -> CGFloat {
        CGFloat(count) * tabWidth + 2 * tabStripPadding
    }

    public static func showsTabTitles(tabWidth: CGFloat) -> Bool {
        tabWidth >= tabTitleMinWidth
    }

    // MARK: Slim

    /// Gap between the stack's left edge and the first dash (lines up with the traffic lights).
    public static let dashInset: CGFloat = 12
    public static let dashHeight: CGFloat = 4
    public static let dashMaxWidth: CGFloat = 28
    public static let dashSpacing: CGFloat = 4
    /// The row of dashes never runs longer than this; more windows mean shorter dashes.
    public static let dashRowMaxWidth: CGFloat = 180

    public static func dashWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let spacing = CGFloat(count - 1) * dashSpacing
        return max(0, min(dashMaxWidth, (dashRowMaxWidth - spacing) / CGFloat(count)))
    }

    public static func dashRowWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * dashWidth(count: count) + CGFloat(count - 1) * dashSpacing
    }

    // MARK: Shared

    /// The cell under `x` in a row of `count` cells of `cellWidth` separated by `spacing`,
    /// starting at 0 — clamped to the row, so a drag past either end targets the end cell.
    public static func cellIndex(at x: CGFloat, cellWidth: CGFloat, spacing: CGFloat = 0, count: Int) -> Int {
        guard count > 0, cellWidth > 0 else { return 0 }
        let index = Int((x / (cellWidth + spacing)).rounded(.down))
        return min(max(index, 0), count - 1)
    }

    /// The 0-based index one step from `index` around a ring of `count`, wrapping at the ends.
    public static func step(_ index: Int, count: Int, forward: Bool) -> Int {
        guard count > 0 else { return 0 }
        return (index + (forward ? 1 : count - 1)) % count
    }

    /// `items` with the element at `from` moved to `to` — the drag-to-reorder result,
    /// where dropping onto a cell puts the dragged item at that cell's position.
    public static func moving<T>(_ items: [T], from: Int, to: Int) -> [T] {
        guard items.indices.contains(from), items.indices.contains(to), from != to else { return items }
        var result = items
        let item = result.remove(at: from)
        result.insert(item, at: to)
        return result
    }
}
