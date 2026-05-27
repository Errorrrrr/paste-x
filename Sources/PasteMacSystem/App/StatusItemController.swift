import AppKit
import Foundation

@MainActor
public final class StatusItemController: NSObject {
    private let toggleHandler: () -> Void
    private var statusItem: NSStatusItem?

    public init(toggleHandler: @escaping () -> Void) {
        self.toggleHandler = toggleHandler
        super.init()
    }

    public func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "Paste clipboard history"
        )
        item.button?.target = self
        item.button?.action = #selector(didClickStatusItem)
        statusItem = item
    }

    public func uninstall() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    @objc private func didClickStatusItem() {
        toggleHandler()
    }
}
