import Foundation

/// Process-local protection for orphan cleanup. Old objects and already-issued
/// responses cannot recreate a removed row; a new provisioning may create it.
enum GatewayOrphanGuard {
    struct Scope: Hashable {
        let account: String
        let region: String
        let siteID: String
    }
    struct Token {
        let scope: Scope
        let mac: String
        let revision: UInt64
    }
    static let payloadKey = "_localGatewayReadContext"
    private static let lock = NSRecursiveLock()
    private static var sequence: UInt64 = 0
    private static var revisions: [Scope: [String: UInt64]] = [:]
    private static var activityRevisions: [Scope: UInt64] = [:]
    private static var activities: [Scope: Int] = [:]
    private static var imports: [Scope: Int] = [:]

    static func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }
    static func normalized(_ mac: String) -> String {
        mac.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
    static func token(scope: Scope, mac: String) -> Token {
        synchronized {
            let mac = normalized(mac)
            return Token(scope: scope, mac: mac, revision: revisions[scope]?[mac] ?? 0)
        }
    }
    static func isCurrent(_ token: Token) -> Bool {
        synchronized { token.revision == (revisions[token.scope]?[token.mac] ?? 0) }
    }
    static func didRemove(scope: Scope, macs: Set<String>) {
        synchronized {
            for mac in macs {
                sequence += 1
                revisions[scope, default: [:]][normalized(mac)] = sequence
            }
        }
    }
    static func beginActivity(_ scope: Scope) {
        synchronized {
            activities[scope, default: 0] += 1
            activityRevisions[scope, default: 0] += 1
        }
    }
    static func endActivity(_ scope: Scope) {
        synchronized {
            activities[scope] = max(0, (activities[scope] ?? 0) - 1)
            activityRevisions[scope, default: 0] += 1
        }
    }
    static func beginImport(_ scope: Scope) { synchronized { imports[scope, default: 0] += 1 } }
    static func endImport(_ scope: Scope) { synchronized { imports[scope] = max(0, (imports[scope] ?? 0) - 1) } }

    static func capture(account: String, region: String, detailSiteID: String?) -> [String: String] {
        synchronized {
            let scope = Scope(account: account, region: region, siteID: detailSiteID ?? "")
            return ["account": account, "region": region, "epoch": String(sequence),
                    "detailSiteID": detailSiteID ?? "", "activity": String(activityRevisions[scope] ?? 0)]
        }
    }
    static func annotate(_ response: [String: Any], context: [String: String]) -> [String: Any] {
        var result = response
        guard var data = result["data"] as? [String: Any] else { return result }
        data[payloadKey] = context
        if let sites = data["sites"] as? [[String: Any]] {
            data["sites"] = sites.map { site -> [String: Any] in
                var value = site; value[payloadKey] = context; return value
            }
        }
        result["data"] = data
        return result
    }
    static func allowsImport(_ payload: [String: Any], scope: Scope, mac: String) -> Bool {
        synchronized {
            let context = payload[payloadKey] as? [String: String]
            if let context, context["account"] != scope.account || context["region"] != scope.region { return false }
            // Unstamped legacy payloads may import normally until this MAC was
            // cleaned; after that only a subsequently issued request may restore it.
            let epoch = context?["epoch"].flatMap(UInt64.init) ?? 0
            return epoch >= (revisions[scope]?[normalized(mac)] ?? 0)
        }
    }
    static func acceptsSnapshot(_ payload: [String: Any], scope: Scope) -> Bool {
        synchronized {
            guard let context = payload[payloadKey] as? [String: String] else { return true }
            guard context["account"] == scope.account, context["region"] == scope.region,
                  let epoch = context["epoch"].flatMap(UInt64.init) else { return false }
            // Reject the whole old Site response before its Space metadata can
            // reintroduce associations to the gateways we just removed.
            return epoch >= (revisions[scope]?.values.max() ?? 0)
        }
    }
    static func canReconcile(_ payload: [String: Any], scope: Scope) -> Bool {
        synchronized {
            guard let context = payload[payloadKey] as? [String: String],
                  context["account"] == scope.account, context["region"] == scope.region,
                  context["detailSiteID"] == scope.siteID,
                  payload["uuid"] as? String == scope.siteID,
                  payload["role"] as? String == "owner",
                  let epoch = context["epoch"].flatMap(UInt64.init),
                  epoch >= (revisions[scope]?.values.max() ?? 0),
                  context["activity"].flatMap(UInt64.init) == (activityRevisions[scope] ?? 0),
                  (activities[scope] ?? 0) == 0, (imports[scope] ?? 0) == 0 else { return false }
            return true
        }
    }
}

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
