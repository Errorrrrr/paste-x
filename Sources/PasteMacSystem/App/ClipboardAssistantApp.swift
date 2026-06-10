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
    private let settingsPresenter: ShortcutSettingsPresenting?
    private let shortcutStore: ShortcutSettingsStoring?
    private let settingsStore: AppSettingsStoring?
    private var shortcut: HotKeyShortcut
    private var settings: AppSettings

    public init(
        hotKeyManager: HotKeyManaging,
        clipboardMonitor: ClipboardMonitoring,
        historyStore: ClipboardHistoryProviding,
        overlayPresenter: OverlayPresenting,
        focusTracker: FocusTracking,
        statusItemController: StatusItemController,
        settingsPresenter: ShortcutSettingsPresenting? = nil,
        shortcutStore: ShortcutSettingsStoring? = nil,
        settingsStore: AppSettingsStoring? = nil,
        shortcut: HotKeyShortcut = .defaultToggleOverlay,
        settings: AppSettings = .default
    ) {
        self.hotKeyManager = hotKeyManager
        self.clipboardMonitor = clipboardMonitor
        self.historyStore = historyStore
        self.overlayPresenter = overlayPresenter
        self.focusTracker = focusTracker
        self.statusItemController = statusItemController
        self.settingsPresenter = settingsPresenter
        self.shortcutStore = shortcutStore
        self.settingsStore = settingsStore
        self.shortcut = shortcut
        self.settings = settings
        apply(settings: settings)
    }

    public func start() -> Result<Void, HotKeyError> {
        NSApp.setActivationPolicy(.accessory)
        statusItemController.install()
        clipboardMonitor.start()

        return registerActiveShortcut()
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

    public func openSettings() {
        overlayPresenter.hide()
        settingsPresenter?.openSettings(
            currentShortcut: shortcut,
            defaultShortcut: .defaultToggleOverlay,
            currentSettings: settings,
            saveHandler: { [weak self] shortcut in
                guard let self else {
                    return .failure(.systemFailure("PasteX is no longer running"))
                }

                return self.updateShortcut(shortcut)
            },
            settingsChangeHandler: { [weak self] settings in
                self?.updateSettings(settings)
            }
        )
    }

    public func closeOverlay() {
        overlayPresenter.hide()
    }

    @discardableResult
    public func updateShortcut(_ newShortcut: HotKeyShortcut) -> Result<Void, HotKeyError> {
        guard newShortcut != shortcut else {
            shortcutStore?.saveShortcut(newShortcut)
            return .success(())
        }

        let previousShortcut = shortcut
        let result = register(shortcut: newShortcut)
        switch result {
        case .success:
            shortcut = newShortcut
            shortcutStore?.saveShortcut(newShortcut)
            statusItemController.clearHotKeyRegistrationNotice()
        case let .failure(error):
            _ = register(shortcut: previousShortcut)
            shortcut = previousShortcut
            statusItemController.showHotKeyRegistrationFailure(error, shortcut: newShortcut)
        }

        return result
    }

    public func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        settingsStore?.saveSettings(newSettings)
        apply(settings: newSettings)
    }

    func registerActiveShortcut() -> Result<Void, HotKeyError> {
        let result = register(shortcut: shortcut)

        switch result {
        case .success:
            statusItemController.clearHotKeyRegistrationNotice()
        case let .failure(error):
            statusItemController.showHotKeyRegistrationFailure(error, shortcut: shortcut)
        }

        return result
    }

    private func register(shortcut: HotKeyShortcut) -> Result<Void, HotKeyError> {
        hotKeyManager.register(shortcut: shortcut) { [weak self] in
            Task { @MainActor in
                self?.toggleOverlay()
            }
        }
    }

    private func apply(settings: AppSettings) {
        statusItemController.updateLanguage(settings.language)
        overlayPresenter.updateLanguage(settings.language)
    }

    private func refreshedPasteTarget() -> PasteTarget? {
        if let focusTracker = focusTracker as? FocusTargetRefreshing {
            return focusTracker.refreshCurrentTarget(at: Date())
        }

        return focusTracker.currentTarget
    }
}
