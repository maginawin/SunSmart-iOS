import Foundation

enum SiteGatewayAssociationConsistencyDecision: Equatable {
    case preserve
    case clearOrphan(gatewayId: String)
}

struct SiteGatewayAssociationSnapshot {

    private let authoritativeGatewayIds: Set<String>?

    var isComplete: Bool {
        authoritativeGatewayIds != nil
    }

    static func make(
        isComplete: Bool,
        rawGatewayIds: [String?]?
    ) -> SiteGatewayAssociationSnapshot {
        guard isComplete, let rawGatewayIds else {
            return .init(authoritativeGatewayIds: nil)
        }

        var normalizedIds: Set<String> = []
        for rawGatewayId in rawGatewayIds {
            guard let gatewayId = normalized(rawGatewayId) else {
                return .init(authoritativeGatewayIds: nil)
            }
            normalizedIds.insert(gatewayId)
        }
        return .init(authoritativeGatewayIds: normalizedIds)
    }

    func decision(
        for rawSpaceGatewayId: String?
    ) -> SiteGatewayAssociationConsistencyDecision {
        guard
            let displayGatewayId = rawSpaceGatewayId?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !displayGatewayId.isEmpty,
            let normalizedSpaceGatewayId = Self.normalized(displayGatewayId),
            let authoritativeGatewayIds
        else {
            return .preserve
        }

        guard !authoritativeGatewayIds.contains(normalizedSpaceGatewayId) else {
            return .preserve
        }
        return .clearOrphan(gatewayId: displayGatewayId)
    }

    private static func normalized(_ rawGatewayId: String?) -> String? {
        guard
            let gatewayId = rawGatewayId?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !gatewayId.isEmpty
        else {
            return nil
        }
        return gatewayId.lowercased()
    }
}
