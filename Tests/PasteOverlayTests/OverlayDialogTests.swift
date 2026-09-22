import AppKit
import Foundation
import SwiftUI
import Testing
import PasteCore
@testable import PasteOverlay

@MainActor
@Test func openingAndClosingEveryDialogKeepsOverlayAtScreenBottom() async throws {
    let store = OverlaySelectionStore(items: OverlayMockData.items())
    let controller = OverlayWindowController(store: store)
    controller.show(items: store.items)
    defer { controller.hideOverlay() }
    // Allow the normal entrance animation to complete before measuring its settled frame.
    try await Task.sleep(for: .milliseconds(300))
    let initial = try #require(controller.overlayFrame)

    store.showsLibrarySettings = true
    await Task.yield()
    let settings = try #require(controller.dialogWindow)
    #expect(settings.isVisible)
    #expect(settings.sheetParent == nil)
    #expect(settings.parent?.frame == initial)
    #expect(controller.overlayFrame == initial)
    settings.performClose(nil)
    await Task.yield()
    #expect(!store.showsLibrarySettings)
    #expect(controller.dialogWindow == nil)
    #expect(controller.overlayFrame == initial)

    let detailItem = try #require(store.items.first)
    store.detailItem = detailItem
    await Task.yield()
    let detail = try #require(controller.dialogWindow)
    #expect(detail.isVisible)
    #expect(detail.sheetParent == nil)
    #expect(controller.overlayFrame == initial)
    // A nested confirmation is attached only to the dialog, never to the overlay.
    let confirmation = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
                               styleMask: [.titled], backing: .buffered, defer: false)
    detail.beginSheet(confirmation, completionHandler: { _ in })
    try await Task.sleep(for: .milliseconds(300))
    #expect(controller.overlayFrame == initial)
    detail.endSheet(confirmation)
    confirmation.orderOut(nil)
    store.detailItem = nil
    await Task.yield()
    #expect(controller.dialogWindow == nil)
    #expect(controller.overlayFrame == initial)

    store.showsGroupCreation = true
    await Task.yield()
    #expect(controller.dialogWindow?.isVisible == true)
    #expect(controller.overlayFrame == initial)
    controller.hideOverlay()
    #expect(!store.isShowingDialog)
    #expect(controller.dialogWindow == nil)
}

@Test func dialogPlacementClampsToSelectedScreenWithoutUsingMainScreenOrigin() {
    let display = NSRect(x: -1920, y: 200, width: 1920, height: 1080)
    let overlay = NSRect(x: -1920, y: 200, width: 1920, height: 388)
    let frame = OverlayDialogController.frame(size: NSSize(width: 640, height: 650), overlay: overlay, visibleScreen: display)
    #expect(frame.midX == overlay.midX)
    #expect(frame.midY == display.midY)
    #expect(display.contains(frame))
}

@Test func oversizedDialogClampsToAvailableScreen() {
    let display = NSRect(x: 100, y: 0, width: 800, height: 560)
    let frame = OverlayDialogController.frame(size: NSSize(width: 640, height: 900), overlay: display, visibleScreen: display)
    #expect(frame.height == 560)
    #expect(display.contains(frame))
}

@MainActor
@Test func delayedCloseDoesNotHideReopenedOverlayAndDismissesOnlyOnce() async throws {
    var dismissCount = 0
    let controller = OverlayWindowController(onDismiss: { dismissCount += 1 })
    let items = OverlayMockData.items()
    controller.show(items: items)
    controller.hideOverlay()
    controller.show(items: items)
    try await Task.sleep(for: .milliseconds(750))
    #expect(controller.isVisible)
    #expect(dismissCount == 0)
    controller.hideOverlay()
    try await Task.sleep(for: .milliseconds(750))
    #expect(!controller.isVisible)
    #expect(dismissCount == 1)
}
