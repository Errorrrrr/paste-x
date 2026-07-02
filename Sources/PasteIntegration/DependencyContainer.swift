import Foundation
import PasteCore
import PasteMacSystem
import PasteOverlay

@MainActor
public final class ClipboardAssistantDependencyContainer {
    public let historyStore: ClipboardHistoryStore
    public let clipboardMonitor: ClipboardMonitor
    public let focusTracker: FocusTracker
    public let overlayPresenter: ClipboardOverlayCoordinator
    public let app: ClipboardAssistantApp

    private let toggleProxy: ClipboardAssistantToggleProxy

    public init(
        historyCapacity: Int = 50,
        monitorInterval: TimeInterval = 0.5,
        hotKeyManager: HotKeyManaging = HotKeyManager(),
        clipboardSource: ClipboardPayloadSource = SystemClipboardPayloadSource(),
        classifier: ClipboardClassifying = ClipboardClassifier(),
        pasteCoordinator: PasteCoordinating = PasteCoordinator(),
        permissionPresenter: PermissionPresenting? = AccessibilityPermissionPresenter(),
        settingsPresenter: ShortcutSettingsPresenting? = ShortcutSettingsPresenter(),
        shortcutStore: ShortcutSettingsStoring? = UserDefaultsShortcutSettingsStore(),
        appSettingsStore: AppSettingsStoring? = UserDefaultsAppSettingsStore(),
        launchAtLoginManager: LaunchAtLoginManaging? = SMAppServiceLaunchAtLoginManager(),
        settingsHandler: (() -> Void)? = nil,
        quitHandler: (() -> Void)? = nil
    ) {
        let appSettings = appSettingsStore?.loadSettings() ?? .default
        let historyStore = ClipboardHistoryStore(capacity: historyCapacity)
        let focusTracker = FocusTracker()
        let commandProxy = ClipboardAssistantCommandProxy(
            settingsHandler: settingsHandler,
            quitHandler: quitHandler
        )
        let toggleProxy = ClipboardAssistantToggleProxy()
        let canOpenSettings = settingsHandler != nil || settingsPresenter != nil
        let statusItemController = StatusItemController(
            language: appSettings.language,
            toggleHandler: {
                toggleProxy.toggleOverlay()
            },
            settingsHandler: canOpenSettings ? {
                commandProxy.openSettings()
            } : nil,
            quitHandler: quitHandler != nil ? {
                commandProxy.quit()
            } : nil
        )
        let clipboardMonitor = ClipboardMonitor(
            source: clipboardSource,
            classifier: classifier,
            historyStore: historyStore,
            interval: monitorInterval,
            newItemHandler: { [weak statusItemController] _ in
                Task { @MainActor in
                    statusItemController?.playClipboardCaptureAnimation()
                }
            }
        )
        let overlayPresenter = ClipboardOverlayCoordinator(
            pasteCoordinator: pasteCoordinator,
            permissionPresenter: permissionPresenter,
            language: appSettings.language,
            markSelfWrite: { [clipboardMonitor] item in
                clipboardMonitor.markSelfWrite(signature: item.signature)
            },
            cancelSelfWrite: { [clipboardMonitor] item in
                clipboardMonitor.cancelSelfWrite(signature: item.signature)
            },
            promoteHistoryItem: { [historyStore] item in
                historyStore.insert(item)
            },
            onMenuAction: { [commandProxy] action in
                commandProxy.handle(action)
            }
        )
        let shortcut = shortcutStore?.loadShortcut() ?? .defaultToggleOverlay
        let app = ClipboardAssistantApp(
            hotKeyManager: hotKeyManager,
            clipboardMonitor: clipboardMonitor,
            historyStore: historyStore,
            overlayPresenter: overlayPresenter,
            focusTracker: focusTracker,
            statusItemController: statusItemController,
            settingsPresenter: settingsPresenter,
            shortcutStore: shortcutStore,
            settingsStore: appSettingsStore,
            launchAtLoginManager: launchAtLoginManager,
            shortcut: shortcut,
            settings: appSettings
        )

        toggleProxy.app = app
        commandProxy.app = app

        self.historyStore = historyStore
        self.clipboardMonitor = clipboardMonitor
        self.focusTracker = focusTracker
        self.overlayPresenter = overlayPresenter
        self.app = app
        self.toggleProxy = toggleProxy
    }

    @discardableResult
    public func start() -> Result<Void, HotKeyError> {
        focusTracker.start()
        return app.start()
    }

    public func stop() {
        app.stop()
        focusTracker.stop()
    }
}

@MainActor
private final class ClipboardAssistantToggleProxy {
    weak var app: ClipboardAssistantApp?

    func toggleOverlay() {
        app?.toggleOverlay()
    }
}

@MainActor
private final class ClipboardAssistantCommandProxy {
    weak var app: ClipboardAssistantApp?
    private let settingsHandler: (() -> Void)?
    private let quitHandler: (() -> Void)?

    init(settingsHandler: (() -> Void)?, quitHandler: (() -> Void)?) {
        self.settingsHandler = settingsHandler
        self.quitHandler = quitHandler
    }

    func handle(_ action: OverlayMenuAction) {
        switch action {
        case .settings:
            openSettings()
        case .close:
            closeOverlay()
        case .quit:
            quit()
        }
    }

    func openSettings() {
        if let settingsHandler {
            settingsHandler()
            return
        }

        app?.openSettings()
    }

    func quit() {
        quitHandler?()
    }

    func closeOverlay() {
        app?.closeOverlay()
    }
}
