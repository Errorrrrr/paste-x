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

    public var selectedItem: ClipboardItem? {
        guard let selectedItemID else {
            return nil
        }

        return items.first { $0.id == selectedItemID }
    }

    public init(items: [ClipboardItem] = []) {
        self.items = items
        self.selectedItemID = items.first?.id
    }

    public func replaceItems(_ newItems: [ClipboardItem]) {
        let previousSelection = selectedItemID
        feedbackMessage = nil
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

    private func moveSelection(by offset: Int) {
        guard !items.isEmpty else {
            selectedItemID = nil
            return
        }

        guard
            let currentSelection = selectedItemID,
            let currentIndex = items.firstIndex(where: { $0.id == currentSelection })
        else {
            selectedItemID = items.first?.id
            return
        }

        let targetIndex = max(0, min(items.count - 1, currentIndex + offset))
        selectedItemID = items[targetIndex].id
    }
}
