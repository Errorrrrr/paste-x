public enum PasteFallbackReason: String, Codable, Equatable, Sendable {
    case accessibilityNotTrusted
    case targetUnavailable
    case activationFailed
    case eventPostFailed
}

public enum PasteFailureReason: String, Codable, Equatable, Sendable {
    case emptyPayload
    case pasteboardWriteFailed
    case unsupportedPayload
}

public enum PasteResult: Codable, Equatable, Sendable {
    case pasted
    case copiedOnly(reason: PasteFallbackReason)
    case failed(reason: PasteFailureReason)
}
