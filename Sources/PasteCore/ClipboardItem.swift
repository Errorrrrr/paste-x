import Foundation

public struct ClipboardItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ClipboardKind
    public let summary: String
    public let createdAt: Date
    public let signature: String
    public let payloads: [ClipboardPayload]

    public init(
        id: UUID = UUID(),
        kind: ClipboardKind,
        summary: String,
        createdAt: Date,
        signature: String,
        payloads: [ClipboardPayload]
    ) {
        self.id = id
        self.kind = kind
        self.summary = summary
        self.createdAt = createdAt
        self.signature = signature
        self.payloads = payloads
    }
}
