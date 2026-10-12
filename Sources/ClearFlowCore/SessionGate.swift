import Foundation

/// Only the active recording's final result may be delivered, exactly once.
public struct SessionGate {
    public enum Phase: Equatable { case idle, recording(UUID), transcribing(UUID), completed(UUID) }
    public private(set) var phase: Phase = .idle
    public init() {}
    public mutating func begin(_ id: UUID) -> Bool {
        switch phase {
        case .idle, .completed: phase = .recording(id); return true
        default: return false
        }
    }
    public mutating func finishRecording(_ id: UUID) -> Bool {
        guard phase == .recording(id) else { return false }
        phase = .transcribing(id); return true
    }
    public mutating func acceptResult(_ id: UUID) -> Bool {
        guard phase == .transcribing(id) else { return false }
        phase = .completed(id); return true
    }
    public mutating func cancel() { phase = .idle }
}
public enum Endpoint {
    public static func validated(_ string: String) -> URL? {
        guard var c = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.scheme == "https" || (c.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host))
        else { return nil }
        while c.path.hasSuffix("/") { c.path.removeLast() }
        return c.url
    }
}

public enum PasteRestoration {
    public static func allowed(expected: String?, observed: String?, clipboardUnchanged: Bool) -> Bool {
        guard let expected else { return false }
        return clipboardUnchanged && observed == expected
    }
}

/// A fixed-size history of microphone measurements, not an idle animation.
public struct MeterHistory {
    public private(set) var samples = Array(repeating: 0.0, count: 10)
    public init() {}
    public mutating func append(_ level: Double) {
        let input = level.isFinite ? min(1, max(0, level)) : 0
        let previous = samples.last ?? 0
        let weight = input > previous ? 0.75 : 0.35
        let next = previous + (input - previous) * weight
        samples.removeFirst()
        samples.append(next < 0.035 ? 0 : next)
    }
    public mutating func reset() { samples = Array(repeating: 0, count: 10) }
}
public enum DestinationPolicy {
    public static func pid(frontmost: Int32?, previous: Int32?, own: Int32) -> Int32? {
        if let frontmost, frontmost != own { return frontmost }
        if let previous, previous != own { return previous }
        return nil
    }
    public static func failure(accessibility: Bool, hasApp: Bool, hasField: Bool, secure: Bool, editable: Bool) -> String? {
        guard accessibility else { return "Enable Accessibility for ClearFlow in System Settings to insert text automatically." }
        guard hasApp else { return "Select a text field in another app, then start with Option–Shift–Space." }
        guard hasField else { return "The selected app did not expose a focused text field. Click its editor, then start with Option–Shift–Space." }
        guard !secure else { return "Automatic insertion is disabled in password fields." }
        guard editable else { return "The focused control is not an editable text field. Click inside the editor first." }
        return nil
    }
}
