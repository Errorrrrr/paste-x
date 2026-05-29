import Foundation
import PasteCore

public enum OverlayMockData {
    public static func items(referenceDate: Date = Date()) -> [ClipboardItem] {
        [
            makeItem(
                kind: .text,
                summary: "Quarterly launch notes and follow-up tasks",
                createdAt: referenceDate.addingTimeInterval(0),
                payloads: [
                    ClipboardPayload(
                        typeIdentifier: "public.utf8-plain-text",
                        data: Data("Quarterly launch notes and follow-up tasks".utf8)
                    )
                ]
            ),
            makeItem(
                kind: .url,
                summary: "https://github.com/Errorrrrr/paste",
                createdAt: referenceDate.addingTimeInterval(-60),
                payloads: [
                    ClipboardPayload(
                        typeIdentifier: "public.url",
                        data: Data("https://github.com/Errorrrrr/paste".utf8)
                    )
                ]
            ),
            makeItem(
                kind: .image,
                summary: "Screenshot 2 x 2",
                createdAt: referenceDate.addingTimeInterval(-120),
                payloads: [
                    ClipboardPayload(
                        typeIdentifier: "public.png",
                        data: sampleImagePNGData
                    )
                ]
            ),
            makeItem(
                kind: .file,
                summary: "/Users/me/Desktop/spec.pdf",
                createdAt: referenceDate.addingTimeInterval(-180),
                payloads: [
                    ClipboardPayload(
                        typeIdentifier: "public.file-url",
                        data: Data("file:///Users/me/Desktop/spec.pdf".utf8)
                    )
                ]
            ),
            makeItem(
                kind: .unknown,
                summary: "Unsupported pasteboard data",
                createdAt: referenceDate.addingTimeInterval(-240),
                payloads: [
                    ClipboardPayload(
                        typeIdentifier: "com.example.custom-pasteboard-type",
                        data: Data([0x01, 0x02, 0x03])
                    )
                ]
            )
        ]
    }

    private static func makeItem(
        kind: ClipboardKind,
        summary: String,
        createdAt: Date,
        payloads: [ClipboardPayload]
    ) -> ClipboardItem {
        ClipboardItem(
            kind: kind,
            summary: summary,
            createdAt: createdAt,
            signature: ClipboardSignature.make(kind: kind, payloads: payloads),
            payloads: payloads
        )
    }

    private static let sampleImagePNGData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAGElEQVR42mP8z8Dwn4GBgYGBgYGJAQoAHxcCAuGgeUYAAAAASUVORK5CYII=") ?? Data()
}
