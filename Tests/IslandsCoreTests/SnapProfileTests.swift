import CoreGraphics
import Testing
@testable import IslandsCore

/// Tests for the settings value types the layout depends on. These pin the fraction
/// tables `AxisLayout.make` consumes and the raw values `SettingsStore` persists to
/// `UserDefaults` (reordering cases would silently break saved prefs).
@Suite struct SnapProfileTests {

    @Test func fractionsPinned() {
        // Bind to typed locals: `#expect`'s macro expansion can't type-check a
        // CGFloat-array literal compared inline in reasonable time.
        let quarters: [CGFloat] = [1.0 / 4, 1.0 / 2, 3.0 / 4]
        let sixths: [CGFloat] = [1.0 / 6, 2.0 / 6, 3.0 / 6, 4.0 / 6, 5.0 / 6]
        let both: [CGFloat] = [1.0 / 6, 1.0 / 4, 1.0 / 3, 1.0 / 2, 2.0 / 3, 3.0 / 4, 5.0 / 6]
        #expect(SnapProfile.quarters.availableFractions == quarters)
        #expect(SnapProfile.sixths.availableFractions == sixths)
        #expect(SnapProfile.both.availableFractions == both)
    }

    /// `AxisLayout.make` requires fractions to be unique, sorted, and strictly inside
    /// `(0, 1)` — `Dictionary(uniqueKeysWithValues:)` would trap on a duplicate.
    @Test(arguments: SnapProfile.allCases)
    func fractionsAreUniqueSortedInUnitInterval(_ profile: SnapProfile) {
        let fractions = profile.availableFractions
        #expect(!fractions.isEmpty)
        #expect(Set(fractions).count == fractions.count, "unique")
        #expect(fractions == fractions.sorted(), "sorted")
        #expect(fractions.allSatisfy { $0 > 0 && $0 < 1 }, "in (0,1)")
    }

    @Test func snapProfileRawValuesPinned() {
        #expect(SnapProfile.quarters.rawValue == 0)
        #expect(SnapProfile.sixths.rawValue == 1)
        #expect(SnapProfile.both.rawValue == 2)
        let allCases: [SnapProfile] = [.quarters, .sixths, .both]
        #expect(SnapProfile.allCases == allCases)
    }

    @Test func peekSizePointsPinned() {
        #expect(PeekSizePreset.small.points == 4)
        #expect(PeekSizePreset.medium.points == 8)
        #expect(PeekSizePreset.large.points == 12)
    }

    @Test func peekSizeRawValuesPinned() {
        #expect(PeekSizePreset.small.rawValue == 0)
        #expect(PeekSizePreset.medium.rawValue == 1)
        #expect(PeekSizePreset.large.rawValue == 2)
        let allCases: [PeekSizePreset] = [.small, .medium, .large]
        #expect(PeekSizePreset.allCases == allCases)
    }

    @Test func peekSizePointsAreIncreasingAndPositive() {
        let points = PeekSizePreset.allCases.map { $0.points }
        #expect(points == points.sorted())
        #expect(points.allSatisfy { $0 > 0 })
    }
}
