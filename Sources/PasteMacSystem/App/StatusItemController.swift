import AppKit
import Foundation
import PasteCore

struct HotKeyRegistrationNotice: Equatable, Sendable {
    let menuTitle: String
    let fallbackTitle: String
    let toolTip: String

    static func failure(error: HotKeyError, shortcut: HotKeyShortcut) -> HotKeyRegistrationNotice {
        let shortcutName = shortcut.displayName
        let reason: String
        switch error {
        case .conflict:
            reason = "\(shortcutName) is already used by another app"
        case .unsupported:
            reason = "\(shortcutName) is not supported on this Mac"
        case let .systemFailure(message):
            reason = message
        }

        return HotKeyRegistrationNotice(
            menuTitle: "Shortcut unavailable: \(reason)",
            fallbackTitle: "Show Clipboard History (menu fallback)",
            toolTip: "Paste clipboard history. Shortcut unavailable: \(reason). Use the menu bar icon or menu fallback."
        )
    }
}

@MainActor
public final class StatusItemController: NSObject {
    private let toggleHandler: () -> Void
    private let quitHandler: (() -> Void)?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private(set) var hotKeyNotice: HotKeyRegistrationNotice?

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
        item.button?.toolTip = currentToolTip
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

    public func clearHotKeyRegistrationNotice() {
        hotKeyNotice = nil
        updateToolTip()
    }

    public func showHotKeyRegistrationFailure(_ error: HotKeyError, shortcut: HotKeyShortcut) {
        hotKeyNotice = .failure(error: error, shortcut: shortcut)
        updateToolTip()
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
        if let hotKeyNotice {
            let warningItem = NSMenuItem(
                title: hotKeyNotice.menuTitle,
                action: nil,
                keyEquivalent: ""
            )
            warningItem.isEnabled = false
            menu.addItem(warningItem)
        }

        let toggleItem = NSMenuItem(
            title: hotKeyNotice?.fallbackTitle ?? "Show Clipboard History",
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

    private var currentToolTip: String {
        hotKeyNotice?.toolTip ?? "Paste clipboard history"
    }

    private func updateToolTip() {
        statusItem?.button?.toolTip = currentToolTip
    }
}

private extension HotKeyShortcut {
    var displayName: String {
        let modifierNames: [(String, String)] = [
            ("command", "Cmd"),
            ("option", "Option"),
            ("control", "Control"),
            ("shift", "Shift")
        ]
        let displayModifiers = modifierNames.compactMap { key, name in
            modifiers.contains(key) ? name : nil
        }
        let keyName: String
        switch keyEquivalent.lowercased() {
        case "space":
            keyName = "Space"
        case "return":
            keyName = "Return"
        case "escape":
            keyName = "Escape"
        default:
            keyName = keyEquivalent.uppercased()
        }

        return (displayModifiers + [keyName]).joined(separator: "+")
    }
}
