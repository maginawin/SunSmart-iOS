import Foundation

struct DeviceScheduleAddressCleanupResult<Address: Equatable> {
    let activeAddresses: [Address]
    let pendingDeleteAddresses: [Address]
    let didChange: Bool
}

enum DeviceScheduleAddressCleanup {
    static func removing<Address: Equatable>(
        address: Address,
        activeAddresses: [Address],
        pendingDeleteAddresses: [Address]
    ) -> DeviceScheduleAddressCleanupResult<Address> {
        let filteredActiveAddresses = activeAddresses.filter { $0 != address }
        let filteredPendingDeleteAddresses = pendingDeleteAddresses.filter { $0 != address }
        return DeviceScheduleAddressCleanupResult(
            activeAddresses: filteredActiveAddresses,
            pendingDeleteAddresses: filteredPendingDeleteAddresses,
            didChange: filteredActiveAddresses.count != activeAddresses.count
                || filteredPendingDeleteAddresses.count != pendingDeleteAddresses.count
        )
    }
}

/// Durable intent is scoped to the Space, never to a Device UUID alone.
struct SpaceDeletionJournal: Codable {
    struct Scope: Codable, Equatable {
        let siteId: String
        let spaceId: String
        let meshUUID: String
        let networkId: String
    }

    struct Entry: Codable, Equatable {
        struct CloudRemoval: Codable, Equatable {
            let baselineTimestamp: Int64
            let remoteTimestamp: Int64
            let submissionID: UUID?
            let instance: SpaceCloudNodeRemovalPolicy.Instance
        }
        enum Stage: String, Codable { case prepared, removed, cleaned }
        let id: UUID
        let nodeUUID: String
        let primaryAddress: UInt16
        let elementAddresses: Set<UInt16>
        let macAddress: String?
        let productId: UInt16?
        var stage: Stage = .prepared
        var completedTimestamp: Int64?
        var replacement: SiteDeviceOwnershipPolicy.Instance?
        var cloudRemoval: CloudRemoval? = nil
    }

    let scope: Scope
    var entries: [Entry] = []

    var needsCleanup: Bool { entries.contains { $0.stage != .cleaned } }

    mutating func confirmUpload(timestamp: Int64) {
        entries.removeAll { entry in
            entry.stage == .cleaned && entry.completedTimestamp.map { $0 <= timestamp } == true
        }
    }

    static func read(from url: URL, scope: Scope) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init(scope: scope) }
        let journal = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard journal.scope == scope else { throw CocoaError(.fileReadCorruptFile) }
        return journal
    }

    func write(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

/// MAC identifies a physical device only within one Site. UUID/address identify
/// a particular provisioning instance; neither is an ordering signal.
enum SiteDeviceOwnershipPolicy {
    struct Instance: Codable, Equatable {
        let siteId: String
        let spaceId: String
        let networkId: String
        let uuid: String
        let address: UInt16
        let created: Int64
        let mac: String
    }

    static func normalizedMAC(_ value: String?) -> String? {
        guard let value else { return nil }
        let mac = value.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").uppercased()
        guard mac.utf8.count == 12, mac != "000000000000", mac != "FFFFFFFFFFFF",
              mac.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }) else { return nil }
        return mac
    }

    /// A conservative preflight: timestamps and deletion decisions still use
    /// the complete, current instances after a cross-Space identity is found.
    static func hasCrossSpaceDuplicate(_ identities: [(spaceId: String, mac: String?)]) -> Bool {
        var owners: [String: String] = [:]
        for identity in identities {
            guard let mac = normalizedMAC(identity.mac) else { continue }
            if let owner = owners[mac], owner != identity.spaceId { return true }
            owners[mac] = identity.spaceId
        }
        return false
    }

    static func removals(_ instances: [Instance], preferred: Instance? = nil) -> [(old: Instance, winner: Instance)] {
        let grouped = Dictionary(grouping: instances) { $0.siteId + "/" + $0.mac }
        return grouped.values.flatMap { candidates -> [(old: Instance, winner: Instance)] in
            guard Set(candidates.map(\.spaceId)).count > 1 else { return [] }
            let latest = candidates.filter { $0.created > 0 }.map(\.created).max()
            let newest = candidates.filter { $0.created == latest }
            let winner: Instance
            if let preferred, candidates.contains(preferred) {
                winner = preferred
            } else if newest.count == 1, let only = newest.first {
                winner = only
            } else { return [] } // A tie/unknown generation cannot justify deleting another instance.
            return candidates.filter { $0.spaceId != winner.spaceId && $0.address != winner.address && ($0.created > 0 || winner == preferred) }
                .map { ($0, winner) }
        }
    }
}

/// Local recovery bookkeeping. No credentials or Mesh transport state are stored here.
struct SpaceRecoveryState: Codable, Equatable {
    struct Identity: Codable, Equatable {
        let account: String
        let region: String
        let space: SpaceDeletionJournal.Scope
    }
    enum Phase: String, Codable { case active, removing, retired }
    enum Authority: String, Codable { case writable, waitingForAuthorization, readOnly, revoked }
    struct Submission: Codable, Equatable {
        enum Phase: String, Codable { case prepared, accepted, verified }
        let id: UUID
        let timestamp: Int64
        let configuration: Data
        var phase: Phase = .prepared
        var keyFingerprint: String?
        /// Absent on receipts written before scene-target readback was added.
        var scheduleTargets: Data? = nil
        /// Exact observations submitted by clients that support Model snapshots.
        var schedulerModelStates: Data? = nil
        var nodeIdentities: [SpaceCloudNodeRemovalPolicy.Instance]? = nil
        /// Explicitly false for migrated unknown-outcome receipts.
        var permitsCloudRemoval: Bool? = nil
    }
    let identity: Identity
    var generation = UUID()
    var phase: Phase = .active
    var authority: Authority = .writable
    // nil uses the pre-existing recovery directory during migration.
    var directoryName: String?
    var submission: Submission?
    var authorizationBaseline: Data?
    /// Last confirmed cloud observations, independent of subsequent device reads.
    var schedulerModelStatesBaseline: Data? = nil
    var nodeIdentitiesBaseline: [SpaceCloudNodeRemovalPolicy.Instance]? = nil
    var unbindRequested: Bool?
    var requiresRemoteImport: Bool?
    var siteCreationTimestamp: Int64?
    var pendingArchives: [String]?

    var preservesUpload: Bool {
        phase == .active && authority != .readOnly && authority != .revoked
    }

    func matches(_ other: Self) -> Bool {
        identity == other.identity && generation == other.generation && phase == .active
    }

    static func read(from url: URL, identity: Identity) throws -> Self? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let state = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard state.identity == identity else { throw CocoaError(.fileReadCorruptFile) }
        return state
    }

    func write(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
