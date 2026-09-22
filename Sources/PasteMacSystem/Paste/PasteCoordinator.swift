import ApplicationServices
import AppKit
import Foundation
import PasteCore

public protocol PasteCoordinatorServices: AnyObject {
    func writeToPasteboard(_ item: ClipboardItem) -> Bool
    func isAccessibilityTrusted() -> Bool
    func activate(target: PasteTarget) -> Bool
    func postPasteCommand() -> Bool
    func waitForActivation(target: PasteTarget) async -> Bool
}

public extension PasteCoordinatorServices {
    func waitForActivation(target: PasteTarget) async -> Bool { true }
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

        guard await services.waitForActivation(target: target) else {
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
        let objects = Dictionary(grouping: item.payloads, by: \.itemIndex).sorted { $0.key < $1.key }.compactMap { _, formats -> NSPasteboardItem? in
            let object = NSPasteboardItem()
            var hasData = false
            for payload in formats where !payload.data.isEmpty {
                guard object.setData(payload.data, forType: NSPasteboard.PasteboardType(payload.typeIdentifier)) else { return nil }
                hasData = true
            }
            return hasData ? object : nil
        }
        guard !objects.isEmpty, objects.count == Set(item.payloads.map(\.itemIndex)).count else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects(objects)
    }

    public func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public func activate(target: PasteTarget) -> Bool {
        NSRunningApplication(processIdentifier: target.processIdentifier)?.activate() ?? false
    }

    public func waitForActivation(target: PasteTarget) async -> Bool {
        // activate() only accepts the request; the app may not own the keyboard yet.
        for _ in 0..<25 {
            if await MainActor.run(body: { NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier }) {
                return true
            }
            do { try await Task.sleep(for: .milliseconds(20)) }
            catch { return false }
        }
        return false
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
