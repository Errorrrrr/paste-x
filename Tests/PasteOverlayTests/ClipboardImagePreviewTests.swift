import AppKit
import Foundation
import PasteCore
@testable import PasteOverlay
import Testing

@Test func imagePreviewDecodesFirstRenderableImagePayload() throws {
    let payload = ClipboardPayload(
        typeIdentifier: "public.png",
        data: try makePNGData(width: 4, height: 3)
    )

    let preview = try #require(ClipboardImagePreview.make(from: [payload]))

    #expect(preview.image.isValid)
    #expect(preview.pixelSize == ClipboardImagePixelSize(width: 4, height: 3))
}

@Test func imagePreviewSkipsInvalidPayloads() throws {
    let preview = ClipboardImagePreview.make(from: [
        ClipboardPayload(typeIdentifier: "public.png", data: Data([0x89, 0x50, 0x4E, 0x47])),
        ClipboardPayload(typeIdentifier: "public.utf8-plain-text", data: Data("not an image".utf8))
    ])

    #expect(preview == nil)
}

private func makePNGData(width: Int, height: Int) throws -> Data {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))

    bitmap.setColor(NSColor(deviceRed: 0.1, green: 0.75, blue: 0.35, alpha: 1), atX: 0, y: 0)
    return try #require(bitmap.representation(using: .png, properties: [:]))
}
