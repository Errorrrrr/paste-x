import Foundation

public struct HotKeyShortcut: Codable, Equatable, Sendable {
    public let keyEquivalent: String
    public let modifiers: Set<String>

    public init(keyEquivalent: String, modifiers: Set<String>) {
        self.keyEquivalent = keyEquivalent
        self.modifiers = modifiers
    }
}

public enum HotKeyError: Error, Equatable, Sendable {
    case conflict
    case unsupported
    case systemFailure(String)
}

public protocol ClipboardClassifying {
    func makeItem(from payloads: [ClipboardPayload], createdAt: Date) -> ClipboardItem?
}

public protocol ClipboardHistoryProviding: AnyObject {
    var items: [ClipboardItem] { get }

    func insert(_ item: ClipboardItem)
    func clear()
}

public protocol ClipboardMonitoring: AnyObject {
    func start()
    func stop()
}

public protocol FocusTracking: AnyObject {
    var currentTarget: PasteTarget? { get }
}

public protocol HotKeyManaging: AnyObject {
    func register(shortcut: HotKeyShortcut, handler: @escaping @Sendable () -> Void) -> Result<Void, HotKeyError>
    func unregister()
}

public protocol OverlayPresenting: AnyObject {
    func toggle(items: [ClipboardItem], target: PasteTarget?)
    func hide()
    func updateLanguage(_ language: AppLanguage)
}

public extension OverlayPresenting {
    func updateLanguage(_ language: AppLanguage) {}
}

public protocol PasteCoordinating: AnyObject {
    func paste(_ item: ClipboardItem, to target: PasteTarget?) async -> PasteResult
}

public protocol PermissionPresenting: AnyObject {
    func ensureAccessibilityPermission() -> Bool
    func openAccessibilitySettings()
}
