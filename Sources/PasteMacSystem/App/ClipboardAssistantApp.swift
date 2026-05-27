import AppKit
import Foundation
import PasteCore

@MainActor
public final class ClipboardAssistantApp {
    private let hotKeyManager: HotKeyManaging
    private let clipboardMonitor: ClipboardMonitoring
    private let historyStore: ClipboardHistoryProviding
    private let overlayPresenter: OverlayPresenting
    private let focusTracker: FocusTracking
    private let statusItemController: StatusItemController
    private let shortcut: HotKeyShortcut

    public init(
        hotKeyManager: HotKeyManaging,
        clipboardMonitor: ClipboardMonitoring,
        historyStore: ClipboardHistoryProviding,
        overlayPresenter: OverlayPresenting,
        focusTracker: FocusTracking,
        statusItemController: StatusItemController,
        shortcut: HotKeyShortcut = .defaultToggleOverlay
    ) {
        self.hotKeyManager = hotKeyManager
        self.clipboardMonitor = clipboardMonitor
        self.historyStore = historyStore
        self.overlayPresenter = overlayPresenter
        self.focusTracker = focusTracker
        self.statusItemController = statusItemController
        self.shortcut = shortcut
    }

    public func start() -> Result<Void, HotKeyError> {
        NSApp.setActivationPolicy(.accessory)
        statusItemController.install()
        clipboardMonitor.start()

        let result = hotKeyManager.register(shortcut: shortcut) { [weak self] in
            Task { @MainActor in
                self?.toggleOverlay()
            }
        }

        switch result {
        case .success:
            statusItemController.clearHotKeyRegistrationNotice()
        case let .failure(error):
            statusItemController.showHotKeyRegistrationFailure(error, shortcut: shortcut)
        }

        return result
    }

    public func stop() {
        hotKeyManager.unregister()
        clipboardMonitor.stop()
        statusItemController.uninstall()
        overlayPresenter.hide()
    }

    public func toggleOverlay() {
        let target = refreshedPasteTarget()
        overlayPresenter.toggle(items: historyStore.items, target: target)
    }

    private func refreshedPasteTarget() -> PasteTarget? {
        if let focusTracker = focusTracker as? FocusTargetRefreshing {
            return focusTracker.refreshCurrentTarget(at: Date())
        }

        return focusTracker.currentTarget
    }
}
