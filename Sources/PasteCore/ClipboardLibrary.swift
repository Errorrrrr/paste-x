import Foundation

public struct ClipboardGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
}

public struct ClipboardLibrarySettings: Codable, Equatable, Sendable {
    /// Zero means unlimited count/days; bytes are always bounded.
    public var historyLimit = 1000
    public var retentionDays = 30
    public var storageLimitMB = 500
    public var excludedBundleIDs: [String] = ["com.agilebits.onepassword7", "com.1password.1password", "com.bitwarden.desktop", "com.apple.Passwords"]
    public var ignoreConfidential = true
    public var capturePaused = false
    public var recognizeImages = true
    public init() {}
}

public enum ClipboardLibraryAction: Sendable {
    case update(ClipboardItem)
    case delete(Set<UUID>)
    case clearHistory
    case createGroup(String)
    case renameGroup(UUID, String)
    case deleteGroup(UUID)
    case move(UUID, before: UUID)
    case settings(ClipboardLibrarySettings)
}

public enum ClipboardTextTransform: String, CaseIterable, Sendable {
    case formatJSON, encodeURL, decodeURL, trimWhitespace
    public func apply(to text: String) throws -> String {
        switch self {
        case .formatJSON:
            let json = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
            return String(decoding: data, as: UTF8.self)
        case .encodeURL:
            return text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? text
        case .decodeURL:
            guard let result = text.removingPercentEncoding else { throw CocoaError(.formatting) }
            return result
        case .trimWhitespace:
            return text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
