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
@Test func overlayPanelPresentationUsesNonactivatingKeyPanel() {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 960, height: 336),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )

    OverlayPanelPresentation.configure(panel)

    #expect(OverlayPanelPresentation.styleMask.contains(.nonactivatingPanel))
    #expect(panel.styleMask.contains(.nonactivatingPanel))
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
