import Foundation
import Testing
@testable import PasteMacSystem
import PasteCore

@Test func hotKeyManagerRegistersDefaultShortcutAndInvokesHandler() throws {
    let backend = FakeHotKeyBackend()
    let manager = HotKeyManager(backend: backend)
    let invocationCounter = InvocationCounter()

    let result = manager.register(shortcut: .defaultToggleOverlay) {
        invocationCounter.increment()
    }
    backend.fire()

    #expect(result.isSuccess)
    #expect(backend.lastShortcut == .defaultToggleOverlay)
    #expect(invocationCounter.count == 1)
}

@Test func hotKeyManagerReturnsConflictWhenBackendCannotRegister() {
    let backend = FakeHotKeyBackend()
    backend.result = .failure(.conflict)
    let manager = HotKeyManager(backend: backend)

    let result = manager.register(shortcut: .defaultToggleOverlay) {}

    #expect(result.failure == .conflict)
}

@Test func hotKeyManagerUnregistersExistingShortcutBeforeReplacingIt() {
    let backend = FakeHotKeyBackend()
    let manager = HotKeyManager(backend: backend)

    _ = manager.register(shortcut: .defaultToggleOverlay) {}
    _ = manager.register(shortcut: HotKeyShortcut(keyEquivalent: "b", modifiers: ["command"])) {}

    #expect(backend.unregisterCount == 1)
    #expect(backend.lastShortcut == HotKeyShortcut(keyEquivalent: "b", modifiers: ["command"]))
}

private final class FakeHotKeyBackend: HotKeyRegistrationBackend {
    var result: Result<Void, HotKeyError> = .success(())
    private(set) var lastShortcut: HotKeyShortcut?
    private(set) var unregisterCount = 0
    private var handler: (@Sendable () -> Void)?

    func register(shortcut: HotKeyShortcut, handler: @escaping @Sendable () -> Void) -> Result<Void, HotKeyError> {
        lastShortcut = shortcut
        self.handler = handler
        return result
    }

    func unregister() {
        unregisterCount += 1
        handler = nil
    }

    func fire() {
        handler?()
    }
}

private final class InvocationCounter: @unchecked Sendable {
    private(set) var count = 0

    func increment() {
        count += 1
    }
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
