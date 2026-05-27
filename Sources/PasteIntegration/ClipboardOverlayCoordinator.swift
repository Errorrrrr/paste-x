import AppKit
import Foundation
import PasteCore
import PasteOverlay

@MainActor
public protocol ClipboardOverlayWindowControlling: AnyObject {
    var isVisible: Bool { get }

    func show(items: [ClipboardItem], on screen: NSScreen?)
    func hideOverlay()
}

extension OverlayWindowController: ClipboardOverlayWindowControlling {}

@MainActor
public final class ClipboardOverlayCoordinator: OverlayPresenting {
    private let windowController: ClipboardOverlayWindowControlling
    // PasteCoordinating is intentionally not actor-isolated in the T1 contract.
    // Keep that contract stable and bridge the Swift 6 isolation boundary here.
    private let pasteCoordinator: SendablePasteCoordinator
    private let permissionPresenter: PermissionPresenting?
    private let markSelfWrite: (ClipboardItem) -> Void
    private var currentTarget: PasteTarget?

    public private(set) var lastPasteResult: PasteResult?

    public convenience init(
        pasteCoordinator: PasteCoordinating,
        permissionPresenter: PermissionPresenting?,
        markSelfWrite: @escaping (ClipboardItem) -> Void
    ) {
        let relay = OverlayPasteRequestRelay()
        let windowController = OverlayWindowController(
            onPasteRequested: { [relay] request in
                relay.submit(request)
            }
        )

        self.init(
            windowController: windowController,
            pasteCoordinator: pasteCoordinator,
            permissionPresenter: permissionPresenter,
            markSelfWrite: markSelfWrite
        )

        relay.handler = { [weak self] request in
            self?.submit(request)
        }
    }

    public init(
        windowController: ClipboardOverlayWindowControlling,
        pasteCoordinator: PasteCoordinating,
        permissionPresenter: PermissionPresenting?,
        markSelfWrite: @escaping (ClipboardItem) -> Void
    ) {
        self.windowController = windowController
        self.pasteCoordinator = SendablePasteCoordinator(base: pasteCoordinator)
        self.permissionPresenter = permissionPresenter
        self.markSelfWrite = markSelfWrite
    }

    public nonisolated func toggle(items: [ClipboardItem], target: PasteTarget?) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            currentTarget = target
            if windowController.isVisible {
                windowController.hideOverlay()
            } else {
                windowController.show(items: items, on: nil)
            }
        }
    }

    public nonisolated func hide() {
        Task { @MainActor [weak self] in
            self?.windowController.hideOverlay()
        }
    }

    public func submit(_ request: OverlayPasteRequest) {
        Task { @MainActor [weak self] in
            await self?.paste(request)
        }
    }

    @discardableResult
    public func paste(_ request: OverlayPasteRequest) async -> PasteResult {
        _ = permissionPresenter?.ensureAccessibilityPermission()

        let coordinator = pasteCoordinator
        let result = await coordinator.paste(request.item, to: currentTarget)
        lastPasteResult = result

        if result.wrotePasteboard {
            markSelfWrite(request.item)
        }

        if result.shouldHideOverlayAfterPaste {
            windowController.hideOverlay()
        }

        return result
    }
}

private struct SendablePasteCoordinator: @unchecked Sendable {
    let base: PasteCoordinating

    func paste(_ item: ClipboardItem, to target: PasteTarget?) async -> PasteResult {
        await base.paste(item, to: target)
    }
}

private final class OverlayPasteRequestRelay {
    var handler: ((OverlayPasteRequest) -> Void)?

    @MainActor
    func submit(_ request: OverlayPasteRequest) {
        handler?(request)
    }
}

private extension PasteResult {
    var wrotePasteboard: Bool {
        switch self {
        case .pasted, .copiedOnly:
            return true
        case .failed:
            return false
        }
    }

    var shouldHideOverlayAfterPaste: Bool {
        switch self {
        case .pasted, .copiedOnly:
            return true
        case .failed:
            return false
        }
    }
}
