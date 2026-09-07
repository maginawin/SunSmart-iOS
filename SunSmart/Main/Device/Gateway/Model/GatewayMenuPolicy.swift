import Foundation

enum GatewayFirmwareKind {
    case fourG
    case wifi

    var customerId: String {
        switch self {
        case .fourG:
            return "4g"
        case .wifi:
            return "wifi"
        }
    }

    var pageTitleLocalizationKey: String {
        switch self {
        case .fourG:
            return "4g_firmware_update"
        case .wifi:
            return "wifi_firmware_update"
        }
    }

    var sessionNamespace: String {
        customerId
    }
}

struct GatewayFirmwareDFUProfile: Equatable {
    let firmwareKind: GatewayFirmwareKind
    let nodeProductId: UInt16

    let manufacturerId = "0A78"

    var deviceType: UInt16 {
        switch firmwareKind {
        case .fourG:
            return 0x2703
        case .wifi:
            return nodeProductId
        }
    }

    var customerId: String {
        firmwareKind.customerId
    }

    var usesServerProvidedDownloadURL: Bool {
        firmwareKind == .fourG
    }

    var pageTitleLocalizationKey: String {
        firmwareKind.pageTitleLocalizationKey
    }

    var sessionNamespace: String {
        firmwareKind.sessionNamespace
    }
}

enum GatewayMenuAction: Equatable {
    case fourGDFU
    case wifiDFU
    case delete
    case information
    case identify
    case forceClearSpaces
}

enum GatewayBottomActionMode: Equatable {
    case saveOnly
    case hidden
}

struct GatewayMenuPolicy {

    static func menuActions(
        firmwareKind: GatewayFirmwareKind,
        canDelete: Bool,
        isBluetoothOffline: Bool,
        hasAssociatedSpaces: Bool,
        canForceClearSpaces: Bool
    ) -> [GatewayMenuAction] {
        var actions: [GatewayMenuAction] = [
            firmwareKind == .wifi ? .wifiDFU : .fourGDFU
        ]
        if canDelete {
            actions.append(.delete)
        }
        actions.append(contentsOf: [.information, .identify])
        if isBluetoothOffline && hasAssociatedSpaces && canForceClearSpaces {
            actions.append(.forceClearSpaces)
        }
        return actions
    }

    static func bottomActionMode(
        isConfigured: Bool
    ) -> GatewayBottomActionMode {
        isConfigured ? .saveOnly : .hidden
    }
}
