import Foundation
import Testing
@testable import PasteMacSystem

@Test func semanticVersionComparesNumericComponentsAndPrereleasePrecedence() throws {
    let ordered = [
        "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
        "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.9",
        "1.0.10", "1.9.0", "1.10.0", "2.0.0", "999999999999999999999999.0.0"
    ]
    let versions = try ordered.map { try #require(SemanticVersion($0)) }
    for (previous, next) in zip(versions, versions.dropFirst()) {
        #expect(previous < next)
        #expect(!(next < previous))
    }
    #expect(SemanticVersion("v1.2.3") == SemanticVersion("1.2.3+build.42"))
    #expect(SemanticVersion("1.2.3+001") == SemanticVersion("V1.2.3+another"))
}

@Test(arguments: ["", "1", "1.2", "1.2.3.4", "01.2.3", "1.-2.3", "1.2.3-", "1.2.3-01", "1.2.3-alpha..1", "1.2.3+", "1.2.3+a+b", "1.2.3+bad/name", " 1.2.3", "1.2.3\n", "１.2.3"])
func semanticVersionRejectsMalformedVersions(_ value: String) {
    #expect(SemanticVersion(value) == nil)
}

@Test func updateCheckerFindsNewerReleaseAndSendsGitHubHeaders() async throws {
    let checker = AppUpdateChecker(architecture: "arm64") { request in
        #expect(request.url?.absoluteString == "https://api.github.com/repos/Errorrrrr/paste-x/releases/latest")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.timeoutInterval == 20)
        return try response(data: releaseData())
    }

    let result = try await checker.check(currentVersion: "1.1.2")

    #expect(result == .updateAvailable(AppUpdate(
        version: "1.2.0",
        releaseURL: URL(string: "https://github.com/Errorrrrr/paste-x/releases/tag/v1.2.0")!
    )))
}

@Test(arguments: ["1.2.0", "1.2.0+local.1", "2.0.0"])
func updateCheckerDoesNotOfferSameVersionOrDowngrade(_ current: String) async throws {
    let checker = checker(data: try releaseData())

    #expect(try await checker.check(currentVersion: current) == .upToDate(latestVersion: "1.2.0"))
}

@Test func updateCheckerOffersStableReleaseToPrereleaseUser() async throws {
    let result = try await checker(data: releaseData()).check(currentVersion: "1.2.0-rc.2")
    guard case .updateAvailable(let update) = result else {
        Issue.record("Expected the stable release to replace the prerelease")
        return
    }
    #expect(update.version == "1.2.0")
}

@Test func updateCheckerRejectsInvalidCurrentVersionBeforeNetworking() async {
    let checker = AppUpdateChecker(architecture: "arm64") { _ in
        Issue.record("An invalid current version must not trigger networking")
        throw URLError(.badURL)
    }
    await #expect(throws: AppUpdateError.invalidCurrentVersion) {
        try await checker.check(currentVersion: "unknown")
    }
}

@Test func updateCheckerSkipsDraftsAndPrereleases() async throws {
    for data in [
        try releaseData(draft: true),
        try releaseData(prerelease: true),
        try releaseData(tag: "v1.2.0-beta.1")
    ] {
        await #expect(throws: AppUpdateError.noPublishedRelease) {
            try await checker(data: data).check(currentVersion: "1.1.2")
        }
    }
}

@Test func updateCheckerRejectsMissingUnreadyOrIncompatiblePackages() async throws {
    let assets = [
        [],
        [asset(name: "Source.zip")],
        [asset(name: "PasteX-1.2.0-macos-x86_64.zip")],
        [asset(state: "new")],
        [asset(size: 0)],
        [asset(downloadURL: "https://example.com/PasteX-1.2.0-macos-arm64.zip")],
        [asset(downloadURL: "https://github.com/another/repo/releases/download/v1.2.0/PasteX-1.2.0-macos-arm64.zip")]
    ]
    for assets in assets {
        let data = try releaseData(assets: assets)
        await #expect(throws: AppUpdateError.releaseNotReady) {
            try await checker(data: data).check(currentVersion: "1.1.2")
        }
    }
}

@Test(arguments: ["arm64", "x86_64"])
func updateCheckerAcceptsDMGOnlyReleaseForNativeAndUniversalArchitectures(_ architecture: String) async throws {
    for packageArchitecture in [architecture, "universal"] {
        let data = try releaseData(assets: [asset(name: "PasteX-1.2.0-macos-\(packageArchitecture).dmg")])
        let result = try await checker(data: data, architecture: architecture).check(currentVersion: "1.1.5")

        #expect(result == .updateAvailable(AppUpdate(
            version: "1.2.0",
            releaseURL: URL(string: "https://github.com/Errorrrrr/paste-x/releases/tag/v1.2.0")!
        )))
    }
}

@Test func updateCheckerRejectsUnreadyIncompatibleOrUntrustedDMGs() async throws {
    let name = "PasteX-1.2.0-macos-arm64.dmg"
    let assets = [
        asset(name: "PasteX-1.2.0-macos-x86_64.dmg"),
        asset(name: "PasteX-1.1.9-macos-arm64.dmg"),
        asset(name: name, state: "new"),
        asset(name: name, size: 0),
        asset(name: name, downloadURL: "https://example.com/\(name)"),
        asset(name: name, downloadURL: "http://github.com/Errorrrrr/paste-x/releases/download/v1.2.0/\(name)"),
        asset(name: name, downloadURL: "https://github.com/another/repo/releases/download/v1.2.0/\(name)"),
        asset(name: name, downloadURL: "https://github.com/Errorrrrr/paste-x/releases/download/v1.1.9/\(name)"),
        asset(name: name, downloadURL: "https://github.com/Errorrrrr/paste-x/releases/download/v1.2.0/\(name)?redirect=example.com")
    ]
    for asset in assets {
        let data = try releaseData(assets: [asset])
        await #expect(throws: AppUpdateError.releaseNotReady) {
            try await checker(data: data).check(currentVersion: "1.1.5")
        }
    }
}

@Test(arguments: [
    "PasteX-1.2.0-macos-arm64.zip",
    "PasteX-1.2.0-macos-arm64-qa-only.zip",
    "PasteX-1.2.0-macos-universal.zip",
    "PasteX-1.2.0-macos-universal-qa-only.zip"
])
func updateCheckerRetainsPublishedZIPAndLegacyQACompatibility(_ name: String) async throws {
    let result = try await checker(data: releaseData(assets: [asset(name: name)])).check(currentVersion: "1.1.2")
    guard case .updateAvailable = result else {
        Issue.record("Expected a compatible published package to be available")
        return
    }
}

@Test(arguments: [
    "https://example.com/Errorrrrr/paste-x/releases/tag/v1.2.0",
    "http://github.com/Errorrrrr/paste-x/releases/tag/v1.2.0",
    "https://github.com/other/repo/releases/tag/v1.2.0",
    "https://github.com/Errorrrrr/paste-x/releases/tag/v1.1.0",
    "https://github.com/Errorrrrr/paste-x/releases/tag/v1.2.0?redirect=example.com",
    "https://user@github.com/Errorrrrr/paste-x/releases/tag/v1.2.0",
    "https://github.com:443/Errorrrrr/paste-x/releases/tag/v1.2.0"
])
func updateCheckerRejectsUntrustedReleaseURLs(_ url: String) async throws {
    let data = try releaseData(htmlURL: url)
    await #expect(throws: AppUpdateError.invalidRelease) {
        try await checker(data: data).check(currentVersion: "1.1.2")
    }
}

@Test func updateCheckerHandlesHTTPAndNetworkFailures() async throws {
    for code in [403, 429, 500] {
        await #expect(throws: AppUpdateError.httpStatus(code)) {
            try await checker(data: Data(), status: code).check(currentVersion: "1.1.2")
        }
    }
    await #expect(throws: AppUpdateError.noPublishedRelease) {
        try await checker(data: Data(), status: 404).check(currentVersion: "1.1.2")
    }

    let offline = AppUpdateChecker(architecture: "arm64") { _ in throw URLError(.notConnectedToInternet) }
    await #expect(throws: AppUpdateError.network(URLError(.notConnectedToInternet).localizedDescription)) {
        try await offline.check(currentVersion: "1.1.2")
    }
}

@Test func updateCheckerPreservesCancellation() async {
    let cancelled = AppUpdateChecker(architecture: "arm64") { _ in throw URLError(.cancelled) }
    await #expect(throws: CancellationError.self) {
        try await cancelled.check(currentVersion: "1.1.2")
    }
}

@Test func updateCheckerRejectsMalformedReleaseResponse() async throws {
    for data in [Data("not json".utf8), Data("{}".utf8), try releaseData(tag: "latest")] {
        await #expect(throws: AppUpdateError.invalidRelease) {
            try await checker(data: data).check(currentVersion: "1.1.2")
        }
    }
}

private func checker(data: Data, status: Int = 200, architecture: String = "arm64") -> AppUpdateChecker {
    AppUpdateChecker(architecture: architecture) { _ in try response(data: data, status: status) }
}

private func response(data: Data, status: Int = 200) throws -> (Data, HTTPURLResponse) {
    let response = try #require(HTTPURLResponse(
        url: URL(string: "https://api.github.com/repos/Errorrrrr/paste-x/releases/latest")!,
        statusCode: status,
        httpVersion: nil,
        headerFields: nil
    ))
    return (data, response)
}

private func asset(
    name: String = "PasteX-1.2.0-macos-arm64.zip",
    state: String = "uploaded",
    size: Int = 1024,
    downloadURL: String? = nil
) -> [String: Any] {
    [
        "name": name,
        "state": state,
        "size": size,
        "browser_download_url": downloadURL ?? "https://github.com/Errorrrrr/paste-x/releases/download/v1.2.0/\(name)"
    ]
}

private func releaseData(
    tag: String = "v1.2.0",
    draft: Bool = false,
    prerelease: Bool = false,
    htmlURL: String? = nil,
    assets: [[String: Any]]? = nil
) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "tag_name": tag,
        "html_url": htmlURL ?? "https://github.com/Errorrrrr/paste-x/releases/tag/\(tag)",
        "draft": draft,
        "prerelease": prerelease,
        "assets": assets ?? [asset()]
    ])
}
