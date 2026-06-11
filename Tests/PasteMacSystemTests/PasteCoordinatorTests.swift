import Foundation
import Testing
@testable import PasteMacSystem
import PasteCore

@Test func pasteCoordinatorCopiesOnlyWhenAccessibilityIsNotTrusted() async {
    let services = FakePasteServices()
    services.permissionTrusted = false
    let coordinator = PasteCoordinator(services: services)
    let item = makePasteItem()

    let result = await coordinator.paste(item, to: makeTarget())

    #expect(result == .copiedOnly(reason: .accessibilityNotTrusted))
    #expect(services.writtenItem == item)
    #expect(services.activatedTarget == nil)
    #expect(services.postedPasteCommand == false)
}

@Test func pasteCoordinatorPastesWhenClipboardTargetPermissionAndEventAllSucceed() async {
    let services = FakePasteServices()
    let coordinator = PasteCoordinator(services: services)
    let item = makePasteItem()
    let target = makeTarget()

    let result = await coordinator.paste(item, to: target)

    #expect(result == .pasted)
    #expect(services.writtenItem == item)
    #expect(services.activatedTarget == target)
    #expect(services.postedPasteCommand == true)
}

@Test func pasteCoordinatorFallsBackWhenTargetIsMissingOrActivationFails() async {
    let noTargetServices = FakePasteServices()
    let noTargetCoordinator = PasteCoordinator(services: noTargetServices)
    let noTargetResult = await noTargetCoordinator.paste(makePasteItem(), to: nil)

    let activationServices = FakePasteServices()
    activationServices.activateResult = false
    let activationCoordinator = PasteCoordinator(services: activationServices)
    let activationResult = await activationCoordinator.paste(makePasteItem(), to: makeTarget())

    #expect(noTargetResult == .copiedOnly(reason: .targetUnavailable))
    #expect(activationResult == .copiedOnly(reason: .activationFailed))
}

@Test func pasteCoordinatorReturnsFailureWhenPasteboardWriteFailsOrPayloadIsEmpty() async {
    let writeServices = FakePasteServices()
    writeServices.writeResult = false
    let writeCoordinator = PasteCoordinator(services: writeServices)
    let writeResult = await writeCoordinator.paste(makePasteItem(), to: makeTarget())

    let emptyCoordinator = PasteCoordinator(services: FakePasteServices())
    let emptyResult = await emptyCoordinator.paste(makePasteItem(payloads: []), to: makeTarget())

    #expect(writeResult == .failed(reason: .pasteboardWriteFailed))
    #expect(emptyResult == .failed(reason: .emptyPayload))
}

@Test func focusTrackerIgnoresSelfAndCapturesLastExternalApplication() {
    let tracker = FocusTracker(ownBundleIdentifier: "com.example.PasteX")
    let external = RunningApplicationInfo(
        bundleIdentifier: "com.apple.TextEdit",
        processIdentifier: 42
    )

    tracker.recordActivatedApplication(RunningApplicationInfo(bundleIdentifier: "com.example.PasteX", processIdentifier: 7), at: Date(timeIntervalSince1970: 1))
    tracker.recordActivatedApplication(external, at: Date(timeIntervalSince1970: 2))

    #expect(tracker.currentTarget == PasteTarget(
        bundleIdentifier: "com.apple.TextEdit",
        processIdentifier: 42,
        capturedAt: Date(timeIntervalSince1970: 2)
    ))
}

@Test func focusTrackerRefreshesTargetFromFrontmostApplicationWithoutActivationEvent() {
    let tracker = FocusTracker(
        ownBundleIdentifier: "com.example.PasteX",
        ownProcessIdentifier: 7,
        frontmostApplicationProvider: {
            RunningApplicationInfo(
                bundleIdentifier: "com.apple.TextEdit",
                processIdentifier: 42
            )
        }
    )

    let target = tracker.refreshCurrentTarget(at: Date(timeIntervalSince1970: 3))

    #expect(target == PasteTarget(
        bundleIdentifier: "com.apple.TextEdit",
        processIdentifier: 42,
        capturedAt: Date(timeIntervalSince1970: 3)
    ))
    #expect(tracker.currentTarget == target)
}

@MainActor
@Test func clipboardAssistantRefreshesTargetBeforeShowingOverlay() {
    let item = makePasteItem()
    let target = makeTarget()
    let overlay = FakeOverlayPresenter()
    let focusTracker = FakeRefreshableFocusTracker(target: target)
    let app = ClipboardAssistantApp(
        hotKeyManager: FakeHotKeyManager(),
        clipboardMonitor: FakeClipboardMonitor(),
        historyStore: FakeClipboardHistory(items: [item]),
        overlayPresenter: overlay,
        focusTracker: focusTracker,
        statusItemController: StatusItemController(toggleHandler: {})
    )

    app.toggleOverlay()

    #expect(focusTracker.refreshCount == 1)
    #expect(overlay.toggles == [OverlayToggle(items: [item], target: target)])
}

@MainActor
@Test func clipboardAssistantRegisteredHotKeyUsesToggleOverlayEntryPoint() async {
    let item = makePasteItem()
    let target = makeTarget()
    let hotKeyManager = FakeHotKeyManager()
    let overlay = FakeOverlayPresenter()
    let focusTracker = FakeRefreshableFocusTracker(target: target)
    let app = ClipboardAssistantApp(
        hotKeyManager: hotKeyManager,
        clipboardMonitor: FakeClipboardMonitor(),
        historyStore: FakeClipboardHistory(items: [item]),
        overlayPresenter: overlay,
        focusTracker: focusTracker,
        statusItemController: StatusItemController(toggleHandler: {})
    )

    let result = app.registerActiveShortcut()
    hotKeyManager.fire()
    await Task.yield()

    #expect(result.isSuccess)
    #expect(hotKeyManager.registeredShortcuts == [.defaultToggleOverlay])
    #expect(focusTracker.refreshCount == 1)
    #expect(overlay.toggles == [OverlayToggle(items: [item], target: target)])
}

@MainActor
@Test func clipboardAssistantOpensSettingsAndPersistsUpdatedShortcut() {
    let hotKeyManager = FakeHotKeyManager()
    let settingsPresenter = FakeShortcutSettingsPresenter()
    let shortcutStore = FakeShortcutSettingsStore()
    let overlay = FakeOverlayPresenter()
    let app = ClipboardAssistantApp(
        hotKeyManager: hotKeyManager,
        clipboardMonitor: FakeClipboardMonitor(),
        historyStore: FakeClipboardHistory(items: []),
        overlayPresenter: overlay,
        focusTracker: FakeRefreshableFocusTracker(target: makeTarget()),
        statusItemController: StatusItemController(toggleHandler: {}),
        settingsPresenter: settingsPresenter,
        shortcutStore: shortcutStore
    )

    app.openSettings()
    let customShortcut = HotKeyShortcut(keyEquivalent: "b", modifiers: ["command", "shift"])
    let result = settingsPresenter.saveHandler?(customShortcut)

    #expect(settingsPresenter.currentShortcut == .defaultToggleOverlay)
    #expect(settingsPresenter.defaultShortcut == .defaultToggleOverlay)
    #expect(settingsPresenter.currentSettings == .default)
    #expect(result?.isSuccess == true)
    #expect(hotKeyManager.registeredShortcuts == [customShortcut])
    #expect(shortcutStore.savedShortcuts == [customShortcut])
    #expect(overlay.hideCount == 1)
}

@MainActor
@Test func clipboardAssistantRestoresDefaultShortcutThroughSettingsPresenter() {
    let hotKeyManager = FakeHotKeyManager()
    let settingsPresenter = FakeShortcutSettingsPresenter()
    let shortcutStore = FakeShortcutSettingsStore()
    let currentShortcut = HotKeyShortcut(keyEquivalent: "b", modifiers: ["command", "shift"])
    let app = ClipboardAssistantApp(
        hotKeyManager: hotKeyManager,
        clipboardMonitor: FakeClipboardMonitor(),
        historyStore: FakeClipboardHistory(items: []),
        overlayPresenter: FakeOverlayPresenter(),
        focusTracker: FakeRefreshableFocusTracker(target: makeTarget()),
        statusItemController: StatusItemController(toggleHandler: {}),
        settingsPresenter: settingsPresenter,
        shortcutStore: shortcutStore,
        shortcut: currentShortcut
    )

    app.openSettings()
    let result = settingsPresenter.saveHandler?(.defaultToggleOverlay)

    #expect(settingsPresenter.currentShortcut == currentShortcut)
    #expect(settingsPresenter.defaultShortcut == .defaultToggleOverlay)
    #expect(settingsPresenter.currentSettings == .default)
    #expect(result?.isSuccess == true)
    #expect(hotKeyManager.registeredShortcuts == [.defaultToggleOverlay])
    #expect(shortcutStore.savedShortcuts == [.defaultToggleOverlay])
}

@MainActor
@Test func clipboardAssistantPersistsLanguageSettingsAndUpdatesOverlayImmediately() {
    let settingsPresenter = FakeShortcutSettingsPresenter()
    let settingsStore = FakeAppSettingsStore()
    let overlay = FakeOverlayPresenter()
    let statusItemController = StatusItemController(toggleHandler: {})
    let app = ClipboardAssistantApp(
        hotKeyManager: FakeHotKeyManager(),
        clipboardMonitor: FakeClipboardMonitor(),
        historyStore: FakeClipboardHistory(items: []),
        overlayPresenter: overlay,
        focusTracker: FakeRefreshableFocusTracker(target: makeTarget()),
        statusItemController: statusItemController,
        settingsPresenter: settingsPresenter,
        settingsStore: settingsStore
    )

    app.openSettings()
    settingsPresenter.settingsChangeHandler?(AppSettings(language: .simplifiedChinese))

    #expect(settingsStore.savedSettings == [AppSettings(language: .simplifiedChinese)])
    #expect(overlay.languages == [.english, .simplifiedChinese])
}

@MainActor
@Test func clipboardAssistantCloseOverlayHidesWindowWithoutStoppingApp() {
    let overlay = FakeOverlayPresenter()
    let app = ClipboardAssistantApp(
        hotKeyManager: FakeHotKeyManager(),
        clipboardMonitor: FakeClipboardMonitor(),
        historyStore: FakeClipboardHistory(items: []),
        overlayPresenter: overlay,
        focusTracker: FakeRefreshableFocusTracker(target: makeTarget()),
        statusItemController: StatusItemController(toggleHandler: {})
    )

    app.closeOverlay()

    #expect(overlay.hideCount == 1)
}

@MainActor
@Test func clipboardAssistantRestoresPreviousShortcutWhenUpdatedShortcutConflicts() {
    let hotKeyManager = FakeHotKeyManager()
    hotKeyManager.results = [.failure(.conflict), .success(())]
    let shortcutStore = FakeShortcutSettingsStore()
    let app = ClipboardAssistantApp(
        hotKeyManager: hotKeyManager,
        clipboardMonitor: FakeClipboardMonitor(),
        historyStore: FakeClipboardHistory(items: []),
        overlayPresenter: FakeOverlayPresenter(),
        focusTracker: FakeRefreshableFocusTracker(target: makeTarget()),
        statusItemController: StatusItemController(toggleHandler: {}),
        shortcutStore: shortcutStore
    )

    let customShortcut = HotKeyShortcut(keyEquivalent: "b", modifiers: ["command", "shift"])
    let result = app.updateShortcut(customShortcut)

    #expect(result.failure == .conflict)
    #expect(hotKeyManager.registeredShortcuts == [customShortcut, .defaultToggleOverlay])
    #expect(shortcutStore.savedShortcuts == [])
}

@Test func appSettingsStoreDefaultsToEnglishAndPersistsLanguage() {
    let suiteName = "PasteX.AppSettingsStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }
    let store = UserDefaultsAppSettingsStore(defaults: defaults)

    #expect(store.loadSettings() == .default)

    let settings = AppSettings(language: .simplifiedChinese)
    store.saveSettings(settings)

    #expect(store.loadSettings() == settings)
}

private final class FakePasteServices: PasteCoordinatorServices {
    var writeResult = true
    var permissionTrusted = true
    var activateResult = true
    var postResult = true
    private(set) var writtenItem: ClipboardItem?
    private(set) var activatedTarget: PasteTarget?
    private(set) var postedPasteCommand = false

    func writeToPasteboard(_ item: ClipboardItem) -> Bool {
        writtenItem = item
        return writeResult
    }

    func isAccessibilityTrusted() -> Bool {
        permissionTrusted
    }

    func activate(target: PasteTarget) -> Bool {
        activatedTarget = target
        return activateResult
    }

    func postPasteCommand() -> Bool {
        postedPasteCommand = true
        return postResult
    }
}

private struct OverlayToggle: Equatable {
    let items: [ClipboardItem]
    let target: PasteTarget?
}

private final class FakeOverlayPresenter: OverlayPresenting {
    private(set) var toggles: [OverlayToggle] = []
    private(set) var hideCount = 0
    private(set) var languages: [AppLanguage] = []

    func toggle(items: [ClipboardItem], target: PasteTarget?) {
        toggles.append(OverlayToggle(items: items, target: target))
    }

    func hide() {
        hideCount += 1
    }

    func updateLanguage(_ language: AppLanguage) {
        languages.append(language)
    }
}

private final class FakeRefreshableFocusTracker: FocusTargetRefreshing {
    private let target: PasteTarget
    private(set) var refreshCount = 0
    var currentTarget: PasteTarget? { nil }

    init(target: PasteTarget) {
        self.target = target
    }

    func refreshCurrentTarget(at date: Date) -> PasteTarget? {
        refreshCount += 1
        return target
    }
}

private final class FakeClipboardHistory: ClipboardHistoryProviding {
    let items: [ClipboardItem]

    init(items: [ClipboardItem]) {
        self.items = items
    }

    func insert(_ item: ClipboardItem) {}
    func clear() {}
}

private final class FakeClipboardMonitor: ClipboardMonitoring {
    func start() {}
    func stop() {}
}

private final class FakeHotKeyManager: HotKeyManaging {
    var results: [Result<Void, HotKeyError>] = []
    private(set) var registeredShortcuts: [HotKeyShortcut] = []
    private var handler: (@Sendable () -> Void)?

    func register(shortcut: HotKeyShortcut, handler: @escaping @Sendable () -> Void) -> Result<Void, HotKeyError> {
        registeredShortcuts.append(shortcut)
        self.handler = handler
        if results.isEmpty {
            return .success(())
        }
        return results.removeFirst()
    }

    func unregister() {
        handler = nil
    }

    func fire() {
        handler?()
    }
}

@MainActor
private final class FakeShortcutSettingsPresenter: ShortcutSettingsPresenting {
    private(set) var currentShortcut: HotKeyShortcut?
    private(set) var defaultShortcut: HotKeyShortcut?
    private(set) var currentSettings: AppSettings?
    private(set) var saveHandler: ((HotKeyShortcut) -> Result<Void, HotKeyError>)?
    private(set) var settingsChangeHandler: ((AppSettings) -> Void)?

    func openSettings(
        currentShortcut: HotKeyShortcut,
        defaultShortcut: HotKeyShortcut,
        currentSettings: AppSettings,
        saveHandler: @escaping (HotKeyShortcut) -> Result<Void, HotKeyError>,
        settingsChangeHandler: @escaping (AppSettings) -> Void
    ) {
        self.currentShortcut = currentShortcut
        self.defaultShortcut = defaultShortcut
        self.currentSettings = currentSettings
        self.saveHandler = saveHandler
        self.settingsChangeHandler = settingsChangeHandler
    }
}

private final class FakeShortcutSettingsStore: ShortcutSettingsStoring {
    var loadedShortcut: HotKeyShortcut?
    private(set) var savedShortcuts: [HotKeyShortcut] = []

    func loadShortcut() -> HotKeyShortcut? {
        loadedShortcut
    }

    func saveShortcut(_ shortcut: HotKeyShortcut) {
        savedShortcuts.append(shortcut)
    }
}

private final class FakeAppSettingsStore: AppSettingsStoring {
    var loadedSettings: AppSettings = .default
    private(set) var savedSettings: [AppSettings] = []

    func loadSettings() -> AppSettings {
        loadedSettings
    }

    func saveSettings(_ settings: AppSettings) {
        savedSettings.append(settings)
    }
}

private func makePasteItem(payloads: [ClipboardPayload]? = nil) -> ClipboardItem {
    let itemPayloads = payloads ?? [
        ClipboardPayload(typeIdentifier: PasteboardTypeIdentifier.plainText, data: Data("hello".utf8))
    ]
    return ClipboardItem(
        kind: .text,
        summary: "hello",
        createdAt: Date(timeIntervalSince1970: 1),
        signature: "text:hello",
        payloads: itemPayloads
    )
}

private func makeTarget() -> PasteTarget {
    PasteTarget(
        bundleIdentifier: "com.apple.TextEdit",
        processIdentifier: 42,
        capturedAt: Date(timeIntervalSince1970: 2)
    )
}

private extension Result where Success == Void, Failure == HotKeyError {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    var failure: HotKeyError? {
        if case let .failure(error) = self {
            return error
        }
        return nil
    }
}
