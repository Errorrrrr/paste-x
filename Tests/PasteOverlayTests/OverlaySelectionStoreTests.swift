import Foundation
import PasteCore
@testable import PasteOverlay
import Testing

@MainActor
@Test func selectionDefaultsToFirstItemAndMovesWithinBounds() throws {
    let items = OverlayMockData.items(referenceDate: Date(timeIntervalSince1970: 100))
    let store = OverlaySelectionStore(items: Array(items.prefix(3)))

    #expect(store.selectedItem?.id == items[0].id)

    store.selectNext()
    #expect(store.selectedItem?.id == items[1].id)

    store.selectNext()
    store.selectNext()
    #expect(store.selectedItem?.id == items[2].id)

    store.selectPrevious()
    #expect(store.selectedItem?.id == items[1].id)
}

@MainActor
@Test func selectionRefreshPreservesVisibleSelectionOrFallsBackToFirst() throws {
    let items = OverlayMockData.items(referenceDate: Date(timeIntervalSince1970: 200))
    let store = OverlaySelectionStore(items: Array(items.prefix(3)))
    store.select(id: items[1].id)

    store.replaceItems([items[2], items[1], items[0]])
    #expect(store.selectedItem?.id == items[1].id)

    store.replaceItems([items[3], items[4]])
    #expect(store.selectedItem?.id == items[3].id)

    store.replaceItems([])
    #expect(store.selectedItem == nil)
}

@MainActor
@Test func pasteRequestReturnsSelectedItemAndTrigger() throws {
    let items = OverlayMockData.items(referenceDate: Date(timeIntervalSince1970: 300))
    let store = OverlaySelectionStore(items: Array(items.prefix(2)))
    store.select(id: items[1].id)

    let request = store.makePasteRequest(trigger: .returnKey)

    #expect(request?.item == items[1])
    #expect(request?.trigger == .returnKey)
}

@Test func mockDataCoversEveryRenderableKindWithPayloads() throws {
    let items = OverlayMockData.items(referenceDate: Date(timeIntervalSince1970: 400))
    let kinds = Set(items.map(\.kind))

    #expect(kinds == Set(ClipboardKind.allCases))
    #expect(items.allSatisfy { !$0.summary.isEmpty })
    #expect(items.allSatisfy { !$0.signature.isEmpty })
    #expect(items.allSatisfy { !$0.payloads.isEmpty })
}
