import Foundation

public struct AppUpdate: Equatable, Sendable {
    public let version: String
    public let releaseURL: URL

    public init(version: String, releaseURL: URL) {
        self.version = version
        self.releaseURL = releaseURL
    }
}

public enum AppUpdateCheckResult: Equatable, Sendable {
    case upToDate(latestVersion: String)
    case updateAvailable(AppUpdate)
}

public enum AppUpdateError: Error, Equatable, Sendable {
    case invalidCurrentVersion
    case noPublishedRelease
    case invalidRelease
    case releaseNotReady
    case invalidResponse
    case httpStatus(Int)
    case network(String)
}

/// Checks published GitHub releases without downloading or replacing the running app.
public struct AppUpdateChecker: Sendable {
    typealias Request = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private static let repositoryPath = "/Errorrrrr/paste-x"
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/Errorrrrr/paste-x/releases/latest")!
    private let architecture: String
    private let request: Request

    public init() {
        self.init(architecture: Self.currentArchitecture) { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw AppUpdateError.invalidResponse
            }
            return (data, response)
        }
    }

    init(architecture: String, request: @escaping Request) {
        self.architecture = architecture
        self.request = request
    }

    public func check(currentVersion: String) async throws -> AppUpdateCheckResult {
        guard let current = SemanticVersion(currentVersion) else {
            throw AppUpdateError.invalidCurrentVersion
        }

        var request = URLRequest(url: Self.latestReleaseURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("PasteX-UpdateChecker", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await self.request(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as AppUpdateError {
            throw error
        } catch {
            throw AppUpdateError.network(error.localizedDescription)
        }

        if response.statusCode == 404 {
            throw AppUpdateError.noPublishedRelease
        }
        guard response.statusCode == 200 else {
            throw AppUpdateError.httpStatus(response.statusCode)
        }
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            throw AppUpdateError.invalidRelease
        }
        guard !release.draft, !release.prerelease else {
            throw AppUpdateError.noPublishedRelease
        }
        guard let latest = SemanticVersion(release.tagName) else {
            throw AppUpdateError.invalidRelease
        }
        guard latest.isStable else {
            throw AppUpdateError.noPublishedRelease
        }
        guard let releaseURL = trustedGitHubURL(
            release.htmlURL,
            path: "\(Self.repositoryPath)/releases/tag/\(release.tagName)"
        ) else {
            throw AppUpdateError.invalidRelease
        }
        guard latest > current else {
            return .upToDate(latestVersion: latest.description)
        }
        guard release.assets.contains(where: { asset in
            isInstallableAsset(asset, version: latest.description, tag: release.tagName)
        }) else {
            throw AppUpdateError.releaseNotReady
        }
        return .updateAvailable(AppUpdate(version: latest.description, releaseURL: releaseURL))
    }

    private func isInstallableAsset(_ asset: GitHubRelease.Asset, version: String, tag: String) -> Bool {
        let architectures = [architecture, "universal"]
        let names = architectures.flatMap { architecture in
            [
                "PasteX-\(version)-macos-\(architecture).dmg",
                "PasteX-\(version)-macos-\(architecture).zip",
                "PasteX-\(version)-macos-\(architecture)-qa-only.zip"
            ]
        }
        return asset.state == "uploaded"
            && asset.size > 0
            && names.contains(asset.name)
            && trustedGitHubURL(
                asset.browserDownloadURL,
                path: "\(Self.repositoryPath)/releases/download/\(tag)/\(asset.name)"
            ) != nil
    }

    private func trustedGitHubURL(_ value: String, path: String) -> URL? {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "github.com",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil,
              components.path == path else {
            return nil
        }
        return components.url
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let state: String
        let size: Int
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name, state, size
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case draft, prerelease, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

/// SemVer precedence uses decimal strings, so large version numbers cannot overflow.
struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    let description: String
    private let core: [String]
    private let prerelease: [String]

    var isStable: Bool { prerelease.isEmpty }

    init?(_ value: String) {
        let version = value.hasPrefix("v") || value.hasPrefix("V") ? String(value.dropFirst()) : value
        let buildParts = version.split(separator: "+", omittingEmptySubsequences: false)
        guard (1...2).contains(buildParts.count),
              buildParts.count == 1 || Self.validIdentifiers(String(buildParts[1]), numericLeadingZerosAllowed: true) else {
            return nil
        }
        let releaseParts = buildParts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = releaseParts[0].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard core.count == 3, core.allSatisfy(Self.validNumber) else { return nil }
        let prerelease: [String]
        if releaseParts.count == 2 {
            let identifiers = String(releaseParts[1])
            guard Self.validIdentifiers(identifiers, numericLeadingZerosAllowed: false) else { return nil }
            prerelease = identifiers.split(separator: ".").map(String.init)
        } else {
            prerelease = []
        }
        self.description = version
        self.core = core
        self.prerelease = prerelease
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.core == rhs.core && lhs.prerelease == rhs.prerelease
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for (left, right) in zip(lhs.core, rhs.core) where left != right {
            return numberIsLess(left, than: right)
        }
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
        }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            let leftIsNumber = isNumber(left)
            let rightIsNumber = isNumber(right)
            if leftIsNumber && rightIsNumber { return numberIsLess(left, than: right) }
            if leftIsNumber != rightIsNumber { return leftIsNumber }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func validIdentifiers(_ value: String, numericLeadingZerosAllowed: Bool) -> Bool {
        value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { identifier in
            guard !identifier.isEmpty, identifier.utf8.allSatisfy({ byte in
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45
            }) else { return false }
            return numericLeadingZerosAllowed || !isNumber(String(identifier)) || validNumber(String(identifier))
        }
    }

    private static func isNumber(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func validNumber(_ value: String) -> Bool {
        isNumber(value) && (value == "0" || !value.hasPrefix("0"))
    }

    private static func numberIsLess(_ lhs: String, than rhs: String) -> Bool {
        lhs.count == rhs.count ? lhs < rhs : lhs.count < rhs.count
    }
}
