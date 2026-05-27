import AppKit
import Foundation
import PasteCore
@testable import PasteIntegration
import PasteOverlay
import Testing

@MainActor
@Test func overlayCoordinatorPastesSelectedItemToCapturedTargetAndClosesOverlay() async {
    let item = makeItem(summary: "hello", signature: "text:hello")
    let target = makeTarget()
    let windowController = FakeOverlayWindowController()
    let pasteCoordinator = FakePasteCoordinator(result: .pasted)
    let permissionPresenter = FakePermissionPresenter()
    var markedSelfWrites: [String] = []
    let coordinator = ClipboardOverlayCoordinator(
        windowController: windowController,
        pasteCoordinator: pasteCoordinator,
        permissionPresenter: permissionPresenter,
        markSelfWrite: { item in
            markedSelfWrites.append(item.signature)
        }
    )

    coordinator.toggle(items: [item], target: target)
    await Task.yield()
    let result = await coordinator.paste(OverlayPasteRequest(item: item, trigger: .returnKey))

    #expect(windowController.shownItems == [item])
    #expect(result == .pasted)
    #expect(coordinator.lastPasteResult == .pasted)
    #expect(pasteCoordinator.requests == [PasteRequest(item: item, target: target)])
    #expect(permissionPresenter.ensureCount == 1)
    #expect(markedSelfWrites == ["text:hello"])
    #expect(windowController.hideCount == 1)
    #expect(windowController.isVisible == false)
}

@MainActor
@Test func overlayCoordinatorHidesCopiedOnlyFallbackButKeepsFailedPasteVisible() async {
    let item = makeItem(summary: "hello", signature: "text:hello")
    let target = makeTarget()
    let copiedOnlyWindow = FakeOverlayWindowController()
    let copiedOnlyCoordinator = ClipboardOverlayCoordinator(
        windowController: copiedOnlyWindow,
        pasteCoordinator: FakePasteCoordinator(result: .copiedOnly(reason: .accessibilityNotTrusted)),
        permissionPresenter: nil,
        markSelfWrite: { _ in }
    )

    copiedOnlyCoordinator.toggle(items: [item], target: target)
    await Task.yield()
    let copiedOnlyResult = await copiedOnlyCoordinator.paste(OverlayPasteRequest(item: item, trigger: .spaceKey))

    #expect(copiedOnlyResult == .copiedOnly(reason: .accessibilityNotTrusted))
    #expect(copiedOnlyWindow.hideCount == 1)
    #expect(copiedOnlyWindow.isVisible == false)

    let failedWindow = FakeOverlayWindowController()
    var failedMarkedSelfWrites: [String] = []
    let failedCoordinator = ClipboardOverlayCoordinator(
        windowController: failedWindow,
        pasteCoordinator: FakePasteCoordinator(result: .failed(reason: .pasteboardWriteFailed)),
        permissionPresenter: nil,
        markSelfWrite: { item in
            failedMarkedSelfWrites.append(item.signature)
        }
    )

    failedCoordinator.toggle(items: [item], target: target)
    await Task.yield()
    let failedResult = await failedCoordinator.paste(OverlayPasteRequest(item: item, trigger: .doubleClick))

    #expect(failedResult == .failed(reason: .pasteboardWriteFailed))
    #expect(failedWindow.hideCount == 0)
    #expect(failedWindow.isVisible == true)
    #expect(failedMarkedSelfWrites == [])
}

@MainActor
@Test func overlayCoordinatorToggleHidesExistingOverlayWithoutChangingHistoryItems() async {
    let first = makeItem(summary: "first", signature: "text:first")
    let second = makeItem(summary: "second", signature: "text:second")
    let windowController = FakeOverlayWindowController()
    let coordinator = ClipboardOverlayCoordinator(
        windowController: windowController,
        pasteCoordinator: FakePasteCoordinator(result: .pasted),
        permissionPresenter: nil,
        markSelfWrite: { _ in }
    )

    coordinator.toggle(items: [first, second], target: makeTarget())
    await Task.yield()
    coordinator.toggle(items: [second], target: nil)
    await Task.yield()

    #expect(windowController.showCount == 1)
    #expect(windowController.hideCount == 1)
    #expect(windowController.shownItems == [first, second])
    #expect(windowController.isVisible == false)
}

private struct PasteRequest: Equatable {
    let item: ClipboardItem
    let target: PasteTarget?
}

@MainActor
private final class FakeOverlayWindowController: ClipboardOverlayWindowControlling {
    var isVisible = false
    private(set) var showCount = 0
    private(set) var hideCount = 0
    private(set) var shownItems: [ClipboardItem] = []

    func show(items: [ClipboardItem], on screen: NSScreen?) {
        isVisible = true
        showCount += 1
        shownItems = items
    }

    func hideOverlay() {
        isVisible = false
        hideCount += 1
    }
}

private final class FakePasteCoordinator: PasteCoordinating {
    private let result: PasteResult
    private(set) var requests: [PasteRequest] = []

    init(result: PasteResult) {
        self.result = result
    }

    func paste(_ item: ClipboardItem, to target: PasteTarget?) async -> PasteResult {
        requests.append(PasteRequest(item: item, target: target))
        return result
    }
}

private final class FakePermissionPresenter: PermissionPresenting {
    private(set) var ensureCount = 0

    func ensureAccessibilityPermission() -> Bool {
        ensureCount += 1
        return true
    }

    func openAccessibilitySettings() {}
}

private func makeItem(summary: String, signature: String) -> ClipboardItem {
    ClipboardItem(
        kind: .text,
        summary: summary,
        createdAt: Date(timeIntervalSince1970: 1),
        signature: signature,
        payloads: [
            ClipboardPayload(typeIdentifier: "public.utf8-plain-text", data: Data(summary.utf8))
        ]
    )
}

private func makeTarget() -> PasteTarget {
    PasteTarget(
        bundleIdentifier: "com.apple.TextEdit",
        processIdentifier: 42,
        capturedAt: Date(timeIntervalSince1970: 2)
    )
}
