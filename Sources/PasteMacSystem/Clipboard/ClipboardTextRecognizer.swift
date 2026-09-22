import Foundation
import PasteCore
import Vision

public enum ClipboardTextRecognizer {
    public static func recognize(_ data: Data) async throws -> String {
        try await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            let handler = VNImageRequestHandler(data: data)
            try handler.perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}

/// Serial OCR keeps large clipboard bursts from launching one Vision job per image.
@MainActor
public final class ClipboardOCRIndexer {
    private weak var store: ClipboardHistoryStore?
    private var pending: [UUID] = []
    private var processed = Set<String>()
    private var task: Task<Void, Never>?
    public var onError: ((String) -> Void)?

    public init(store: ClipboardHistoryStore) { self.store = store }

    public func indexAvailableItems() {
        guard let store, store.settings.recognizeImages, !store.settings.capturePaused else { return }
        processed.formIntersection(Set(store.items.map(\.signature)))
        for item in store.items where item.kind == .image && item.extractedText.isEmpty && !processed.contains(item.signature) {
            if !pending.contains(item.id) { pending.append(item.id) }
        }
        guard task == nil, !pending.isEmpty else { return }
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            while !pending.isEmpty && !Task.isCancelled {
                let id = pending.removeFirst()
                guard let store = self.store, store.settings.recognizeImages, !store.settings.capturePaused else {
                    pending.removeAll(); return
                }
                guard let item = store.items.first(where: { $0.id == id }),
                      !processed.contains(item.signature),
                      let data = item.payloads.first(where: { $0.typeIdentifier == "public.png" })?.data
                        ?? item.payloads.first(where: { ClipboardClassifier.isImageType($0.typeIdentifier) })?.data else { continue }
                processed.insert(item.signature)
                do {
                    let text = try await ClipboardTextRecognizer.recognize(data)
                    guard !Task.isCancelled, store.settings.recognizeImages, !store.settings.capturePaused,
                          var current = store.items.first(where: { $0.id == id && $0.signature == item.signature }),
                          !text.isEmpty else { continue }
                    current.extractedText = text
                    store.apply(.update(current))
                } catch {
                    onError?("OCR 无法识别此图片 / Could not recognize this image: \(error.localizedDescription)")
                }
            }
        }
    }

    public func stop() { task?.cancel(); task = nil; pending.removeAll() }
}
