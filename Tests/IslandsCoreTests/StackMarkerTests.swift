import CoreGraphics
import Testing
@testable import IslandsCore

/// Tests for the stack marker geometry and the icon colour pick.
@Suite struct StackMarkerTests {

    // MARK: Tabs

    @Test func tabsShareANarrowStack() {
        // A third of a 1280pt display: 427 - 2·4 inset - 2·1 padding = 417, split four ways.
        #expect(isClose(StackMarkerLayout.tabWidth(count: 4, stackWidth: 427), 417.0 / 4))
    }

    /// A stack spanning a whole display still gets a compact strip: tabs stop at their cap.
    @Test func tabsStopGrowingOnWideStacks() {
        #expect(StackMarkerLayout.tabWidth(count: 3, stackWidth: 2560) == StackMarkerLayout.tabMaxWidth)
        let strip = StackMarkerLayout.tabStripWidth(count: 3, tabWidth: StackMarkerLayout.tabMaxWidth)
        #expect(strip == 3 * StackMarkerLayout.tabMaxWidth + 2 * StackMarkerLayout.tabStripPadding)
    }

    @Test func narrowTabsDropTheirTitles() {
        #expect(StackMarkerLayout.showsTabTitles(tabWidth: 104))
        #expect(!StackMarkerLayout.showsTabTitles(tabWidth: 69))
    }

    // MARK: Slim

    @Test func dashesKeepTheirWidthUntilTheRowIsFull() {
        #expect(StackMarkerLayout.dashWidth(count: 4) == StackMarkerLayout.dashMaxWidth)
        // Typed local: inside `#expect` the literal arithmetic doesn't infer as CGFloat.
        let row: CGFloat = 4 * 28 + 3 * 4
        #expect(StackMarkerLayout.dashRowWidth(count: 4) == row)
    }

    @Test(arguments: [2, 6, 7, 12])
    func dashRowNeverPassesItsCap(_ count: Int) {
        #expect(StackMarkerLayout.dashRowWidth(count: count) <= StackMarkerLayout.dashRowMaxWidth + 1e-9)
        #expect(StackMarkerLayout.dashWidth(count: count) > 0)
    }

    // MARK: Hit testing, cycling, reordering

    @Test func cellIndexClampsToTheRow() {
        #expect(StackMarkerLayout.cellIndex(at: -10, cellWidth: 50, count: 4) == 0)
        #expect(StackMarkerLayout.cellIndex(at: 75, cellWidth: 50, count: 4) == 1)
        #expect(StackMarkerLayout.cellIndex(at: 999, cellWidth: 50, count: 4) == 3)
        // With spacing, a point in the gap after cell 0 still reads as cell 0.
        #expect(StackMarkerLayout.cellIndex(at: 30, cellWidth: 28, spacing: 4, count: 4) == 0)
        #expect(StackMarkerLayout.cellIndex(at: 33, cellWidth: 28, spacing: 4, count: 4) == 1)
    }

    @Test func stepWrapsBothWays() {
        #expect(StackMarkerLayout.step(0, count: 3, forward: true) == 1)
        #expect(StackMarkerLayout.step(2, count: 3, forward: true) == 0)
        #expect(StackMarkerLayout.step(0, count: 3, forward: false) == 2)
    }

    @Test func movingPutsTheItemAtTheDropTarget() {
        #expect(StackMarkerLayout.moving([1, 2, 3, 4], from: 0, to: 2) == [2, 3, 1, 4])
        #expect(StackMarkerLayout.moving([1, 2, 3, 4], from: 3, to: 0) == [4, 1, 2, 3])
        #expect(StackMarkerLayout.moving([1, 2, 3], from: 1, to: 1) == [1, 2, 3])
        #expect(StackMarkerLayout.moving([1, 2, 3], from: 5, to: 0) == [1, 2, 3])
    }

    // MARK: Icon tint

    private func pixels(_ count: Int, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat, a: CGFloat = 1) -> [IconTint.Pixel] {
        Array(repeating: IconTint.Pixel(r: r, g: g, b: b, a: a), count: count)
    }

    /// Terminal-style icons (greys, black, white) have no colour to use; the marker falls back.
    @Test func greyIconsHaveNoTint() {
        let icon = pixels(500, 0.2, 0.2, 0.22) + pixels(300, 0.9, 0.9, 0.9) + pixels(200, 0, 0, 0)
        #expect(IconTint.dominantColor(of: icon) == nil)
        #expect(IconTint.dominantColor(of: []) == nil)
        #expect(IconTint.dominantColor(of: pixels(100, 1, 0.5, 0, a: 0)) == nil, "transparent pixels don't count")
    }

    /// An orange glyph on a dark-grey tile (Sublime Text) reads as orange.
    @Test func colouredGlyphOnGreyReadsAsItsColour() throws {
        let icon = pixels(700, 0.25, 0.25, 0.25) + pixels(300, 0.95, 0.55, 0.2)
        let tint = try #require(IconTint.dominantColor(of: icon))
        #expect(isClose(tint.r, 0.95, 1e-6) && isClose(tint.g, 0.55, 1e-6) && isClose(tint.b, 0.2, 1e-6))
    }

    @Test func theLargerHueWins() throws {
        let icon = pixels(200, 0.9, 0.1, 0.1) + pixels(500, 0.15, 0.45, 0.9)
        let tint = try #require(IconTint.dominantColor(of: icon))
        #expect(tint.b > tint.r, "blue covers more of the icon")
    }

    @Test func aSpeckOfColourIsNotEnough() {
        // 5% coloured is under the 12% share an icon needs to count as coloured.
        let icon = pixels(950, 0.3, 0.3, 0.3) + pixels(50, 0.2, 0.8, 0.3)
        #expect(IconTint.dominantColor(of: icon) == nil)
    }
}
