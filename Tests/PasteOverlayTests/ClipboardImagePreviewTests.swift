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

@Test func imagePreviewReusesCachedPreviewForSameClipboardItemSignature() throws {
    let payload = ClipboardPayload(
        typeIdentifier: "public.png",
        data: try makePNGData(width: 8, height: 6)
    )
    let item = ClipboardItem(
        kind: .image,
        summary: "8 × 6",
        createdAt: Date(timeIntervalSince1970: 10),
        signature: "image/png:cached-preview",
        payloads: [payload]
    )

    let firstPreview = try #require(ClipboardImagePreview.make(from: item))
    let secondPreview = try #require(ClipboardImagePreview.make(from: item))

    #expect(firstPreview.image === secondPreview.image)
    #expect(secondPreview.pixelSize == ClipboardImagePixelSize(width: 8, height: 6))
}

@Test func imagePreviewSkipsInvalidPayloads() throws {
    let preview = ClipboardImagePreview.make(from: [
        ClipboardPayload(typeIdentifier: "public.png", data: Data([0x89, 0x50, 0x4E, 0x47])),
        ClipboardPayload(typeIdentifier: "public.utf8-plain-text", data: Data("not an image".utf8))
    ])

    #expect(preview == nil)
}

@Test func imagePreviewDecodesFinderImageFilePayload() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("PasteXPreview-\(UUID().uuidString)")
        .appendingPathExtension("png")
    try makePNGData(width: 5, height: 4).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let preview = try #require(ClipboardImagePreview.makeFromFilePayloads([
        ClipboardPayload(typeIdentifier: "public.file-url", data: Data(fileURL.absoluteString.utf8))
    ]))

    #expect(preview.image.isValid)
    #expect(preview.pixelSize == ClipboardImagePixelSize(width: 5, height: 4))
}

@Test func imagePreviewSkipsNonImageFilePayload() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("PasteXPreview-\(UUID().uuidString)")
        .appendingPathExtension("txt")
    try Data("not an image".utf8).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let preview = ClipboardImagePreview.makeFromFilePayloads([
        ClipboardPayload(typeIdentifier: "public.file-url", data: Data(fileURL.absoluteString.utf8))
    ])

    #expect(preview == nil)
}

@Test func imagePreviewSkipsPDFFilePayload() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("PasteXPreview-\(UUID().uuidString)")
        .appendingPathExtension("pdf")
    try makePDFData().write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let preview = ClipboardImagePreview.makeFromFilePayloads([
        ClipboardPayload(typeIdentifier: "public.file-url", data: Data(fileURL.absoluteString.utf8))
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

private func makePDFData() -> Data {
    Data("""
    %PDF-1.4
    1 0 obj
    << /Type /Catalog /Pages 2 0 R >>
    endobj
    2 0 obj
    << /Type /Pages /Kids [3 0 R] /Count 1 >>
    endobj
    3 0 obj
    << /Type /Page /Parent 2 0 R /MediaBox [0 0 120 80] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>
    endobj
    4 0 obj
    << /Length 47 >>
    stream
    BT /F1 14 Tf 16 40 Td (PasteX QA PDF) Tj ET
    endstream
    endobj
    5 0 obj
    << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
    endobj
    xref
    0 6
    0000000000 65535 f
    0000000009 00000 n
    0000000058 00000 n
    0000000115 00000 n
    0000000241 00000 n
    0000000337 00000 n
    trailer
    << /Size 6 /Root 1 0 R >>
    startxref
    407
    %%EOF
    """.utf8)
}
