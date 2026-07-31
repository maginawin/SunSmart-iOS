@main
struct GatewayAssociatedSpaceCandidatePolicyTests {

    static func main() {
        testReturnsTwoEditableUnboundSpacesFromExplicitAppKeyMap()
        testMissingAppKeyIsUnavailableInsteadOfEmpty()
        testNonEditableSpaceDoesNotCauseDataFailure()
        testSpaceBoundToAnotherGatewayIsExcluded()
        testCurrentGatewayMatchIsCaseInsensitive()
        print("GatewayAssociatedSpaceCandidatePolicyTests passed")
    }

    private static func testReturnsTwoEditableUnboundSpacesFromExplicitAppKeyMap() {
        let result = GatewayAssociatedSpaceCandidatePolicy.resolve(
            spaces: [
                .init(
                    spaceId: "space-1",
                    canEdit: true,
                    associatedGatewayId: nil,
                    meshNetworkId: "network-1"
                ),
                .init(
                    spaceId: "space-2",
                    canEdit: true,
                    associatedGatewayId: nil,
                    meshNetworkId: "network-2"
                ),
            ],
            currentGatewayId: "gateway-a",
            appKeyIndicesByNetworkId: [
                "network-1": 7,
                "network-2": 9,
            ]
        )

        precondition(
            result == .available([
                .init(spaceId: "space-1", appKeyIndex: 7),
                .init(spaceId: "space-2", appKeyIndex: 9),
            ])
        )
    }

    private static func testMissingAppKeyIsUnavailableInsteadOfEmpty() {
        let result = GatewayAssociatedSpaceCandidatePolicy.resolve(
            spaces: [
                .init(
                    spaceId: "space-1",
                    canEdit: true,
                    associatedGatewayId: nil,
                    meshNetworkId: "missing-network"
                ),
            ],
            currentGatewayId: "gateway-a",
            appKeyIndicesByNetworkId: [:]
        )

        precondition(
            result == .unavailable(missingAppKeySpaceIds: ["space-1"])
        )
    }

    private static func testNonEditableSpaceDoesNotCauseDataFailure() {
        let result = GatewayAssociatedSpaceCandidatePolicy.resolve(
            spaces: [
                .init(
                    spaceId: "space-1",
                    canEdit: false,
                    associatedGatewayId: nil,
                    meshNetworkId: "missing-network"
                ),
            ],
            currentGatewayId: "gateway-a",
            appKeyIndicesByNetworkId: [:]
        )

        precondition(result == .available([]))
    }

    private static func testSpaceBoundToAnotherGatewayIsExcluded() {
        let result = GatewayAssociatedSpaceCandidatePolicy.resolve(
            spaces: [
                .init(
                    spaceId: "space-1",
                    canEdit: true,
                    associatedGatewayId: "gateway-b",
                    meshNetworkId: "network-1"
                ),
            ],
            currentGatewayId: "gateway-a",
            appKeyIndicesByNetworkId: ["network-1": 7]
        )

        precondition(result == .available([]))
    }

    private static func testCurrentGatewayMatchIsCaseInsensitive() {
        let result = GatewayAssociatedSpaceCandidatePolicy.resolve(
            spaces: [
                .init(
                    spaceId: "space-1",
                    canEdit: true,
                    associatedGatewayId: "GATEWAY-A",
                    meshNetworkId: "NETWORK-1"
                ),
            ],
            currentGatewayId: "gateway-a",
            appKeyIndicesByNetworkId: ["network-1": 7]
        )

        precondition(
            result == .available([
                .init(spaceId: "space-1", appKeyIndex: 7),
            ])
        )
    }
}
