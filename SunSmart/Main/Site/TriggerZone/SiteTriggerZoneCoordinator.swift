import Foundation

@MainActor
final class SiteTriggerZoneCoordinator {
    enum Failure: Error {
        case storage, permission, unsupported, conflict, network, unconfirmed
        var message: String {
            switch self {
            case .storage: return "site_zones_storage_failed".localizedString
            case .permission: return "no_permission".localizedString
            case .unsupported: return "site_zones_unsupported".localizedString
            case .conflict: return "site_zones_conflict".localizedString
            case .network, .unconfirmed: return "site_zones_sync_pending".localizedString
            }
        }
    }

    private static var uploads: [String: _Concurrency.Task<Result<Void, Failure>, Never>] = [:]
    let site: SiteData
    private let account = UserData.currentUserId
    private let region = UserData.currentServerRegion

    init(site: SiteData) { self.site = site }

    private var isCurrent: Bool {
        account == UserData.currentUserId && region == UserData.currentServerRegion
            && SiteData.load(siteId: site.id)?.state == .normal
    }

    func state() throws -> SiteTriggerZoneState { try SiteTriggerZoneStore.load(site) }

    func add(count: Int) throws {
        try mutate { data in
            guard var zones = data.zones, count > 0,
                  count <= SiteTriggerZone.maximumCount - zones.count else { throw Failure.unsupported }
            zones.append(contentsOf: (0..<count).map { _ in SiteTriggerZone() })
            data.replaceZones(zones)
        }
    }

    func delete(zoneId: UUID) throws {
        try mutate { data in
            guard var zones = data.zones,
                  let index = zones.firstIndex(where: { $0.zoneId == zoneId }) else { return }
            zones.remove(at: index)
            data.replaceZones(zones)
        }
    }

    private func mutate(_ mutation: (inout SiteExtensionData) throws -> Void) throws {
        guard isCurrent, let current = SiteData.load(siteId: site.id),
              current.canManageSiteTriggerZones else { throw Failure.permission }
        try SiteTriggerZoneStore.update(site) { state in
            guard !state.conflict else { throw Failure.conflict }
            guard state.rejectedRemote == nil, state.data.supportsEmptyZoneEditing else { throw Failure.unsupported }
            var data = state.data
            try mutation(&data)
            state.commit(data, now: Int64(Date().timeIntervalSince1970), siteTimestamp: current.lastUpdate)
        }
    }

    /// Only an explicit user choice may discard a local draft after a conflict.
    func useServerVersion() throws {
        guard isCurrent else { throw Failure.permission }
        try SiteTriggerZoneStore.update(site) { $0.discardPending() }
    }

    func synchronize(zoneID: UUID? = nil) async -> Result<Void, Failure> {
        let key = "\(account)/\(region)/\(site.id)"
        while let task = Self.uploads[key] {
            let result = await task.value
            if zoneID == nil { return result }
            // A row Save must perform its own scoped operation after an existing upload finishes.
            // Let the owning caller release its completed task before acquiring the Site again.
            await _Concurrency.Task<Never, Never>.yield()
        }
        let task = _Concurrency.Task { @MainActor in await self.performSynchronization(zoneID: zoneID) }
        Self.uploads[key] = task
        let result = await task.value
        Self.uploads[key] = nil
        return result
    }

    private struct Remote {
        let object: [String: Any]
        let timestamp: Int64
        let canEdit: Bool
    }

    private func retrieve() async throws -> Remote {
        guard isCurrent, NetworkRequest.shared.networkable else { throw Failure.network }
        let result = await NetworkRequest.shared.request(.siteInfo(siteId: site.id))
        guard isCurrent else { throw Failure.permission }
        guard case .success(let response) = result,
              let object = response["data"] as? [String: Any],
              object["uuid"] as? String == site.id,
              let timestamp = object["updateTimestamp"] as? NSNumber,
              CFGetTypeID(timestamp) != CFBooleanGetTypeID() else { throw Failure.network }
        let localSpaces = SpaceData.load(siteId: site.id)
        let remoteSpaces = object["spaces"] as? [[String: Any]] ?? []
        let editableIDs = Set(remoteSpaces.compactMap { space -> String? in
            guard let role = space["role"] as? String, role == "owner" || role == "editor" else { return nil }
            return space["uuid"] as? String
        })
        let owner = object["role"] as? String == "owner"
        let canEdit = localSpaces.contains { $0.canEditing && (owner || editableIDs.contains($0.id)) }
        return Remote(object: object, timestamp: timestamp.int64Value, canEdit: canEdit)
    }

    private func performSynchronization(zoneID: UUID?) async -> Result<Void, Failure> {
        do {
            // A locally created Site must first acquire its server identity via normal Site sync.
            guard site.uploadCloud else { return .failure(.unconfirmed) }
            while true {
                let remote = try await retrieve()
                guard remote.canEdit else { return .failure(.permission) }
                try SiteTriggerZoneStore.receive(site, object: remote.object, timestamp: remote.timestamp)
                var current = try state()
                guard !current.conflict else { return .failure(.conflict) }
                if let zoneID, current.data.zones?.contains(where: { $0.zoneId == zoneID }) != true {
                    return .failure(.unsupported)
                }
                guard var pending = current.pending else { return .success(()) }
                guard current.rejectedRemote == nil, current.data.supportsEmptyZoneEditing else { return .failure(.unsupported) }
                // A draft made before the first GET must not overwrite another editor's zones.
                if pending.base == nil, let server = current.serverData,
                   server != SiteExtensionData(), server != pending.target {
                    try SiteTriggerZoneStore.update(site) { $0.conflict = true }
                    return .failure(.conflict)
                }
                if let zoneID {
                    guard let zone = current.data.zones?.first(where: { $0.zoneId == zoneID }) else {
                        return .failure(.unsupported)
                    }
                    // The API accepts the extension object. Retain the server's other zones,
                    // not their unsaved local versions, and replace only the selected ID.
                    var target = current.serverData ?? SiteExtensionData()
                    guard var zones = target.zones else { return .failure(.unsupported) }
                    if let index = zones.firstIndex(where: { $0.zoneId == zoneID }) {
                        zones[index] = zone
                    } else {
                        guard zones.count < SiteTriggerZone.maximumCount else { return .failure(.unsupported) }
                        zones.append(zone)
                    }
                    target.replaceZones(zones)
                    guard target != current.serverData else { return .success(()) }
                    pending = .init(operationId: UUID(), timestamp: max(pending.timestamp, remote.timestamp + 1),
                                    base: current.serverData, target: target)
                }
                guard isCurrent else { return .failure(.permission) }
                try SiteTriggerZoneStore.update(site) { $0.submitted = pending }
                let props: [String: Any] = [
                    "extensionData": try pending.target.jsonObject(),
                    "updateTimestamp": max(pending.timestamp, remote.timestamp + 1)
                ]
                let result = await NetworkRequest.shared.request(.sitePropsUpdate(siteId: site.id, props: props))
                guard isCurrent else { return .failure(.permission) }
                guard case .success = result else { return .failure(.network) }
                // The legacy update response can contain only a timestamp; always verify via GET.
                let verified = try await retrieve()
                guard verified.canEdit else { return .failure(.permission) }
                try SiteTriggerZoneStore.receive(site, object: verified.object, timestamp: verified.timestamp)
                current = try state()
                if current.conflict { return .failure(.conflict) }
                if zoneID != nil {
                    guard current.serverData == pending.target,
                          current.serverTimestamp >= pending.timestamp else { return .failure(.unconfirmed) }
                    // Other pending zones remain local; a row Save never drains the entire Site.
                    return .success(())
                }
                if current.pending == nil { return .success(()) }
                guard current.pending?.operationId != pending.operationId else { return .failure(.unconfirmed) }
                // A second local edit arrived while awaiting HTTP. Revalidate and submit that snapshot.
            }
        } catch let failure as Failure { return .failure(failure) }
        catch { return .failure(.storage) }
    }
}
