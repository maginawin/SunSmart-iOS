struct GatewayAssociatedSpaceCandidateInput: Equatable {
    let spaceId: String
    let canEdit: Bool
    let associatedGatewayId: String?
    let meshNetworkId: String
}

struct GatewayAssociatedSpaceCandidate: Equatable {
    let spaceId: String
    let appKeyIndex: UInt16
}

enum GatewayAssociatedSpaceCandidateResolution: Equatable {
    case available([GatewayAssociatedSpaceCandidate])
    case unavailable(missingAppKeySpaceIds: [String])
}

enum GatewayAssociatedSpaceCandidatePolicy {

    static func resolve(
        spaces: [GatewayAssociatedSpaceCandidateInput],
        currentGatewayId: String,
        appKeyIndicesByNetworkId: [String: UInt16]
    ) -> GatewayAssociatedSpaceCandidateResolution {
        let normalizedGatewayId = currentGatewayId.lowercased()
        var normalizedAppKeyIndices: [String: UInt16] = [:]
        appKeyIndicesByNetworkId.forEach { networkId, appKeyIndex in
            let normalizedNetworkId = networkId.lowercased()
            if normalizedAppKeyIndices[normalizedNetworkId] == nil {
                normalizedAppKeyIndices[normalizedNetworkId] = appKeyIndex
            }
        }

        var candidates: [GatewayAssociatedSpaceCandidate] = []
        var missingAppKeySpaceIds: [String] = []

        for space in spaces {
            guard space.canEdit else {
                continue
            }
            if let associatedGatewayId = space.associatedGatewayId,
               !associatedGatewayId.isEmpty,
               associatedGatewayId.lowercased() != normalizedGatewayId {
                continue
            }

            guard let appKeyIndex = normalizedAppKeyIndices[
                space.meshNetworkId.lowercased()
            ] else {
                missingAppKeySpaceIds.append(space.spaceId)
                continue
            }
            candidates.append(
                GatewayAssociatedSpaceCandidate(
                    spaceId: space.spaceId,
                    appKeyIndex: appKeyIndex
                )
            )
        }

        guard missingAppKeySpaceIds.isEmpty else {
            return .unavailable(
                missingAppKeySpaceIds: missingAppKeySpaceIds
            )
        }
        return .available(candidates)
    }
}
