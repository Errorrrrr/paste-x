import AppKit
import Combine
import PasteCore
import SwiftUI

@MainActor
public protocol AppUpdatePresenting: AnyObject {
    func checkForUpdates(language: AppLanguage)
    func close()
}

@MainActor
public final class AppUpdatePresenter: NSObject, AppUpdatePresenting, NSWindowDelegate {
    private let model: AppUpdateModel
    private var windowController: NSWindowController?

    public override init() {
        model = AppUpdateModel(
            currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        )
        super.init()
    }

    public func checkForUpdates(language: AppLanguage) {
        let content = NSHostingController(rootView: AppUpdateView(model: model, language: language))
        let window: NSWindow
        if let existing = windowController?.window {
            window = existing
            window.contentViewController = content
        } else {
            window = NSWindow(contentViewController: content)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.delegate = self
            window.center()
            windowController = NSWindowController(window: window)
        }
        window.title = language == .english ? "PasteX Updates" : "PasteX 更新"
        NSApp.activate(ignoringOtherApps: true)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        model.check()
    }

    public func close() {
        model.cancel()
        windowController?.close()
    }

    public func windowWillClose(_ notification: Notification) {
        model.cancel()
    }
}

@MainActor
final class AppUpdateModel: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(latestVersion: String)
        case available(AppUpdate)
        case failed(AppUpdateError)
    }

    let currentVersion: String
    @Published private(set) var state: State = .idle
    @Published private(set) var failedToOpenDownload = false
    private let checkUpdate: @Sendable (String) async throws -> AppUpdateCheckResult
    private let openURL: (URL) -> Bool
    private var task: Task<Void, Never>?
    private var requestID: UUID?

    init(
        currentVersion: String,
        checkUpdate: @escaping @Sendable (String) async throws -> AppUpdateCheckResult = {
            try await AppUpdateChecker().check(currentVersion: $0)
        },
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.currentVersion = currentVersion
        self.checkUpdate = checkUpdate
        self.openURL = openURL
    }

    func check() {
        guard task == nil else { return }
        let id = UUID()
        requestID = id
        state = .checking
        failedToOpenDownload = false
        let checkUpdate = self.checkUpdate
        let version = currentVersion
        task = Task { [weak self] in
            let nextState: State
            do {
                switch try await checkUpdate(version) {
                case let .upToDate(latestVersion):
                    nextState = .upToDate(latestVersion: latestVersion)
                case let .updateAvailable(update):
                    nextState = .available(update)
                }
            } catch let error as AppUpdateError {
                nextState = .failed(error)
            } catch {
                nextState = .failed(.network(error.localizedDescription))
            }
            guard !Task.isCancelled, let self, self.requestID == id else { return }
            self.state = nextState
            self.task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        requestID = nil
        state = .idle
    }

    func openDownload() {
        guard case let .available(update) = state else { return }
        failedToOpenDownload = !openURL(update.releaseURL)
    }
}

@MainActor
private struct AppUpdateView: View {
    @ObservedObject var model: AppUpdateModel
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(english ? "Check for Updates" : "检查更新")
                .font(.system(size: 20, weight: .semibold))
            Text(currentVersionLabel)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Group {
                switch model.state {
                case .idle, .checking:
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text(english ? "Checking for updates…" : "正在检查更新…")
                    }
                case let .upToDate(latestVersion):
                    Label(english ? "You’re up to date" : "当前已是最新版本", systemImage: "checkmark.circle")
                    Text(english ? "Latest release: \(latestVersion)" : "最新发布版本：\(latestVersion)")
                        .foregroundStyle(.secondary)
                case let .available(update):
                    Label(english ? "PasteX \(update.version) is available" : "发现新版本 PasteX \(update.version)",
                          systemImage: "arrow.down.circle")
                    Text(english
                         ? "Download the app from GitHub, quit PasteX, then replace the installed app. Your clipboard history is kept."
                         : "前往 GitHub 下载，退出 PasteX 后替换已安装的应用。剪贴板历史会保留。")
                        .foregroundStyle(.secondary)
                case let .failed(error):
                    Label(english ? "Couldn’t check for updates" : "无法检查更新", systemImage: "exclamationmark.triangle")
                    Text(error.message(language: language))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)

            if model.failedToOpenDownload {
                Text(english ? "Couldn’t open the browser. Please try again." : "无法打开浏览器，请重试。")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                if case .available = model.state {
                    Button(english ? "Download Update…" : "下载更新…") { model.openDownload() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(english ? "Check Again" : "重新检查") { model.check() }
                        .disabled(model.state == .checking || model.state == .idle)
                }
            }
        }
        .padding(24)
        .frame(width: 440, alignment: .leading)
    }

    private var english: Bool { language == .english }

    private var currentVersionLabel: String {
        let version = model.currentVersion.isEmpty ? (english ? "Unknown" : "未知") : model.currentVersion
        return english ? "Current version: \(version)" : "当前版本：\(version)"
    }
}

private extension AppUpdateError {
    func message(language: AppLanguage) -> String {
        let english = language == .english
        switch self {
        case .invalidCurrentVersion:
            return english ? "This app’s version could not be read. Run an installed copy of PasteX."
                : "无法读取应用版本，请运行已安装的 PasteX 应用。"
        case .noPublishedRelease:
            return english ? "No published release is available yet. Please try again later."
                : "暂时没有可用的发布版本，请稍后重试。"
        case .releaseNotReady:
            return english ? "The latest release has no download for this Mac yet. Please try again later."
                : "最新版本暂未提供适用于这台 Mac 的安装包，请稍后重试。"
        case .invalidRelease, .invalidResponse:
            return english ? "The update information could not be verified. Please try again later."
                : "无法验证更新信息，请稍后重试。"
        case .httpStatus(403), .httpStatus(429):
            return english ? "GitHub is limiting update requests. Please try again later."
                : "GitHub 暂时限制了请求频率，请稍后重试。"
        case .httpStatus, .network:
            return english ? "Couldn’t reach GitHub. Check your internet connection and try again."
                : "无法连接 GitHub，请检查网络连接后重试。"
        }
    }
}
