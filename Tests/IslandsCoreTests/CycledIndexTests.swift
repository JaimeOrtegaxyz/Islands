import Testing
@testable import IslandsCore

/// Tests for `LayoutGeometry.cycledIndex` — the 1-based ring-cycle math behind
/// centered-mode size cycling (centerH/centerV shrink/grow).
@Suite struct CycledIndexTests {

    @Test func forwardStepsThroughTheRing() {
        let count = 4
        let expected = [2, 3, 4, 1]
        for start in 1...count {
            #expect(LayoutGeometry.cycledIndex(start, count: count, forward: true) == expected[start - 1], "from \(start)")
        }
    }

    @Test func backwardStepsThroughTheRing() {
        let count = 4
        let expected = [4, 1, 2, 3]
        for start in 1...count {
            #expect(LayoutGeometry.cycledIndex(start, count: count, forward: false) == expected[start - 1], "from \(start)")
        }
    }

    /// The wrap guards: forward off the last slot returns to 1; backward off the
    /// first slot returns to the last. Dropping either guard would walk out of range.
    @Test func wrapsAtBothEnds() {
        let count = 6
        #expect(LayoutGeometry.cycledIndex(count, count: count, forward: true) == 1, "forward wrap")
        #expect(LayoutGeometry.cycledIndex(1, count: count, forward: false) == count, "backward wrap")
    }

    /// `count` forward steps return to the start; same backward. No slot is skipped
    /// or visited twice.
    @Test func fullCycleReturnsToStart() {
        let count = 6
        for start in 1...count {
            var forward = start
            var backward = start
            var visited: Set<Int> = []
            for _ in 0..<count {
                visited.insert(forward)
                forward = LayoutGeometry.cycledIndex(forward, count: count, forward: true)
                backward = LayoutGeometry.cycledIndex(backward, count: count, forward: false)
            }
            #expect(forward == start, "forward returns to \(start)")
            #expect(backward == start, "backward returns to \(start)")
            #expect(visited == Set(1...count), "forward visits every slot from \(start)")
        }
    }

    /// Forward and backward are inverses.
    @Test func directionsAreInverses() {
        let count = 5
        for start in 1...count {
            let forwardThenBack = LayoutGeometry.cycledIndex(
                LayoutGeometry.cycledIndex(start, count: count, forward: true),
                count: count, forward: false
            )
            #expect(forwardThenBack == start, "from \(start)")
        }
    }

    /// A single-slot ring stays put in either direction (no real SnapProfile yields
    /// this, but the math must not walk to 0 or 2).
    @Test func singleSlotRingStaysPut() {
        #expect(LayoutGeometry.cycledIndex(1, count: 1, forward: true) == 1)
        #expect(LayoutGeometry.cycledIndex(1, count: 1, forward: false) == 1)
    }
}
