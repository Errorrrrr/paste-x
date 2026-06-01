import AppKit
import Foundation
import PasteCore

struct ClipboardImagePreview {
    let image: NSImage
    let pixelSize: ClipboardImagePixelSize?

    static func make(from item: ClipboardItem) -> ClipboardImagePreview? {
        make(from: item.payloads)
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
}

struct ClipboardImagePixelSize: Equatable {
    let width: Int
    let height: Int
}
