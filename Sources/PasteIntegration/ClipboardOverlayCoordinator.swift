import AppKit
import Foundation
import PasteCore
import PasteOverlay

@MainActor
public protocol ClipboardOverlayWindowControlling: AnyObject {
    var isVisible: Bool { get }

    func show(items: [ClipboardItem], on screen: NSScreen?)
    func hideOverlay()
    func showPasteFeedback(_ message: String, hideAfter delay: TimeInterval)
    func updateLanguage(_ language: AppLanguage)
}

public extension ClipboardOverlayWindowControlling {
    func updateLanguage(_ language: AppLanguage) {}
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
    private let cancelSelfWrite: (ClipboardItem) -> Void
    private let onMenuAction: (OverlayMenuAction) -> Void
    private var language: AppLanguage
    private var currentTarget: PasteTarget?

    public private(set) var lastPasteResult: PasteResult?

    public convenience init(
        pasteCoordinator: PasteCoordinating,
        permissionPresenter: PermissionPresenting?,
        language: AppLanguage = .english,
        markSelfWrite: @escaping (ClipboardItem) -> Void,
        cancelSelfWrite: @escaping (ClipboardItem) -> Void = { _ in },
        onMenuAction: @escaping (OverlayMenuAction) -> Void = { _ in }
    ) {
        let relay = OverlayPasteRequestRelay()
        let windowController = OverlayWindowController(
            language: language,
            onPasteRequested: { [relay] request in
                relay.submit(request)
            },
            onMenuAction: { [relay] action in
                relay.submit(action)
            }
        )

        self.init(
            windowController: windowController,
            pasteCoordinator: pasteCoordinator,
            permissionPresenter: permissionPresenter,
            language: language,
            markSelfWrite: markSelfWrite,
            cancelSelfWrite: cancelSelfWrite,
            onMenuAction: onMenuAction
        )

        relay.handler = { [weak self] request in
            self?.submit(request)
        }
        relay.menuHandler = { [weak self] action in
            self?.submit(action)
        }
    }

    public init(
        windowController: ClipboardOverlayWindowControlling,
        pasteCoordinator: PasteCoordinating,
        permissionPresenter: PermissionPresenting?,
        language: AppLanguage = .english,
        markSelfWrite: @escaping (ClipboardItem) -> Void,
        cancelSelfWrite: @escaping (ClipboardItem) -> Void = { _ in },
        onMenuAction: @escaping (OverlayMenuAction) -> Void = { _ in }
    ) {
        self.windowController = windowController
        self.pasteCoordinator = SendablePasteCoordinator(base: pasteCoordinator)
        self.permissionPresenter = permissionPresenter
        self.markSelfWrite = markSelfWrite
        self.cancelSelfWrite = cancelSelfWrite
        self.onMenuAction = onMenuAction
        self.language = language
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

    public func submit(_ action: OverlayMenuAction) {
        onMenuAction(action)
    }

    public nonisolated func updateLanguage(_ language: AppLanguage) {
        Task { @MainActor [weak self] in
            self?.language = language
            self?.windowController.updateLanguage(language)
        }
    }

    @discardableResult
    public func paste(_ request: OverlayPasteRequest) async -> PasteResult {
        _ = permissionPresenter?.ensureAccessibilityPermission()

        let coordinator = pasteCoordinator
        let expectsPasteboardWrite = !request.item.payloads.isEmpty
        if expectsPasteboardWrite {
            markSelfWrite(request.item)
        }

        let result = await coordinator.paste(request.item, to: currentTarget)
        lastPasteResult = result

        if expectsPasteboardWrite && !result.wrotePasteboard {
            cancelSelfWrite(request.item)
        }

        if let feedbackMessage = result.copyOnlyFeedbackMessage(language: language) {
            windowController.showPasteFeedback(feedbackMessage, hideAfter: Constants.copyOnlyFeedbackDuration)
        } else if result.shouldHideOverlayAfterPaste {
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
    var menuHandler: ((OverlayMenuAction) -> Void)?

    @MainActor
    func submit(_ request: OverlayPasteRequest) {
        handler?(request)
    }

    @MainActor
    func submit(_ action: OverlayMenuAction) {
        menuHandler?(action)
    }
}

private extension PasteResult {
    func copyOnlyFeedbackMessage(language: AppLanguage) -> String? {
        switch self {
        case let .copiedOnly(reason):
            return reason.feedbackMessage(language: language)
        case .pasted, .failed:
            return nil
        }
    }

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

private extension PasteFallbackReason {
    func feedbackMessage(language: AppLanguage) -> String {
        switch self {
        case .accessibilityNotTrusted:
            return language == .english
                ? "Copied to clipboard. Enable Accessibility to paste automatically."
                : "已复制到剪贴板。请开启辅助功能权限以自动粘贴。"
        case .targetUnavailable:
            return language == .english
                ? "Copied to clipboard. Reopen PasteX from the target app to paste automatically."
                : "已复制到剪贴板。请从目标应用重新打开 PasteX 以自动粘贴。"
        case .activationFailed:
            return language == .english
                ? "Copied to clipboard. Could not return to the target app."
                : "已复制到剪贴板。无法返回目标应用。"
        case .eventPostFailed:
            return language == .english
                ? "Copied to clipboard. Could not send the paste command."
                : "已复制到剪贴板。无法发送粘贴命令。"
        }
    }
}

private enum Constants {
    static let copyOnlyFeedbackDuration: TimeInterval = 1.4
}
