import Foundation

public struct PasteTarget: Codable, Equatable, Sendable {
    public let bundleIdentifier: String?
    public let processIdentifier: Int32
    public let capturedAt: Date

    public init(bundleIdentifier: String?, processIdentifier: Int32, capturedAt: Date) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.capturedAt = capturedAt
    }
}
