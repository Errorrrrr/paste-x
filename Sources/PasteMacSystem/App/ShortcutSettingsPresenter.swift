import AppKit
import PasteCore
import SwiftUI

@MainActor
public protocol ShortcutSettingsPresenting: AnyObject {
    func openSettings(
        currentShortcut: HotKeyShortcut,
        defaultShortcut: HotKeyShortcut,
        currentSettings: AppSettings,
        saveHandler: @escaping (HotKeyShortcut) -> Result<Void, HotKeyError>,
        settingsChangeHandler: @escaping (AppSettings) -> Void
    )
}

@MainActor
public final class ShortcutSettingsPresenter: ShortcutSettingsPresenting {
    private var windowController: NSWindowController?

    public init() {}

    public func openSettings(
        currentShortcut: HotKeyShortcut,
        defaultShortcut: HotKeyShortcut,
        currentSettings: AppSettings,
        saveHandler: @escaping (HotKeyShortcut) -> Result<Void, HotKeyError>,
        settingsChangeHandler: @escaping (AppSettings) -> Void
    ) {
        let view = ShortcutSettingsView(
            currentShortcut: currentShortcut,
            defaultShortcut: defaultShortcut,
            currentSettings: currentSettings,
            saveHandler: saveHandler,
            settingsChangeHandler: { [weak self] settings in
                self?.updateWindowTitle(language: settings.language)
                settingsChangeHandler(settings)
            }
        )
        let hostingController = NSHostingController(rootView: view)

        if let windowController {
            guard let window = windowController.window else { return }
            window.contentViewController = hostingController
            updateWindowTitle(language: currentSettings.language)
            present(window)
            return
        }

        let window = NSWindow(contentViewController: hostingController)
        configure(window, language: currentSettings.language)

        let controller = NSWindowController(window: window)
        windowController = controller
        present(window)
    }

    private func configure(_ window: NSWindow, language: AppLanguage) {
        window.title = ShortcutSettingsStrings(language: language).windowTitle
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setContentSize(NSSize(width: 460, height: 312))
        window.center()
    }

    private func updateWindowTitle(language: AppLanguage) {
        windowController?.window?.title = ShortcutSettingsStrings(language: language).windowTitle
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

@MainActor
private struct ShortcutSettingsView: View {
    @State private var keyEquivalent: String
    @State private var command: Bool
    @State private var option: Bool
    @State private var control: Bool
    @State private var shift: Bool
    @State private var language: AppLanguage
    @State private var feedback: SettingsFeedback?

    private let defaultShortcut: HotKeyShortcut
    private let saveHandler: (HotKeyShortcut) -> Result<Void, HotKeyError>
    private let settingsChangeHandler: (AppSettings) -> Void

    init(
        currentShortcut: HotKeyShortcut,
        defaultShortcut: HotKeyShortcut,
        currentSettings: AppSettings,
        saveHandler: @escaping (HotKeyShortcut) -> Result<Void, HotKeyError>,
        settingsChangeHandler: @escaping (AppSettings) -> Void
    ) {
        _keyEquivalent = State(initialValue: currentShortcut.keyEquivalent)
        _command = State(initialValue: currentShortcut.modifiers.contains("command"))
        _option = State(initialValue: currentShortcut.modifiers.contains("option"))
        _control = State(initialValue: currentShortcut.modifiers.contains("control"))
        _shift = State(initialValue: currentShortcut.modifiers.contains("shift"))
        _language = State(initialValue: currentSettings.language)
        self.defaultShortcut = defaultShortcut
        self.saveHandler = saveHandler
        self.settingsChangeHandler = settingsChangeHandler
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(strings.keyboardShortcutTitle)
                .font(.system(size: 20, weight: .semibold))

            Text(strings.keyboardShortcutDescription)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Picker(strings.languageTitle, selection: $language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(ShortcutSettingsStrings(language: self.language).languageName(language))
                        .tag(language)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .top, spacing: 18) {
                modifiers

                VStack(alignment: .leading, spacing: 6) {
                    Text(strings.keyTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("v", text: $keyEquivalent)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            if let feedback {
                Text(feedback.message(language: language))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(feedback.isError ? .red : .green)
                    .lineLimit(2)
            }

            HStack {
                Button(strings.restoreDefault) {
                    applyShortcut(defaultShortcut, synchronizeControls: true)
                }
                Spacer()
            }
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
        .onChange(of: command) { _, _ in applyCandidateShortcut() }
        .onChange(of: option) { _, _ in applyCandidateShortcut() }
        .onChange(of: control) { _, _ in applyCandidateShortcut() }
        .onChange(of: shift) { _, _ in applyCandidateShortcut() }
        .onChange(of: keyEquivalent) { _, _ in applyCandidateShortcut() }
        .onChange(of: language) { _, newLanguage in
            settingsChangeHandler(AppSettings(language: newLanguage))
        }
    }

    private var modifiers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.modifiersTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Toggle(strings.commandModifier, isOn: $command)
            Toggle(strings.optionModifier, isOn: $option)
            Toggle(strings.controlModifier, isOn: $control)
            Toggle(strings.shiftModifier, isOn: $shift)
        }
        .toggleStyle(.checkbox)
    }

    private var candidateShortcut: HotKeyShortcut {
        var modifiers: Set<String> = []
        if command { modifiers.insert("command") }
        if option { modifiers.insert("option") }
        if control { modifiers.insert("control") }
        if shift { modifiers.insert("shift") }

        return HotKeyShortcut(
            keyEquivalent: normalizedKeyEquivalent,
            modifiers: modifiers
        )
    }

    private var normalizedKeyEquivalent: String {
        keyEquivalent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var strings: ShortcutSettingsStrings {
        ShortcutSettingsStrings(language: language)
    }

    private func applyCandidateShortcut() {
        applyShortcut(candidateShortcut, synchronizeControls: false)
    }

    private func applyShortcut(_ shortcut: HotKeyShortcut, synchronizeControls: Bool) {
        if synchronizeControls {
            keyEquivalent = shortcut.keyEquivalent
            command = shortcut.modifiers.contains("command")
            option = shortcut.modifiers.contains("option")
            control = shortcut.modifiers.contains("control")
            shift = shortcut.modifiers.contains("shift")
        }

        guard !shortcut.keyEquivalent.isEmpty, !shortcut.modifiers.isEmpty else {
            feedback = .incompleteShortcut
            return
        }

        switch saveHandler(shortcut) {
        case .success:
            feedback = .appliedShortcut(shortcut.displayName)
        case let .failure(error):
            feedback = .shortcutFailure(error)
        }
    }
}

enum SettingsFeedback: Equatable {
    case incompleteShortcut
    case appliedShortcut(String)
    case shortcutFailure(HotKeyError)

    var isError: Bool {
        switch self {
        case .appliedShortcut:
            return false
        case .incompleteShortcut, .shortcutFailure:
            return true
        }
    }

    func message(language: AppLanguage) -> String {
        let strings = ShortcutSettingsStrings(language: language)
        switch self {
        case .incompleteShortcut:
            return strings.incompleteShortcutMessage
        case let .appliedShortcut(shortcut):
            return strings.appliedShortcutMessage(shortcut)
        case let .shortcutFailure(error):
            return error.settingsDescription(language: language)
        }
    }
}

private extension HotKeyError {
    func settingsDescription(language: AppLanguage) -> String {
        switch self {
        case .conflict:
            return language == .english ? "Shortcut is already used by another app." : "快捷键已被其他应用占用。"
        case .unsupported:
            return language == .english ? "Shortcut is not supported." : "不支持该快捷键。"
        case let .systemFailure(message):
            return message
        }
    }
}

private struct ShortcutSettingsStrings {
    let language: AppLanguage

    var windowTitle: String {
        language == .english ? "PasteX Settings" : "PasteX 设置"
    }

    var keyboardShortcutTitle: String {
        language == .english ? "Keyboard Shortcut" : "键盘快捷键"
    }

    var keyboardShortcutDescription: String {
        language == .english
            ? "Changes are saved immediately and take effect without a Save button."
            : "修改会立即保存并生效，无需保存按钮。"
    }

    var languageTitle: String {
        language == .english ? "Language" : "语言"
    }

    var keyTitle: String {
        language == .english ? "Key" : "按键"
    }

    var modifiersTitle: String {
        language == .english ? "Modifiers" : "修饰键"
    }

    var commandModifier: String {
        language == .english ? "Command" : "Command"
    }

    var optionModifier: String {
        language == .english ? "Option" : "Option"
    }

    var controlModifier: String {
        language == .english ? "Control" : "Control"
    }

    var shiftModifier: String {
        language == .english ? "Shift" : "Shift"
    }

    var restoreDefault: String {
        language == .english ? "Restore Default" : "恢复默认"
    }

    var incompleteShortcutMessage: String {
        language == .english
            ? "Choose at least one modifier and one key."
            : "请至少选择一个修饰键和一个按键。"
    }

    func appliedShortcutMessage(_ shortcut: String) -> String {
        language == .english ? "Applied \(shortcut)." : "已应用 \(shortcut)。"
    }

    func languageName(_ option: AppLanguage) -> String {
        switch option {
        case .english:
            return language == .english ? "English" : "英文"
        case .simplifiedChinese:
            return language == .english ? "Chinese" : "中文"
        }
    }
}
