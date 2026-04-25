import AppKit

extension Notification.Name {
    static let settingsDidChange = Notification.Name("IslandsSettingsDidChange")
}

struct ModifierSet: OptionSet, Hashable {
    let rawValue: Int

    static let control = ModifierSet(rawValue: 1 << 0)
    static let option = ModifierSet(rawValue: 1 << 1)
    static let command = ModifierSet(rawValue: 1 << 2)
    static let shift = ModifierSet(rawValue: 1 << 3)

    static let orderedCases: [ModifierSet] = [.control, .option, .command, .shift]

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        var modifiers: ModifierSet = []
        let flags = eventFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        self = modifiers
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.control) {
            flags.insert(.control)
        }
        if contains(.option) {
            flags.insert(.option)
        }
        if contains(.command) {
            flags.insert(.command)
        }
        if contains(.shift) {
            flags.insert(.shift)
        }
        return flags
    }

    var symbolString: String {
        guard !isEmpty else { return "None" }

        return Self.orderedCases.compactMap { modifier in
            guard contains(modifier) else { return nil }
            switch modifier {
            case .control: return "⌃"
            case .option: return "⌥"
            case .command: return "⌘"
            case .shift: return "⇧"
            default: return nil
            }
        }.joined()
    }

    var displayString: String {
        guard !isEmpty else { return "None" }

        return Self.orderedCases.compactMap { modifier in
            guard contains(modifier) else { return nil }
            switch modifier {
            case .control: return "Control"
            case .option: return "Option"
            case .command: return "Command"
            case .shift: return "Shift"
            default: return nil
            }
        }.joined(separator: " + ")
    }

    var isValidBaseShortcut: Bool {
        !isEmpty && rawValue != Self.all.rawValue
    }

    static var all: ModifierSet {
        [.control, .option, .command, .shift]
    }

    static func extraModifierOptions(excluding base: ModifierSet) -> [ModifierSet] {
        let available = orderedCases.filter { !base.contains($0) }
        guard !available.isEmpty else { return [] }

        var results: [ModifierSet] = []
        let combinations = 1 << available.count
        for rawMask in 1..<combinations {
            var option: ModifierSet = []
            for (index, modifier) in available.enumerated() where rawMask & (1 << index) != 0 {
                option.insert(modifier)
            }
            results.append(option)
        }

        return results.sorted {
            if $0.rawValue.nonzeroBitCount == $1.rawValue.nonzeroBitCount {
                return $0.rawValue < $1.rawValue
            }
            return $0.rawValue.nonzeroBitCount < $1.rawValue.nonzeroBitCount
        }
    }
}

enum SnapProfile: Int, CaseIterable {
    case quarters
    case sixths
    case both

    var displayName: String {
        switch self {
        case .quarters: return "Quarters"
        case .sixths: return "Sixths"
        case .both: return "Quarters + Sixths"
        }
    }

    var availableFractions: [CGFloat] {
        switch self {
        case .quarters:
            return [1.0 / 4, 1.0 / 2, 3.0 / 4]
        case .sixths:
            return [1.0 / 6, 2.0 / 6, 3.0 / 6, 4.0 / 6, 5.0 / 6]
        case .both:
            return [1.0 / 6, 1.0 / 4, 1.0 / 3, 1.0 / 2, 2.0 / 3, 3.0 / 4, 5.0 / 6]
        }
    }
}

enum PeekSizePreset: Int, CaseIterable {
    case small
    case medium
    case large

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var points: CGFloat {
        switch self {
        case .small: return 4
        case .medium: return 8
        case .large: return 12
        }
    }
}

struct AppSettingsSnapshot {
    var baseModifiers: ModifierSet
    var reverseCycleExtraModifiers: ModifierSet
    var centeredModeExtraModifiers: ModifierSet
    var snapProfile: SnapProfile
    var peekSize: PeekSizePreset

    var reverseCycleModifiers: ModifierSet {
        baseModifiers.union(reverseCycleExtraModifiers)
    }

    var centeredModeModifiers: ModifierSet {
        baseModifiers.union(centeredModeExtraModifiers)
    }
}

final class SettingsStore {
    private enum Keys {
        static let baseModifiers = "baseModifiers"
        static let reverseCycleExtraModifiers = "reverseCycleExtraModifiers"
        static let centeredModeExtraModifiers = "centeredModeExtraModifiers"
        static let snapProfile = "snapProfile"
        static let peekSize = "peekSize"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
        persist(snapshot)
    }

    var snapshot: AppSettingsSnapshot {
        let base = ModifierSet(rawValue: defaults.integer(forKey: Keys.baseModifiers))
        let reverse = ModifierSet(rawValue: defaults.integer(forKey: Keys.reverseCycleExtraModifiers))
        let centered = ModifierSet(rawValue: defaults.integer(forKey: Keys.centeredModeExtraModifiers))
        let snap = SnapProfile(rawValue: defaults.integer(forKey: Keys.snapProfile)) ?? .both
        let peek = PeekSizePreset(rawValue: defaults.integer(forKey: Keys.peekSize)) ?? .medium

        return normalizedSnapshot(
            baseModifiers: base,
            reverseCycleExtraModifiers: reverse,
            centeredModeExtraModifiers: centered,
            snapProfile: snap,
            peekSize: peek
        )
    }

    func setBaseModifiers(_ modifiers: ModifierSet) {
        guard modifiers.isValidBaseShortcut else { return }
        var updated = snapshot
        updated.baseModifiers = modifiers
        persist(updated)
    }

    func setReverseCycleExtraModifiers(_ modifiers: ModifierSet) {
        var updated = snapshot
        updated.reverseCycleExtraModifiers = modifiers
        persist(updated)
    }

    func setCenteredModeExtraModifiers(_ modifiers: ModifierSet) {
        var updated = snapshot
        updated.centeredModeExtraModifiers = modifiers
        persist(updated)
    }

    func setSnapProfile(_ profile: SnapProfile) {
        var updated = snapshot
        updated.snapProfile = profile
        persist(updated)
    }

    func setPeekSize(_ preset: PeekSizePreset) {
        var updated = snapshot
        updated.peekSize = preset
        persist(updated)
    }

    func restoreDefaults() {
        persist(Self.defaultSnapshot)
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.baseModifiers: Self.defaultSnapshot.baseModifiers.rawValue,
            Keys.reverseCycleExtraModifiers: Self.defaultSnapshot.reverseCycleExtraModifiers.rawValue,
            Keys.centeredModeExtraModifiers: Self.defaultSnapshot.centeredModeExtraModifiers.rawValue,
            Keys.snapProfile: Self.defaultSnapshot.snapProfile.rawValue,
            Keys.peekSize: Self.defaultSnapshot.peekSize.rawValue,
        ])
    }

    private func persist(_ snapshot: AppSettingsSnapshot) {
        let normalized = normalizedSnapshot(
            baseModifiers: snapshot.baseModifiers,
            reverseCycleExtraModifiers: snapshot.reverseCycleExtraModifiers,
            centeredModeExtraModifiers: snapshot.centeredModeExtraModifiers,
            snapProfile: snapshot.snapProfile,
            peekSize: snapshot.peekSize
        )

        defaults.set(normalized.baseModifiers.rawValue, forKey: Keys.baseModifiers)
        defaults.set(normalized.reverseCycleExtraModifiers.rawValue, forKey: Keys.reverseCycleExtraModifiers)
        defaults.set(normalized.centeredModeExtraModifiers.rawValue, forKey: Keys.centeredModeExtraModifiers)
        defaults.set(normalized.snapProfile.rawValue, forKey: Keys.snapProfile)
        defaults.set(normalized.peekSize.rawValue, forKey: Keys.peekSize)

        NotificationCenter.default.post(name: .settingsDidChange, object: self)
    }

    private func normalizedSnapshot(
        baseModifiers: ModifierSet,
        reverseCycleExtraModifiers: ModifierSet,
        centeredModeExtraModifiers: ModifierSet,
        snapProfile: SnapProfile,
        peekSize: PeekSizePreset
    ) -> AppSettingsSnapshot {
        let normalizedBase = baseModifiers.isValidBaseShortcut ? baseModifiers : Self.defaultSnapshot.baseModifiers
        let extraOptions = ModifierSet.extraModifierOptions(excluding: normalizedBase)

        let normalizedReverse = extraOptions.contains(reverseCycleExtraModifiers)
            ? reverseCycleExtraModifiers
            : Self.defaultReverseExtra(for: normalizedBase)

        let normalizedCentered = extraOptions.contains(centeredModeExtraModifiers)
            ? centeredModeExtraModifiers
            : Self.defaultCenteredExtra(for: normalizedBase)

        return AppSettingsSnapshot(
            baseModifiers: normalizedBase,
            reverseCycleExtraModifiers: normalizedReverse,
            centeredModeExtraModifiers: normalizedCentered,
            snapProfile: snapProfile,
            peekSize: peekSize
        )
    }

    private static let defaultSnapshot = AppSettingsSnapshot(
        baseModifiers: [.command, .option],
        reverseCycleExtraModifiers: [.shift],
        centeredModeExtraModifiers: [.control],
        snapProfile: .both,
        peekSize: .medium
    )

    private static func defaultReverseExtra(for base: ModifierSet) -> ModifierSet {
        let options = ModifierSet.extraModifierOptions(excluding: base)
        return options.first(where: { $0 == [.shift] })
            ?? options.first(where: { $0 == [.command] })
            ?? options.first
            ?? [.shift]
    }

    private static func defaultCenteredExtra(for base: ModifierSet) -> ModifierSet {
        let options = ModifierSet.extraModifierOptions(excluding: base)
        return options.first(where: { $0 == [.command] })
            ?? options.first(where: { $0 == [.shift] })
            ?? options.first
            ?? [.command]
    }
}
