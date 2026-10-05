import Combine
import Foundation
import PasteCore
import Testing
@testable import PasteMacSystem

@Test @MainActor func updateModelCoalescesRepeatedChecksAndAllowsRetry() async throws {
    let requests = SuspendedUpdateRequests()
    let model = AppUpdateModel(currentVersion: "1.1.2", checkUpdate: { version in
        try await requests.check(version: version)
    })

    model.check()
    model.check()
    model.check()
    await requests.waitForRequestCount(1)
    #expect(model.state == .checking)
    #expect(await requests.versions == ["1.1.2"])

    await requests.finish(0, with: .success(.upToDate(latestVersion: "1.1.2")))
    await waitForUpdateState(.upToDate(latestVersion: "1.1.2"), model: model)

    model.check()
    await requests.waitForRequestCount(2)
    #expect(await requests.versions == ["1.1.2", "1.1.2"])
    await requests.finish(1, with: .failure(AppUpdateError.httpStatus(429)))
    await waitForUpdateState(.failed(.httpStatus(429)), model: model)
}

@Test @MainActor func updateModelCancelledRequestCannotOverwriteReopenedCheck() async {
    let requests = SuspendedUpdateRequests()
    let model = AppUpdateModel(currentVersion: "1.1.2", checkUpdate: { version in
        try await requests.check(version: version)
    })
    var observedStates: [AppUpdateModel.State] = []
    let observation = model.$state.sink { observedStates.append($0) }
    defer { observation.cancel() }

    model.check()
    await requests.waitForRequestCount(1)
    model.cancel()
    #expect(model.state == .idle)
    model.check()
    await requests.waitForRequestCount(2)

    // The first request deliberately ignores cancellation, like a late transport callback.
    await requests.finish(0, with: .success(.upToDate(latestVersion: "9.0.0")))
    let update = AppUpdate(version: "1.2.0", releaseURL: updateReleaseURL)
    await requests.finish(1, with: .success(.updateAvailable(update)))
    await waitForUpdateState(.available(update), model: model)
    #expect(!observedStates.contains(.upToDate(latestVersion: "9.0.0")))
    #expect(model.state == .available(update))
}

@Test @MainActor func updateModelOpensDownloadOnlyAfterUpdateAndHandlesBrowserRetry() async {
    var openedURLs: [URL] = []
    var browserCanOpen = false
    let update = AppUpdate(version: "1.2.0", releaseURL: updateReleaseURL)
    let model = AppUpdateModel(
        currentVersion: "1.1.2",
        checkUpdate: { _ in .updateAvailable(update) },
        openURL: { url in
            openedURLs.append(url)
            return browserCanOpen
        }
    )

    model.openDownload()
    #expect(openedURLs.isEmpty)
    model.check()
    await waitForUpdateState(.available(update), model: model)
    model.openDownload()
    #expect(openedURLs == [updateReleaseURL])
    #expect(model.failedToOpenDownload)

    browserCanOpen = true
    model.openDownload()
    #expect(openedURLs == [updateReleaseURL, updateReleaseURL])
    #expect(!model.failedToOpenDownload)
}

@Test func updateMenuEntryIsAvailableInBothLanguagesAndOptional() {
    for (language, title) in [(AppLanguage.english, "Check for Updates…"), (.simplifiedChinese, "检查更新…")] {
        let menu = StatusItemMenuModel.make(
            hotKeyNotice: nil,
            includesSettings: true,
            includesQuit: true,
            includesUpdateCheck: true,
            language: language
        )
        let entry = menu.items.first { $0.action == .checkForUpdates }
        #expect(entry?.title == title)
        #expect(entry?.isEnabled == true)
        #expect(menu.items.compactMap(\.action) == [.toggleOverlay, .openSettings, .checkForUpdates, .quit])
    }

    let menuWithoutUpdates = StatusItemMenuModel.make(
        hotKeyNotice: nil,
        includesSettings: false,
        includesQuit: false
    )
    #expect(menuWithoutUpdates.items.map(\.action) == [.toggleOverlay])
}

private let updateReleaseURL = URL(string: "https://github.com/Errorrrrr/paste-x/releases/tag/v1.2.0")!

@MainActor
private func waitForUpdateState(_ expected: AppUpdateModel.State, model: AppUpdateModel) async {
    for await state in model.$state.values {
        if state == expected { return }
    }
}

private actor SuspendedUpdateRequests {
    private(set) var versions: [String] = []
    private var requests: [Int: CheckedContinuation<AppUpdateCheckResult, Error>] = [:]
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func check(version: String) async throws -> AppUpdateCheckResult {
        let index = versions.count
        versions.append(version)
        return try await withCheckedThrowingContinuation { continuation in
            requests[index] = continuation
            let ready = countWaiters.filter { $0.0 <= versions.count }
            countWaiters.removeAll { $0.0 <= versions.count }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func waitForRequestCount(_ count: Int) async {
        guard versions.count < count else { return }
        await withCheckedContinuation { countWaiters.append((count, $0)) }
    }

    func finish(_ index: Int, with result: Result<AppUpdateCheckResult, AppUpdateError>) {
        guard let request = requests.removeValue(forKey: index) else {
            Issue.record("No update request with index \(index)")
            return
        }
        request.resume(with: result.mapError { $0 as Error })
    }
}
