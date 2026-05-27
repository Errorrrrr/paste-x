import AppKit
import Foundation
import PasteCore
import PasteIntegration

@main
enum PasteAppMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = PasteAppDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()

        _ = delegate
    }
}

@MainActor
private final class PasteAppDelegate: NSObject, NSApplicationDelegate {
    private var container: ClipboardAssistantDependencyContainer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let container = ClipboardAssistantDependencyContainer(
            quitHandler: {
                NSApp.terminate(nil)
            }
        )
        self.container = container

        switch container.start() {
        case .success:
            NSLog("Paste started with menu bar status item and default Cmd+Option+V hotkey.")
        case let .failure(error):
            NSLog("Paste started, but default hotkey registration failed: \(error.startupDescription)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        container?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        container?.app.toggleOverlay()
        return false
    }
}

private extension HotKeyError {
    var startupDescription: String {
        switch self {
        case .conflict:
            return "Cmd+Option+V is already registered by another app. The menu bar item remains available."
        case .unsupported:
            return "The default shortcut is unsupported. The menu bar item remains available."
        case let .systemFailure(message):
            return "\(message). The menu bar item remains available."
        }
    }
}
