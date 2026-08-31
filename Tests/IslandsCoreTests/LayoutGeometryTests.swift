import CoreGraphics
import Testing
@testable import IslandsCore

/// Tests for `LayoutGeometry` — the pure frame math and accordion peek fan-out.
@Suite struct LayoutGeometryTests {

    // A non-origin screen so any dropped `screenFrame.origin` term shows up.
    let screen = CGRect(x: 100, y: 200, width: 1000, height: 800)
    let h = AxisLayout.make(for: .quarters)
    let v = AxisLayout.make(for: .quarters)

    private func frame(_ state: WindowState, peek: CGFloat = 0) -> CGRect {
        LayoutGeometry.frame(for: state, horizontal: h, vertical: v, screenFrame: screen, peekInset: peek)
    }

    // MARK: Frame geometry

    @Test func fullScreenFillsScreen() {
        let state = WindowState(hIdx: h.fullEdgeIndex, vIdx: v.fullEdgeIndex)
        expectRect(frame(state), x: 100, y: 200, width: 1000, height: 800)
    }

    @Test func leftHalf() {
        // hIdx 2 → quarters edge slot (offset 0, size 1/2).
        let state = WindowState(hIdx: 2, vIdx: v.fullEdgeIndex)
        expectRect(frame(state), x: 100, y: 200, width: 500, height: 800)
    }

    @Test func rightHalf() {
        // hIdx 6 → trailing 1/2 (offset 1/2, size 1/2).
        let state = WindowState(hIdx: 6, vIdx: v.fullEdgeIndex)
        expectRect(frame(state), x: 600, y: 200, width: 500, height: 800)
    }

    @Test func leftAndRightQuarter() {
        let left = WindowState(hIdx: 1, vIdx: v.fullEdgeIndex)
        expectRect(frame(left), x: 100, y: 200, width: 250, height: 800, "left quarter")

        let right = WindowState(hIdx: 7, vIdx: v.fullEdgeIndex)
        expectRect(frame(right), x: 850, y: 200, width: 250, height: 800, "right quarter")
    }

    @Test func topAndBottomHalf() {
        let top = WindowState(hIdx: h.fullEdgeIndex, vIdx: 2)
        expectRect(frame(top), x: 100, y: 200, width: 1000, height: 400, "top half")

        let bottom = WindowState(hIdx: h.fullEdgeIndex, vIdx: 6)
        expectRect(frame(bottom), x: 100, y: 600, width: 1000, height: 400, "bottom half")
    }

    @Test func horizontallyCenteredHalf() {
        // centerPositions[2] for quarters = offset 1/4, size 1/2.
        var state = WindowState(hIdx: 2, vIdx: v.fullEdgeIndex)
        state.hCentered = true
        state.hCenterIdx = 3
        expectRect(frame(state), x: 350, y: 200, width: 500, height: 800)
    }

    @Test func verticallyCenteredHalf() {
        var state = WindowState(hIdx: h.fullEdgeIndex, vIdx: 2)
        state.vCentered = true
        state.vCenterIdx = 3
        expectRect(frame(state), x: 100, y: 400, width: 1000, height: 400)
    }

    // MARK: Peek inset

    @Test func peekInsetShiftsDownAndTrimsHeight() {
        let state = WindowState(hIdx: h.fullEdgeIndex, vIdx: v.fullEdgeIndex)
        expectRect(frame(state, peek: 8), x: 100, y: 208, width: 1000, height: 792)
    }

    /// Peek touches only the vertical axis: x and width are invariant; y rises by the
    /// inset and height drops by it, for any state.
    @Test(arguments: [
        WindowState(hIdx: 2, vIdx: 2),
        WindowState(hIdx: 6, vIdx: 6),
        WindowState(hIdx: 1, vIdx: 7),
    ])
    func peekAffectsOnlyVerticalAxis(_ state: WindowState) {
        let peek: CGFloat = 10
        let base = frame(state)
        let peeked = frame(state, peek: peek)
        #expect(isClose(peeked.origin.x, base.origin.x), "x invariant")
        #expect(isClose(peeked.size.width, base.size.width), "width invariant")
        #expect(isClose(peeked.origin.y, base.origin.y + peek), "y shifted")
        #expect(isClose(peeked.size.height, base.size.height - peek), "height trimmed")
    }

    // MARK: Fan-out

    @Test func peekInsetSingleMemberHasNoInset() {
        #expect(LayoutGeometry.peekInset(stackIndex: 0, count: 1, peekPixels: 8) == 0)
    }

    @Test func peekInsetFanOut() {
        let peek = PeekSizePreset.medium.points // 8
        #expect(LayoutGeometry.peekInset(stackIndex: 0, count: 3, peekPixels: peek) == 16)
        #expect(LayoutGeometry.peekInset(stackIndex: 1, count: 3, peekPixels: peek) == 8)
        #expect(LayoutGeometry.peekInset(stackIndex: 2, count: 3, peekPixels: peek) == 0)
    }

    /// Front member (index 0) sits lowest at `(count-1) * peek`; back member gets 0;
    /// the inset decreases by exactly `peek` per step down the stack.
    @Test func peekInsetIsAMonotonicStaircase() {
        let count = 5
        let peek: CGFloat = 12
        #expect(LayoutGeometry.peekInset(stackIndex: 0, count: count, peekPixels: peek) == CGFloat(count - 1) * peek)
        #expect(LayoutGeometry.peekInset(stackIndex: count - 1, count: count, peekPixels: peek) == 0)
        for index in 1..<count {
            let prev = LayoutGeometry.peekInset(stackIndex: index - 1, count: count, peekPixels: peek)
            let curr = LayoutGeometry.peekInset(stackIndex: index, count: count, peekPixels: peek)
            #expect(isClose(prev - curr, peek), "step \(index)")
        }
    }

    @Test func peekInsetZeroPeekPixels() {
        for index in 0..<4 {
            #expect(LayoutGeometry.peekInset(stackIndex: index, count: 4, peekPixels: 0) == 0, "index \(index)")
        }
    }

    // MARK: Nearest slot

    @Test func nearestSlotPicksCenteredWhenCloser() {
        // Half-width window at offset 0.14: leading-half (offset 0) is 0.14 away,
        // centered-half (offset 0.25) only 0.11 — centered wins.
        let slot = LayoutGeometry.nearestSlot(offset: 0.14, size: 0.5, in: h)
        #expect(slot.centered)
        #expect(slot.index == 3)
    }

    @Test func nearestSlotEdgeOnlyIgnoresCenteredSlots() {
        let slot = LayoutGeometry.nearestSlot(offset: 0.14, size: 0.5, in: h, includeCentered: false)
        #expect(!slot.centered)
        #expect(slot.index == 2)
    }

    @Test func nearestSlotFullSizeResolvesToEdgeModel() {
        // The centered duplicate of full-size is skipped even when centered slots
        // are allowed, so a full-size window resolves to the edge model.
        let slot = LayoutGeometry.nearestSlot(offset: 0, size: 1, in: h)
        #expect(!slot.centered)
        #expect(slot.index == h.fullEdgeIndex)
    }

    // MARK: Nearest state

    /// `nearestState` is the inverse of `frame(for:)` up to slot resolution: framing
    /// any slot exactly and inferring it back must land on a state with that frame.
    @Test func nearestStateRoundTripsEverySlotFrame() {
        var states: [WindowState] = []
        for hIdx in 1...h.maxEdgeIndex {
            for vIdx in 1...v.maxEdgeIndex {
                states.append(WindowState(hIdx: hIdx, vIdx: vIdx))
            }
        }
        // Centered slots, skipping index 1 (the duplicate of full-size).
        for hCenterIdx in 2...h.centerPositions.count {
            var state = WindowState(hIdx: h.centerToLeading[hCenterIdx]!, vIdx: v.fullEdgeIndex)
            state.hCentered = true
            state.hCenterIdx = hCenterIdx
            states.append(state)
        }
        for vCenterIdx in 2...v.centerPositions.count {
            var state = WindowState(hIdx: h.fullEdgeIndex, vIdx: v.centerToLeading[vCenterIdx]!)
            state.vCentered = true
            state.vCenterIdx = vCenterIdx
            states.append(state)
        }

        for state in states {
            let original = frame(state)
            let inferred = LayoutGeometry.nearestState(
                for: original, horizontal: h, vertical: v, screenFrame: screen
            )
            let reconstructed = frame(inferred)
            expectRect(
                reconstructed,
                x: original.origin.x, y: original.origin.y,
                width: original.size.width, height: original.size.height,
                "h\(state.hIdx) v\(state.vIdx) hC\(state.hCentered) vC\(state.vCentered)"
            )
        }
    }

    @Test func nearestStateCenteredMatchCarriesSameSizeEdgeIndex() {
        // A window on centered-half must carry leading-half as its edge index, so
        // leaving centered mode preserves its size.
        var centeredHalf = WindowState(hIdx: 2, vIdx: v.fullEdgeIndex)
        centeredHalf.hCentered = true
        centeredHalf.hCenterIdx = 3
        let inferred = LayoutGeometry.nearestState(
            for: frame(centeredHalf), horizontal: h, vertical: v, screenFrame: screen
        )
        #expect(inferred.hCentered)
        #expect(inferred.hCenterIdx == 3)
        #expect(inferred.hIdx == 2)
    }

    @Test func nearestStateEdgeOnlyAxisNeverGoesCentered() {
        // Slightly off centered-half: full inference picks the centered slot, but an
        // edge-only horizontal axis (an arrow press) must stay on edge slots.
        let nearCenter = CGRect(x: 100 + 0.14 * 1000, y: 200, width: 500, height: 800)
        let full = LayoutGeometry.nearestState(
            for: nearCenter, horizontal: h, vertical: v, screenFrame: screen
        )
        #expect(full.hCentered)

        let edgeOnly = LayoutGeometry.nearestState(
            for: nearCenter, horizontal: h, vertical: v, screenFrame: screen,
            hIncludeCentered: false
        )
        #expect(!edgeOnly.hCentered)
        #expect(edgeOnly.hIdx == 2)
    }

    // MARK: On-slot predicate

    @Test func framesApproximatelyEqualHonorsTolerance() {
        let base = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(LayoutGeometry.framesApproximatelyEqual(base, base))
        #expect(LayoutGeometry.framesApproximatelyEqual(base, base.offsetBy(dx: LayoutGeometry.snapTolerance, dy: 0)))
        #expect(!LayoutGeometry.framesApproximatelyEqual(base, base.offsetBy(dx: LayoutGeometry.snapTolerance + 0.5, dy: 0)))

        let widened = CGRect(x: 0, y: 0, width: 100 + LayoutGeometry.snapTolerance + 0.5, height: 100)
        #expect(!LayoutGeometry.framesApproximatelyEqual(base, widened))
        #expect(LayoutGeometry.framesApproximatelyEqual(base, widened, tolerance: 10))
    }
}
