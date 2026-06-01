import AppKit
import Foundation
import Testing
@testable import PasteMacSystem
import PasteCore

@Test func classifierDetectsUrlsBeforePlainText() throws {
    let classifier = ClipboardClassifier()
    let payload = ClipboardPayload(
        typeIdentifier: PasteboardTypeIdentifier.plainText,
        data: Data("https://example.com/articles?id=1".utf8)
    )

    let item = try #require(classifier.makeItem(from: [payload], createdAt: Date(timeIntervalSince1970: 10)))

    #expect(item.kind == .url)
    #expect(item.summary == "https://example.com/articles?id=1")
    #expect(item.signature.hasPrefix("url:"))
}

@Test func classifierBuildsFileImageTextAndUnknownSummaries() throws {
    let classifier = ClipboardClassifier()
    let createdAt = Date(timeIntervalSince1970: 20)

    let file = try #require(classifier.makeItem(
        from: [
            ClipboardPayload(
                typeIdentifier: PasteboardTypeIdentifier.fileURL,
                data: Data("file:///Users/example/Report.pdf".utf8)
            )
        ],
        createdAt: createdAt
    ))
    let image = try #require(classifier.makeItem(
        from: [
            ClipboardPayload(
                typeIdentifier: PasteboardTypeIdentifier.png,
                data: Data([0x89, 0x50, 0x4E, 0x47])
            )
        ],
        createdAt: createdAt
    ))
    let text = try #require(classifier.makeItem(
        from: [
            ClipboardPayload(
                typeIdentifier: PasteboardTypeIdentifier.plainText,
                data: Data("  hello clipboard  ".utf8)
            )
        ],
        createdAt: createdAt
    ))
    let unknown = try #require(classifier.makeItem(
        from: [
            ClipboardPayload(
                typeIdentifier: "com.example.custom",
                data: Data([1, 2, 3])
            )
        ],
        createdAt: createdAt
    ))

    #expect(file.kind == .file)
    #expect(file.summary == "Report.pdf")
    #expect(image.kind == .image)
    #expect(image.summary == "Image")
    #expect(text.kind == .text)
    #expect(text.summary == "hello clipboard")
    #expect(unknown.kind == .unknown)
    #expect(unknown.summary == "Unsupported clipboard data")
}

@Test func classifierIncludesImageDimensionsWhenImagePayloadCanDecode() throws {
    let classifier = ClipboardClassifier()
    let createdAt = Date(timeIntervalSince1970: 25)
    let payload = ClipboardPayload(
        typeIdentifier: PasteboardTypeIdentifier.png,
        data: try makePNGData(width: 3, height: 2)
    )

    let item = try #require(classifier.makeItem(from: [payload], createdAt: createdAt))

    #expect(item.kind == .image)
    #expect(item.summary == "Image 3 x 2")
    #expect(item.signature.hasPrefix("image:"))
}

@Test func classifierTreatsUTTypeImagesAsImagesBeforeText() throws {
    let classifier = ClipboardClassifier()
    let createdAt = Date(timeIntervalSince1970: 26)
    let item = try #require(classifier.makeItem(
        from: [
            ClipboardPayload(
                typeIdentifier: PasteboardTypeIdentifier.plainText,
                data: Data("https://example.com/image.png".utf8)
            ),
            ClipboardPayload(
                typeIdentifier: "public.heif",
                data: Data([1, 2, 3])
            )
        ],
        createdAt: createdAt
    ))

    #expect(item.kind == .image)
    #expect(item.summary == "Image")
    #expect(item.signature.hasPrefix("image:"))
}

@Test func systemClipboardPayloadSourceAddsPngPreviewForPasteboardImages() throws {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasteXTests.\(UUID().uuidString)"))
    pasteboard.clearContents()
    let image = try makeImage(width: 4, height: 3)

    #expect(pasteboard.writeObjects([image]))

    let source = SystemClipboardPayloadSource(pasteboard: pasteboard)
    let payloads = source.currentPayloads()
    let item = try #require(ClipboardClassifier().makeItem(from: payloads, createdAt: Date(timeIntervalSince1970: 27)))

    #expect(payloads.first?.typeIdentifier == PasteboardTypeIdentifier.png)
    #expect(item.kind == .image)
    #expect(item.summary == "Image 4 x 3")
}

@Test func systemClipboardPayloadSourceKeepsImageFileURLsAsFiles() throws {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasteXTests.\(UUID().uuidString)"))
    pasteboard.clearContents()
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("PasteXTests-\(UUID().uuidString)")
        .appendingPathExtension("png")
    try makePNGData(width: 2, height: 2).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    #expect(pasteboard.writeObjects([fileURL as NSURL]))

    let source = SystemClipboardPayloadSource(pasteboard: pasteboard)
    let payloads = source.currentPayloads()
    let item = try #require(ClipboardClassifier().makeItem(from: payloads, createdAt: Date(timeIntervalSince1970: 28)))

    #expect(payloads.contains { $0.typeIdentifier == PasteboardTypeIdentifier.png } == false)
    #expect(item.kind == .file)
    #expect(item.summary == fileURL.lastPathComponent)
}

@Test func classifierIgnoresEmptyPayloads() {
    let classifier = ClipboardClassifier()

    let item = classifier.makeItem(from: [], createdAt: Date(timeIntervalSince1970: 30))

    #expect(item == nil)
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

    bitmap.setColor(NSColor(deviceRed: 0.1, green: 0.35, blue: 0.95, alpha: 1), atX: 0, y: 0)
    return try #require(bitmap.representation(using: .png, properties: [:]))
}

private func makeImage(width: Int, height: Int) throws -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
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

    bitmap.setColor(NSColor(deviceRed: 0.95, green: 0.25, blue: 0.15, alpha: 1), atX: 0, y: 0)
    let pngData = try #require(bitmap.representation(using: .png, properties: [:]))
    image.addRepresentation(try #require(NSBitmapImageRep(data: pngData)))
    return image
}
