import AppKit
@testable import PasteOverlay
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
