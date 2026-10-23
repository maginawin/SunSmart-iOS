import Foundation

/// Pending replacement of the complete Site extensionData object.
struct SiteExtensionPending: Codable, Equatable {
    let operationId: UUID
    /// Local ordering token only. The Site props endpoint assigns its own updateTimestamp.
    let timestamp: Int64
    let base: SiteExtensionData?
    let target: SiteExtensionData
}

/// Persisted local/server snapshots and recovery state for Site extensionData.
struct SiteExtensionState: Codable, Equatable {
    /// Local recovery only. The table already isolates Site and region; accounts
    /// retain independent generations even if a database is reused at sign-in.
    var referenceCleanupRequests: [String: UUID]?
    var data = SiteExtensionData()
    var serverData: SiteExtensionData?
    var serverTimestamp: Int64 = 0
    var pending: SiteExtensionPending?
    var submitted: SiteExtensionPending?
    /// Superseded local edits are retained for review, never retried automatically.
    var archivedPendings: [SiteExtensionPending]?
    var archivedReviewNeeded: Bool?
    var needsArchivedReview: Bool { archivedReviewNeeded == true }
    var rejectedRemote: Data?
    var conflict = false
    /// Equal server versions with different content cannot establish an ordering.
    var ambiguousRemote: Bool?
    var hasAmbiguousRemote: Bool { ambiguousRemote == true }
    /// Retained after cloud confirmation for the later device-sync planner.
    var deviceSyncChanges: [SiteTriggerZoneDeviceSyncChange]?

    mutating func commit(_ data: SiteExtensionData, now: Int64, siteTimestamp: Int64) {
        guard data != self.data else { return }
        let timestamp = max(now, max(siteTimestamp, max(serverTimestamp, pending?.timestamp ?? 0)) + 1)
        pending = .init(operationId: UUID(), timestamp: timestamp,
                        base: pending?.base ?? serverData, target: data)
        self.data = data
    }

    /// Missing fields are patches, never a deletion. A readback confirms only its own target.
    mutating func receive(_ remote: SiteExtensionData, timestamp: Int64) {
        guard timestamp >= serverTimestamp else { return }
        var remote = remote
        for key in SiteExtensionData.metadataKeys where remote.fields[key] == nil {
            // Omitted props are not an explicit clear or a receipt for a new local value.
            if let pending,
               (pending.target.fields[key] ?? .null) != (pending.base?.fields[key] ?? .null) { return }
            remote.fields[key] = (serverData ?? data).fields[key]
        }
        if remote.fields["isHdbSite"] == nil {
            // An omitted field cannot confirm a newly submitted type, but must retain
            // the known type when an existing Site receives a partial props response.
            if let pending, pending.target.isHdbSite != (pending.base?.isHdbSite ?? false) { return }
            remote.isHdbSite = (serverData ?? data).isHdbSite
        }
        if remote.fields["triggerZones"] == nil {
            remote.fields["triggerZones"] = (serverData ?? data).fields["triggerZones"]
            // A response without the requested field cannot acknowledge a pending mutation.
            guard pending == nil else { return }
        }
        if timestamp == serverTimestamp, let serverData, remote != serverData {
            ambiguousRemote = true
            return
        }
        ambiguousRemote = false
        let previousServer = serverData
        let pendingBeforeReceive = pending
        let submittedBeforeReceive = submitted
        if let pending {
            if remote == pending.target {
                self.pending = nil
                submitted = nil
                data = remote
                conflict = false
            } else if let submitted, remote == submitted.target,
               submitted.operationId != pending.operationId {
                self.pending = .init(operationId: pending.operationId,
                                     timestamp: max(pending.timestamp, timestamp + 1),
                                     base: remote, target: pending.target)
                self.submitted = nil
                conflict = false
            } else if let base = pending.base, remote != base {
                if SiteExtensionData.targetCoversServerChanges(
                    base: base, server: remote, target: pending.target
                ) {
                    self.pending = .init(
                        operationId: pending.operationId,
                        timestamp: max(pending.timestamp, timestamp + 1),
                        base: remote, target: pending.target
                    )
                    submitted = nil
                    conflict = false
                } else {
                    archive(pending)
                    self.pending = nil
                    submitted = nil
                    data = remote
                    conflict = false
                }
            } else if pending.base == nil, remote != pending.target {
                archive(pending)
                self.pending = nil
                submitted = nil
                data = remote
                conflict = false
            }
        } else {
            data = remote
            conflict = false
        }
        if let previousServer, previousServer != remote {
            recordDeviceSyncChanges(from: .init(
                operationId: UUID(), timestamp: timestamp,
                base: previousServer, target: remote
            ))
        } else if previousServer == nil,
                  let receipt = [pendingBeforeReceive, submittedBeforeReceive].compactMap({ $0 })
                    .first(where: { $0.target == remote }) {
            recordDeviceSyncChanges(from: receipt)
        }
        serverData = remote
        serverTimestamp = timestamp
    }

    private mutating func archive(_ pending: SiteExtensionPending) {
        var records = archivedPendings ?? []
        if !records.contains(where: { $0.operationId == pending.operationId }) {
            records.append(pending)
        }
        archivedPendings = records
        archivedReviewNeeded = true
    }

    mutating func acknowledgeArchivedReview() { archivedReviewNeeded = false }

    private mutating func recordDeviceSyncChanges(from receipt: SiteExtensionPending) {
        guard let targetZones = receipt.target.zones else { return }
        let baseZones = receipt.base?.zones ?? []
        let zoneIDs = targetZones.map(\.zoneId)
            + baseZones.map(\.zoneId).filter { id in !targetZones.contains { $0.zoneId == id } }
        var changes = deviceSyncChanges ?? []
        for id in zoneIDs {
            let old = baseZones.first(where: { $0.zoneId == id })?.fields["members"] ?? .array([])
            let new = targetZones.first(where: { $0.zoneId == id })?.fields["members"] ?? .array([])
            guard old != new else { continue }
            let original = changes.first(where: { $0.zoneID == id })?.previousMembers ?? old
            changes.removeAll { $0.zoneID == id }
            if original != new {
                changes.append(.init(zoneID: id, previousMembers: original, targetMembers: new))
            }
        }
        deviceSyncChanges = changes
    }

    mutating func discardPending() {
        guard let serverData else { return }
        if let pending { archive(pending) }
        data = serverData
        pending = nil
        submitted = nil
        conflict = false
    }
}
