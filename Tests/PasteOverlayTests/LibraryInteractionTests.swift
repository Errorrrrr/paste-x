import Foundation
import Testing
import PasteCore
@testable import PasteOverlay

private func textItem(_ text: String) -> ClipboardItem {
    let payloads = [ClipboardPayload(typeIdentifier: "public.utf8-plain-text", data: Data(text.utf8))]
    return ClipboardItem(kind: .text, summary: String(text.prefix(120)), createdAt: Date(),
                         signature: ClipboardSignature.make(kind: .text, payloads: payloads), payloads: payloads)
}

@MainActor
@Test func searchFindsFullTextLabelsApplicationsAndOCRWithCombinedFilters() {
    var item = textItem(String(repeating: "a", count: 150) + "needle")
    item.label = "工作"; item.sourceAppName = "Editor"; item.sourceBundleID = "test.editor"
    item.isPinned = true; item.extractedText = "图片文字"
    let store = OverlaySelectionStore(items: [item, textItem("other")])
    for query in ["needle", "工作", "editor", "图片文字"] {
        store.updateSearchQuery(query)
        #expect(store.visibleItems.map(\.id) == [item.id])
    }
    store.kindFilter = .file
    #expect(store.visibleItems.isEmpty)
    #expect(store.selectedItem == nil)
    store.kindFilter = .text; store.pinnedOnly = true; store.sourceFilter = "test.editor"
    #expect(store.visibleItems.map(\.id) == [item.id])
}

@MainActor
@Test func queueOnlyAdvancesAfterSuccessfulPasteAndDeletionRemovesStaleIDs() throws {
    let first = textItem("first"), second = textItem("second")
    let store = OverlaySelectionStore(items: [first, second])
    store.selectedIDs = [first.id, second.id]
    store.enqueueSelection(); store.enqueueSelection()
    #expect(store.queueIDs == [first.id, second.id])
    let request = try #require(store.queueRequest())
    store.completePaste(request, succeeded: false)
    #expect(store.queueIDs == [first.id, second.id])
    store.completePaste(request, succeeded: true)
    #expect(store.queueIDs == [second.id])
    store.syncLibrary(items: [], groups: [], settings: ClipboardLibrarySettings(), error: nil)
    #expect(store.queueIDs.isEmpty)
    #expect(store.selectedIDs.isEmpty)
}

@MainActor
@Test func multiSelectMergeUsesVisibleOrderAndDoesNotMutateOriginalItems() throws {
    let first = textItem("first"), second = textItem("second")
    let store = OverlaySelectionStore(items: [first, second])
    store.selectedIDs = [second.id, first.id]
    let request = try #require(store.mergedRequest())
    #expect(request.item.textContent == "first\nsecond")
    #expect(request.item.id != first.id)
    #expect(store.items == [first, second])
}

@Test func textTransformHandlesJSONUnicodeAndInvalidInput() throws {
    #expect(try ClipboardTextTransform.decodeURL.apply(to: ClipboardTextTransform.encodeURL.apply(to: "你好 /a?b=1")) == "你好 /a?b=1")
    #expect(try ClipboardTextTransform.trimWhitespace.apply(to: "  a \n b  \n") == "a\nb")
    let result = try ClipboardTextTransform.formatJSON.apply(to: "{\"b\":2,\"a\":1}")
    #expect(result.contains("\n"))
    #expect(throws: (any Error).self) { try ClipboardTextTransform.formatJSON.apply(to: "{bad") }
    #expect(throws: (any Error).self) { try ClipboardTextTransform.decodeURL.apply(to: "%ZZ") }
}

@MainActor
@Test func filterChangesAlwaysSelectAVisibleResult() {
    let first = textItem("first")
    var second = textItem("second"); second.isPinned = true
    let store = OverlaySelectionStore(items: [first, second])
    store.pinnedOnly = true
    #expect(store.selectedItemID == second.id)
    store.kindFilter = .image
    #expect(store.selectedItemID == nil)
    store.resetFilters()
    #expect(store.selectedItemID == second.id) // Clearing filters preserves a still-visible selection.
}


@MainActor
@Test func numberedShortcutAndPlainTextModifierProduceCorrectPasteRequests() async {
    let first = textItem("first"), second = textItem("second")
    let store = OverlaySelectionStore(items: [first, second])
    var requests: [OverlayPasteRequest] = []
    let controller = OverlayWindowController(store: store, onPasteRequested: { requests.append($0) })
    #expect(controller.handleKeyboardEvent(OverlayKeyboardEvent(keyCode: 19, modifiers: [.command], characters: "2", isRepeat: false)))
    await Task.yield()
    #expect(requests.first?.item.id == second.id)
    #expect(controller.handleKeyboardEvent(OverlayKeyboardEvent(keyCode: 36, modifiers: [.shift], characters: "\\r", isRepeat: false)))
    await Task.yield()
    #expect(requests.last?.plainText == true)
    #expect(requests.last?.item.id == second.id)
}
