import AppKit
import Foundation
import PasteCore
@testable import PasteOverlay
import SwiftUI
import Testing

@MainActor
@Test func clipboardItemMouseViewDispatchesSingleClickToSelection() throws {
    let view = ClipboardItemMouseEventView(frame: NSRect(x: 0, y: 0, width: 248, height: 244))
    var actions: [String] = []
    view.onSelect = { actions.append("select") }
    view.onPaste = { actions.append("paste") }

    view.mouseDown(with: try makeMouseDown(clickCount: 1))

    #expect(actions == ["select"])
}

@MainActor
@Test func clipboardItemMouseViewDispatchesDoubleClickDirectlyToPaste() throws {
    let view = ClipboardItemMouseEventView(frame: NSRect(x: 0, y: 0, width: 248, height: 244))
    var actions: [String] = []
    view.onSelect = { actions.append("select") }
    view.onPaste = { actions.append("paste") }

    view.mouseDown(with: try makeMouseDown(clickCount: 2))

    #expect(actions == ["paste"])
}

@MainActor
@Test func clipboardItemMouseViewSelectsImmediatelyBeforeDoubleClickPaste() throws {
    let view = ClipboardItemMouseEventView(frame: NSRect(x: 0, y: 0, width: 248, height: 244))
    var actions: [String] = []
    view.onSelect = { actions.append("select") }
    view.onPaste = { actions.append("paste") }

    view.mouseDown(with: try makeMouseDown(clickCount: 1))
    view.mouseDown(with: try makeMouseDown(clickCount: 2))

    #expect(actions == ["select", "paste"])
}

@MainActor
@Test func scrollableListDoubleClickOnUncenteredMouseSelectedItemPastesOriginalItemBeforeDeferredScroll() throws {
    let items = makeScrollableTextItems(count: 8)
    let targetItem = items[6]
    let store = OverlaySelectionStore(items: items)
    let scrollPolicy = OverlaySelectionScrollPolicy(mouseSelectionDelay: 0.5)
    let view = ClipboardItemMouseEventView(frame: NSRect(x: 0, y: 0, width: 248, height: 244))
    var immediateScrollIDs: [ClipboardItem.ID] = []
    var deferredScrollIDs: [ClipboardItem.ID] = []
    var deferredScrolls: [() -> Void] = []
    var pasteRequests: [OverlayPasteRequest] = []

    func applySelectionScroll() {
        guard let request = scrollPolicy.scrollRequest(
            for: store.selectedItemID,
            source: store.lastSelectionSource
        ) else {
            return
        }

        if request.delay > 0 {
            deferredScrolls.append {
                deferredScrollIDs.append(request.itemID)
            }
        } else {
            immediateScrollIDs.append(request.itemID)
        }
    }

    view.onSelect = {
        store.select(id: targetItem.id, source: .mouse)
        applySelectionScroll()
    }
    view.onPaste = {
        store.select(id: targetItem.id, source: .mouse)
        if let request = store.makePasteRequest(trigger: .doubleClick) {
            pasteRequests.append(request)
        }
    }

    view.mouseDown(with: try makeMouseDown(clickCount: 1))

    #expect(store.selectedItemID == targetItem.id)
    #expect(immediateScrollIDs.isEmpty)
    #expect(deferredScrolls.count == 1)

    view.mouseDown(with: try makeMouseDown(clickCount: 2))

    #expect(pasteRequests == [OverlayPasteRequest(item: targetItem, trigger: .doubleClick)])
    #expect(immediateScrollIDs.isEmpty)
    #expect(deferredScrollIDs.isEmpty)

    deferredScrolls.forEach { $0() }
    #expect(deferredScrollIDs == [targetItem.id])
}

@MainActor
@Test func mouseSingleClickStillSelectsItemAfterPresentationReset() throws {
    let items = makeScrollableTextItems(count: 8)
    let targetItem = items[5]
    let store = OverlaySelectionStore(items: items)
    let scrollPolicy = OverlaySelectionScrollPolicy(mouseSelectionDelay: 0.5)
    let view = ClipboardItemMouseEventView(frame: NSRect(x: 0, y: 0, width: 248, height: 244))
    var immediateScrollIDs: [ClipboardItem.ID] = []
    var deferredScrollIDs: [ClipboardItem.ID] = []

    store.select(id: items[7].id)
    store.replaceItems(items)

    view.onSelect = {
        store.select(id: targetItem.id, source: .mouse)
        guard let request = scrollPolicy.scrollRequest(
            for: store.selectedItemID,
            source: store.lastSelectionSource
        ) else {
            return
        }

        if request.delay > 0 {
            deferredScrollIDs.append(request.itemID)
        } else {
            immediateScrollIDs.append(request.itemID)
        }
    }

    view.mouseDown(with: try makeMouseDown(clickCount: 1))

    #expect(store.selectedItemID == targetItem.id)
    #expect(store.lastSelectionSource == .mouse)
    #expect(immediateScrollIDs.isEmpty)
    #expect(deferredScrollIDs == [targetItem.id])
}

@MainActor
@Test func clipboardItemMouseBridgeCoversRenderedCardHitTarget() throws {
    let item = makeScrollableTextItems(count: 1)[0]
    var didSelect = false
    let hostingView = NSHostingView(
        rootView: ClipboardItemView(
            item: item,
            displayIndex: 1,
            isSelected: false,
            onSelect: { didSelect = true },
            onPaste: {}
        )
    )
    hostingView.frame = NSRect(x: 0, y: 0, width: 248, height: 244)
    hostingView.layoutSubtreeIfNeeded()

    let bridge = try #require(hostingView.firstDescendant(ofType: ClipboardItemMouseEventView.self))
    #expect(bridge.frame == NSRect(x: 0, y: 0, width: 248, height: 244))
    #expect(bridge.bounds.size == NSSize(width: 248, height: 244))
    #expect(hostingView.firstClipboardItemMouseEventView(containingWindowPoint: NSPoint(x: 124, y: 122)) === bridge)

    bridge.handleMouseDown(try makeMouseDown(clickCount: 1))
    #expect(didSelect)
}

@MainActor
@Test func mouseDoubleClickAfterPresentationResetPastesClickedItem() throws {
    let items = makeScrollableTextItems(count: 8)
    let targetItem = items[6]
    let store = OverlaySelectionStore(items: items)
    let view = ClipboardItemMouseEventView(frame: NSRect(x: 0, y: 0, width: 248, height: 244))
    var pasteRequests: [OverlayPasteRequest] = []

    store.select(id: items[7].id)
    store.replaceItems(items)

    view.onPaste = {
        store.select(id: targetItem.id, source: .mouse)
        if let request = store.makePasteRequest(trigger: .doubleClick) {
            pasteRequests.append(request)
        }
    }

    view.mouseDown(with: try makeMouseDown(clickCount: 2))

    #expect(store.selectedItemID == targetItem.id)
    #expect(store.lastSelectionSource == .mouse)
    #expect(pasteRequests == [OverlayPasteRequest(item: targetItem, trigger: .doubleClick)])
}

private extension NSView {
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        if let typedSelf = self as? T {
            return typedSelf
        }

        for subview in subviews {
            if let match = subview.firstDescendant(ofType: type) {
                return match
            }
        }

        return nil
    }
}

private func makeMouseDown(clickCount: Int) throws -> NSEvent {
    try #require(
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 40, y: 40),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: clickCount,
            clickCount: clickCount,
            pressure: 1
        )
    )
}

private func makeScrollableTextItems(count: Int) -> [ClipboardItem] {
    (0..<count).map { index in
        let summary = "Scrollable clipboard item \(index)"
        let payload = ClipboardPayload(
            typeIdentifier: "public.utf8-plain-text",
            data: Data(summary.utf8)
        )

        return ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", index))") ?? UUID(),
            kind: .text,
            summary: summary,
            createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
            signature: "scrollable-text-\(index)",
            payloads: [payload]
        )
    }
}
