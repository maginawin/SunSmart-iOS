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
}

enum GatewayBottomActionMode: Equatable {
    case saveOnly
    case hidden
}

struct GatewayMenuPolicy {

    static func menuActions(
        firmwareKind: GatewayFirmwareKind,
        canDelete: Bool
    ) -> [GatewayMenuAction] {
        var actions: [GatewayMenuAction] = [
            firmwareKind == .wifi ? .wifiDFU : .fourGDFU
        ]
        if canDelete {
            actions.append(.delete)
        }
        actions.append(contentsOf: [.information, .identify])
        return actions
    }

    static func bottomActionMode(
        isConfigured: Bool
    ) -> GatewayBottomActionMode {
        isConfigured ? .saveOnly : .hidden
    }
}
