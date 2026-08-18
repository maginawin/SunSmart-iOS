import Foundation

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

struct GatewayAssociatedSpaceMutationPlan: Equatable {
    let additionSpaceIDs: [String]
    let removalSpaceIDs: [String]
}

enum GatewayAssociatedSpaceMutationResolution: Equatable {
    case allowed(GatewayAssociatedSpaceMutationPlan)
    case topologyChanged
    case denied
}

enum GatewayAssociatedSpaceMutationPolicy {

    static func resolve(
        isOwner: Bool,
        baselineSpaceIDs: [String],
        latestServerSpaceIDs: [String],
        requestedSpaceIDs: [String],
        editableSpaceIDs: Set<String>
    ) -> GatewayAssociatedSpaceMutationResolution {
        let baseline = normalizedSet(baselineSpaceIDs)
        let latest = normalizedSet(latestServerSpaceIDs)
        guard baseline == latest else {
            return .topologyChanged
        }

        let requested = normalizedSet(requestedSpaceIDs)
        let additions = requested.subtracting(latest)
        let removals = latest.subtracting(requested)
        let editable = normalizedSet(Array(editableSpaceIDs))

        if !isOwner,
           (!additions.isSubset(of: editable) ||
            !removals.isSubset(of: editable)) {
            return .denied
        }

        return .allowed(
            GatewayAssociatedSpaceMutationPlan(
                additionSpaceIDs: requestedSpaceIDs.filter {
                    additions.contains(normalized($0))
                },
                removalSpaceIDs: latestServerSpaceIDs.filter {
                    removals.contains(normalized($0))
                }
            )
        )
    }

    private static func normalizedSet(_ values: [String]) -> Set<String> {
        Set(values.map(normalized))
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum GatewayDestructiveAccessPolicy {

    static func canPerform(
        isOwner: Bool,
        hasAnyEditableSiteSpace: Bool,
        associatedSpaceEditableStates: [Bool]
    ) -> Bool {
        if isOwner {
            return true
        }
        if associatedSpaceEditableStates.isEmpty {
            return hasAnyEditableSiteSpace
        }
        return associatedSpaceEditableStates.allSatisfy { $0 }
    }
}

enum GatewaySubnetAppKeyIndexPolicy {

    static func desiredIndexes(
        isActivated: Bool,
        associatedSpaceIndexes: [UInt16]
    ) -> [UInt16] {
        guard isActivated else { return [] }
        return Array(Set(associatedSpaceIndexes)).sorted()
    }
}
