import ApplicationServices
import AppKit
import Foundation
import PasteCore

public protocol PasteCoordinatorServices: AnyObject {
    func writeToPasteboard(_ item: ClipboardItem) -> Bool
    func isAccessibilityTrusted() -> Bool
    func activate(target: PasteTarget) -> Bool
    func postPasteCommand() -> Bool
}

public final class PasteCoordinator: PasteCoordinating {
    private let services: PasteCoordinatorServices

    public init(services: PasteCoordinatorServices = SystemPasteCoordinatorServices()) {
        self.services = services
    }

    public func paste(_ item: ClipboardItem, to target: PasteTarget?) async -> PasteResult {
        guard !item.payloads.isEmpty else {
            return .failed(reason: .emptyPayload)
        }

        guard services.writeToPasteboard(item) else {
            return .failed(reason: .pasteboardWriteFailed)
        }

        guard services.isAccessibilityTrusted() else {
            return .copiedOnly(reason: .accessibilityNotTrusted)
        }

        guard let target else {
            return .copiedOnly(reason: .targetUnavailable)
        }

        guard services.activate(target: target) else {
            return .copiedOnly(reason: .activationFailed)
        }

        guard services.postPasteCommand() else {
            return .copiedOnly(reason: .eventPostFailed)
        }

        return .pasted
    }
}

public final class SystemPasteCoordinatorServices: PasteCoordinatorServices {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func writeToPasteboard(_ item: ClipboardItem) -> Bool {
        let pasteboardItem = NSPasteboardItem()
        var wroteAnyPayload = false

        for payload in item.payloads {
            guard !payload.data.isEmpty else { continue }
            pasteboardItem.setData(payload.data, forType: NSPasteboard.PasteboardType(payload.typeIdentifier))
            wroteAnyPayload = true
        }

        guard wroteAnyPayload else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([pasteboardItem])
    }

    public func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public func activate(target: PasteTarget) -> Bool {
        NSRunningApplication(processIdentifier: target.processIdentifier)?.activate() ?? false
    }

    public func postPasteCommand() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
