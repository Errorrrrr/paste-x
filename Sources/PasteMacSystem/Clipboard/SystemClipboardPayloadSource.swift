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
        var payloads = pasteboard.pasteboardItems?.flatMap(Self.payloads(from:)) ?? []
        let hasFileURL = payloads.contains { $0.typeIdentifier == PasteboardTypeIdentifier.fileURL }
        let hasImageType = payloads.contains { ClipboardClassifier.isImageType($0.typeIdentifier) }

        if !payloads.contains(where: { $0.typeIdentifier == PasteboardTypeIdentifier.png }),
           (!hasFileURL || hasImageType),
           let imagePayload = Self.imagePreviewPayload(from: pasteboard) {
            payloads.append(imagePayload)
        }

        return payloads.sorted { lhs, rhs in
            let lhsPriority = Self.priority(for: lhs.typeIdentifier)
            let rhsPriority = Self.priority(for: rhs.typeIdentifier)
            if lhsPriority == rhsPriority {
                return lhs.typeIdentifier < rhs.typeIdentifier
            }

            return lhsPriority < rhsPriority
        }
    }

    private static func payloads(from item: NSPasteboardItem) -> [ClipboardPayload] {
        item.types.compactMap { type in
            item.data(forType: type).map {
                ClipboardPayload(typeIdentifier: type.rawValue, data: $0)
            }
        }
    }

    private static func imagePreviewPayload(from pasteboard: NSPasteboard) -> ClipboardPayload? {
        guard let image = NSImage(pasteboard: pasteboard), image.isValid else {
            return nil
        }

        guard let data = pngData(from: image) else {
            return nil
        }

        return ClipboardPayload(typeIdentifier: PasteboardTypeIdentifier.png, data: data)
    }

    private static func pngData(from image: NSImage) -> Data? {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            return bitmap.representation(using: .png, properties: [:])
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private static func priority(for typeIdentifier: String) -> Int {
        if ClipboardClassifier.isImageType(typeIdentifier) {
            return 0
        }

        if typeIdentifier == PasteboardTypeIdentifier.fileURL {
            return 1
        }

        if typeIdentifier == PasteboardTypeIdentifier.url {
            return 2
        }

        if typeIdentifier == PasteboardTypeIdentifier.plainText
            || typeIdentifier == PasteboardTypeIdentifier.legacyPlainText {
            return 3
        }

        return 4
    }
}
