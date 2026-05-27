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
