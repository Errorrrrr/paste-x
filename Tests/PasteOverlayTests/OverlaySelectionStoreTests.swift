import Foundation
import PasteCore
@testable import PasteOverlay
import Testing

@Test func menuActionContractUsesFrontendCaseNamesAndRawValues() throws {
    #expect(OverlayMenuAction.settings.rawValue == "settings")
    #expect(OverlayMenuAction.close.rawValue == "close")
    #expect(OverlayMenuAction.quit.rawValue == "quit")
}

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
@Test func selectingCurrentItemDoesNotPublishRedundantSelectionChange() throws {
    let items = OverlayMockData.items(referenceDate: Date(timeIntervalSince1970: 150))
    let store = OverlaySelectionStore(items: Array(items.prefix(2)))
    var changeCount = 0
    let cancellable = store.objectWillChange.sink {
        changeCount += 1
    }

    store.select(id: items[0].id)
    #expect(changeCount == 0)

    store.select(id: items[1].id)
    #expect(changeCount == 1)

    _ = cancellable
}

@MainActor
@Test func selectionRefreshResetsToFirstItemOnEveryPresentation() throws {
    let items = OverlayMockData.items(referenceDate: Date(timeIntervalSince1970: 200))
    let store = OverlaySelectionStore(items: Array(items.prefix(3)))
    store.select(id: items[1].id)
    let initialRevision = store.presentationRevision

    store.replaceItems([items[2], items[1], items[0]])
    #expect(store.selectedItem?.id == items[2].id)
    #expect(store.presentationRevision == initialRevision + 1)

    store.replaceItems([items[3], items[4]])
    #expect(store.selectedItem?.id == items[3].id)
    #expect(store.presentationRevision == initialRevision + 2)

    store.replaceItems([])
    #expect(store.selectedItem == nil)
    #expect(store.presentationRevision == initialRevision + 3)
}

@MainActor
@Test func presentationScrollTargetsContentLeadingInsetInsteadOfFirstItem() throws {
    let items = Array(OverlayMockData.items(referenceDate: Date(timeIntervalSince1970: 225)).prefix(2))
    let policy = OverlayPresentationScrollPolicy()

    let target = policy.initialTarget(visibleItems: items)

    #expect(OverlayContentLayout.itemStripHorizontalInset > 0)
    #expect(target == .contentLeadingInset)
    #expect(target != .item(items[0].id))
    #expect(policy.animatesInitialScroll == false)
    #expect(policy.scrollViewIdentity(presentationRevision: 1) != policy.scrollViewIdentity(presentationRevision: 2))
}

@MainActor
@Test func presentationRefreshDoesNotRequestSelectionScrollFromResetSelection() throws {
    let items = OverlayMockData.items(referenceDate: Date(timeIntervalSince1970: 250))
    let store = OverlaySelectionStore(items: Array(items.prefix(3)))
    store.select(id: items[2].id)

    store.replaceItems(Array(items.prefix(3)))

    let request = OverlaySelectionScrollPolicy(mouseSelectionDelay: 0.5).scrollRequest(
        for: store.selectedItemID,
        source: store.lastSelectionSource
    )
    #expect(store.selectedItemID == items[0].id)
    #expect(store.lastSelectionSource == .presentation)
    #expect(request == nil)
}

@MainActor
@Test func selectionScrollRequestsMinimalVisibilityInsteadOfCentering() throws {
    let itemID = OverlayMockData.items(referenceDate: Date(timeIntervalSince1970: 275))[2].id
    let request = OverlaySelectionScrollPolicy(mouseSelectionDelay: 0.5).scrollRequest(
        for: itemID,
        source: .automatic
    )

    #expect(request?.itemID == itemID)
    #expect(request?.delay == 0)
    #expect(request?.alignment == .minimalVisibility)
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

@MainActor
@Test func searchFiltersItemsAndKeepsSelectionInsideResults() throws {
    let items = OverlayMockData.items(referenceDate: Date(timeIntervalSince1970: 325))
    let store = OverlaySelectionStore(items: Array(items.prefix(4)))

    store.updateSearchQuery("https")

    #expect(store.isSearching)
    #expect(store.visibleItems.map(\.kind) == [.url])
    #expect(store.selectedItem?.kind == .url)

    store.updateSearchQuery("missing-value")
    #expect(store.visibleItems.isEmpty)
    #expect(store.selectedItem == nil)

    store.deactivateSearch()
    #expect(store.visibleItems.count == 4)
    #expect(store.selectedItem?.id == items[0].id)
}

@MainActor
@Test func directTypingCanPrefillSearchAndRefreshClearsSearchMode() throws {
    let items = OverlayMockData.items(referenceDate: Date(timeIntervalSince1970: 330))
    let store = OverlaySelectionStore(items: Array(items.prefix(3)))

    store.activateSearch(prefill: "im")
    store.appendSearchText("age")

    #expect(store.searchQuery == "image")
    #expect(store.visibleItems.map(\.kind) == [.image])

    store.replaceItems(Array(items.suffix(2)))
    #expect(!store.isSearching)
    #expect(store.searchQuery.isEmpty)
    #expect(store.visibleItems == Array(items.suffix(2)))
}

@MainActor
@Test func feedbackMessageCanBeShownClearedAndResetsWhenItemsRefresh() throws {
    let items = OverlayMockData.items(referenceDate: Date(timeIntervalSince1970: 350))
    let store = OverlaySelectionStore(items: Array(items.prefix(2)))

    store.showFeedback("Copied to clipboard")
    #expect(store.feedbackMessage == "Copied to clipboard")

    store.clearFeedback()
    #expect(store.feedbackMessage == nil)

    store.showFeedback("Copied again")
    store.replaceItems([items[2]])
    #expect(store.feedbackMessage == nil)
}

@Test func mockDataCoversEveryRenderableKindWithPayloads() throws {
    let items = OverlayMockData.items(referenceDate: Date(timeIntervalSince1970: 400))
    let kinds = Set(items.map(\.kind))

    #expect(kinds == Set(ClipboardKind.allCases))
    #expect(items.allSatisfy { !$0.summary.isEmpty })
    #expect(items.allSatisfy { !$0.signature.isEmpty })
    #expect(items.allSatisfy { !$0.payloads.isEmpty })
}
