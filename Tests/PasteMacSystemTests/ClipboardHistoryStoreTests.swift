import Foundation
import Testing
@testable import PasteMacSystem
import PasteCore

@Test func historyStoreKeepsNewestItemFirstAndCapsCapacity() {
    let store = ClipboardHistoryStore(capacity: 2)
    let first = makeItem(summary: "first", signature: "text:first", seconds: 1)
    let second = makeItem(summary: "second", signature: "text:second", seconds: 2)
    let third = makeItem(summary: "third", signature: "text:third", seconds: 3)

    store.insert(first)
    store.insert(second)
    store.insert(third)

    #expect(store.items.map(\.summary) == ["third", "second"])
}

@Test func historyStoreMovesDuplicateToFrontInsteadOfGrowing() {
    let store = ClipboardHistoryStore(capacity: 10)
    let original = makeItem(summary: "original", signature: "text:same", seconds: 1)
    let laterDuplicate = makeItem(summary: "later", signature: "text:same", seconds: 2)
    let other = makeItem(summary: "other", signature: "text:other", seconds: 3)

    store.insert(original)
    store.insert(other)
    store.insert(laterDuplicate)

    #expect(store.items.map(\.summary) == ["later", "other"])
    #expect(store.items.count == 2)
}

@Test func clipboardMonitorOnlyProcessesNewPasteboardChangesAndSkipsOwnWrites() {
    let source = FakeClipboardSource()
    let store = ClipboardHistoryStore(capacity: 10)
    let classifier = ClipboardClassifier()
    let monitor = ClipboardMonitor(source: source, classifier: classifier, historyStore: store)

    source.changeCount = 1
    source.payloads = [ClipboardPayload(typeIdentifier: PasteboardTypeIdentifier.plainText, data: Data("first".utf8))]
    monitor.poll(createdAt: Date(timeIntervalSince1970: 1))
    monitor.poll(createdAt: Date(timeIntervalSince1970: 2))

    let firstSignature = store.items[0].signature
    source.changeCount = 2
    source.payloads = [ClipboardPayload(typeIdentifier: PasteboardTypeIdentifier.plainText, data: Data("self".utf8))]
    monitor.markSelfWrite(signature: ClipboardSignature.make(kind: .text, payloads: source.payloads))
    monitor.poll(createdAt: Date(timeIntervalSince1970: 3))

    source.changeCount = 3
    source.payloads = [ClipboardPayload(typeIdentifier: PasteboardTypeIdentifier.plainText, data: Data("second".utf8))]
    monitor.poll(createdAt: Date(timeIntervalSince1970: 4))

    #expect(firstSignature.hasPrefix("text:"))
    #expect(store.items.map(\.summary) == ["second", "first"])
}

@Test func clipboardMonitorClearsStaleSelfWriteAfterOneObservedChange() {
    let source = FakeClipboardSource()
    let store = ClipboardHistoryStore(capacity: 10)
    let classifier = ClipboardClassifier()
    let monitor = ClipboardMonitor(source: source, classifier: classifier, historyStore: store)
    let staleSelfPayloads = [
        ClipboardPayload(typeIdentifier: PasteboardTypeIdentifier.plainText, data: Data("self".utf8))
    ]

    monitor.markSelfWrite(signature: ClipboardSignature.make(kind: .text, payloads: staleSelfPayloads))

    source.changeCount = 1
    source.payloads = [ClipboardPayload(typeIdentifier: PasteboardTypeIdentifier.plainText, data: Data("external".utf8))]
    monitor.poll(createdAt: Date(timeIntervalSince1970: 1))

    source.changeCount = 2
    source.payloads = staleSelfPayloads
    monitor.poll(createdAt: Date(timeIntervalSince1970: 2))

    #expect(store.items.map(\.summary) == ["self", "external"])
}

private final class FakeClipboardSource: ClipboardPayloadSource {
    var changeCount = 0
    var payloads: [ClipboardPayload] = []

    func currentChangeCount() -> Int {
        changeCount
    }

    func currentPayloads() -> [ClipboardPayload] {
        payloads
    }
}

private func makeItem(summary: String, signature: String, seconds: TimeInterval) -> ClipboardItem {
    ClipboardItem(
        kind: .text,
        summary: summary,
        createdAt: Date(timeIntervalSince1970: seconds),
        signature: signature,
        payloads: [
            ClipboardPayload(typeIdentifier: PasteboardTypeIdentifier.plainText, data: Data(summary.utf8))
        ]
    )
}
