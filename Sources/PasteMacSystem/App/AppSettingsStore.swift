import Foundation
import PasteCore

public protocol AppSettingsStoring: AnyObject {
    func loadSettings() -> AppSettings
    func saveSettings(_ settings: AppSettings)
}

public final class UserDefaultsAppSettingsStore: AppSettingsStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "PasteX.appSettings"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func loadSettings() -> AppSettings {
        guard let data = defaults.data(forKey: key) else {
            return .default
        }

        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? .default
    }

    public func saveSettings(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
