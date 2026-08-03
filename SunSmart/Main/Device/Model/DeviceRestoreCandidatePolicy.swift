struct DeviceRestoreProductIdentity: Hashable {
    let companyIdentifier: UInt16
    let productIdentifier: UInt16
}

struct DeviceRestoreProductRegistration: Equatable {
    let identity: DeviceRestoreProductIdentity
    let deviceCategory: String
}

enum DeviceRestoreCandidateFilter {
    case all
    case gatewaysOnly
    case currentSpaceNonGateways
}

enum DeviceRestoreCandidatePolicy {

    static func identity(
        companyIdentifier: UInt16?,
        productIdentifier: UInt16?
    ) -> DeviceRestoreProductIdentity? {
        guard let companyIdentifier, let productIdentifier else {
            return nil
        }
        return DeviceRestoreProductIdentity(
            companyIdentifier: companyIdentifier,
            productIdentifier: productIdentifier
        )
    }

    static func isRegisteredEmergencyController(
        _ identity: DeviceRestoreProductIdentity?,
        registrations: [DeviceRestoreProductRegistration]
    ) -> Bool {
        guard let identity else {
            return false
        }
        return registrations.contains {
            $0.identity == identity && $0.deviceCategory == "EmergencyController"
        }
    }

    static func includesHistoricalNode(
        filter: DeviceRestoreCandidateFilter,
        isGateway: Bool,
        belongsToCurrentSpace: Bool
    ) -> Bool {
        switch filter {
        case .all:
            return true
        case .gatewaysOnly:
            return isGateway
        case .currentSpaceNonGateways:
            return !isGateway && belongsToCurrentSpace
        }
    }

    static func allowsScannedIdentity(
        historicalIdentity: DeviceRestoreProductIdentity?,
        advertisedIdentity: DeviceRestoreProductIdentity?,
        registrations: [DeviceRestoreProductRegistration]
    ) -> Bool {
        let historicalIsEmergencyController = isRegisteredEmergencyController(
            historicalIdentity,
            registrations: registrations
        )
        let advertisedIsEmergencyController = isRegisteredEmergencyController(
            advertisedIdentity,
            registrations: registrations
        )

        guard historicalIsEmergencyController || advertisedIsEmergencyController else {
            return true
        }
        return historicalIsEmergencyController &&
            advertisedIsEmergencyController &&
            historicalIdentity == advertisedIdentity
    }
}
