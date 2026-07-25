import CoreGraphics

/// Pure geometry for the window manager. Stateless — every input is a parameter,
/// so these can be exercised in isolation from the Accessibility layer.
public enum LayoutGeometry {

    /// The screen-space frame for a window in a given snap `state`.
    ///
    /// `peekInset` shifts the window down and trims its height by the same amount,
    /// revealing the accordion peek strip at the top. It affects only the vertical
    /// axis — x and width are independent of it.
    public static func frame(
        for state: WindowState,
        horizontal: AxisLayout,
        vertical: AxisLayout,
        screenFrame: CGRect,
        peekInset: CGFloat = 0
    ) -> CGRect {
        let horizontalEntry = state.hCentered
            ? horizontal.centerPositions[state.hCenterIdx - 1]
            : horizontal.edgePositions[state.hIdx - 1]

        let verticalEntry = state.vCentered
            ? vertical.centerPositions[state.vCenterIdx - 1]
            : vertical.edgePositions[state.vIdx - 1]

        return CGRect(
            x: screenFrame.origin.x + screenFrame.width * horizontalEntry.offset,
            y: screenFrame.origin.y + screenFrame.height * verticalEntry.offset + peekInset,
            width: screenFrame.width * horizontalEntry.size,
            height: screenFrame.height * verticalEntry.size - peekInset
        )
    }

    /// The peek inset for a window at `stackIndex` within an accordion of `count`
    /// members. The front member (index 0) sits lowest — `(count - 1) * peekPixels`
    /// — and the back member (index `count - 1`) gets none, so the stack fans out
    /// as a downward staircase. Callers pass `stackIndex` in `0..<count`.
    public static func peekInset(stackIndex: Int, count: Int, peekPixels: CGFloat) -> CGFloat {
        CGFloat(count - 1 - stackIndex) * peekPixels
    }

    /// The slot on one axis whose geometry best matches an actual window, measured in
    /// screen fractions. Distance is `|Δoffset| + |Δsize|` over the edge slots and the
    /// centered slots; the centered duplicate of full-size is skipped so a full-size
    /// window resolves to the edge model. The returned 1-based index points into
    /// `edgePositions`, or into `centerPositions` when `centered`.
    public static func nearestSlot(offset: CGFloat, size: CGFloat, in layout: AxisLayout) -> (centered: Bool, index: Int) {
        var best = (centered: false, index: layout.fullEdgeIndex)
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for (position, entry) in layout.edgePositions.enumerated() {
            let distance = abs(offset - entry.offset) + abs(size - entry.size)
            if distance < bestDistance {
                bestDistance = distance
                best = (centered: false, index: position + 1)
            }
        }

        for (position, entry) in layout.centerPositions.enumerated() where position > 0 {
            let distance = abs(offset - entry.offset) + abs(size - entry.size)
            if distance < bestDistance {
                bestDistance = distance
                best = (centered: true, index: position + 1)
            }
        }

        return best
    }

    /// Advance a 1-based index one step around a ring of `count` slots, wrapping at
    /// the ends. `forward` goes `1 → 2 → … → count → 1`; backward goes
    /// `1 → count → … → 2 → 1`. Used to cycle centered-mode sizes.
    public static func cycledIndex(_ current: Int, count: Int, forward: Bool) -> Int {
        if forward {
            return current == count ? 1 : current + 1
        } else {
            return current == 1 ? count : current - 1
        }
    }
}
