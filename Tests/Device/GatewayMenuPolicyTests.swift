import Foundation

@main
struct GatewayMenuPolicyTests {

    static func main() {
        testFourGMenuWithDelete()
        testFourGMenuWithoutDelete()
        testWiFiMenuKeepsCommonActions()
        testForceClearSpacesRequiresOfflineNonemptyAndPermission()
        testBottomActionModes()
        print("GatewayMenuPolicyTests passed")
    }

    private static func testFourGMenuWithDelete() {
        precondition(
            GatewayMenuPolicy.menuActions(
                firmwareKind: .fourG,
                canDelete: true,
                isBluetoothOffline: false,
                hasAssociatedSpaces: true,
                canForceClearSpaces: true
            ) == [.fourGDFU, .delete, .information, .identify]
        )
    }

    private static func testFourGMenuWithoutDelete() {
        precondition(
            GatewayMenuPolicy.menuActions(
                firmwareKind: .fourG,
                canDelete: false,
                isBluetoothOffline: false,
                hasAssociatedSpaces: true,
                canForceClearSpaces: true
            ) == [.fourGDFU, .information, .identify]
        )
    }

    private static func testWiFiMenuKeepsCommonActions() {
        precondition(
            GatewayMenuPolicy.menuActions(
                firmwareKind: .wifi,
                canDelete: true,
                isBluetoothOffline: false,
                hasAssociatedSpaces: true,
                canForceClearSpaces: true
            ) == [.wifiDFU, .delete, .information, .identify]
        )
    }

    private static func testForceClearSpacesRequiresOfflineNonemptyAndPermission() {
        precondition(
            GatewayMenuPolicy.menuActions(
                firmwareKind: .fourG,
                canDelete: true,
                isBluetoothOffline: true,
                hasAssociatedSpaces: true,
                canForceClearSpaces: true
            ) == [.fourGDFU, .delete, .information, .identify, .forceClearSpaces]
        )
        precondition(
            !GatewayMenuPolicy.menuActions(
                firmwareKind: .fourG,
                canDelete: true,
                isBluetoothOffline: false,
                hasAssociatedSpaces: true,
                canForceClearSpaces: true
            ).contains(.forceClearSpaces)
        )
        precondition(
            !GatewayMenuPolicy.menuActions(
                firmwareKind: .fourG,
                canDelete: true,
                isBluetoothOffline: true,
                hasAssociatedSpaces: false,
                canForceClearSpaces: true
            ).contains(.forceClearSpaces)
        )
        precondition(
            !GatewayMenuPolicy.menuActions(
                firmwareKind: .fourG,
                canDelete: true,
                isBluetoothOffline: true,
                hasAssociatedSpaces: true,
                canForceClearSpaces: false
            ).contains(.forceClearSpaces)
        )
    }

    private static func testBottomActionModes() {
        precondition(
            GatewayMenuPolicy.bottomActionMode(isConfigured: true) == .saveOnly
        )
        precondition(
            GatewayMenuPolicy.bottomActionMode(isConfigured: false) == .hidden
        )
    }
}
