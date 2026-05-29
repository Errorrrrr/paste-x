import AppKit
import Foundation
import PasteCore
import QuartzCore

struct HotKeyRegistrationNotice: Equatable, Sendable {
    let menuTitle: String
    let fallbackTitle: String
    let toolTip: String

    static func failure(error: HotKeyError, shortcut: HotKeyShortcut, language: AppLanguage = .english) -> HotKeyRegistrationNotice {
        let shortcutName = shortcut.displayName
        let reason: String
        switch error {
        case .conflict:
            reason = language == .english ? "\(shortcutName) is already used by another app" : "\(shortcutName) 已被其他应用占用"
        case .unsupported:
            reason = language == .english ? "\(shortcutName) is not supported on this Mac" : "这台 Mac 不支持 \(shortcutName)"
        case let .systemFailure(message):
            reason = message
        }

        let strings = StatusItemStrings(language: language)
        return HotKeyRegistrationNotice(
            menuTitle: strings.shortcutUnavailable(reason: reason),
            fallbackTitle: strings.menuFallbackTitle,
            toolTip: strings.shortcutUnavailableToolTip(reason: reason)
        )
    }
}

enum StatusItemMenuAction: Equatable, Sendable {
    case toggleOverlay
    case openSettings
    case quit
}

enum StatusItemClickRoute: Equatable {
    case toggleOverlay
    case openMenu
}

struct StatusItemClickEvent: Equatable {
    let type: NSEvent.EventType
    let modifierFlags: NSEvent.ModifierFlags
    let buttonNumber: Int
}

enum StatusItemClickRouter {
    static func route(for event: StatusItemClickEvent?) -> StatusItemClickRoute {
        guard let event else {
            return .toggleOverlay
        }

        if event.type == .rightMouseDown || event.type == .rightMouseUp {
            return .openMenu
        }

        if event.buttonNumber != 0 || event.modifierFlags.contains(.control) {
            return .openMenu
        }

        return .toggleOverlay
    }
}

struct StatusItemMenuItemDescriptor: Equatable, Sendable {
    let title: String
    let action: StatusItemMenuAction?
    let keyEquivalent: String
    let isEnabled: Bool

    static let separator = StatusItemMenuItemDescriptor(
        title: "-",
        action: nil,
        keyEquivalent: "",
        isEnabled: false
    )
}

struct StatusItemMenuModel: Equatable, Sendable {
    let items: [StatusItemMenuItemDescriptor]

    static func make(
        hotKeyNotice: HotKeyRegistrationNotice?,
        includesSettings: Bool,
        includesQuit: Bool,
        language: AppLanguage = .english
    ) -> StatusItemMenuModel {
        let strings = StatusItemStrings(language: language)
        var items: [StatusItemMenuItemDescriptor] = []

        if let hotKeyNotice {
            items.append(
                StatusItemMenuItemDescriptor(
                    title: hotKeyNotice.menuTitle,
                    action: nil,
                    keyEquivalent: "",
                    isEnabled: false
                )
            )
        }

        items.append(
            StatusItemMenuItemDescriptor(
                title: hotKeyNotice?.fallbackTitle ?? strings.showClipboardHistory,
                action: .toggleOverlay,
                keyEquivalent: "",
                isEnabled: true
            )
        )

        if includesSettings || includesQuit {
            items.append(.separator)
        }

        if includesSettings {
            items.append(
                StatusItemMenuItemDescriptor(
                    title: strings.settings,
                    action: .openSettings,
                    keyEquivalent: ",",
                    isEnabled: true
                )
            )
        }

        if includesQuit {
            items.append(
                StatusItemMenuItemDescriptor(
                    title: strings.quit,
                    action: .quit,
                    keyEquivalent: "q",
                    isEnabled: true
                )
            )
        }

        return StatusItemMenuModel(items: items)
    }
}

@MainActor
public final class StatusItemController: NSObject {
    private let toggleHandler: () -> Void
    private let settingsHandler: (() -> Void)?
    private let quitHandler: (() -> Void)?
    private var language: AppLanguage
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private(set) var hotKeyNotice: HotKeyRegistrationNotice?
    private var hotKeyFailure: (error: HotKeyError, shortcut: HotKeyShortcut)?
    private var captureAnimationResetTimer: Timer?
    private var captureAnimationID: UUID?

    public init(
        language: AppLanguage = .english,
        toggleHandler: @escaping () -> Void,
        settingsHandler: (() -> Void)? = nil,
        quitHandler: (() -> Void)? = nil
    ) {
        self.language = language
        self.toggleHandler = toggleHandler
        self.settingsHandler = settingsHandler
        self.quitHandler = quitHandler
        super.init()
    }

    public func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(didClickStatusItem)
        item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        statusItem = item
        updateStatusButtonPresentation()
    }

    public func uninstall() {
        guard let statusItem else { return }
        clearClipboardCaptureAnimation()
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    public func playClipboardCaptureAnimation() {
        guard let button = statusItem?.button else { return }

        captureAnimationResetTimer?.invalidate()
        let animationID = UUID()
        captureAnimationID = animationID

        let accessibility = strings.statusAccessibility
        button.image = statusImage(
            systemSymbolName: StatusItemAnimation.captureSymbolName,
            accessibilityDescription: accessibility
        )
        button.contentTintColor = .controlAccentColor
        button.wantsLayer = true
        button.layer?.removeAnimation(forKey: StatusItemAnimation.pulseKey)
        addClipboardCapturePulse(to: button)

        captureAnimationResetTimer = Timer.scheduledTimer(
            withTimeInterval: StatusItemAnimation.resetDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.finishClipboardCaptureAnimation(animationID: animationID)
            }
        }
    }

    public func clearHotKeyRegistrationNotice() {
        hotKeyFailure = nil
        hotKeyNotice = nil
        updateStatusButtonPresentation()
    }

    public func showHotKeyRegistrationFailure(_ error: HotKeyError, shortcut: HotKeyShortcut) {
        hotKeyFailure = (error, shortcut)
        hotKeyNotice = .failure(error: error, shortcut: shortcut, language: language)
        updateStatusButtonPresentation()
    }

    public func updateLanguage(_ language: AppLanguage) {
        self.language = language
        if let hotKeyFailure {
            hotKeyNotice = .failure(
                error: hotKeyFailure.error,
                shortcut: hotKeyFailure.shortcut,
                language: language
            )
        }
        updateStatusButtonPresentation()
    }

    @objc private func didClickStatusItem() {
        if StatusItemClickRouter.route(for: currentClickEvent) == .openMenu {
            openMenu()
            return
        }

        toggleHandler()
    }

    @objc private func didChooseToggleOverlay() {
        toggleHandler()
    }

    @objc private func didChooseSettings() {
        settingsHandler?()
    }

    @objc private func didChooseQuit() {
        quitHandler?()
    }

    private var currentClickEvent: StatusItemClickEvent? {
        guard let event = NSApp.currentEvent else { return nil }
        return StatusItemClickEvent(
            type: event.type,
            modifierFlags: event.modifierFlags,
            buttonNumber: event.buttonNumber
        )
    }

    private func openMenu() {
        guard let statusItem else { return }

        let menu = NSMenu()
        let model = StatusItemMenuModel.make(
            hotKeyNotice: hotKeyNotice,
            includesSettings: settingsHandler != nil,
            includesQuit: quitHandler != nil,
            language: language
        )

        for descriptor in model.items {
            if descriptor == .separator {
                menu.addItem(.separator())
                continue
            }

            let item = NSMenuItem(
                title: descriptor.title,
                action: selector(for: descriptor.action),
                keyEquivalent: descriptor.keyEquivalent
            )
            item.isEnabled = descriptor.isEnabled
            item.target = self
            menu.addItem(item)
        }

        statusMenu = menu
        menu.delegate = self

        guard let button = statusItem.button else {
            statusMenu = nil
            return
        }

        let didOpen = menu.popUp(
            positioning: nil,
            at: NSPoint(x: button.bounds.midX, y: button.bounds.minY),
            in: button
        )
        if !didOpen {
            statusMenu = nil
        }
    }

    private var currentToolTip: String {
        hotKeyNotice?.toolTip ?? strings.statusAccessibility
    }

    private func updateStatusButtonPresentation() {
        guard let button = statusItem?.button else { return }
        let accessibility = strings.statusAccessibility
        let toolTip = currentToolTip
        button.image = statusImage(
            systemSymbolName: StatusItemAnimation.defaultSymbolName,
            accessibilityDescription: accessibility
        )
        button.contentTintColor = nil
        button.toolTip = toolTip
        button.setAccessibilityLabel(accessibility)
        button.setAccessibilityHelp(toolTip)
    }

    private func statusImage(systemSymbolName: String, accessibilityDescription: String) -> NSImage? {
        let image = NSImage(
            systemSymbolName: systemSymbolName,
            accessibilityDescription: accessibilityDescription
        )
        image?.isTemplate = true
        return image
    }

    private func addClipboardCapturePulse(to button: NSStatusBarButton) {
        guard let layer = button.layer else { return }

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1.0, 1.22, 0.96, 1.0]
        scale.keyTimes = [0.0, 0.32, 0.72, 1.0]
        scale.duration = StatusItemAnimation.pulseDuration
        scale.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        layer.add(scale, forKey: StatusItemAnimation.pulseKey)
    }

    private func finishClipboardCaptureAnimation(animationID: UUID) {
        guard captureAnimationID == animationID else { return }
        clearClipboardCaptureAnimation()
        updateStatusButtonPresentation()
    }

    private func clearClipboardCaptureAnimation() {
        captureAnimationResetTimer?.invalidate()
        captureAnimationResetTimer = nil
        captureAnimationID = nil
        statusItem?.button?.layer?.removeAnimation(forKey: StatusItemAnimation.pulseKey)
    }

    private func selector(for action: StatusItemMenuAction?) -> Selector? {
        switch action {
        case .toggleOverlay:
            return #selector(didChooseToggleOverlay)
        case .openSettings:
            return #selector(didChooseSettings)
        case .quit:
            return #selector(didChooseQuit)
        case nil:
            return nil
        }
    }

    private var strings: StatusItemStrings {
        StatusItemStrings(language: language)
    }
}

extension StatusItemController: NSMenuDelegate {
    public func menuDidClose(_ menu: NSMenu) {
        if menu === statusMenu {
            statusMenu = nil
        }
    }
}

public extension HotKeyShortcut {
    var displayName: String {
        let modifierNames: [(String, String)] = [
            ("command", "Cmd"),
            ("option", "Option"),
            ("control", "Control"),
            ("shift", "Shift")
        ]
        let displayModifiers = modifierNames.compactMap { key, name in
            modifiers.contains(key) ? name : nil
        }
        let keyName: String
        switch keyEquivalent.lowercased() {
        case "space":
            keyName = "Space"
        case "return":
            keyName = "Return"
        case "escape":
            keyName = "Escape"
        default:
            keyName = keyEquivalent.uppercased()
        }

        return (displayModifiers + [keyName]).joined(separator: "+")
    }
}

private struct StatusItemStrings {
    let language: AppLanguage

    var statusAccessibility: String {
        language == .english ? "PasteX clipboard history" : "PasteX 剪贴板历史"
    }

    var showClipboardHistory: String {
        language == .english ? "Show Clipboard History" : "显示剪贴板历史"
    }

    var menuFallbackTitle: String {
        language == .english ? "Show Clipboard History (menu fallback)" : "显示剪贴板历史（菜单备用）"
    }

    var settings: String {
        language == .english ? "Settings..." : "设置..."
    }

    var quit: String {
        language == .english ? "Quit PasteX" : "退出 PasteX"
    }

    func shortcutUnavailable(reason: String) -> String {
        language == .english ? "Shortcut unavailable: \(reason)" : "快捷键不可用：\(reason)"
    }

    func shortcutUnavailableToolTip(reason: String) -> String {
        if language == .english {
            return "PasteX clipboard history. Shortcut unavailable: \(reason). Use the menu bar icon or menu fallback."
        }

        return "PasteX 剪贴板历史。快捷键不可用：\(reason)。请使用菜单栏图标或菜单备用项。"
    }
}

private enum StatusItemAnimation {
    static let defaultSymbolName = "doc.on.clipboard"
    static let captureSymbolName = "doc.on.clipboard.fill"
    static let pulseKey = "PasteXClipboardCapturePulse"
    static let pulseDuration: TimeInterval = 0.42
    static let resetDelay: TimeInterval = 0.5
}
