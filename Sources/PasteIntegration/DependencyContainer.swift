import Foundation
import PasteCore
import PasteMacSystem

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
        permissionPresenter: PermissionPresenting? = AccessibilityPermissionPresenter()
    ) {
        let historyStore = ClipboardHistoryStore(capacity: historyCapacity)
        let clipboardMonitor = ClipboardMonitor(
            source: clipboardSource,
            classifier: classifier,
            historyStore: historyStore,
            interval: monitorInterval
        )
        let focusTracker = FocusTracker()
        let overlayPresenter = ClipboardOverlayCoordinator(
            pasteCoordinator: pasteCoordinator,
            permissionPresenter: permissionPresenter,
            markSelfWrite: { [clipboardMonitor] item in
                clipboardMonitor.markSelfWrite(signature: item.signature)
            }
        )
        let toggleProxy = ClipboardAssistantToggleProxy()
        let statusItemController = StatusItemController {
            toggleProxy.toggleOverlay()
        }
        let app = ClipboardAssistantApp(
            hotKeyManager: hotKeyManager,
            clipboardMonitor: clipboardMonitor,
            historyStore: historyStore,
            overlayPresenter: overlayPresenter,
            focusTracker: focusTracker,
            statusItemController: statusItemController
        )

        toggleProxy.app = app

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
