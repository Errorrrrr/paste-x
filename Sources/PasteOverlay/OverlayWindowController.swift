import AppKit
import Combine
import PasteCore
import QuartzCore
import SwiftUI

@MainActor
public final class OverlayWindowController: NSObject {
    private let store: OverlaySelectionStore
    private let onPasteRequested: (OverlayPasteRequest) -> Void
    private let onMenuAction: (OverlayMenuAction) -> Void
    private let onDismiss: () -> Void
    private var language: AppLanguage
    private var panel: OverlayPanel?
    private var feedbackHideTask: Task<Void, Never>?
    private var localMouseDownMonitor: Any?
    private var globalMouseDownMonitor: Any?
    private var appResignObserver: NSObjectProtocol?
    private var visibilityAnimationID = UUID()
    private var hideCompletionTask: Task<Void, Never>?
    private let dialogController = OverlayDialogController()
    private var dialogSubscription: AnyCancellable?
    private var dialogIdentity: String?
    private var isDismissingDialog = false
    var overlayFrame: NSRect? { panel?.frame }
    var dialogWindow: NSPanel? { dialogController.window }
    private var hostingView: NSHostingView<OverlayRootView>?

    public init(
        store: OverlaySelectionStore = OverlaySelectionStore(),
        language: AppLanguage = .english,
        onPasteRequested: @escaping (OverlayPasteRequest) -> Void = { _ in },
        onMenuAction: @escaping (OverlayMenuAction) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {}
    ) {
        self.store = store
        self.language = language
        self.onPasteRequested = onPasteRequested
        self.onMenuAction = onMenuAction
        self.onDismiss = onDismiss
        super.init()
        dialogSubscription = store.$detailItem.combineLatest(store.$showsLibrarySettings, store.$showsGroupCreation)
            .sink { [weak self] item, settings, group in
                self?.updateDialog(item: item, settings: settings, group: group)
            }
    }

    public var isVisible: Bool {
        panel?.isVisible == true
    }

    public func show(items: [ClipboardItem], on screen: NSScreen? = nil) {
        hideCompletionTask?.cancel()
        hideCompletionTask = nil
        store.replaceItems(items)
        let panel = makePanelIfNeeded()
        let frame = restingFrame(on: screen ?? screenContainingMouse() ?? NSScreen.main)
        refreshHostingView()
        if panel.isVisible {
            visibilityAnimationID = UUID()
            panel.animator().setFrame(frame, display: true)
            panel.alphaValue = 1
            OverlayPanelPresentation.presentWithoutActivatingApplication(panel)
        } else {
            animateIn(panel: panel, restingFrame: frame)
        }

        hostingView?.layoutSubtreeIfNeeded()
        hostingView?.displayIfNeeded()
        startOutsideClickMonitoring(for: panel)
        updateDialog(item: store.detailItem, settings: store.showsLibrarySettings, group: store.showsGroupCreation)
    }

    public func hideOverlay() {
        feedbackHideTask?.cancel()
        feedbackHideTask = nil
        store.clearFeedback()
        dismissDialog(restoreFocus: false)
        stopOutsideClickMonitoring()

        guard let panel, panel.isVisible else {
            onDismiss()
            return
        }

        animateOut(panel: panel)
    }

    public func applyLanguage(_ language: AppLanguage) {
        self.language = language
        dialogIdentity = nil
        updateDialog(item: store.detailItem, settings: store.showsLibrarySettings, group: store.showsGroupCreation)
        refreshHostingView()
        hostingView?.layoutSubtreeIfNeeded()
        hostingView?.displayIfNeeded()
    }

    public func showPersistentFeedback(_ message: String) { store.showFeedback(message) }

    public func showPasteFeedback(_ message: String, hideAfter delay: TimeInterval = 1.4) {
        store.showFeedback(message)
        feedbackHideTask?.cancel()

        let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
        feedbackHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            await MainActor.run {
                self?.hideOverlay()
            }
        }
    }

    private func toggleOnMain(items: [ClipboardItem]) {
        if isVisible {
            hideOverlay()
        } else {
            show(items: items)
        }
    }

    private func makePanelIfNeeded() -> OverlayPanel {
        if let panel {
            return panel
        }

        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: Layout.panelHeight),
            styleMask: OverlayPanelPresentation.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        OverlayPanelPresentation.configure(panel)
        panel.keyDownHandler = { [weak self] event in
            self?.handleKeyboardEvent(OverlayKeyboardEvent(event)) ?? false
        }

        let hostingView = NSHostingView(rootView: makeRootView())
        panel.contentView = hostingView
        self.hostingView = hostingView
        self.panel = panel
        return panel
    }

    private func makeRootView() -> OverlayRootView {
        OverlayRootView(
            store: store,
            language: language,
            onPasteRequest: { [weak self] request in
                self?.submitPasteRequest(request)
            },
            onMenuAction: { [weak self] action in
                self?.onMenuAction(action)
            }
        )
    }

    private func refreshHostingView() {
        hostingView?.rootView = makeRootView()
    }

    private func updateDialog(item: ClipboardItem?, settings: Bool, group: Bool) {
        guard !isDismissingDialog, let panel, panel.isVisible else { return }
        let identity = item.map { "detail:\($0.id)" } ?? (settings ? "settings" : (group ? "group" : nil))
        guard identity != dialogIdentity else { return }
        dialogIdentity = identity
        let dismiss: () -> Void = { [weak self] in self?.dismissDialog() }
        if let item {
            let view = ClipboardDetailView(item: item, language: language, dismiss: dismiss) { [weak self] updated in
                guard let self else { return }
                self.store.perform(.update(updated))
                if self.store.storageError == nil { self.dismissDialog() }
            }
            dialogController.present(content: view, title: language == .english ? "Item details" : "内容详情",
                                     size: NSSize(width: 640, height: 620), parent: panel, onClose: dismiss)
        } else if settings {
            dialogController.present(content: LibrarySettingsView(store: store, language: language, dismiss: dismiss),
                                     title: language == .english ? "History & privacy" : "历史与隐私",
                                     size: NSSize(width: 540, height: 600), parent: panel, onClose: dismiss)
        } else if group {
            dialogController.present(content: ClipboardGroupCreationView(store: store, language: language, dismiss: dismiss),
                                     title: language == .english ? "New group" : "新建分组",
                                     size: NSSize(width: 400, height: 200), parent: panel, onClose: dismiss)
        } else {
            dialogController.close()
            panel.makeKey()
        }
    }

    private func dismissDialog(restoreFocus: Bool = true) {
        isDismissingDialog = true
        defer { isDismissingDialog = false }
        dialogController.close()
        dialogIdentity = nil
        store.detailItem = nil
        store.showsLibrarySettings = false
        store.showsGroupCreation = false
        if restoreFocus, panel?.isVisible == true { panel?.makeKey() }
    }

    private func restingFrame(on screen: NSScreen?) -> NSRect {
        let screenFrame = screen?.frame ?? NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 720, height: Layout.panelHeight)
        return OverlayPanelGeometry.restingFrame(in: screenFrame)
    }

    private func animateIn(panel: NSPanel, restingFrame: NSRect) {
        let animationID = UUID()
        visibilityAnimationID = animationID
        panel.setFrame(OverlayPanelGeometry.hiddenFrame(from: restingFrame), display: false)
        panel.alphaValue = 0
        OverlayPanelPresentation.presentWithoutActivatingApplication(panel)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(restingFrame, display: true)
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard self?.visibilityAnimationID == animationID else { return }
                panel?.alphaValue = 1
            }
        }
    }

    private func animateOut(panel: NSPanel) {
        hideCompletionTask?.cancel()
        let animationID = UUID()
        visibilityAnimationID = animationID
        let hiddenFrame = OverlayPanelGeometry.hiddenFrame(from: panel.frame)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(hiddenFrame, display: true)
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                self?.finishHiding(panel: panel, animationID: animationID)
            }
        }

        // AppKit can suspend animation callbacks while the display is locked or asleep.
        // Closing must still finish, without allowing an old close to hide a reopened panel.
        hideCompletionTask = Task { [weak self, weak panel] in
            do { try await Task.sleep(for: .seconds(Layout.animationDuration + 0.25)) }
            catch { return }
            self?.finishHiding(panel: panel, animationID: animationID)
        }
    }

    private func finishHiding(panel: NSPanel?, animationID: UUID) {
        guard visibilityAnimationID == animationID else { return }
        visibilityAnimationID = UUID()
        hideCompletionTask?.cancel()
        hideCompletionTask = nil
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        onDismiss()
    }

    private func startOutsideClickMonitoring(for panel: NSPanel) {
        stopOutsideClickMonitoring()

        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: Layout.outsideClickEventMask) { [weak self, weak panel] event in
            guard let panel else { return event }
            if panel.attachedSheet != nil || self?.store.isShowingDialog == true { return event }

            return OverlayLocalMouseDownRouter.route(
                event,
                panelFrame: panel.frame,
                eventWindowIsPanel: event.window === panel,
                hostingView: self?.hostingView,
                onOutsidePanelClick: {
                    Task { @MainActor in
                        self?.hideOverlay()
                    }
                }
            )
        }

        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: Layout.outsideClickEventMask) { [weak self, weak panel] _ in
            guard let panel else { return }
            if panel.attachedSheet != nil || self?.store.isShowingDialog == true { return }

            let isOutsidePanel = OverlayOutsideClickPolicy.isOutsidePanel(
                panelFrame: panel.frame,
                eventWindowIsPanel: false,
                mouseLocation: NSEvent.mouseLocation
            )
            guard isOutsidePanel else {
                return
            }

            Task { @MainActor in
                self?.hideOverlay()
            }
        }

        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel?.attachedSheet == nil, !self.store.isShowingDialog else { return }
                self.hideOverlay()
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        if let localMouseDownMonitor {
            NSEvent.removeMonitor(localMouseDownMonitor)
            self.localMouseDownMonitor = nil
        }

        if let globalMouseDownMonitor {
            NSEvent.removeMonitor(globalMouseDownMonitor)
            self.globalMouseDownMonitor = nil
        }

        if let appResignObserver {
            NotificationCenter.default.removeObserver(appResignObserver)
            self.appResignObserver = nil
        }
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }

    @discardableResult
    func handleKeyboardEvent(_ event: OverlayKeyboardEvent) -> Bool {
        guard !store.isShowingDialog else { return false }
        if event.modifiers == [.command], let key = event.characters?.lowercased() {
            if key == "f" { store.activateSearch(); return true }
            if key == "a" { store.selectedIDs = Set(store.visibleItems.map(\.id)); return true }
            if let number = Int(key), (1...9).contains(number), number <= store.visibleItems.count {
                store.select(id: store.visibleItems[number - 1].id)
                requestPaste(trigger: .returnKey)
                return true
            }
        }
        if event.keyCode == KeyCode.returnKey || event.keyCode == KeyCode.keypadEnter {
            if event.modifiers.contains(.command) {
                if let request = store.queueRequest() { submitPasteRequest(request) }
                return true
            }
            if event.modifiers.contains(.shift), let item = store.selectedItem {
                if !item.textContent.isEmpty { submitPasteRequest(OverlayPasteRequest(item: item, trigger: .returnKey, plainText: true)) }
                return true
            }
        }
        if event.keyCode == 51, !store.isSearching {
            let ids = store.selectedIDs.isEmpty ? Set([store.selectedItemID].compactMap { $0 }) : store.selectedIDs
            store.perform(.delete(ids))
            return true
        }
        if store.isSearching, let text = searchText(from: event) {
            store.appendSearchText(text)
            return true
        }

        switch event.keyCode {
        case KeyCode.leftArrow:
            store.selectPrevious()
            return true
        case KeyCode.rightArrow:
            store.selectNext()
            return true
        case KeyCode.space:
            requestPaste(trigger: .spaceKey)
            return true
        case KeyCode.returnKey, KeyCode.keypadEnter:
            requestPaste(trigger: .returnKey)
            return true
        case KeyCode.escape:
            if store.isSearching {
                store.deactivateSearch()
                return true
            }

            hideOverlay()
            return true
        default:
            if let text = searchText(from: event) {
                store.activateSearch(prefill: text)
                return true
            }

            return false
        }
    }

    private func searchText(from event: OverlayKeyboardEvent) -> String? {
        if event.modifiers.contains(.command)
            || event.modifiers.contains(.control)
            || event.modifiers.contains(.option) {
            return nil
        }

        guard
            let characters = event.characters,
            !characters.isEmpty,
            characters.rangeOfCharacter(from: .controlCharacters) == nil
        else {
            return nil
        }

        return characters
    }

    private func requestPaste(trigger: OverlayPasteTrigger) {
        guard let request = store.makePasteRequest(trigger: trigger) else {
            return
        }

        submitPasteRequest(request)
    }

    private func submitPasteRequest(_ request: OverlayPasteRequest) {
        guard !store.isPasting else { return }
        OverlayPanelPresentation.performAfterRelinquishingKeyFocus(panel) { [weak self] in
            self?.onPasteRequested(request)
        }
    }
}

extension OverlayWindowController: OverlayPresenting {
    public nonisolated func toggle(items: [ClipboardItem], target: PasteTarget?) {
        Task { @MainActor [weak self] in
            self?.toggleOnMain(items: items)
        }
    }

    public nonisolated func hide() {
        Task { @MainActor [weak self] in
            self?.hideOverlay()
        }
    }

    public nonisolated func updateLanguage(_ language: AppLanguage) {
        Task { @MainActor [weak self] in
            self?.applyLanguage(language)
        }
    }
}

private enum Layout {
    static let panelHeight: CGFloat = 388
    static let minimumPanelWidth: CGFloat = 760
    static let horizontalInset: CGFloat = 0
    static let bottomInset: CGFloat = 0
    static let slideDistance: CGFloat = 72
    static let animationDuration: TimeInterval = 0.22
    static let outsideClickEventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
}

enum OverlayPanelPresentation {
    static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]

    @MainActor
    static func configure(_ panel: NSPanel) {
        panel.styleMask.insert(.nonactivatingPanel)
        panel.becomesKeyOnlyIfNeeded = true
        // Target app activation during paste deactivates PasteX; keep the panel visible
        // long enough for the custom slide/fade dismissal instead of NSPanel auto-hide.
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
    }

    @MainActor
    static func presentWithoutActivatingApplication(_ panel: NSPanel) {
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    @MainActor
    static func performAfterRelinquishingKeyFocus(
        _ panel: NSPanel?,
        action: @escaping @MainActor () -> Void
    ) {
        panel?.resignKey()
        DispatchQueue.main.async {
            action()
        }
    }
}

enum OverlayPanelGeometry {
    static func restingFrame(in screenFrame: NSRect) -> NSRect {
        let width = max(Layout.minimumPanelWidth, screenFrame.width - Layout.horizontalInset * 2)
        return NSRect(
            x: screenFrame.minX + (screenFrame.width - width) / 2,
            y: screenFrame.minY + Layout.bottomInset,
            width: width,
            height: Layout.panelHeight
        )
    }

    static func hiddenFrame(from restingFrame: NSRect) -> NSRect {
        restingFrame.offsetBy(dx: 0, dy: -Layout.slideDistance)
    }
}

enum OverlayOutsideClickPolicy {
    static func isOutsidePanel(
        panelFrame: NSRect,
        eventWindowIsPanel: Bool,
        mouseLocation: NSPoint
    ) -> Bool {
        !eventWindowIsPanel && !panelFrame.contains(mouseLocation)
    }
}

enum OverlayLocalMouseDownRouter {
    @MainActor
    static func route(
        _ event: NSEvent,
        panelFrame: NSRect,
        eventWindowIsPanel: Bool,
        hostingView: NSView?,
        mouseLocation: NSPoint = NSEvent.mouseLocation,
        onOutsidePanelClick: () -> Void
    ) -> NSEvent? {
        if event.type == .leftMouseDown,
           eventWindowIsPanel,
           let mouseEventView = hostingView?.firstClipboardItemMouseEventView(containingWindowPoint: event.locationInWindow) {
            mouseEventView.handleMouseDown(event)
            return nil
        }

        let isOutsidePanel = OverlayOutsideClickPolicy.isOutsidePanel(
            panelFrame: panelFrame,
            eventWindowIsPanel: eventWindowIsPanel,
            mouseLocation: mouseLocation
        )
        if isOutsidePanel {
            onOutsidePanelClick()
        }

        return event
    }
}

private enum KeyCode {
    static let returnKey: UInt16 = 36
    static let space: UInt16 = 49
    static let escape: UInt16 = 53
    static let keypadEnter: UInt16 = 76
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
}

private final class OverlayPanel: NSPanel {
    var keyDownHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let supported = (modifiers == .command && (Int(key).map { (1...9).contains($0) } == true || key == "f"))
            || ((modifiers.contains(.command) || modifiers.contains(.shift)) && event.keyCode == 36)
        if attachedSheet == nil, supported, keyDownHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if keyDownHandler?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}
