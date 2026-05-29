import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public var id: String {
        rawValue
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var language: AppLanguage

    public init(language: AppLanguage = .english) {
        self.language = language
    }

    public static let `default` = AppSettings(language: .english)
}
