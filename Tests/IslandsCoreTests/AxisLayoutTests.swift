import CoreGraphics
import Testing
@testable import IslandsCore

/// Tests for `AxisLayout.make` — the pure table that turns a `SnapProfile` into
/// edge/center slots and the maps that translate between them.
///
/// The generic invariants run over every profile and are the real safety net:
/// they encode what the layout *means* (1-based indexing, mirror symmetry,
/// size-preserving centering, total maps) independently of the concrete numbers.
/// The pinned-table tests guard against silent reordering of those numbers.
@Suite struct AxisLayoutTests {

    // MARK: Generic invariants (every profile)

    @Test(arguments: SnapProfile.allCases)
    func cardinalities(_ profile: SnapProfile) {
        let n = profile.availableFractions.count
        let layout = AxisLayout.make(for: profile)
        #expect(layout.edgePositions.count == 2 * n + 1)
        #expect(layout.centerPositions.count == n + 1)
        #expect(layout.fullEdgeIndex == n + 1)
        #expect(layout.maxEdgeIndex == 2 * n + 1)
    }

    /// The full-screen slot is the midpoint of the edge ladder and the head of the
    /// center ladder, and is always offset 0 / size 1.
    @Test(arguments: SnapProfile.allCases)
    func fullScreenSlots(_ profile: SnapProfile) {
        let layout = AxisLayout.make(for: profile)
        expectEntry(layout.edgePositions[layout.fullEdgeIndex - 1], offset: 0, size: 1, "full edge")
        expectEntry(layout.centerPositions[0], offset: 0, size: 1, "full center")
    }

    /// Edge ladder: leading fractions (left/top-aligned) → full → trailing fractions
    /// (right/bottom-aligned, the mirror of the leading ones).
    @Test(arguments: SnapProfile.allCases)
    func edgeLadderShape(_ profile: SnapProfile) {
        let fractions = profile.availableFractions
        let n = fractions.count
        let layout = AxisLayout.make(for: profile)

        for i in 0..<n {
            expectEntry(layout.edgePositions[i], offset: 0, size: fractions[i], "leading \(i)")
        }
        let reversed = Array(fractions.reversed())
        for j in 0..<n {
            let trailing = layout.edgePositions[layout.fullEdgeIndex + j]
            expectEntry(trailing, offset: 1 - reversed[j], size: reversed[j], "trailing \(j)")
            // Right/bottom-aligned: the slot ends exactly at the screen edge.
            #expect(isClose(trailing.offset + trailing.size, 1), "trailing flush \(j)")
        }
    }

    /// Every centered slot is actually centered: equal margins on both sides.
    @Test(arguments: SnapProfile.allCases)
    func centerSlotsAreCentered(_ profile: SnapProfile) {
        let layout = AxisLayout.make(for: profile)
        for (i, entry) in layout.centerPositions.enumerated() {
            #expect(isClose(2 * entry.offset + entry.size, 1), "centered \(i)")
        }
    }

    /// `edgeToCenter` is total over every edge slot; `centerTo{Leading,Trailing}`
    /// are total over every center slot. No slot is left without a mapping.
    @Test(arguments: SnapProfile.allCases)
    func mapsAreTotal(_ profile: SnapProfile) {
        let layout = AxisLayout.make(for: profile)
        #expect(Set(layout.edgeToCenter.keys) == Set(1...layout.maxEdgeIndex))
        #expect(Set(layout.centerToLeading.keys) == Set(1...layout.centerPositions.count))
        #expect(Set(layout.centerToTrailing.keys) == Set(1...layout.centerPositions.count))

        #expect(layout.edgeToCenter.values.allSatisfy { (1...layout.centerPositions.count).contains($0) })
        #expect(layout.centerToLeading.values.allSatisfy { (1...layout.maxEdgeIndex).contains($0) })
        #expect(layout.centerToTrailing.values.allSatisfy { (1...layout.maxEdgeIndex).contains($0) })
    }

    /// Round-trip: going edge → center → back to the leading/trailing edge returns
    /// the same center. moveLeft/moveRight + centerH rely on this.
    ///
    /// The round-trip alone is symmetric (both edge slots of a fraction map to the
    /// same center), so it can't tell `centerToLeading` from `centerToTrailing`. Also
    /// pin that the leading slot is left/top-aligned and the trailing slot is flush to
    /// the far edge — that catches a leading/trailing swap on every profile, not just
    /// the ones with a pinned table.
    @Test(arguments: SnapProfile.allCases)
    func edgeCenterRoundTrips(_ profile: SnapProfile) throws {
        let layout = AxisLayout.make(for: profile)
        for center in 1...layout.centerPositions.count {
            let leading = try #require(layout.centerToLeading[center])
            let trailing = try #require(layout.centerToTrailing[center])
            #expect(layout.edgeToCenter[leading] == center, "leading round-trip \(center)")
            #expect(layout.edgeToCenter[trailing] == center, "trailing round-trip \(center)")

            let leadingEntry = layout.edgePositions[leading - 1]
            let trailingEntry = layout.edgePositions[trailing - 1]
            #expect(isClose(leadingEntry.offset, 0), "leading aligned \(center)")
            #expect(isClose(trailingEntry.offset + trailingEntry.size, 1), "trailing flush \(center)")
        }
    }

    /// Centering preserves size: the centered slot a window lands in is the same
    /// width as the edge slot it came from (and as its trailing mirror).
    @Test(arguments: SnapProfile.allCases)
    func centeringPreservesSize(_ profile: SnapProfile) throws {
        let layout = AxisLayout.make(for: profile)
        for center in 1...layout.centerPositions.count {
            let centerSize = layout.centerPositions[center - 1].size
            let leading = try #require(layout.centerToLeading[center])
            let trailing = try #require(layout.centerToTrailing[center])
            #expect(isClose(centerSize, layout.edgePositions[leading - 1].size), "center==leading \(center)")
            #expect(isClose(centerSize, layout.edgePositions[trailing - 1].size), "center==trailing \(center)")
        }
    }

    /// The edge ladder is mirror-symmetric about the full-screen slot: slot `i` and
    /// its mirror `maxEdgeIndex + 1 - i` resolve to the same centered size.
    @Test(arguments: SnapProfile.allCases)
    func edgeLadderMirrorSymmetry(_ profile: SnapProfile) {
        let layout = AxisLayout.make(for: profile)
        for i in 1...layout.maxEdgeIndex {
            let mirror = layout.maxEdgeIndex + 1 - i
            #expect(layout.edgeToCenter[i] == layout.edgeToCenter[mirror], "mirror \(i)")
        }
    }

    /// The full-screen slot maps to center index 1 in both directions.
    @Test(arguments: SnapProfile.allCases)
    func fullScreenMapping(_ profile: SnapProfile) {
        let layout = AxisLayout.make(for: profile)
        #expect(layout.edgeToCenter[layout.fullEdgeIndex] == 1)
        #expect(layout.centerToLeading[1] == layout.fullEdgeIndex)
        #expect(layout.centerToTrailing[1] == layout.fullEdgeIndex)
    }

    // MARK: Pinned tables (regression guards)

    @Test func quartersTablePinned() {
        let layout = AxisLayout.make(for: .quarters)

        #expect(layout.fullEdgeIndex == 4)
        #expect(layout.maxEdgeIndex == 7)

        expectEntry(layout.edgePositions[0], offset: 0, size: 1.0 / 4)
        expectEntry(layout.edgePositions[1], offset: 0, size: 1.0 / 2)
        expectEntry(layout.edgePositions[2], offset: 0, size: 3.0 / 4)
        expectEntry(layout.edgePositions[3], offset: 0, size: 1)
        expectEntry(layout.edgePositions[4], offset: 1.0 / 4, size: 3.0 / 4)
        expectEntry(layout.edgePositions[5], offset: 1.0 / 2, size: 1.0 / 2)
        expectEntry(layout.edgePositions[6], offset: 3.0 / 4, size: 1.0 / 4)

        expectEntry(layout.centerPositions[0], offset: 0, size: 1)
        expectEntry(layout.centerPositions[1], offset: 1.0 / 8, size: 3.0 / 4)
        expectEntry(layout.centerPositions[2], offset: 1.0 / 4, size: 1.0 / 2)
        expectEntry(layout.centerPositions[3], offset: 3.0 / 8, size: 1.0 / 4)

        let edgeToCenter: [Int: Int] = [1: 4, 2: 3, 3: 2, 4: 1, 5: 2, 6: 3, 7: 4]
        let centerToLeading: [Int: Int] = [1: 4, 2: 3, 3: 2, 4: 1]
        let centerToTrailing: [Int: Int] = [1: 4, 2: 5, 3: 6, 4: 7]
        #expect(layout.edgeToCenter == edgeToCenter)
        #expect(layout.centerToLeading == centerToLeading)
        #expect(layout.centerToTrailing == centerToTrailing)
    }

    @Test func bothMapsPinned() {
        let layout = AxisLayout.make(for: .both)

        #expect(layout.fullEdgeIndex == 8)
        #expect(layout.maxEdgeIndex == 15)
        let edgeToCenter: [Int: Int] = [
            1: 8, 2: 7, 3: 6, 4: 5, 5: 4, 6: 3, 7: 2, 8: 1,
            9: 2, 10: 3, 11: 4, 12: 5, 13: 6, 14: 7, 15: 8,
        ]
        let centerToLeading: [Int: Int] = [1: 8, 2: 7, 3: 6, 4: 5, 5: 4, 6: 3, 7: 2, 8: 1]
        let centerToTrailing: [Int: Int] = [1: 8, 2: 9, 3: 10, 4: 11, 5: 12, 6: 13, 7: 14, 8: 15]
        #expect(layout.edgeToCenter == edgeToCenter)
        #expect(layout.centerToLeading == centerToLeading)
        #expect(layout.centerToTrailing == centerToTrailing)
    }

    @Test func sixthsCardinality() {
        // The default profile — keep an explicit size guard alongside the generic ones.
        let layout = AxisLayout.make(for: .sixths)
        #expect(layout.fullEdgeIndex == 6)
        #expect(layout.maxEdgeIndex == 11)
        #expect(layout.centerPositions.count == 6)
    }
}
