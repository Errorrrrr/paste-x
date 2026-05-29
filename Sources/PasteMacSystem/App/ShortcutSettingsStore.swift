import Foundation
import PasteCore

public protocol ShortcutSettingsStoring: AnyObject {
    func loadShortcut() -> HotKeyShortcut?
    func saveShortcut(_ shortcut: HotKeyShortcut)
}

public final class UserDefaultsShortcutSettingsStore: ShortcutSettingsStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "PasteX.hotKeyShortcut"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func loadShortcut() -> HotKeyShortcut? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(HotKeyShortcut.self, from: data)
    }

    public func saveShortcut(_ shortcut: HotKeyShortcut) {
        guard let data = try? JSONEncoder().encode(shortcut) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
