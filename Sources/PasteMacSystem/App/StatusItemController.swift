import AppKit
import Foundation

@MainActor
public final class StatusItemController: NSObject {
    private let toggleHandler: () -> Void
    private let quitHandler: (() -> Void)?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?

    public init(toggleHandler: @escaping () -> Void, quitHandler: (() -> Void)? = nil) {
        self.toggleHandler = toggleHandler
        self.quitHandler = quitHandler
        super.init()
    }

    public func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "Paste clipboard history"
        )
        item.button?.toolTip = "Paste clipboard history"
        item.button?.target = self
        item.button?.action = #selector(didClickStatusItem)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    public func uninstall() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    @objc private func didClickStatusItem() {
        if shouldOpenMenu {
            openMenu()
            return
        }

        toggleHandler()
    }

    @objc private func didChooseToggleOverlay() {
        toggleHandler()
    }

    @objc private func didChooseQuit() {
        quitHandler?()
    }

    private var shouldOpenMenu: Bool {
        guard let event = NSApp.currentEvent else { return false }
        return event.type == .rightMouseUp || event.modifierFlags.contains(.control)
    }

    private func openMenu() {
        guard let statusItem else { return }

        let menu = NSMenu()
        let toggleItem = NSMenuItem(
            title: "Show Clipboard History",
            action: #selector(didChooseToggleOverlay),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        if quitHandler != nil {
            menu.addItem(.separator())
            let quitItem = NSMenuItem(
                title: "Quit Paste",
                action: #selector(didChooseQuit),
                keyEquivalent: "q"
            )
            quitItem.target = self
            menu.addItem(quitItem)
        }

        statusMenu = menu
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
        statusMenu = nil
    }
}
