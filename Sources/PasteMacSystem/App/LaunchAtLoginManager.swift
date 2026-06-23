import Foundation
import ServiceManagement

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable(String)

    public var isEnabled: Bool {
        self == .enabled
    }
}

public enum LaunchAtLoginError: Error, Equatable, Sendable {
    case unavailable(String)
    case operationFailed(String)
}

public protocol LaunchAtLoginManaging: AnyObject {
    func status() -> LaunchAtLoginStatus
    func setEnabled(_ enabled: Bool) -> Result<LaunchAtLoginStatus, LaunchAtLoginError>
}

public final class SMAppServiceLaunchAtLoginManager: LaunchAtLoginManaging {
    public init() {}

    public func status() -> LaunchAtLoginStatus {
        serviceStatus()
    }

    public func setEnabled(_ enabled: Bool) -> Result<LaunchAtLoginStatus, LaunchAtLoginError> {
        let currentStatus = serviceStatus()
        if enabled, currentStatus == .enabled {
            return .success(currentStatus)
        }
        if !enabled, currentStatus == .disabled {
            return .success(currentStatus)
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return .success(serviceStatus())
        } catch {
            return .failure(.operationFailed(error.localizedDescription))
        }
    }

    private func serviceStatus() -> LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable("PasteX is not available as a login item from this bundle.")
        @unknown default:
            return .unavailable("PasteX login item status is not supported on this macOS version.")
        }
    }
}
