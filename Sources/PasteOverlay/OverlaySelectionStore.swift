import Combine
import Foundation
import PasteCore

public enum OverlayPasteTrigger: String, Codable, Equatable, Sendable {
    case returnKey
    case spaceKey
    case doubleClick
}

public struct OverlayPasteRequest: Equatable, Sendable {
    public let item: ClipboardItem
    public let trigger: OverlayPasteTrigger

    public init(item: ClipboardItem, trigger: OverlayPasteTrigger) {
        self.item = item
        self.trigger = trigger
    }
}

@MainActor
public final class OverlaySelectionStore: ObservableObject {
    @Published public private(set) var items: [ClipboardItem]
    @Published public private(set) var selectedItemID: ClipboardItem.ID?
    @Published public private(set) var feedbackMessage: String?
    @Published public private(set) var searchQuery = ""
    @Published public private(set) var isSearching = false

    public var selectedItem: ClipboardItem? {
        guard let selectedItemID else {
            return nil
        }

        return items.first { $0.id == selectedItemID }
    }

    public var visibleItems: [ClipboardItem] {
        let query = normalizedSearchQuery
        guard !query.isEmpty else {
            return items
        }

        return items.filter { item in
            item.summary.localizedCaseInsensitiveContains(query)
                || item.kind.rawValue.localizedCaseInsensitiveContains(query)
                || item.kind.searchDisplayName.localizedCaseInsensitiveContains(query)
        }
    }

    public init(items: [ClipboardItem] = []) {
        self.items = items
        self.selectedItemID = items.first?.id
    }

    public func replaceItems(_ newItems: [ClipboardItem]) {
        let previousSelection = selectedItemID
        feedbackMessage = nil
        clearSearch()
        items = newItems

        if let previousSelection, newItems.contains(where: { $0.id == previousSelection }) {
            selectedItemID = previousSelection
        } else {
            selectedItemID = newItems.first?.id
        }
    }

    public func select(id: ClipboardItem.ID) {
        guard items.contains(where: { $0.id == id }) else {
            return
        }

        selectedItemID = id
    }

    public func activateSearch(prefill: String = "") {
        isSearching = true
        if !prefill.isEmpty {
            searchQuery = prefill
        }
        normalizeSelectionForVisibleItems()
    }

    public func updateSearchQuery(_ query: String) {
        searchQuery = query
        isSearching = true
        normalizeSelectionForVisibleItems()
    }

    public func appendSearchText(_ text: String) {
        guard !text.isEmpty else { return }
        updateSearchQuery(searchQuery + text)
    }

    public func deactivateSearch() {
        clearSearch()
        normalizeSelectionForVisibleItems()
    }

    public func selectNext() {
        moveSelection(by: 1)
    }

    public func selectPrevious() {
        moveSelection(by: -1)
    }

    public func makePasteRequest(trigger: OverlayPasteTrigger) -> OverlayPasteRequest? {
        guard let selectedItem else {
            return nil
        }

        return OverlayPasteRequest(item: selectedItem, trigger: trigger)
    }

    public func showFeedback(_ message: String) {
        feedbackMessage = message
    }

    public func clearFeedback() {
        feedbackMessage = nil
    }

    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearSearch() {
        searchQuery = ""
        isSearching = false
    }

    private func normalizeSelectionForVisibleItems() {
        let visibleItems = visibleItems
        guard !visibleItems.isEmpty else {
            selectedItemID = nil
            return
        }

        if let selectedItemID, visibleItems.contains(where: { $0.id == selectedItemID }) {
            return
        }

        selectedItemID = visibleItems.first?.id
    }

    private func moveSelection(by offset: Int) {
        let selectionItems = visibleItems
        guard !selectionItems.isEmpty else {
            selectedItemID = nil
            return
        }

        guard
            let currentSelection = selectedItemID,
            let currentIndex = selectionItems.firstIndex(where: { $0.id == currentSelection })
        else {
            selectedItemID = selectionItems.first?.id
            return
        }

        let targetIndex = max(0, min(selectionItems.count - 1, currentIndex + offset))
        selectedItemID = selectionItems[targetIndex].id
    }
}

private extension ClipboardKind {
    var searchDisplayName: String {
        switch self {
        case .text:
            return "text txt 文本"
        case .url:
            return "url link 链接"
        case .image:
            return "image img 图片"
        case .file:
            return "file document 文件"
        case .unknown:
            return "unknown other 未知"
        }
    }
}
