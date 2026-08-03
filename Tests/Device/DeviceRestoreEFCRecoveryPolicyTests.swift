@main
struct DeviceRestoreEFCRecoveryPolicyTests {

    private static let emergencyController = DeviceRestoreProductIdentity(
        companyIdentifier: 0x0A78,
        productIdentifier: 0x2131
    )
    private static let anotherEmergencyController = DeviceRestoreProductIdentity(
        companyIdentifier: 0x1234,
        productIdentifier: 0x5678
    )
    private static let light = DeviceRestoreProductIdentity(
        companyIdentifier: 0x0A78,
        productIdentifier: 0x2001
    )
    private static let registrations = [
        DeviceRestoreProductRegistration(
            identity: emergencyController,
            deviceCategory: "EmergencyController"
        ),
        DeviceRestoreProductRegistration(
            identity: anotherEmergencyController,
            deviceCategory: "EmergencyController"
        ),
        DeviceRestoreProductRegistration(
            identity: light,
            deviceCategory: "Lighting"
        ),
    ]

    static func main() {
        testUsesNormalRestoreForNonEmergencyCandidate()
        testAllowsMatchingProvisionedEmergencyController()
        testRejectsMissingProvisionedIdentity()
        testRejectsDifferentEmergencyControllerProduct()
        testRejectsProvisionedNormalProduct()
        testReportsOnlyAuthoritativelySuccessfulNodes()
        testReportsAutomaticRestoreOnlyAfterAuthoritativeSuccess()
        testKeepsAutomaticRestoreForCancelledOrUnresolvedResults()
        print("DeviceRestoreEFCRecoveryPolicyTests passed")
    }

    private static func testUsesNormalRestoreForNonEmergencyCandidate() {
        precondition(
            DeviceRestoreEFCRecoveryPolicy.provisionedIdentityDecision(
                wasScannedAsEmergencyController: false,
                scannedIdentity: light,
                provisionedIdentity: nil,
                registrations: registrations
            ) == .normalRestore
        )
    }

    private static func testAllowsMatchingProvisionedEmergencyController() {
        precondition(
            DeviceRestoreEFCRecoveryPolicy.provisionedIdentityDecision(
                wasScannedAsEmergencyController: true,
                scannedIdentity: emergencyController,
                provisionedIdentity: emergencyController,
                registrations: registrations
            ) == .emergencyController
        )
    }

    private static func testRejectsMissingProvisionedIdentity() {
        precondition(
            DeviceRestoreEFCRecoveryPolicy.provisionedIdentityDecision(
                wasScannedAsEmergencyController: true,
                scannedIdentity: emergencyController,
                provisionedIdentity: nil,
                registrations: registrations
            ) == .identityFailed
        )
    }

    private static func testRejectsDifferentEmergencyControllerProduct() {
        precondition(
            DeviceRestoreEFCRecoveryPolicy.provisionedIdentityDecision(
                wasScannedAsEmergencyController: true,
                scannedIdentity: emergencyController,
                provisionedIdentity: anotherEmergencyController,
                registrations: registrations
            ) == .identityFailed
        )
    }

    private static func testRejectsProvisionedNormalProduct() {
        precondition(
            DeviceRestoreEFCRecoveryPolicy.provisionedIdentityDecision(
                wasScannedAsEmergencyController: true,
                scannedIdentity: emergencyController,
                provisionedIdentity: light,
                registrations: registrations
            ) == .identityFailed
        )
    }

    private static func testReportsOnlyAuthoritativelySuccessfulNodes() {
        precondition(
            DeviceRestoreEFCRecoveryPolicy.shouldReportSuccessfulNode(
                deviceSucceeded: true,
                isEmergencyController: false,
                controllerIsSynced: false,
                nodeNeedsSync: false
            )
        )
        precondition(
            !DeviceRestoreEFCRecoveryPolicy.shouldReportSuccessfulNode(
                deviceSucceeded: true,
                isEmergencyController: false,
                controllerIsSynced: false,
                nodeNeedsSync: true
            )
        )
        precondition(
            DeviceRestoreEFCRecoveryPolicy.shouldReportSuccessfulNode(
                deviceSucceeded: true,
                isEmergencyController: true,
                controllerIsSynced: true,
                nodeNeedsSync: true
            )
        )
        precondition(
            !DeviceRestoreEFCRecoveryPolicy.shouldReportSuccessfulNode(
                deviceSucceeded: true,
                isEmergencyController: true,
                controllerIsSynced: false,
                nodeNeedsSync: false
            )
        )
        precondition(
            !DeviceRestoreEFCRecoveryPolicy.shouldReportSuccessfulNode(
                deviceSucceeded: false,
                isEmergencyController: false,
                controllerIsSynced: true,
                nodeNeedsSync: false
            )
        )
    }

    private static func testReportsAutomaticRestoreOnlyAfterAuthoritativeSuccess() {
        precondition(
            DeviceRestoreEFCRecoveryPolicy.automatedCompletionDecision(
                syncResult: .succeeded,
                hasIdentityFailure: false,
                hasMigrationFailure: false,
                hasSyncFailure: false,
                hasUnsyncedEmergencyController: false,
                hasNormalNodeNeedingSync: false
            ) == .reportAndExit
        )
    }

    private static func testKeepsAutomaticRestoreForCancelledOrUnresolvedResults() {
        precondition(
            DeviceRestoreEFCRecoveryPolicy.automatedCompletionDecision(
                syncResult: .cancelled,
                hasIdentityFailure: false,
                hasMigrationFailure: false,
                hasSyncFailure: false,
                hasUnsyncedEmergencyController: false,
                hasNormalNodeNeedingSync: false
            ) == .stayInRestore
        )
        precondition(
            DeviceRestoreEFCRecoveryPolicy.automatedCompletionDecision(
                syncResult: .needsAttention,
                hasIdentityFailure: false,
                hasMigrationFailure: false,
                hasSyncFailure: false,
                hasUnsyncedEmergencyController: false,
                hasNormalNodeNeedingSync: false
            ) == .stayInRestore
        )
        precondition(
            DeviceRestoreEFCRecoveryPolicy.automatedCompletionDecision(
                syncResult: .succeeded,
                hasIdentityFailure: true,
                hasMigrationFailure: false,
                hasSyncFailure: false,
                hasUnsyncedEmergencyController: false,
                hasNormalNodeNeedingSync: false
            ) == .stayInRestore
        )
        precondition(
            DeviceRestoreEFCRecoveryPolicy.automatedCompletionDecision(
                syncResult: .succeeded,
                hasIdentityFailure: false,
                hasMigrationFailure: true,
                hasSyncFailure: false,
                hasUnsyncedEmergencyController: false,
                hasNormalNodeNeedingSync: false
            ) == .stayInRestore
        )
        precondition(
            DeviceRestoreEFCRecoveryPolicy.automatedCompletionDecision(
                syncResult: .succeeded,
                hasIdentityFailure: false,
                hasMigrationFailure: false,
                hasSyncFailure: true,
                hasUnsyncedEmergencyController: false,
                hasNormalNodeNeedingSync: false
            ) == .stayInRestore
        )
        precondition(
            DeviceRestoreEFCRecoveryPolicy.automatedCompletionDecision(
                syncResult: .succeeded,
                hasIdentityFailure: false,
                hasMigrationFailure: false,
                hasSyncFailure: false,
                hasUnsyncedEmergencyController: true,
                hasNormalNodeNeedingSync: false
            ) == .stayInRestore
        )
        precondition(
            DeviceRestoreEFCRecoveryPolicy.automatedCompletionDecision(
                syncResult: .succeeded,
                hasIdentityFailure: false,
                hasMigrationFailure: false,
                hasSyncFailure: false,
                hasUnsyncedEmergencyController: false,
                hasNormalNodeNeedingSync: true
            ) == .stayInRestore
        )
    }
}
