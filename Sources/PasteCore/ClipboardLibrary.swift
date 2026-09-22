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

    private enum CodingKeys: String, CodingKey {
        case historyLimit, retentionDays, storageLimitMB, excludedBundleIDs
        case ignoreConfidential, capturePaused, recognizeImages
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Stored preferences predate newly added options. Only absent keys get
        // defaults; an invalid existing value must not silently reset user policy.
        if values.contains(.historyLimit) { historyLimit = try values.decode(Int.self, forKey: .historyLimit) }
        if values.contains(.retentionDays) { retentionDays = try values.decode(Int.self, forKey: .retentionDays) }
        if values.contains(.storageLimitMB) { storageLimitMB = try values.decode(Int.self, forKey: .storageLimitMB) }
        if values.contains(.excludedBundleIDs) { excludedBundleIDs = try values.decode([String].self, forKey: .excludedBundleIDs) }
        if values.contains(.ignoreConfidential) { ignoreConfidential = try values.decode(Bool.self, forKey: .ignoreConfidential) }
        if values.contains(.capturePaused) { capturePaused = try values.decode(Bool.self, forKey: .capturePaused) }
        if values.contains(.recognizeImages) { recognizeImages = try values.decode(Bool.self, forKey: .recognizeImages) }
    }
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
