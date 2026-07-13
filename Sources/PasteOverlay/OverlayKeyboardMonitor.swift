import AppKit
import Foundation

struct OverlayKeyboardModifiers: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let command = Self(rawValue: 1 << 0)
    static let control = Self(rawValue: 1 << 1)
    static let option = Self(rawValue: 1 << 2)
    static let shift = Self(rawValue: 1 << 3)
}

struct OverlayKeyboardEvent: Equatable, Sendable {
    let keyCode: UInt16
    let modifiers: OverlayKeyboardModifiers
    let characters: String?
    let isRepeat: Bool

    init(
        keyCode: UInt16,
        modifiers: OverlayKeyboardModifiers,
        characters: String?,
        isRepeat: Bool
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.characters = characters
        self.isRepeat = isRepeat
    }

    init(_ event: NSEvent) {
        self.init(
            keyCode: event.keyCode,
            modifiers: OverlayKeyboardModifiers(event.modifierFlags),
            characters: event.characters,
            isRepeat: event.isARepeat
        )
    }
}

private extension OverlayKeyboardModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var result: Self = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        self = result
    }
}
