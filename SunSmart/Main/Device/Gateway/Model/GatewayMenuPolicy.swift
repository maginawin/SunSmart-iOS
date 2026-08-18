import Foundation

enum GatewayFirmwareKind {
    case fourG
    case wifi
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
