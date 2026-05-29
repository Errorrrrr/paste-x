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

    #expect(hiddenFrame.minY == -44)
    #expect(hiddenFrame.width == restingFrame.width)
    #expect(hiddenFrame.height == restingFrame.height)
}
