import AppKit
import Security
import ClearFlowCore

struct AppSettings {
    static let defaults = UserDefaults.standard
    static var shortcut: Shortcut {
        get { Shortcut.load(defaults.data(forKey: "dictationShortcut")) }
        set { defaults.set(newValue.encoded, forKey: "dictationShortcut") }
    }
    static var endpoint: String {
        get { defaults.string(forKey: "endpoint") ?? (Bundle.main.object(forInfoDictionaryKey: "ClearFlowEndpoint") as? String ?? "http://127.0.0.1:8768") }
        set { defaults.set(newValue, forKey: "endpoint") }
    }
    static var vocabulary: String {
        get { defaults.string(forKey: "vocabulary") ?? "" }
        set { defaults.set(newValue, forKey: "vocabulary") }
    }
    static var language: String {
        get { defaults.string(forKey: "language") ?? "" }
        set { defaults.set(newValue, forKey: "language") }
    }
    static var saveHistory: Bool {
        get { defaults.bool(forKey: "saveHistory") }
        set { defaults.set(newValue, forKey: "saveHistory") }
    }
}

enum TokenStore {
    static let service = "org.clearflow.app"
    static let account = "service-token"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ token: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        let value = Data(token.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = value
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AppError.message("Could not save the token in Keychain (\(status)).") }
    }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}

struct Transcript: Identifiable, Codable {
    let id: UUID
    let date: Date
    let text: String
    let target: String
}

enum HistoryStore {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClearFlow/history.json")
    }
    static func load() -> [Transcript] {
        guard AppSettings.saveHistory, let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([Transcript].self, from: data) else { return [] }
        return Array(items.prefix(50))
    }
    static func save(_ items: [Transcript]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(Array(items.prefix(50)))
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
