import Foundation

public struct ClipboardPayload: Codable, Equatable, Sendable {
    public let typeIdentifier: String
    public let data: Data
    /// Formats with the same index belong to one NSPasteboardItem.
    public let itemIndex: Int

    public init(typeIdentifier: String, data: Data, itemIndex: Int = 0) {
        self.typeIdentifier = typeIdentifier
        self.data = data
        self.itemIndex = max(0, itemIndex)
    }

    private enum CodingKeys: String, CodingKey { case typeIdentifier, data, itemIndex }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        typeIdentifier = try c.decode(String.self, forKey: .typeIdentifier)
        data = try c.decode(Data.self, forKey: .data)
        itemIndex = max(0, try c.decodeIfPresent(Int.self, forKey: .itemIndex) ?? 0)
    }
}
