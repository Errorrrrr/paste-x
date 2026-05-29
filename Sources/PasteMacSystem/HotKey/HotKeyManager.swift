import Carbon
import Foundation
import PasteCore

public extension HotKeyShortcut {
    static let defaultToggleOverlay = HotKeyShortcut(
        keyEquivalent: "v",
        modifiers: ["command", "option"]
    )
}

public protocol HotKeyRegistrationBackend: AnyObject {
    func register(shortcut: HotKeyShortcut, handler: @escaping @Sendable () -> Void) -> Result<Void, HotKeyError>
    func unregister()
}

public final class HotKeyManager: HotKeyManaging {
    private let backend: HotKeyRegistrationBackend
    private var isRegistered = false

    public init(backend: HotKeyRegistrationBackend = CarbonHotKeyRegistrationBackend()) {
        self.backend = backend
    }

    public func register(shortcut: HotKeyShortcut, handler: @escaping @Sendable () -> Void) -> Result<Void, HotKeyError> {
        unregister()

        let result = backend.register(shortcut: shortcut, handler: handler)
        if case .success = result {
            isRegistered = true
        }
        return result
    }

    public func unregister() {
        guard isRegistered else { return }
        backend.unregister()
        isRegistered = false
    }
}

public final class CarbonHotKeyRegistrationBackend: HotKeyRegistrationBackend {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (@Sendable () -> Void)?

    public init() {}

    public func register(shortcut: HotKeyShortcut, handler: @escaping @Sendable () -> Void) -> Result<Void, HotKeyError> {
        unregister()

        guard let keyCode = KeyCodeMapper.keyCode(for: shortcut.keyEquivalent) else {
            return .failure(.unsupported)
        }

        let modifiers = CarbonModifierMapper.modifiers(for: shortcut.modifiers)
        guard modifiers != 0 else {
            return .failure(.unsupported)
        }

        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installedHandler: EventHandlerRef?
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let backend = Unmanaged<CarbonHotKeyRegistrationBackend>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                backend.handler?()
                return noErr
            },
            1,
            &eventType,
            userData,
            &installedHandler
        )

        guard installStatus == noErr else {
            self.handler = nil
            return .failure(.systemFailure("InstallEventHandler failed with status \(installStatus)"))
        }

        var registeredHotKey: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: FourCharCode.make("PSTE"), id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotKey
        )

        guard registerStatus == noErr else {
            if let installedHandler {
                RemoveEventHandler(installedHandler)
            }
            self.handler = nil
            return .failure(Self.map(status: registerStatus))
        }

        eventHandlerRef = installedHandler
        hotKeyRef = registeredHotKey
        return .success(())
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        hotKeyRef = nil
        eventHandlerRef = nil
        handler = nil
    }

    private static func map(status: OSStatus) -> HotKeyError {
        if status == -9878 {
            return .conflict
        }
        return .systemFailure("RegisterEventHotKey failed with status \(status)")
    }
}

private enum KeyCodeMapper {
    static func keyCode(for keyEquivalent: String) -> UInt16? {
        codes[keyEquivalent.lowercased()]
    }

    private static let codes: [String: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04,
        "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
        "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F,
        "y": 0x10, "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
        "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18, "9": 0x19,
        "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E,
        "o": 0x1F, "u": 0x20, "[": 0x21, "i": 0x22, "p": 0x23,
        "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
        "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E,
        ".": 0x2F, "`": 0x32, "return": 0x24, "space": 0x31,
        "escape": 0x35
    ]
}

private enum CarbonModifierMapper {
    static func modifiers(for values: Set<String>) -> UInt32 {
        values.reduce(UInt32(0)) { result, value in
            switch value.lowercased() {
            case "command", "cmd":
                return result | UInt32(cmdKey)
            case "option", "alt":
                return result | UInt32(optionKey)
            case "control", "ctrl":
                return result | UInt32(controlKey)
            case "shift":
                return result | UInt32(shiftKey)
            default:
                return result
            }
        }
    }
}

private enum FourCharCode {
    static func make(_ value: String) -> OSType {
        value.utf8.reduce(UInt32(0)) { result, character in
            (result << 8) + UInt32(character)
        }
    }
}
