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
    public let plainText: Bool
    public let fromQueue: Bool

    public init(item: ClipboardItem, trigger: OverlayPasteTrigger, plainText: Bool = false, fromQueue: Bool = false) {
        self.item = item
        self.trigger = trigger
        self.plainText = plainText
        self.fromQueue = fromQueue
    }
}

public enum OverlaySelectionSource: Equatable, Sendable {
    case presentation
    case automatic
    case mouse
}

public enum OverlaySelectionScrollAlignment: Equatable, Sendable {
    case minimalVisibility
}

public struct OverlaySelectionScrollRequest: Equatable, Sendable {
    public let itemID: ClipboardItem.ID
    public let delay: TimeInterval
    public let alignment: OverlaySelectionScrollAlignment

    public init(
        itemID: ClipboardItem.ID,
        delay: TimeInterval,
        alignment: OverlaySelectionScrollAlignment = .minimalVisibility
    ) {
        self.itemID = itemID
        self.delay = max(0, delay)
        self.alignment = alignment
    }
}

public struct OverlaySelectionScrollPolicy: Equatable, Sendable {
    public let mouseSelectionDelay: TimeInterval

    public init(mouseSelectionDelay: TimeInterval) {
        self.mouseSelectionDelay = max(0, mouseSelectionDelay)
    }

    public func scrollRequest(
        for itemID: ClipboardItem.ID?,
        source: OverlaySelectionSource
    ) -> OverlaySelectionScrollRequest? {
        guard let itemID else {
            return nil
        }

        guard source != .presentation else {
            return nil
        }

        let delay = source == .mouse ? mouseSelectionDelay : 0
        return OverlaySelectionScrollRequest(
            itemID: itemID,
            delay: delay,
            alignment: .minimalVisibility
        )
    }
}

@MainActor
public final class OverlaySelectionStore: ObservableObject {
    @Published public private(set) var items: [ClipboardItem]
    @Published public private(set) var selectedItemID: ClipboardItem.ID?
    @Published public private(set) var feedbackMessage: String?
    @Published public private(set) var searchQuery = ""
    @Published public private(set) var isSearching = false
    @Published public private(set) var presentationRevision = 0
    @Published public var groups: [ClipboardGroup] = []
    @Published public var librarySettings = ClipboardLibrarySettings()
    @Published public var storageError: String?
    @Published public var kindFilter: ClipboardKind? { didSet { normalizeSelectionForVisibleItems() } }
    @Published public var sourceFilter = "" { didSet { normalizeSelectionForVisibleItems() } }
    @Published public var ageFilterDays = 0 { didSet { normalizeSelectionForVisibleItems() } }
    @Published public var pinnedOnly = false { didSet { normalizeSelectionForVisibleItems() } }
    @Published public var groupFilter: UUID? { didSet { normalizeSelectionForVisibleItems() } }
    @Published public var selectedIDs: Set<UUID> = []
    @Published public var queueIDs: [UUID] = []
    @Published public var detailItem: ClipboardItem?
    @Published public var showsLibrarySettings = false
    @Published public var showsGroupCreation = false
    public var isShowingDialog: Bool { detailItem != nil || showsLibrarySettings || showsGroupCreation }
    @Published public var isPasting = false
    public var onLibraryAction: (ClipboardLibraryAction) -> Void = { _ in }
    public private(set) var lastSelectionSource: OverlaySelectionSource = .automatic

    public var selectedItem: ClipboardItem? {
        guard let selectedItemID else {
            return nil
        }

        return visibleItems.first { $0.id == selectedItemID }
    }

    public var visibleItems: [ClipboardItem] {
        let query = normalizedSearchQuery
        return items.filter { item in
            (query.isEmpty || item.searchText.localizedCaseInsensitiveContains(query)
                || item.kind.rawValue.localizedCaseInsensitiveContains(query)
                || item.kind.searchDisplayName.localizedCaseInsensitiveContains(query))
            && (kindFilter == nil || kindFilter == item.kind)
            && (sourceFilter.isEmpty || item.sourceBundleID == sourceFilter)
            && (ageFilterDays == 0 || item.createdAt >= Date().addingTimeInterval(-Double(ageFilterDays) * 86400))
            && (!pinnedOnly || item.isPinned)
            && (groupFilter == nil || item.groupID == groupFilter)
        }
    }

    public func syncLibrary(items: [ClipboardItem], groups: [ClipboardGroup], settings: ClipboardLibrarySettings, error: String?) {
        self.items = items; self.groups = groups; self.librarySettings = settings; self.storageError = error
        let ids = Set(items.map(\.id))
        selectedIDs.formIntersection(ids)
        queueIDs.removeAll { !ids.contains($0) }
        if let groupFilter, !groups.contains(where: { $0.id == groupFilter }) { self.groupFilter = nil }
        normalizeSelectionForVisibleItems()
    }

    public func perform(_ action: ClipboardLibraryAction) { onLibraryAction(action) }
    public func togglePin(_ item: ClipboardItem) { var copy = item; copy.isPinned.toggle(); perform(.update(copy)) }
    public func assign(_ item: ClipboardItem, group: UUID?) { var copy = item; copy.groupID = group; perform(.update(copy)) }
    public func toggleMultiple(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }
    public func enqueueSelection() {
        let targets = selectedIDs.isEmpty ? [selectedItemID].compactMap { $0 } : visibleItems.filter { selectedIDs.contains($0.id) }.map(\.id)
        for id in targets where !queueIDs.contains(id) { queueIDs.append(id) }
    }
    public func queueRequest() -> OverlayPasteRequest? {
        guard let id = queueIDs.first, let item = items.first(where: { $0.id == id }), !isPasting else { return nil }
        return OverlayPasteRequest(item: item, trigger: .returnKey, fromQueue: true)
    }
    public func completePaste(_ request: OverlayPasteRequest, succeeded: Bool) {
        isPasting = false
        if request.fromQueue && succeeded { queueIDs.removeAll { $0 == request.item.id } }
    }
    public func mergedRequest() -> OverlayPasteRequest? {
        let selected = visibleItems.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty, selected.allSatisfy({ !$0.textContent.isEmpty }) else { return nil }
        let text = selected.map(\.textContent).joined(separator: "\n")
        let payloads = [ClipboardPayload(typeIdentifier: "public.utf8-plain-text", data: Data(text.utf8))]
        let item = ClipboardItem(kind: .text, summary: String(text.prefix(120)), createdAt: Date(), signature: ClipboardSignature.make(kind: .text, payloads: payloads), payloads: payloads)
        return OverlayPasteRequest(item: item, trigger: .returnKey)
    }
    public func resetFilters() {
        kindFilter = nil; sourceFilter = ""; ageFilterDays = 0; pinnedOnly = false; groupFilter = nil
        normalizeSelectionForVisibleItems()
    }

    public init(items: [ClipboardItem] = []) {
        self.items = items
        self.selectedItemID = items.first?.id
    }

    public func replaceItems(_ newItems: [ClipboardItem]) {
        lastSelectionSource = .presentation
        feedbackMessage = nil
        clearSearch()
        items = newItems
        selectedItemID = visibleItems.first?.id
        presentationRevision += 1
    }

    public func select(id: ClipboardItem.ID, source: OverlaySelectionSource = .automatic) {
        guard selectedItemID != id else {
            return
        }

        guard items.contains(where: { $0.id == id }) else {
            return
        }

        lastSelectionSource = source
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
            lastSelectionSource = .automatic
            selectedItemID = nil
            return
        }

        if let selectedItemID, visibleItems.contains(where: { $0.id == selectedItemID }) {
            return
        }

        lastSelectionSource = .automatic
        selectedItemID = visibleItems.first?.id
    }

    private func moveSelection(by offset: Int) {
        let selectionItems = visibleItems
        guard !selectionItems.isEmpty else {
            lastSelectionSource = .automatic
            selectedItemID = nil
            return
        }

        guard
            let currentSelection = selectedItemID,
            let currentIndex = selectionItems.firstIndex(where: { $0.id == currentSelection })
        else {
            lastSelectionSource = .automatic
            selectedItemID = selectionItems.first?.id
            return
        }

        let targetIndex = max(0, min(selectionItems.count - 1, currentIndex + offset))
        lastSelectionSource = .automatic
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
