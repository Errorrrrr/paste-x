import ServiceManagement
import Testing
@testable import PasteMacSystem

@Test func launchAtLoginManagerTreatsNotFoundAsDisabled() {
    let service = FakeMainAppService(statuses: [.notFound])
    let manager = SMAppServiceLaunchAtLoginManager(service: service)

    #expect(manager.status() == .disabled)
}

@Test func launchAtLoginManagerRegistersWhenCurrentStatusIsNotFound() {
    let service = FakeMainAppService(statuses: [.notFound, .enabled])
    let manager = SMAppServiceLaunchAtLoginManager(service: service)

    let result = manager.setEnabled(true)

    #expect(result == .success(.enabled))
    #expect(service.registerCallCount == 1)
    #expect(service.unregisterCallCount == 0)
}

private final class FakeMainAppService: MainAppServiceManaging {
    private var statuses: [SMAppService.Status]
    private let fallbackStatus: SMAppService.Status
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(statuses: [SMAppService.Status]) {
        self.statuses = statuses
        self.fallbackStatus = statuses.last ?? .notRegistered
    }

    var status: SMAppService.Status {
        if statuses.isEmpty {
            return fallbackStatus
        }
        return statuses.removeFirst()
    }

    func register() throws {
        registerCallCount += 1
    }

    func unregister() throws {
        unregisterCallCount += 1
    }
}
