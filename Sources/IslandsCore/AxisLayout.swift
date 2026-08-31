import CoreGraphics

/// A single snap slot expressed as fractions of the screen along one axis:
/// `offset` is the leading edge (0 = left/top) and `size` the extent (1 = full).
public struct PositionEntry {
    public let offset: CGFloat
    public let size: CGFloat

    public init(offset: CGFloat, size: CGFloat) {
        self.offset = offset
        self.size = size
    }
}

/// Per-window snap state: which edge/center slot the window occupies on each axis,
/// plus the accordion zone it currently belongs to.
public struct WindowState {
    public var hIdx: Int
    public var vIdx: Int
    public var hCentered: Bool
    public var vCentered: Bool
    public var hCenterIdx: Int
    public var vCenterIdx: Int
    public var currentZone: String?

    /// The frame the window actually occupied after the last snap applied to it.
    /// Apps with hard minimum sizes or size quantization (Spotify, terminals) settle
    /// off-slot, so this is what distinguishes "the app refused our frame" from "the
    /// user moved the window". Cleared on zone eviction; nil until first snapped.
    public var settledFrame: CGRect?

    public init(
        hIdx: Int,
        vIdx: Int,
        hCentered: Bool = false,
        vCentered: Bool = false,
        hCenterIdx: Int = 1,
        vCenterIdx: Int = 1,
        currentZone: String? = nil,
        settledFrame: CGRect? = nil
    ) {
        self.hIdx = hIdx
        self.vIdx = vIdx
        self.hCentered = hCentered
        self.vCentered = vCentered
        self.hCenterIdx = hCenterIdx
        self.vCenterIdx = vCenterIdx
        self.currentZone = currentZone
        self.settledFrame = settledFrame
    }
}

/// The snap slots for one axis, derived purely from a `SnapProfile`.
///
/// Slot indices are 1-based to match the window-state model (`state.hIdx` etc.;
/// index 0 is unused). `edgePositions` runs leading fractions → full → trailing
/// fractions; `centerPositions` runs full → centered fractions (largest first).
/// The three maps translate an edge slot to its same-size centered counterpart
/// and back, so centering preserves the window's size.
public struct AxisLayout {
    public let edgePositions: [PositionEntry]
    public let centerPositions: [PositionEntry]
    public let edgeToCenter: [Int: Int]
    public let centerToLeading: [Int: Int]
    public let centerToTrailing: [Int: Int]
    public let fullEdgeIndex: Int

    public var maxEdgeIndex: Int {
        edgePositions.count
    }

    public init(
        edgePositions: [PositionEntry],
        centerPositions: [PositionEntry],
        edgeToCenter: [Int: Int],
        centerToLeading: [Int: Int],
        centerToTrailing: [Int: Int],
        fullEdgeIndex: Int
    ) {
        self.edgePositions = edgePositions
        self.centerPositions = centerPositions
        self.edgeToCenter = edgeToCenter
        self.centerToLeading = centerToLeading
        self.centerToTrailing = centerToTrailing
        self.fullEdgeIndex = fullEdgeIndex
    }

    public static func make(for profile: SnapProfile) -> AxisLayout {
        let fractions = profile.availableFractions
        let fullEdgeIndex = fractions.count + 1

        var edgePositions = fractions.map { PositionEntry(offset: 0, size: $0) }
        edgePositions.append(PositionEntry(offset: 0, size: 1))
        edgePositions.append(contentsOf: fractions.reversed().map { PositionEntry(offset: 1 - $0, size: $0) })

        var centerPositions = [PositionEntry(offset: 0, size: 1)]
        centerPositions.append(contentsOf: fractions.reversed().map { PositionEntry(offset: (1 - $0) / 2, size: $0) })

        let centerIndexBySize = Dictionary(uniqueKeysWithValues: fractions.reversed().enumerated().map { ($1, $0 + 2) })
        let leadingIndexBySize = Dictionary(uniqueKeysWithValues: fractions.enumerated().map { ($1, $0 + 1) })
        let trailingIndexBySize = Dictionary(uniqueKeysWithValues: fractions.reversed().enumerated().map { ($1, fullEdgeIndex + $0 + 1) })

        var edgeToCenter: [Int: Int] = [fullEdgeIndex: 1]
        var centerToLeading: [Int: Int] = [1: fullEdgeIndex]
        var centerToTrailing: [Int: Int] = [1: fullEdgeIndex]

        for fraction in fractions {
            guard let centerIndex = centerIndexBySize[fraction],
                  let leadingIndex = leadingIndexBySize[fraction],
                  let trailingIndex = trailingIndexBySize[fraction] else {
                continue
            }

            edgeToCenter[leadingIndex] = centerIndex
            edgeToCenter[trailingIndex] = centerIndex
            centerToLeading[centerIndex] = leadingIndex
            centerToTrailing[centerIndex] = trailingIndex
        }

        return AxisLayout(
            edgePositions: edgePositions,
            centerPositions: centerPositions,
            edgeToCenter: edgeToCenter,
            centerToLeading: centerToLeading,
            centerToTrailing: centerToTrailing,
            fullEdgeIndex: fullEdgeIndex
        )
    }
}
