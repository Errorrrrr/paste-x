import AppKit
@testable import PasteOverlay
import Testing

@Test func overlayRestingFrameSitsOnPhysicalScreenBottom() {
    let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let frame = OverlayPanelGeometry.restingFrame(in: screenFrame)

    #expect(frame.minX == 0)
    #expect(frame.minY == 0)
    #expect(frame.width == 1440)
    #expect(frame.height == 336)
}

@Test func overlayRestingFrameMaintainsMinimumWidthWhenScreenIsNarrow() {
    let screenFrame = NSRect(x: 100, y: 0, width: 640, height: 700)
    let frame = OverlayPanelGeometry.restingFrame(in: screenFrame)

    #expect(frame.width == 760)
    #expect(frame.midX == screenFrame.midX)
    #expect(frame.minY == 0)
}

@Test func overlayHiddenFrameSlidesDownWithoutChangingSize() {
    let restingFrame = NSRect(x: 0, y: 0, width: 1440, height: 336)
    let hiddenFrame = OverlayPanelGeometry.hiddenFrame(from: restingFrame)

    #expect(hiddenFrame.minY == -72)
    #expect(hiddenFrame.width == restingFrame.width)
    #expect(hiddenFrame.height == restingFrame.height)
}

@MainActor
@Test func overlayPanelPresentationKeepsPanelVisibleWhenAppDeactivates() {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 960, height: 336),
        styleMask: OverlayPanelPresentation.styleMask,
        backing: .buffered,
        defer: false
    )

    OverlayPanelPresentation.configure(panel)

    #expect(panel.hidesOnDeactivate == false)
    #expect(panel.animationBehavior == .none)
}

@MainActor
@Test func overlayPanelPresentationUsesNonactivatingKeyFocusForDirectTyping() {
    let panel = KeyTrackingPanel(
        contentRect: NSRect(x: 0, y: 0, width: 960, height: 336),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )

    OverlayPanelPresentation.configure(panel)
    OverlayPanelPresentation.presentWithoutActivatingApplication(panel)

    #expect(OverlayPanelPresentation.styleMask.contains(.nonactivatingPanel))
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(panel.becomesKeyOnlyIfNeeded)
    #expect(panel.makeKeyCallCount == 1)
    #expect(panel.makeKeyAndOrderFrontCallCount == 0)
}

@MainActor
@Test func overlayRelinquishesNonactivatingKeyFocusBeforePasteCallback() async {
    let panel = KeyTrackingPanel(
        contentRect: NSRect(x: 0, y: 0, width: 960, height: 336),
        styleMask: OverlayPanelPresentation.styleMask,
        backing: .buffered,
        defer: false
    )
    var callbackObservedRelinquishedFocus = false

    OverlayPanelPresentation.performAfterRelinquishingKeyFocus(panel) {
        callbackObservedRelinquishedFocus = panel.resignKeyCallCount == 1
    }
    await Task.yield()

    #expect(panel.resignKeyCallCount == 1)
    #expect(callbackObservedRelinquishedFocus)
}

@MainActor
@Test func overlayRoutesReturnToPasteRequest() async throws {
    let item = try #require(OverlayMockData.items().first)
    var requests: [OverlayPasteRequest] = []
    let controller = OverlayWindowController(
        onPasteRequested: { request in
            requests.append(request)
        }
    )

    controller.show(items: [item], on: nil)
    let handled = controller.handleKeyboardEvent(OverlayKeyboardEvent(
        keyCode: 36,
        modifiers: [],
        characters: "\r",
        isRepeat: false
    ))
    await Task.yield()

    #expect(handled)
    #expect(requests == [OverlayPasteRequest(item: item, trigger: .returnKey)])
}

@MainActor
@Test func overlayRoutesDirectTypingToSearchAndEscapeToClearThenClose() async throws {
    let items = OverlayMockData.items()
    let store = OverlaySelectionStore()
    var dismissCount = 0
    let controller = OverlayWindowController(
        store: store,
        onDismiss: {
            dismissCount += 1
        }
    )

    controller.show(items: items, on: nil)
    let searchHandled = controller.handleKeyboardEvent(OverlayKeyboardEvent(
        keyCode: 12,
        modifiers: [],
        characters: "q",
        isRepeat: false
    ))

    #expect(searchHandled)
    #expect(store.isSearching)
    #expect(store.searchQuery == "q")

    let clearHandled = controller.handleKeyboardEvent(OverlayKeyboardEvent(
        keyCode: 53,
        modifiers: [],
        characters: nil,
        isRepeat: false
    ))

    #expect(clearHandled)
    #expect(store.isSearching == false)
    #expect(controller.isVisible)

    let closeHandled = controller.handleKeyboardEvent(OverlayKeyboardEvent(
        keyCode: 53,
        modifiers: [],
        characters: nil,
        isRepeat: false
    ))
    for _ in 0..<100 where dismissCount == 0 {
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(closeHandled)
    #expect(dismissCount == 1)
}

@Test func outsideClickPolicyKeepsGlobalMouseDownInsidePanelOpen() {
    let panelFrame = NSRect(x: 80, y: 40, width: 640, height: 336)

    let isOutside = OverlayOutsideClickPolicy.isOutsidePanel(
        panelFrame: panelFrame,
        eventWindowIsPanel: false,
        mouseLocation: NSPoint(x: 240, y: 120)
    )

    #expect(isOutside == false)
}

@MainActor
private final class KeyTrackingPanel: NSPanel {
    private(set) var makeKeyCallCount = 0
    private(set) var makeKeyAndOrderFrontCallCount = 0
    private(set) var resignKeyCallCount = 0

    override func makeKey() {
        makeKeyCallCount += 1
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyAndOrderFrontCallCount += 1
    }

    override func resignKey() {
        resignKeyCallCount += 1
    }
}

@Test func outsideClickPolicyDismissesGlobalMouseDownOutsidePanel() {
    let panelFrame = NSRect(x: 80, y: 40, width: 640, height: 336)

    let isOutside = OverlayOutsideClickPolicy.isOutsidePanel(
        panelFrame: panelFrame,
        eventWindowIsPanel: false,
        mouseLocation: NSPoint(x: 40, y: 120)
    )

    #expect(isOutside == true)
}

@Test func outsideClickPolicyKeepsPanelWindowEventsOpen() {
    let panelFrame = NSRect(x: 80, y: 40, width: 640, height: 336)

    let isOutside = OverlayOutsideClickPolicy.isOutsidePanel(
        panelFrame: panelFrame,
        eventWindowIsPanel: true,
        mouseLocation: NSPoint(x: 40, y: 120)
    )

    #expect(isOutside == false)
}
