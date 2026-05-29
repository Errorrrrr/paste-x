import Foundation
import PasteCore

public final class ClipboardHistoryStore: ClipboardHistoryProviding {
    private let capacity: Int

    public private(set) var items: [ClipboardItem] = []

    public init(capacity: Int = 50) {
        self.capacity = max(1, capacity)
    }

    public func insert(_ item: ClipboardItem) {
        items.removeAll { $0.signature == item.signature }
        items.insert(item, at: 0)

        if items.count > capacity {
            items.removeSubrange(capacity..<items.count)
        }
    }

    public func clear() {
        items.removeAll()
    }
}
