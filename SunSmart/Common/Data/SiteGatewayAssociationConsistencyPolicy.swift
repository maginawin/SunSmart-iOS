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

    fileprivate static func normalized(_ rawGatewayId: String?) -> String? {
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

/// Server presence metadata is independent of Gateway configuration versions.
struct SiteGatewayLastOnlineSnapshot {
    private struct Observation: Equatable {
        let online: Bool?
        let activated: Bool?
        let timestamp: Int64?
    }

    private let timestamps: [String: Int64]
    private let onlineStates: [String: Bool]
    private let activationStates: [String: Bool]

    init(gateways: [[String: Any]]?) {
        let fractionalParser = ISO8601DateFormatter()
        fractionalParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let secondsParser = ISO8601DateFormatter()
        secondsParser.formatOptions = [.withInternetDateTime]
        var observations: [String: Observation] = [:]
        var ambiguousIDs = Set<String>()

        for gateway in gateways ?? [] {
            let ids = Set([gateway["gatewayId"] as? String, gateway["macAddress"] as? String]
                .compactMap { SiteGatewayAssociationSnapshot.normalized($0) })
            guard ids.count == 1, let id = ids.first else {
                ambiguousIDs.formUnion(ids)
                continue
            }
            let online = gateway["gatewayOnline"] as? Bool
            // Missing metadata remains unknown for older responses. For a
            // present connectAt, only JSON null means not yet activated.
            let activated = gateway["connectAt"].map { !($0 is NSNull) }
            var timestamp: Int64?
            if online == false, let rawDate = gateway["disconnectAt"] as? String {
                let value = rawDate.trimmingCharacters(in: .whitespacesAndNewlines)
                if let date = fractionalParser.date(from: value) ?? secondsParser.date(from: value),
                   date.timeIntervalSince1970 > 0 {
                    timestamp = Int64(exactly: date.timeIntervalSince1970.rounded(.down))
                }
            }
            let observation = Observation(online: online, activated: activated, timestamp: timestamp)
            if let previous = observations[id], previous != observation {
                ambiguousIDs.insert(id)
            }
            observations[id] = observation
        }

        timestamps = observations.reduce(into: [:]) { result, entry in
            guard !ambiguousIDs.contains(entry.key), let timestamp = entry.value.timestamp else { return }
            result[entry.key] = timestamp
        }
        onlineStates = observations.reduce(into: [:]) { result, entry in
            guard !ambiguousIDs.contains(entry.key), let online = entry.value.online else { return }
            result[entry.key] = online
        }
        activationStates = observations.reduce(into: [:]) { result, entry in
            guard !ambiguousIDs.contains(entry.key), let activated = entry.value.activated else { return }
            result[entry.key] = activated
        }
    }

    func activated(for gatewayId: String?) -> Bool? {
        guard let id = SiteGatewayAssociationSnapshot.normalized(gatewayId) else { return nil }
        return activationStates[id]
    }

    func online(for gatewayId: String?) -> Bool? {
        guard let id = SiteGatewayAssociationSnapshot.normalized(gatewayId) else { return nil }
        return onlineStates[id]
    }

    func timestamp(for gatewayId: String?) -> Int64? {
        guard let id = SiteGatewayAssociationSnapshot.normalized(gatewayId) else { return nil }
        return timestamps[id]
    }

    /// Preserve the legacy helper's seconds/milliseconds compatibility.
    static func legacyTimestamp(_ value: Int64?) -> Int64? {
        guard let value, value > 0 else { return nil }
        return value > Int64(UInt32.max) ? value / 1000 : value
    }
}
