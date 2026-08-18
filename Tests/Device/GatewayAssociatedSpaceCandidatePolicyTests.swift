@main
struct GatewayAssociatedSpaceCandidatePolicyTests {

    static func main() {
        testReturnsTwoEditableUnboundSpacesFromExplicitAppKeyMap()
        testMissingAppKeyIsUnavailableInsteadOfEmpty()
        testNonEditableSpaceDoesNotCauseDataFailure()
        testSpaceBoundToAnotherGatewayIsExcluded()
        testCurrentGatewayMatchIsCaseInsensitive()
        testMutationRejectsChangedServerTopology()
        testEditorCanOnlyMutateEditableSpaces()
        testOwnerCanMutateAnySpace()
        testDestructiveAccessRequiresAllAssociations()
        testSubnetIndexesUseCompleteAssociatedSpaces()
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

    private static func testMutationRejectsChangedServerTopology() {
        let result = GatewayAssociatedSpaceMutationPolicy.resolve(
            isOwner: false,
            baselineSpaceIDs: ["space-1"],
            latestServerSpaceIDs: ["space-1", "space-2"],
            requestedSpaceIDs: ["space-1"],
            editableSpaceIDs: ["space-1"]
        )
        precondition(result == .topologyChanged)
    }

    private static func testEditorCanOnlyMutateEditableSpaces() {
        let allowed = GatewayAssociatedSpaceMutationPolicy.resolve(
            isOwner: false,
            baselineSpaceIDs: ["locked", "editable"],
            latestServerSpaceIDs: ["locked", "editable"],
            requestedSpaceIDs: ["locked", "new"],
            editableSpaceIDs: ["editable", "new"]
        )
        precondition(
            allowed == .allowed(
                .init(
                    additionSpaceIDs: ["new"],
                    removalSpaceIDs: ["editable"]
                )
            )
        )

        let denied = GatewayAssociatedSpaceMutationPolicy.resolve(
            isOwner: false,
            baselineSpaceIDs: ["locked", "editable"],
            latestServerSpaceIDs: ["locked", "editable"],
            requestedSpaceIDs: ["editable"],
            editableSpaceIDs: ["editable"]
        )
        precondition(denied == .denied)
    }

    private static func testOwnerCanMutateAnySpace() {
        let result = GatewayAssociatedSpaceMutationPolicy.resolve(
            isOwner: true,
            baselineSpaceIDs: ["space-1"],
            latestServerSpaceIDs: ["space-1"],
            requestedSpaceIDs: ["space-2"],
            editableSpaceIDs: []
        )
        precondition(
            result == .allowed(
                .init(
                    additionSpaceIDs: ["space-2"],
                    removalSpaceIDs: ["space-1"]
                )
            )
        )
    }

    private static func testDestructiveAccessRequiresAllAssociations() {
        precondition(
            GatewayDestructiveAccessPolicy.canPerform(
                isOwner: true,
                hasAnyEditableSiteSpace: false,
                associatedSpaceEditableStates: [false]
            )
        )
        precondition(
            !GatewayDestructiveAccessPolicy.canPerform(
                isOwner: false,
                hasAnyEditableSiteSpace: true,
                associatedSpaceEditableStates: [true, false]
            )
        )
        precondition(
            GatewayDestructiveAccessPolicy.canPerform(
                isOwner: false,
                hasAnyEditableSiteSpace: true,
                associatedSpaceEditableStates: []
            )
        )
    }

    private static func testSubnetIndexesUseCompleteAssociatedSpaces() {
        precondition(
            GatewaySubnetAppKeyIndexPolicy.desiredIndexes(
                isActivated: true,
                associatedSpaceIndexes: [2, 1, 2]
            ) == [1, 2]
        )
        precondition(
            GatewaySubnetAppKeyIndexPolicy.desiredIndexes(
                isActivated: false,
                associatedSpaceIndexes: [1, 2]
            ).isEmpty
        )
    }
}
