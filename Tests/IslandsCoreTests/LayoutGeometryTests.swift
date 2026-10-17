import CoreGraphics
import Testing
@testable import IslandsCore

/// Tests for `LayoutGeometry` — the pure frame math and the stack band inset.
@Suite struct LayoutGeometryTests {

    // A non-origin screen so any dropped `screenFrame.origin` term shows up.
    let screen = CGRect(x: 100, y: 200, width: 1000, height: 800)
    let h = AxisLayout.make(for: .quarters)
    let v = AxisLayout.make(for: .quarters)

    private func frame(_ state: WindowState, inset: CGFloat = 0) -> CGRect {
        LayoutGeometry.frame(for: state, horizontal: h, vertical: v, screenFrame: screen, topInset: inset)
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

    // MARK: Stack inset

    @Test func topInsetShiftsDownAndTrimsHeight() {
        let state = WindowState(hIdx: h.fullEdgeIndex, vIdx: v.fullEdgeIndex)
        expectRect(frame(state, inset: 20), x: 100, y: 220, width: 1000, height: 780)
    }

    /// The inset touches only the vertical axis: x and width are invariant; y rises by the
    /// inset and height drops by it, for any state.
    @Test(arguments: [
        WindowState(hIdx: 2, vIdx: 2),
        WindowState(hIdx: 6, vIdx: 6),
        WindowState(hIdx: 1, vIdx: 7),
    ])
    func topInsetAffectsOnlyVerticalAxis(_ state: WindowState) {
        let inset: CGFloat = 10
        let base = frame(state)
        let insetFrame = frame(state, inset: inset)
        #expect(isClose(insetFrame.origin.x, base.origin.x), "x invariant")
        #expect(isClose(insetFrame.size.width, base.size.width), "width invariant")
        #expect(isClose(insetFrame.origin.y, base.origin.y + inset), "y shifted")
        #expect(isClose(insetFrame.size.height, base.size.height - inset), "height trimmed")
    }

    /// A lone window keeps its whole slot; every member of a real stack gives up the same band.
    @Test func stackInsetIsTheBandOnlyForRealStacks() {
        #expect(LayoutGeometry.stackInset(count: 0, bandHeight: 20) == 0)
        #expect(LayoutGeometry.stackInset(count: 1, bandHeight: 20) == 0)
        for count in 2...6 {
            #expect(LayoutGeometry.stackInset(count: count, bandHeight: 20) == 20, "count \(count)")
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
    /// Runs over every profile — the sixths ladders are where near-ties between edge
    /// and centered slots would show up.
    @Test(arguments: SnapProfile.allCases)
    func nearestStateRoundTripsEverySlotFrame(_ profile: SnapProfile) {
        let h = AxisLayout.make(for: profile)
        let v = AxisLayout.make(for: profile)
        func frame(_ state: WindowState) -> CGRect {
            LayoutGeometry.frame(for: state, horizontal: h, vertical: v, screenFrame: screen)
        }

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
                "\(profile) h\(state.hIdx) v\(state.vIdx) hC\(state.hCentered) vC\(state.vCentered)"
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

    // MARK: Arrow direction

    private func follows(_ actual: CGRect, to target: CGRect, _ arrow: String) -> Bool {
        switch arrow {
        case "left", "right":
            return LayoutGeometry.snapFollowsDirection(
                actualMin: actual.minX, actualMax: actual.maxX,
                targetMin: target.minX, targetMax: target.maxX, forward: arrow == "right")
        default:
            return LayoutGeometry.snapFollowsDirection(
                actualMin: actual.minY, actualMax: actual.maxY,
                targetMin: target.minY, targetMax: target.maxY, forward: arrow == "down")
        }
    }

    @Test func nudgedPastQuadrantOnlySnapsBackTowardIt() {
        // Top-left quadrant nudged 20pt right and down: its nearest edge slot is still the
        // quadrant, but snapping there moves the window left and up — so only Left and Up
        // snap; Right and Down must step on from the quadrant instead.
        let quadrant = frame(WindowState(hIdx: 2, vIdx: 2))
        let nudged = quadrant.offsetBy(dx: 20, dy: 20)
        let target = frame(LayoutGeometry.nearestState(
            for: nudged, horizontal: h, vertical: v, screenFrame: screen,
            hIncludeCentered: false, vIncludeCentered: false
        ))
        expectRect(target, x: quadrant.minX, y: quadrant.minY, width: quadrant.width, height: quadrant.height)

        #expect(follows(nudged, to: target, "left"))
        #expect(follows(nudged, to: target, "up"))
        #expect(!follows(nudged, to: target, "right"))
        #expect(!follows(nudged, to: target, "down"))
    }

    @Test func snapFollowsDirectionNeedsAVisibleMoveThatWay() {
        let slot = CGRect(x: 100, y: 200, width: 500, height: 800)

        // Already on the slot along this axis (within tolerance): the snap moves nothing
        // there, so no direction counts as followed.
        let onAxis = slot.offsetBy(dx: LayoutGeometry.snapTolerance, dy: 0)
        #expect(!follows(onAxis, to: slot, "left"))
        #expect(!follows(onAxis, to: slot, "right"))

        // Resized wider from the slot's left edge: the snap pulls the right edge in, which
        // follows Left (one edge moves left, none moves right) but not Right.
        let wider = CGRect(x: 100, y: 200, width: 550, height: 800)
        #expect(follows(wider, to: slot, "left"))
        #expect(!follows(wider, to: slot, "right"))

        // Narrower and inset on both sides: the snap pushes the edges apart — one against
        // each arrow — so neither direction follows.
        let inset = CGRect(x: 150, y: 200, width: 400, height: 800)
        #expect(!follows(inset, to: slot, "left"))
        #expect(!follows(inset, to: slot, "right"))
    }
}
