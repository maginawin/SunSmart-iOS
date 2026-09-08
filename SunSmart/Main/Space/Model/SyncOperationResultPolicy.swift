import Foundation

/// ACK、业务回读与合法空消息的区别不能在统一调度时丢失。
enum SyncOperationResultPolicy {
    enum Category: CaseIterable {
        case ordinary
        case gatewayRepairInitialization
        case gatewayRecoveryInitialization
        case emergencyFireDeleteCleanup
        case batteryPowerSwitchOwnConfiguration
    }

    struct RetryPolicy {
        let maxRetries: Int
        let retryDelay: TimeInterval
        var maxAttempts: Int { maxRetries + 1 }
    }

    static let emergencyFireDeleteCleanupRetryPolicy = RetryPolicy(maxRetries: 2, retryDelay: 0.2)

    static func ackTimeout(isEmergencyFireDeleteCleanup: Bool) -> TimeInterval {
        isEmergencyFireDeleteCleanup ? 5 : 15
    }

    static func isSuccessful(
        category: Category,
        hasMessages: Bool,
        resultSuccessful: Bool,
        operationSuccessful: Bool
    ) -> Bool {
        switch category {
        case .ordinary:
            return resultSuccessful && operationSuccessful
        case .gatewayRepairInitialization:
            return hasMessages && resultSuccessful && operationSuccessful
        case .gatewayRecoveryInitialization, .emergencyFireDeleteCleanup, .batteryPowerSwitchOwnConfiguration:
            return hasMessages && resultSuccessful
        }
    }
}
