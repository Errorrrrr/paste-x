import AppKit
import PasteCore
import SwiftUI

@MainActor
public final class OverlayWindowController: NSObject {
    private let store: OverlaySelectionStore
    private let onPasteRequested: (OverlayPasteRequest) -> Void
    private let onDismiss: () -> Void
    private var panel: OverlayPanel?
    private var feedbackHideTask: Task<Void, Never>?

    public init(
        store: OverlaySelectionStore = OverlaySelectionStore(),
        onPasteRequested: @escaping (OverlayPasteRequest) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onPasteRequested = onPasteRequested
        self.onDismiss = onDismiss
        super.init()
    }

    public var isVisible: Bool {
        panel?.isVisible == true
    }

    public func show(items: [ClipboardItem], on screen: NSScreen? = nil) {
        store.replaceItems(items)
        let panel = makePanelIfNeeded()
        position(panel: panel, on: screen ?? screenContainingMouse() ?? NSScreen.main)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func hideOverlay() {
        feedbackHideTask?.cancel()
        feedbackHideTask = nil
        store.clearFeedback()
        panel?.orderOut(nil)
        onDismiss()
    }

    public func showPasteFeedback(_ message: String, hideAfter delay: TimeInterval = 1.4) {
        store.showFeedback(message)
        feedbackHideTask?.cancel()

        let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
        feedbackHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            await MainActor.run {
                self?.hideOverlay()
            }
        }
    }

    private func toggleOnMain(items: [ClipboardItem]) {
        if isVisible {
            hideOverlay()
        } else {
            show(items: items)
        }
    }

    private func makePanelIfNeeded() -> OverlayPanel {
        if let panel {
            return panel
        }

        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: Layout.panelHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.keyDownHandler = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }

        let rootView = OverlayRootView(
            store: store,
            onPasteRequest: { [weak self] request in
                self?.onPasteRequested(request)
            }
        )

        panel.contentView = NSHostingView(rootView: rootView)
        self.panel = panel
        return panel
    }

    private func position(panel: NSPanel, on screen: NSScreen?) {
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 720, height: Layout.panelHeight)
        let width = max(Layout.minimumPanelWidth, visibleFrame.width - Layout.horizontalInset * 2)
        let frame = NSRect(
            x: visibleFrame.minX + (visibleFrame.width - width) / 2,
            y: visibleFrame.minY + Layout.bottomInset,
            width: width,
            height: Layout.panelHeight
        )

        panel.setFrame(frame, display: true)
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case KeyCode.leftArrow:
            store.selectPrevious()
            return true
        case KeyCode.rightArrow:
            store.selectNext()
            return true
        case KeyCode.space:
            requestPaste(trigger: .spaceKey)
            return true
        case KeyCode.returnKey, KeyCode.keypadEnter:
            requestPaste(trigger: .returnKey)
            return true
        case KeyCode.escape:
            hideOverlay()
            return true
        default:
            return false
        }
    }

    private func requestPaste(trigger: OverlayPasteTrigger) {
        guard let request = store.makePasteRequest(trigger: trigger) else {
            return
        }

        onPasteRequested(request)
    }
}

extension OverlayWindowController: OverlayPresenting {
    public nonisolated func toggle(items: [ClipboardItem], target: PasteTarget?) {
        Task { @MainActor [weak self] in
            self?.toggleOnMain(items: items)
        }
    }

    public nonisolated func hide() {
        Task { @MainActor [weak self] in
            self?.hideOverlay()
        }
    }
}

private enum Layout {
    static let panelHeight: CGFloat = 116
    static let minimumPanelWidth: CGFloat = 420
    static let horizontalInset: CGFloat = 18
    static let bottomInset: CGFloat = 18
}

private enum KeyCode {
    static let returnKey: UInt16 = 36
    static let space: UInt16 = 49
    static let escape: UInt16 = 53
    static let keypadEnter: UInt16 = 76
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
}

private final class OverlayPanel: NSPanel {
    var keyDownHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func keyDown(with event: NSEvent) {
        if keyDownHandler?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}
