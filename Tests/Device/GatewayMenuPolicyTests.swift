import Foundation

@main
struct GatewayMenuPolicyTests {

    static func main() {
        testFourGMenuWithDelete()
        testFourGMenuWithoutDelete()
        testWiFiMenuKeepsCommonActions()
        testBottomActionModes()
        print("GatewayMenuPolicyTests passed")
    }

    private static func testFourGMenuWithDelete() {
        precondition(
            GatewayMenuPolicy.menuActions(
                firmwareKind: .fourG,
                canDelete: true
            ) == [.fourGDFU, .delete, .information, .identify]
        )
    }

    private static func testFourGMenuWithoutDelete() {
        precondition(
            GatewayMenuPolicy.menuActions(
                firmwareKind: .fourG,
                canDelete: false
            ) == [.fourGDFU, .information, .identify]
        )
    }

    private static func testWiFiMenuKeepsCommonActions() {
        precondition(
            GatewayMenuPolicy.menuActions(
                firmwareKind: .wifi,
                canDelete: true
            ) == [.wifiDFU, .delete, .information, .identify]
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
