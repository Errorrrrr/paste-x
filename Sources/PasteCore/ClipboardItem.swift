import Foundation

public struct ClipboardItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var kind: ClipboardKind
    public var summary: String
    public let createdAt: Date
    public var signature: String
    public var payloads: [ClipboardPayload]
    public var label: String
    public var isPinned: Bool
    public var groupID: UUID?
    public var sourceAppName: String?
    public var sourceBundleID: String?
    public var extractedText: String

    public init(
        id: UUID = UUID(), kind: ClipboardKind, summary: String, createdAt: Date,
        signature: String, payloads: [ClipboardPayload], label: String = "",
        isPinned: Bool = false, groupID: UUID? = nil, sourceAppName: String? = nil,
        sourceBundleID: String? = nil, extractedText: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.summary = summary
        self.createdAt = createdAt
        self.signature = signature
        self.payloads = payloads
        self.label = label
        self.isPinned = isPinned
        self.groupID = groupID
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.extractedText = extractedText
    }

    public var textContent: String {
        let texts = Dictionary(grouping: payloads, by: \.itemIndex).sorted { $0.key < $1.key }.compactMap { _, formats -> String? in
            for type in ["public.utf8-plain-text", "public.plain-text", "public.url", "public.file-url"] {
                if let p = formats.first(where: { $0.typeIdentifier == type }), let text = String(data: p.data, encoding: .utf8) { return text }
            }
            return nil
        }
        return texts.isEmpty ? extractedText : texts.joined(separator: "\n")
    }

    public var searchText: String {
        [label, summary, textContent, extractedText, sourceAppName ?? "", sourceBundleID ?? ""].joined(separator: "\n")
    }
    public var byteCount: Int { payloads.reduce(0) { $0 + $1.data.count } }
    public var displayTitle: String { label.isEmpty ? summary : label }
    public var fileURLs: [URL] {
        payloads.filter { $0.typeIdentifier == "public.file-url" }.sorted { $0.itemIndex < $1.itemIndex }
            .compactMap { String(data: $0.data, encoding: .utf8).flatMap(URL.init(string:)) }
    }

    public func replacingText(_ text: String) -> ClipboardItem {
        var item = self
        item.kind = .text
        item.payloads = [ClipboardPayload(typeIdentifier: "public.utf8-plain-text", data: Data(text.utf8))]
        item.signature = ClipboardSignature.make(kind: .text, payloads: item.payloads)
        item.summary = String(text.prefix(120))
        item.extractedText = ""
        return item
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, summary, createdAt, signature, payloads, label, isPinned, groupID, sourceAppName, sourceBundleID, extractedText
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(ClipboardKind.self, forKey: .kind)
        summary = try c.decode(String.self, forKey: .summary)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        signature = try c.decode(String.self, forKey: .signature)
        payloads = try c.decode([ClipboardPayload].self, forKey: .payloads)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
        sourceAppName = try c.decodeIfPresent(String.self, forKey: .sourceAppName)
        sourceBundleID = try c.decodeIfPresent(String.self, forKey: .sourceBundleID)
        extractedText = try c.decodeIfPresent(String.self, forKey: .extractedText) ?? ""
    }
}
