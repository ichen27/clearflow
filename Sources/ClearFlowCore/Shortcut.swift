import Foundation

/// Physical key codes, independent of typed characters and transient modifier flags.
public struct Shortcut: Codable, Equatable {
    public struct Modifiers: OptionSet, Codable, Equatable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let control = Self(rawValue: 1)
        public static let option = Self(rawValue: 2)
        public static let shift = Self(rawValue: 4)
        public static let command = Self(rawValue: 8)
    }
    public var keyCode: UInt32
    public var modifiers: Modifiers
    public init(keyCode: UInt32, modifiers: Modifiers) { self.keyCode = keyCode; self.modifiers = modifiers }
    public static let fn = Self(keyCode: 63, modifiers: [])
    public var isFn: Bool { self == .fn }
    public static let `default` = Self(keyCode: 49, modifiers: [.option, .shift])
    public static let keys: [(code: UInt32, name: String)] = [
        (49, "Space"), (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"),
        (5, "G"), (4, "H"), (34, "I"), (38, "J"), (40, "K"), (37, "L"), (46, "M"),
        (45, "N"), (31, "O"), (35, "P"), (12, "Q"), (15, "R"), (1, "S"), (17, "T"),
        (32, "U"), (9, "V"), (13, "W"), (7, "X"), (16, "Y"), (6, "Z"),
        (29, "0"), (18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"),
        (22, "6"), (26, "7"), (28, "8"), (25, "9"),
        (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"), (96, "F5"), (97, "F6"),
        (98, "F7"), (100, "F8"), (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12")
    ]
    public var isValid: Bool {
        if isFn { return true }
        return modifiers.rawValue & ~UInt32(15) == 0 &&
        !modifiers.intersection([.control, .option, .command]).isEmpty &&
        Self.keys.contains { $0.code == keyCode }
    }
    public var keycaps: [String] {
        if isFn { return ["Fn"] }
        var labels: [String] = []
        if modifiers.contains(.control) { labels.append("⌃") }
        if modifiers.contains(.option) { labels.append("⌥") }
        if modifiers.contains(.shift) { labels.append("⇧") }
        if modifiers.contains(.command) { labels.append("⌘") }
        labels.append(Self.keys.first { $0.code == keyCode }?.name ?? "Unknown")
        return labels
    }
    public var display: String { keycaps.joined(separator: " ") }
    public var encoded: Data? { try? JSONEncoder().encode(self) }
    public static func load(_ data: Data?) -> Self {
        guard let data, let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return .default }
        return value
    }
}
