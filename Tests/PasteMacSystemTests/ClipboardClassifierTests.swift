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

@Test func classifierIgnoresEmptyPayloads() {
    let classifier = ClipboardClassifier()

    let item = classifier.makeItem(from: [], createdAt: Date(timeIntervalSince1970: 30))

    #expect(item == nil)
}
