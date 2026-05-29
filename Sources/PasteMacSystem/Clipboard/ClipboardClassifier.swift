import AppKit
import Foundation
import PasteCore

public enum PasteboardTypeIdentifier {
    public static let plainText = "public.utf8-plain-text"
    public static let legacyPlainText = "public.plain-text"
    public static let url = "public.url"
    public static let fileURL = "public.file-url"
    public static let png = "public.png"
    public static let tiff = "public.tiff"
    public static let jpeg = "public.jpeg"
    public static let heic = "public.heic"
}

public final class ClipboardClassifier: ClipboardClassifying {
    private let maxSummaryLength: Int

    public init(maxSummaryLength: Int = 120) {
        self.maxSummaryLength = maxSummaryLength
    }

    public func makeItem(from payloads: [ClipboardPayload], createdAt: Date) -> ClipboardItem? {
        guard !payloads.isEmpty else { return nil }

        let kind = detectKind(from: payloads)
        let summary = makeSummary(for: kind, payloads: payloads)
        let signature = ClipboardSignature.make(kind: kind, payloads: payloads)

        return ClipboardItem(
            kind: kind,
            summary: summary,
            createdAt: createdAt,
            signature: signature,
            payloads: payloads
        )
    }

    private func detectKind(from payloads: [ClipboardPayload]) -> ClipboardKind {
        if payloads.contains(where: { $0.typeIdentifier == PasteboardTypeIdentifier.fileURL }) {
            return .file
        }

        if payloads.contains(where: { Self.imageTypes.contains($0.typeIdentifier) }) {
            return .image
        }

        if payloads.contains(where: { $0.typeIdentifier == PasteboardTypeIdentifier.url }) {
            return .url
        }

        if let text = firstText(in: payloads), Self.looksLikeURL(text) {
            return .url
        }

        if firstText(in: payloads) != nil {
            return .text
        }

        return .unknown
    }

    private func makeSummary(for kind: ClipboardKind, payloads: [ClipboardPayload]) -> String {
        switch kind {
        case .text:
            return clippedSummary(firstText(in: payloads) ?? "Text", fallback: "Text")
        case .url:
            return clippedSummary(firstURLString(in: payloads) ?? firstText(in: payloads) ?? "URL", fallback: "URL")
        case .file:
            return clippedSummary(fileName(in: payloads) ?? "File", fallback: "File")
        case .image:
            return imageSummary(in: payloads) ?? "Image"
        case .unknown:
            return "Unsupported clipboard data"
        }
    }

    private func firstText(in payloads: [ClipboardPayload]) -> String? {
        payloads
            .first { Self.textTypes.contains($0.typeIdentifier) }
            .flatMap { String(data: $0.data, encoding: .utf8) }
    }

    private func firstURLString(in payloads: [ClipboardPayload]) -> String? {
        payloads
            .first { $0.typeIdentifier == PasteboardTypeIdentifier.url }
            .flatMap { String(data: $0.data, encoding: .utf8) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private func fileName(in payloads: [ClipboardPayload]) -> String? {
        guard let rawFile = payloads
            .first(where: { $0.typeIdentifier == PasteboardTypeIdentifier.fileURL })
            .flatMap({ String(data: $0.data, encoding: .utf8) })?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawFile.isEmpty
        else {
            return nil
        }

        if let url = URL(string: rawFile), !url.lastPathComponent.isEmpty {
            return url.lastPathComponent
        }

        return URL(fileURLWithPath: rawFile).lastPathComponent
    }

    private func imageSummary(in payloads: [ClipboardPayload]) -> String? {
        for payload in payloads where Self.imageTypes.contains(payload.typeIdentifier) {
            guard let size = Self.imagePixelSize(from: payload.data) else {
                continue
            }

            return "Image \(size.width) x \(size.height)"
        }

        return nil
    }

    private static func imagePixelSize(from data: Data) -> (width: Int, height: Int)? {
        if let bitmap = NSBitmapImageRep(data: data),
           bitmap.pixelsWide > 0,
           bitmap.pixelsHigh > 0 {
            return (bitmap.pixelsWide, bitmap.pixelsHigh)
        }

        guard let image = NSImage(data: data), image.isValid else {
            return nil
        }

        guard let representation = image.representations.first(where: { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }) else {
            return nil
        }

        return (representation.pixelsWide, representation.pixelsHigh)
    }

    private func clippedSummary(_ value: String, fallback: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let base = normalized.isEmpty ? fallback : normalized
        guard base.count > maxSummaryLength else { return base }
        return String(base.prefix(maxSummaryLength))
    }

    private static func looksLikeURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    private static let textTypes: Set<String> = [
        PasteboardTypeIdentifier.plainText,
        PasteboardTypeIdentifier.legacyPlainText
    ]

    private static let imageTypes: Set<String> = [
        PasteboardTypeIdentifier.png,
        PasteboardTypeIdentifier.tiff,
        PasteboardTypeIdentifier.jpeg,
        PasteboardTypeIdentifier.heic
    ]
}
