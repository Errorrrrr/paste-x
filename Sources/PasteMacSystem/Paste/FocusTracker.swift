import AppKit
import Foundation
import PasteCore

public struct RunningApplicationInfo: Equatable, Sendable {
    public let bundleIdentifier: String?
    public let processIdentifier: Int32

    public init(bundleIdentifier: String?, processIdentifier: Int32) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }
}

public final class FocusTracker: NSObject, FocusTracking {
    public private(set) var currentTarget: PasteTarget?

    private let ownBundleIdentifier: String?
    private let ownProcessIdentifier: Int32
    private var isObserving = false
    public init(
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        ownProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        self.ownBundleIdentifier = ownBundleIdentifier
        self.ownProcessIdentifier = ownProcessIdentifier
        super.init()
    }

    public func start() {
        guard !isObserving else { return }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didActivateApplication(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        isObserving = true
    }

    public func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        isObserving = false
    }

    public func recordActivatedApplication(_ application: RunningApplicationInfo, at date: Date = Date()) {
        guard application.processIdentifier != ownProcessIdentifier else { return }

        if let bundleIdentifier = application.bundleIdentifier,
           let ownBundleIdentifier,
           bundleIdentifier == ownBundleIdentifier {
            return
        }

        currentTarget = PasteTarget(
            bundleIdentifier: application.bundleIdentifier,
            processIdentifier: application.processIdentifier,
            capturedAt: date
        )
    }

    @objc private func didActivateApplication(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        recordActivatedApplication(
            RunningApplicationInfo(
                bundleIdentifier: application.bundleIdentifier,
                processIdentifier: application.processIdentifier
            )
        )
    }
}
