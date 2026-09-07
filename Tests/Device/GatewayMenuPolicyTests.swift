import Foundation

@main
struct GatewayMenuPolicyTests {

    static func main() {
        testFourGMenuWithDelete()
        testFourGMenuWithoutDelete()
        testWiFiMenuKeepsCommonActions()
        testForceClearSpacesRequiresOfflineNonemptyAndPermission()
        testBottomActionModes()
        testFirmwareProfilesForCurrentAndFutureProducts()
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

    private static func testFirmwareProfilesForCurrentAndFutureProducts() {
        let fourG = GatewayFirmwareDFUProfile(firmwareKind: .fourG, nodeProductId: 0x2703)
        precondition(fourG.deviceType == 0x2703)
        precondition(fourG.customerId == "4g")
        precondition(fourG.usesServerProvidedDownloadURL)
        precondition(fourG.pageTitleLocalizationKey == "4g_firmware_update")
        precondition(fourG.sessionNamespace == "4g")
        let wifi = GatewayFirmwareDFUProfile(firmwareKind: .wifi, nodeProductId: 0x2721)
        precondition(wifi.deviceType == 0x2721)
        precondition(wifi.customerId == "wifi")
        precondition(!wifi.usesServerProvidedDownloadURL)
        precondition(wifi.pageTitleLocalizationKey == "wifi_firmware_update")
        precondition(wifi.sessionNamespace == "wifi")
        for pid: UInt16 in [0x1701, 0x1702, 0x2701, 0x2702, 0x2711, 0x3703] {
            let profile = GatewayFirmwareDFUProfile(firmwareKind: .fourG, nodeProductId: pid)
            precondition(profile.deviceType == 0x2703)
            precondition(profile.customerId == "4g")
            precondition(profile.pageTitleLocalizationKey == "4g_firmware_update")
        }
        let futureWiFi = GatewayFirmwareDFUProfile(firmwareKind: .wifi, nodeProductId: 0x3721)
        precondition(futureWiFi.deviceType == 0x3721)
        precondition(futureWiFi.customerId == "wifi")
        precondition(futureWiFi.pageTitleLocalizationKey == "wifi_firmware_update")
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
