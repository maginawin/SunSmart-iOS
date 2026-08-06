import Foundation

@main
struct GatewayFirmwareScanNetworkKeyScopePolicyTests {
    static func main() {
        let resolution = GatewayFirmwareScanNetworkKeyScopePolicy.resolve(
            primaryNetworkKeyIndex: 0,
            availableNetworkKeyIndexes: [0, 2, 3, 7, 9, 10],
            boundNetworkKeyIndexByApplicationKeyIndex: [7: 2, 8: 99],
            gateways: [
                .init(
                    address: 0x00C3,
                    associatedApplicationKeyIndexes: [7, 3, 3, 8, 11]
                ),
                .init(
                    address: 0x00D4,
                    associatedApplicationKeyIndexes: [9, 10]
                )
            ]
        )

        precondition(
            resolution.allowedNetworkKeyIndexesByAddress[0x00C3] == [0, 2, 3],
            "Gateway C3 should use primary, bound AppKey 7 -> NetKey 2, and fallback NetKey 3"
        )
        precondition(
            resolution.unresolvedApplicationKeyIndexesByAddress[0x00C3] == [8, 11],
            "Unavailable bound/fallback keys should remain unresolved"
        )
        precondition(
            resolution.allowedNetworkKeyIndexesByAddress[0x00D4] == [0, 9, 10],
            "Gateway D4 must keep an isolated key scope"
        )
        precondition(
            resolution.unresolvedApplicationKeyIndexesByAddress[0x00D4] == [],
            "Resolved gateway should not report unresolved keys"
        )

        let noPrimary = GatewayFirmwareScanNetworkKeyScopePolicy.resolve(
            primaryNetworkKeyIndex: nil,
            availableNetworkKeyIndexes: [4],
            boundNetworkKeyIndexByApplicationKeyIndex: [:],
            gateways: [
                .init(address: 0x0100, associatedApplicationKeyIndexes: [4])
            ]
        )
        precondition(
            noPrimary.allowedNetworkKeyIndexesByAddress[0x0100] == [4]
        )

        print("GatewayFirmwareScanNetworkKeyScopePolicyTests passed")
    }
}
