import AppKit
import SwiftUI

/// A child window, not a sheet: AppKit must never reposition the bottom overlay to fit dialog content.
@MainActor
final class OverlayDialogController: NSObject, NSWindowDelegate {
    private(set) var window: NSPanel?
    private var onClose: (() -> Void)?
    private weak var parent: NSWindow?

    func present<Content: View>(content: Content, title: String, size: NSSize, parent: NSWindow, onClose: @escaping () -> Void) {
        close()
        self.parent = parent
        self.onClose = onClose
        let window = OverlayDialogPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = parent.level
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.delegate = self
        let host = NSHostingView(rootView: ScrollView(.vertical) { content })
        // Dialogs have a stable frame. Editing text or opening a nested confirmation must
        // not let SwiftUI's intrinsic-size changes pull the parent overlay around.
        host.sizingOptions = []
        window.contentView = host
        let visibleFrame = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parent.frame
        window.setContentSize(size)
        let frame = Self.frame(size: window.frame.size, overlay: parent.frame, visibleScreen: visibleFrame)
        window.setFrame(frame, display: false)
        parent.addChildWindow(window, ordered: .above)
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let window else { return }
        self.window = nil
        onClose = nil
        parent?.removeChildWindow(window)
        parent = nil
        window.delegate = nil
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        let callback = onClose
        if let window { parent?.removeChildWindow(window) }
        window = nil
        parent?.makeKey()
        parent = nil
        onClose = nil
        callback?()
    }

    nonisolated static func frame(size: NSSize, overlay: NSRect, visibleScreen: NSRect) -> NSRect {
        let width = min(size.width, visibleScreen.width)
        let height = min(size.height, visibleScreen.height)
        let x = min(max(overlay.midX - width / 2, visibleScreen.minX), visibleScreen.maxX - width)
        let y = min(max(visibleScreen.midY - height / 2, visibleScreen.minY), visibleScreen.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private final class OverlayDialogPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}
