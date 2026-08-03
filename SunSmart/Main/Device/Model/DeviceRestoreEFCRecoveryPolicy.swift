enum DeviceRestoreProvisionedIdentityDecision {
    case normalRestore
    case emergencyController
    case identityFailed
}

enum DeviceRestoreSyncRunResult {
    case succeeded
    case needsAttention
    case cancelled
}

enum DeviceRestoreAutomatedCompletionDecision {
    case reportAndExit
    case stayInRestore
}

enum DeviceRestoreEFCRecoveryPolicy {

    static func provisionedIdentityDecision(
        wasScannedAsEmergencyController: Bool,
        scannedIdentity: DeviceRestoreProductIdentity?,
        provisionedIdentity: DeviceRestoreProductIdentity?,
        registrations: [DeviceRestoreProductRegistration]
    ) -> DeviceRestoreProvisionedIdentityDecision {
        guard wasScannedAsEmergencyController else {
            return .normalRestore
        }
        guard DeviceRestoreCandidatePolicy.isRegisteredEmergencyController(
            scannedIdentity,
            registrations: registrations
        ), DeviceRestoreCandidatePolicy.isRegisteredEmergencyController(
            provisionedIdentity,
            registrations: registrations
        ), scannedIdentity == provisionedIdentity else {
            return .identityFailed
        }
        return .emergencyController
    }

    static func automatedCompletionDecision(
        syncResult: DeviceRestoreSyncRunResult,
        hasIdentityFailure: Bool,
        hasMigrationFailure: Bool,
        hasSyncFailure: Bool,
        hasUnsyncedEmergencyController: Bool,
        hasNormalNodeNeedingSync: Bool
    ) -> DeviceRestoreAutomatedCompletionDecision {
        guard syncResult == .succeeded,
              !hasIdentityFailure,
              !hasMigrationFailure,
              !hasSyncFailure,
              !hasUnsyncedEmergencyController,
              !hasNormalNodeNeedingSync else {
            return .stayInRestore
        }
        return .reportAndExit
    }

    static func shouldReportSuccessfulNode(
        deviceSucceeded: Bool,
        isEmergencyController: Bool,
        controllerIsSynced: Bool,
        nodeNeedsSync: Bool
    ) -> Bool {
        guard deviceSucceeded else {
            return false
        }
        if isEmergencyController {
            return controllerIsSynced
        }
        return !nodeNeedsSync
    }
}
