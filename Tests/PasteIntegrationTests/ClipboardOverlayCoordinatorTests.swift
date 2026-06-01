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
    let permissionPresenter = FakePermissionPresenter()
    var events: [String] = []
    let pasteCoordinator = FakePasteCoordinator(result: .pasted) {
        events.append("paste")
    }
    let coordinator = ClipboardOverlayCoordinator(
        windowController: windowController,
        pasteCoordinator: pasteCoordinator,
        permissionPresenter: permissionPresenter,
        markSelfWrite: { item in
            events.append("mark:\(item.signature)")
        },
        cancelSelfWrite: { item in
            events.append("cancel:\(item.signature)")
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
    #expect(events == ["mark:text:hello", "paste"])
    #expect(windowController.hideCount == 1)
    #expect(windowController.isVisible == false)
}

@MainActor
@Test func overlayCoordinatorShowsCopiedOnlyFallbackButKeepsFailedPasteVisible() async {
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
    #expect(copiedOnlyWindow.hideCount == 0)
    #expect(copiedOnlyWindow.isVisible == true)
    #expect(copiedOnlyWindow.feedbacks == [
        PasteFeedback(
            message: "Copied to clipboard. Enable Accessibility to paste automatically.",
            hideAfter: 1.4
        )
    ])

    let failedWindow = FakeOverlayWindowController()
    var failedEvents: [String] = []
    let failedCoordinator = ClipboardOverlayCoordinator(
        windowController: failedWindow,
        pasteCoordinator: FakePasteCoordinator(result: .failed(reason: .pasteboardWriteFailed)),
        permissionPresenter: nil,
        markSelfWrite: { item in
            failedEvents.append("mark:\(item.signature)")
        },
        cancelSelfWrite: { item in
            failedEvents.append("cancel:\(item.signature)")
        }
    )

    failedCoordinator.toggle(items: [item], target: target)
    await Task.yield()
    let failedResult = await failedCoordinator.paste(OverlayPasteRequest(item: item, trigger: .doubleClick))

    #expect(failedResult == .failed(reason: .pasteboardWriteFailed))
    #expect(failedWindow.hideCount == 0)
    #expect(failedWindow.isVisible == true)
    #expect(failedEvents == ["mark:text:hello", "cancel:text:hello"])
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

@MainActor
@Test func overlayCoordinatorDispatchesSettingsCloseAndQuitMenuActions() {
    let windowController = FakeOverlayWindowController()
    var actions: [OverlayMenuAction] = []
    let coordinator = ClipboardOverlayCoordinator(
        windowController: windowController,
        pasteCoordinator: FakePasteCoordinator(result: .pasted),
        permissionPresenter: nil,
        markSelfWrite: { _ in },
        onMenuAction: { action in
            actions.append(action)
        }
    )

    coordinator.submit(.settings)
    coordinator.submit(.close)
    coordinator.submit(.quit)

    #expect(actions == [.settings, .close, .quit])
}

@MainActor
@Test func dependencyContainerDispatchesOverlaySettingsCloseAndQuitActions() {
    var settingsCount = 0
    var quitCount = 0
    let container = ClipboardAssistantDependencyContainer(
        settingsPresenter: nil,
        shortcutStore: nil,
        appSettingsStore: nil,
        settingsHandler: {
            settingsCount += 1
        },
        quitHandler: {
            quitCount += 1
        }
    )

    container.overlayPresenter.submit(.settings)
    container.overlayPresenter.submit(.close)
    container.overlayPresenter.submit(.quit)

    #expect(settingsCount == 1)
    #expect(quitCount == 1)
}

private struct PasteRequest: Equatable {
    let item: ClipboardItem
    let target: PasteTarget?
}

private struct PasteFeedback: Equatable {
    let message: String
    let hideAfter: TimeInterval
}

@MainActor
private final class FakeOverlayWindowController: ClipboardOverlayWindowControlling {
    var isVisible = false
    private(set) var showCount = 0
    private(set) var hideCount = 0
    private(set) var shownItems: [ClipboardItem] = []
    private(set) var feedbacks: [PasteFeedback] = []

    func show(items: [ClipboardItem], on screen: NSScreen?) {
        isVisible = true
        showCount += 1
        shownItems = items
    }

    func hideOverlay() {
        isVisible = false
        hideCount += 1
    }

    func showPasteFeedback(_ message: String, hideAfter delay: TimeInterval) {
        feedbacks.append(PasteFeedback(message: message, hideAfter: delay))
    }
}

private final class FakePasteCoordinator: PasteCoordinating {
    private let result: PasteResult
    private let onPaste: () -> Void
    private(set) var requests: [PasteRequest] = []

    init(result: PasteResult, onPaste: @escaping () -> Void = {}) {
        self.result = result
        self.onPaste = onPaste
    }

    func paste(_ item: ClipboardItem, to target: PasteTarget?) async -> PasteResult {
        onPaste()
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
