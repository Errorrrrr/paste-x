public enum ClipboardKind: String, CaseIterable, Codable, Equatable, Sendable {
    case text
    case url
    case image
    case file
    case unknown
}
