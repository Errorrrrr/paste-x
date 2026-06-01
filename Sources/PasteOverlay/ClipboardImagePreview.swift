import AppKit
import Foundation
import PasteCore
import UniformTypeIdentifiers

struct ClipboardImagePreview {
    let image: NSImage
    let pixelSize: ClipboardImagePixelSize?

    private nonisolated(unsafe) static let cache = NSCache<NSString, ClipboardImagePreviewCacheEntry>()

    static func make(from item: ClipboardItem) -> ClipboardImagePreview? {
        let key = cacheKey(for: item)
        if let cachedPreview = cache.object(forKey: key)?.preview {
            return cachedPreview
        }

        guard let preview = make(from: item.payloads) else {
            return nil
        }

        cache.setObject(ClipboardImagePreviewCacheEntry(preview: preview), forKey: key)
        return preview
    }

    static func make(from payloads: [ClipboardPayload]) -> ClipboardImagePreview? {
        for payload in payloads {
            guard let image = NSImage(data: payload.data), image.isValid else {
                continue
            }

            return ClipboardImagePreview(
                image: image,
                pixelSize: pixelSize(from: payload.data, image: image)
            )
        }

        return nil
    }

    static func makeFromFilePayloads(_ payloads: [ClipboardPayload]) -> ClipboardImagePreview? {
        for payload in payloads where payload.typeIdentifier == "public.file-url" {
            guard let rawValue = String(data: payload.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !rawValue.isEmpty,
                let fileURL = fileURL(from: rawValue),
                isImageFile(fileURL),
                let image = NSImage(contentsOf: fileURL),
                image.isValid
            else {
                continue
            }

            return ClipboardImagePreview(
                image: image,
                pixelSize: pixelSize(from: image)
            )
        }

        return nil
    }

    private static func pixelSize(from data: Data, image: NSImage) -> ClipboardImagePixelSize? {
        if let bitmap = NSBitmapImageRep(data: data),
           bitmap.pixelsWide > 0,
           bitmap.pixelsHigh > 0 {
            return ClipboardImagePixelSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }

        if let representation = image.representations.first(where: { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }) {
            return ClipboardImagePixelSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }

        return nil
    }

    private static func pixelSize(from image: NSImage) -> ClipboardImagePixelSize? {
        if let representation = image.representations.first(where: { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }) {
            return ClipboardImagePixelSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }

        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        return ClipboardImagePixelSize(width: Int(size.width.rounded()), height: Int(size.height.rounded()))
    }

    private static func fileURL(from value: String) -> URL? {
        if let url = URL(string: value), url.isFileURL {
            return url
        }

        return URL(fileURLWithPath: value)
    }

    private static func isImageFile(_ fileURL: URL) -> Bool {
        if let contentType = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.conforms(to: .image)
        }

        let pathExtension = fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pathExtension.isEmpty, let type = UTType(filenameExtension: pathExtension) else {
            return false
        }

        return type.conforms(to: .image)
    }

    private static func cacheKey(for item: ClipboardItem) -> NSString {
        let payloadFingerprint = item.payloads
            .map { "\($0.typeIdentifier):\($0.data.count)" }
            .joined(separator: "|")

        return "\(item.signature)|\(payloadFingerprint)" as NSString
    }
}

struct ClipboardImagePixelSize: Equatable {
    let width: Int
    let height: Int
}

private final class ClipboardImagePreviewCacheEntry {
    let preview: ClipboardImagePreview

    init(preview: ClipboardImagePreview) {
        self.preview = preview
    }
}
