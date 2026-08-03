@main
struct DeviceRestoreCandidatePolicyTests {

    private static let firstEmergencyController = DeviceRestoreProductIdentity(
        companyIdentifier: 0x0A78,
        productIdentifier: 0x2131
    )
    private static let secondEmergencyController = DeviceRestoreProductIdentity(
        companyIdentifier: 0x1234,
        productIdentifier: 0x5678
    )
    private static let light = DeviceRestoreProductIdentity(
        companyIdentifier: 0x0A78,
        productIdentifier: 0x2001
    )
    private static let registrations = [
        DeviceRestoreProductRegistration(
            identity: firstEmergencyController,
            deviceCategory: "EmergencyController"
        ),
        DeviceRestoreProductRegistration(
            identity: secondEmergencyController,
            deviceCategory: "EmergencyController"
        ),
        DeviceRestoreProductRegistration(
            identity: light,
            deviceCategory: "Lighting"
        ),
    ]

    static func main() {
        testRecognizesEveryRegisteredEmergencyController()
        testAllowsSameRegisteredEmergencyControllerIdentity()
        testRejectsDifferentEmergencyControllerProducts()
        testRejectsMissingEmergencyControllerIdentity()
        testRejectsEmergencyControllerAndNormalDeviceMismatch()
        testPreservesNormalDeviceRestoreIdentityBehavior()
        testAllFilterIncludesEmergencyController()
        testCurrentSpaceFilterIncludesNonGatewayInCurrentSpace()
        testCurrentSpaceFilterRejectsGatewayAndOtherSpace()
        testGatewayFilterOnlyIncludesGateway()
        print("DeviceRestoreCandidatePolicyTests passed")
    }

    private static func testRecognizesEveryRegisteredEmergencyController() {
        precondition(
            DeviceRestoreCandidatePolicy.isRegisteredEmergencyController(
                firstEmergencyController,
                registrations: registrations
            )
        )
        precondition(
            DeviceRestoreCandidatePolicy.isRegisteredEmergencyController(
                secondEmergencyController,
                registrations: registrations
            )
        )
        precondition(
            !DeviceRestoreCandidatePolicy.isRegisteredEmergencyController(
                light,
                registrations: registrations
            )
        )
    }

    private static func testAllowsSameRegisteredEmergencyControllerIdentity() {
        precondition(
            DeviceRestoreCandidatePolicy.allowsScannedIdentity(
                historicalIdentity: firstEmergencyController,
                advertisedIdentity: firstEmergencyController,
                registrations: registrations
            )
        )
    }

    private static func testRejectsDifferentEmergencyControllerProducts() {
        precondition(
            !DeviceRestoreCandidatePolicy.allowsScannedIdentity(
                historicalIdentity: firstEmergencyController,
                advertisedIdentity: secondEmergencyController,
                registrations: registrations
            )
        )
    }

    private static func testRejectsMissingEmergencyControllerIdentity() {
        precondition(
            !DeviceRestoreCandidatePolicy.allowsScannedIdentity(
                historicalIdentity: firstEmergencyController,
                advertisedIdentity: nil,
                registrations: registrations
            )
        )
        precondition(
            !DeviceRestoreCandidatePolicy.allowsScannedIdentity(
                historicalIdentity: nil,
                advertisedIdentity: firstEmergencyController,
                registrations: registrations
            )
        )
    }

    private static func testRejectsEmergencyControllerAndNormalDeviceMismatch() {
        precondition(
            !DeviceRestoreCandidatePolicy.allowsScannedIdentity(
                historicalIdentity: firstEmergencyController,
                advertisedIdentity: light,
                registrations: registrations
            )
        )
        precondition(
            !DeviceRestoreCandidatePolicy.allowsScannedIdentity(
                historicalIdentity: light,
                advertisedIdentity: firstEmergencyController,
                registrations: registrations
            )
        )
    }

    private static func testPreservesNormalDeviceRestoreIdentityBehavior() {
        precondition(
            DeviceRestoreCandidatePolicy.allowsScannedIdentity(
                historicalIdentity: light,
                advertisedIdentity: nil,
                registrations: registrations
            )
        )
        precondition(
            DeviceRestoreCandidatePolicy.allowsScannedIdentity(
                historicalIdentity: nil,
                advertisedIdentity: nil,
                registrations: registrations
            )
        )
    }

    private static func testAllFilterIncludesEmergencyController() {
        precondition(
            DeviceRestoreCandidatePolicy.includesHistoricalNode(
                filter: .all,
                isGateway: false,
                belongsToCurrentSpace: true
            )
        )
    }

    private static func testCurrentSpaceFilterIncludesNonGatewayInCurrentSpace() {
        precondition(
            DeviceRestoreCandidatePolicy.includesHistoricalNode(
                filter: .currentSpaceNonGateways,
                isGateway: false,
                belongsToCurrentSpace: true
            )
        )
    }

    private static func testCurrentSpaceFilterRejectsGatewayAndOtherSpace() {
        precondition(
            !DeviceRestoreCandidatePolicy.includesHistoricalNode(
                filter: .currentSpaceNonGateways,
                isGateway: true,
                belongsToCurrentSpace: true
            )
        )
        precondition(
            !DeviceRestoreCandidatePolicy.includesHistoricalNode(
                filter: .currentSpaceNonGateways,
                isGateway: false,
                belongsToCurrentSpace: false
            )
        )
    }

    private static func testGatewayFilterOnlyIncludesGateway() {
        precondition(
            DeviceRestoreCandidatePolicy.includesHistoricalNode(
                filter: .gatewaysOnly,
                isGateway: true,
                belongsToCurrentSpace: false
            )
        )
        precondition(
            !DeviceRestoreCandidatePolicy.includesHistoricalNode(
                filter: .gatewaysOnly,
                isGateway: false,
                belongsToCurrentSpace: true
            )
        )
    }
}
