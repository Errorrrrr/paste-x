import Foundation
import Testing
@testable import PasteMacSystem
import PasteCore

@Test func pasteCoordinatorCopiesOnlyWhenAccessibilityIsNotTrusted() async {
    let services = FakePasteServices()
    services.permissionTrusted = false
    let coordinator = PasteCoordinator(services: services)
    let item = makePasteItem()

    let result = await coordinator.paste(item, to: makeTarget())

    #expect(result == .copiedOnly(reason: .accessibilityNotTrusted))
    #expect(services.writtenItem == item)
    #expect(services.activatedTarget == nil)
    #expect(services.postedPasteCommand == false)
}

@Test func pasteCoordinatorPastesWhenClipboardTargetPermissionAndEventAllSucceed() async {
    let services = FakePasteServices()
    let coordinator = PasteCoordinator(services: services)
    let item = makePasteItem()
    let target = makeTarget()

    let result = await coordinator.paste(item, to: target)

    #expect(result == .pasted)
    #expect(services.writtenItem == item)
    #expect(services.activatedTarget == target)
    #expect(services.postedPasteCommand == true)
}

@Test func pasteCoordinatorFallsBackWhenTargetIsMissingOrActivationFails() async {
    let noTargetServices = FakePasteServices()
    let noTargetCoordinator = PasteCoordinator(services: noTargetServices)
    let noTargetResult = await noTargetCoordinator.paste(makePasteItem(), to: nil)

    let activationServices = FakePasteServices()
    activationServices.activateResult = false
    let activationCoordinator = PasteCoordinator(services: activationServices)
    let activationResult = await activationCoordinator.paste(makePasteItem(), to: makeTarget())

    #expect(noTargetResult == .copiedOnly(reason: .targetUnavailable))
    #expect(activationResult == .copiedOnly(reason: .activationFailed))
}

@Test func pasteCoordinatorReturnsFailureWhenPasteboardWriteFailsOrPayloadIsEmpty() async {
    let writeServices = FakePasteServices()
    writeServices.writeResult = false
    let writeCoordinator = PasteCoordinator(services: writeServices)
    let writeResult = await writeCoordinator.paste(makePasteItem(), to: makeTarget())

    let emptyCoordinator = PasteCoordinator(services: FakePasteServices())
    let emptyResult = await emptyCoordinator.paste(makePasteItem(payloads: []), to: makeTarget())

    #expect(writeResult == .failed(reason: .pasteboardWriteFailed))
    #expect(emptyResult == .failed(reason: .emptyPayload))
}

@Test func focusTrackerIgnoresSelfAndCapturesLastExternalApplication() {
    let tracker = FocusTracker(ownBundleIdentifier: "com.example.Paste")
    let external = RunningApplicationInfo(
        bundleIdentifier: "com.apple.TextEdit",
        processIdentifier: 42
    )

    tracker.recordActivatedApplication(RunningApplicationInfo(bundleIdentifier: "com.example.Paste", processIdentifier: 7), at: Date(timeIntervalSince1970: 1))
    tracker.recordActivatedApplication(external, at: Date(timeIntervalSince1970: 2))

    #expect(tracker.currentTarget == PasteTarget(
        bundleIdentifier: "com.apple.TextEdit",
        processIdentifier: 42,
        capturedAt: Date(timeIntervalSince1970: 2)
    ))
}

@Test func focusTrackerRefreshesTargetFromFrontmostApplicationWithoutActivationEvent() {
    let tracker = FocusTracker(
        ownBundleIdentifier: "com.example.Paste",
        ownProcessIdentifier: 7,
        frontmostApplicationProvider: {
            RunningApplicationInfo(
                bundleIdentifier: "com.apple.TextEdit",
                processIdentifier: 42
            )
        }
    )

    let target = tracker.refreshCurrentTarget(at: Date(timeIntervalSince1970: 3))

    #expect(target == PasteTarget(
        bundleIdentifier: "com.apple.TextEdit",
        processIdentifier: 42,
        capturedAt: Date(timeIntervalSince1970: 3)
    ))
    #expect(tracker.currentTarget == target)
}

@MainActor
@Test func clipboardAssistantRefreshesTargetBeforeShowingOverlay() {
    let item = makePasteItem()
    let target = makeTarget()
    let overlay = FakeOverlayPresenter()
    let focusTracker = FakeRefreshableFocusTracker(target: target)
    let app = ClipboardAssistantApp(
        hotKeyManager: FakeHotKeyManager(),
        clipboardMonitor: FakeClipboardMonitor(),
        historyStore: FakeClipboardHistory(items: [item]),
        overlayPresenter: overlay,
        focusTracker: focusTracker,
        statusItemController: StatusItemController(toggleHandler: {})
    )

    app.toggleOverlay()

    #expect(focusTracker.refreshCount == 1)
    #expect(overlay.toggles == [OverlayToggle(items: [item], target: target)])
}

private final class FakePasteServices: PasteCoordinatorServices {
    var writeResult = true
    var permissionTrusted = true
    var activateResult = true
    var postResult = true
    private(set) var writtenItem: ClipboardItem?
    private(set) var activatedTarget: PasteTarget?
    private(set) var postedPasteCommand = false

    func writeToPasteboard(_ item: ClipboardItem) -> Bool {
        writtenItem = item
        return writeResult
    }

    func isAccessibilityTrusted() -> Bool {
        permissionTrusted
    }

    func activate(target: PasteTarget) -> Bool {
        activatedTarget = target
        return activateResult
    }

    func postPasteCommand() -> Bool {
        postedPasteCommand = true
        return postResult
    }
}

private struct OverlayToggle: Equatable {
    let items: [ClipboardItem]
    let target: PasteTarget?
}

private final class FakeOverlayPresenter: OverlayPresenting {
    private(set) var toggles: [OverlayToggle] = []

    func toggle(items: [ClipboardItem], target: PasteTarget?) {
        toggles.append(OverlayToggle(items: items, target: target))
    }

    func hide() {}
}

private final class FakeRefreshableFocusTracker: FocusTargetRefreshing {
    private let target: PasteTarget
    private(set) var refreshCount = 0
    var currentTarget: PasteTarget? { nil }

    init(target: PasteTarget) {
        self.target = target
    }

    func refreshCurrentTarget(at date: Date) -> PasteTarget? {
        refreshCount += 1
        return target
    }
}

private final class FakeClipboardHistory: ClipboardHistoryProviding {
    let items: [ClipboardItem]

    init(items: [ClipboardItem]) {
        self.items = items
    }

    func insert(_ item: ClipboardItem) {}
    func clear() {}
}

private final class FakeClipboardMonitor: ClipboardMonitoring {
    func start() {}
    func stop() {}
}

private final class FakeHotKeyManager: HotKeyManaging {
    func register(shortcut: HotKeyShortcut, handler: @escaping @Sendable () -> Void) -> Result<Void, HotKeyError> {
        .success(())
    }

    func unregister() {}
}

private func makePasteItem(payloads: [ClipboardPayload]? = nil) -> ClipboardItem {
    let itemPayloads = payloads ?? [
        ClipboardPayload(typeIdentifier: PasteboardTypeIdentifier.plainText, data: Data("hello".utf8))
    ]
    return ClipboardItem(
        kind: .text,
        summary: "hello",
        createdAt: Date(timeIntervalSince1970: 1),
        signature: "text:hello",
        payloads: itemPayloads
    )
}

private func makeTarget() -> PasteTarget {
    PasteTarget(
        bundleIdentifier: "com.apple.TextEdit",
        processIdentifier: 42,
        capturedAt: Date(timeIntervalSince1970: 2)
    )
}
