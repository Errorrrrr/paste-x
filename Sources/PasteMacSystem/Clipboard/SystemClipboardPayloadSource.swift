import AppKit
import Foundation
import PasteCore

public final class SystemClipboardPayloadSource: ClipboardPayloadSource {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func currentChangeCount() -> Int {
        pasteboard.changeCount
    }

    public func currentPayloads() -> [ClipboardPayload] {
        pasteboard.pasteboardItems?.flatMap(Self.payloads(from:)) ?? []
    }

    private static func payloads(from item: NSPasteboardItem) -> [ClipboardPayload] {
        item.types.compactMap { type in
            item.data(forType: type).map {
                ClipboardPayload(typeIdentifier: type.rawValue, data: $0)
            }
        }
    }
}
