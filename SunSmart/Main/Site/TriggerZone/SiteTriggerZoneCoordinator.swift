import Foundation
import NordicSigMeshSDK

@MainActor
final class SiteTriggerZoneCoordinator {
    enum Failure: Error {
        case storage, permission, unsupported, invalidMember, conflict, network, unconfirmed, serverReplaced, ambiguousRemote
        var message: String {
            switch self {
            case .storage: return "site_zones_storage_failed".localizedString
            case .permission: return "no_permission".localizedString
            case .unsupported: return "site_zones_unsupported".localizedString
            case .invalidMember: return "site_zone_member_changed".localizedString
            case .conflict: return "site_zones_conflict".localizedString
            case .network, .unconfirmed: return "site_zones_sync_pending".localizedString
            case .serverReplaced: return "site_zones_server_replaced".localizedString
            case .ambiguousRemote: return "site_zones_timestamp_ambiguous".localizedString
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
            guard zones[index].isEmpty else { throw Failure.unsupported }
            zones.remove(at: index)
            data.replaceZones(zones)
        }
    }

    func saveMembers(zoneID: UUID, members: [SiteTriggerZoneMember]) throws {
        guard isCurrent, let current = SiteData.load(siteId: site.id),
              current.canManageSiteTriggerZones else { throw Failure.permission }
        try SiteTriggerZoneStore.update(site) { state in
            guard !state.conflict else { throw Failure.conflict }
            guard !state.hasAmbiguousRemote else { throw Failure.ambiguousRemote }
            guard state.rejectedRemote == nil,
                  var zones = state.data.zones,
                  let index = zones.firstIndex(where: { $0.zoneId == zoneID }),
                  Set(members.map(\.identity)).count == members.count else { throw Failure.unsupported }
            guard state.data.supportsZoneEditing(zoneID)
                    || state.data.fields["schemaVersion"] == .integer(2),
                  let old = SiteTriggerZoneTopologyReader.resolvedMembers(of: zones[index], site: current)
            else { throw Failure.unsupported }
            let affected = Set((old + members).map(\.identity.spaceID))
            guard affected.allSatisfy({ id in current.spaces.contains { $0.id == id && $0.canEditing } })
            else { throw Failure.permission }
            guard old != members || zones[index].members == nil else { return }
            zones[index].replaceMembers(members)
            var data = state.data
            data.fields["schemaVersion"] = .integer(2)
            data.replaceZones(zones)
            state.commit(data, now: Int64(Date().timeIntervalSince1970), siteTimestamp: current.lastUpdate)
            #if DEBUG
            print("[SiteZoneSync][draft] site=\(site.id) zone=\(zoneID) oldMembers=\(old.count) targetMembers=\(members.count) operation=\(state.pending?.operationId.uuidString ?? "none") cloudVersion=\(state.serverTimestamp)")
            #endif
        }
    }

    @discardableResult
    func cleanObsoleteMembers() throws -> Bool {
        guard isCurrent, let current = SiteData.load(siteId: site.id), current.canManageSiteTriggerZones else { return false }
        current.spaces = SpaceData.load(siteId: current.id)
        let classify = SiteTriggerZoneTopologyReader.cleanupClassifier(site: current)
        let before = try state()
        guard !before.conflict, !before.hasAmbiguousRemote, before.rejectedRemote == nil,
              before.submitted == nil,
              SiteTriggerZoneReferenceCleanup.clean(before.data, classify: classify) != before.data else { return false }
        var changed = false
        try SiteTriggerZoneStore.update(site) { state in
            guard !state.conflict, !state.hasAmbiguousRemote, state.rejectedRemote == nil,
                  state.submitted == nil else { return }
            let cleaned = SiteTriggerZoneReferenceCleanup.clean(state.data, classify: classify)
            guard cleaned != state.data else { return }
            state.commit(cleaned, now: Int64(Date().timeIntervalSince1970), siteTimestamp: current.lastUpdate)
            changed = true
        }
        return changed
    }

    private func mutate(_ mutation: (inout SiteExtensionData) throws -> Void) throws {
        guard isCurrent, let current = SiteData.load(siteId: site.id),
              current.canManageSiteTriggerZones else { throw Failure.permission }
        try SiteTriggerZoneStore.update(site) { state in
            guard !state.conflict else { throw Failure.conflict }
            guard !state.hasAmbiguousRemote else { throw Failure.ambiguousRemote }
            guard state.rejectedRemote == nil, state.data.supportsMemberEditing else { throw Failure.unsupported }
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
        #if DEBUG
        print("[SiteZoneSync][cloud] phase=start site=\(site.id) zone=\(zoneID?.uuidString ?? "all")")
        #endif
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
        #if DEBUG
        switch result {
        case .success:
            print("[SiteZoneSync][cloud] phase=finished site=\(site.id) zone=\(zoneID?.uuidString ?? "all") result=confirmed")
        case .failure(let failure):
            print("[SiteZoneSync][cloud] phase=finished site=\(site.id) zone=\(zoneID?.uuidString ?? "all") result=failed reason=\(failure)")
        }
        #endif
        return result
    }

    private struct Remote {
        let object: [String: Any]
        let timestamp: Int64
        let canEdit: Bool
        let editableSpaceIDs: Set<String>
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
        let locallyEditable = Set(localSpaces.filter(\.canEditing).map(\.id))
        let effectiveIDs = editableIDs.intersection(locallyEditable)
        return Remote(object: object, timestamp: timestamp.int64Value,
                      canEdit: !effectiveIDs.isEmpty, editableSpaceIDs: effectiveIDs)
    }

    private func performSynchronization(zoneID: UUID?) async -> Result<Void, Failure> {
        do {
            // A locally created Site must first acquire its server identity via normal Site sync.
            guard site.uploadCloud else { return .failure(.unconfirmed) }
            while true {
                let requestedPendingID = try state().pending?.operationId
                let remote = try await retrieve()
                try SiteTriggerZoneStore.receive(site, object: remote.object, timestamp: remote.timestamp)
                var current = try state()
                #if DEBUG
                let currentCloudFingerprint = current.serverData.flatMap {
                    SiteTriggerZoneSyncPlanningPolicy.cloudFingerprint(siteID: site.id, data: $0)
                } ?? "unavailable"
                print("[SiteZoneSync][cloud] phase=get site=\(site.id) zone=\(zoneID?.uuidString ?? "all") version=\(remote.timestamp) cloudFingerprint=\(currentCloudFingerprint) pending=\(current.pending?.operationId.uuidString ?? "none") confirmedZones=\(current.serverData?.zones?.count ?? -1) retainedChanges=\(current.deviceSyncChanges?.count ?? 0) conflict=\(current.conflict) ambiguous=\(current.hasAmbiguousRemote)")
                #endif
                guard remote.canEdit else { return .failure(.permission) }
                if let requestedPendingID,
                   current.archivedPendings?.contains(where: { $0.operationId == requestedPendingID }) == true {
                    return .failure(.serverReplaced)
                }
                guard !current.hasAmbiguousRemote else { return .failure(.ambiguousRemote) }
                guard !current.conflict else { return .failure(.conflict) }
                if let zoneID, current.data.zones?.contains(where: { $0.zoneId == zoneID }) != true {
                    return .failure(.unsupported)
                }
                if zoneID == nil {
                    _ = try cleanObsoleteMembers()
                    current = try state()
                }
                guard var pending = current.pending else { return .success(()) }
                let supported = zoneID.map(current.data.supportsZoneEditing) ?? current.data.supportsMemberEditing
                guard current.rejectedRemote == nil, supported else { return .failure(.unsupported) }
                let affectedZones: [UUID]
                if let zoneID { affectedZones = [zoneID] }
                else { affectedZones = current.data.zones?.map(\.zoneId) ?? [] }
                let affectedSpaces = Set(affectedZones.flatMap { id -> [String] in
                    let old = pending.base?.zones?.first(where: { $0.zoneId == id })?.displayMembers ?? []
                    let new = pending.target.zones?.first(where: { $0.zoneId == id })?.displayMembers ?? []
                    return (old + new).map(\.identity.spaceID)
                })
                guard affectedSpaces.isSubset(of: remote.editableSpaceIDs) else { return .failure(.permission) }
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
                    // The endpoint replaces extensionData as one object. Start with the
                    // latest server object so every other Zone and unknown field survives.
                    guard let target = (current.serverData ?? SiteExtensionData()).replacingZone(zone)
                    else { return .failure(.unsupported) }
                    guard target != current.serverData else { return .success(()) }
                    pending = .init(operationId: UUID(), timestamp: max(pending.timestamp, remote.timestamp + 1),
                                    base: current.serverData, target: target)
                }
                let changedMembers = (pending.target.zones ?? []).flatMap { zone -> [SiteTriggerZoneMember] in
                    let previous = pending.base?.zones?.first(where: { $0.zoneId == zone.zoneId })?.fields["members"]
                    return previous == zone.fields["members"] ? [] : zone.members ?? []
                }
                guard await validateCurrentMembers(changedMembers) else { return .failure(.invalidMember) }
                guard isCurrent else { return .failure(.permission) }
                try SiteTriggerZoneStore.update(site) { $0.submitted = pending }
                let props = try SiteTriggerZoneUpdatePayload.props(extensionData: pending.target)
                let result = await NetworkRequest.shared.request(.sitePropsUpdate(siteId: site.id, props: props))
                guard isCurrent else { return .failure(.permission) }
                guard case .success = result else { return .failure(.network) }
                #if DEBUG
                print("[SiteZoneSync][cloud] phase=post-accepted site=\(site.id) zone=\(zoneID?.uuidString ?? "all") operation=\(pending.operationId) targetCloudFingerprint=\(SiteTriggerZoneSyncPlanningPolicy.cloudFingerprint(siteID: site.id, data: pending.target) ?? "unavailable") targetZones=\(pending.target.zones?.count ?? -1)")
                #endif
                // The legacy update response can contain only a timestamp; always verify via GET.
                let verified = try await retrieve()
                try SiteTriggerZoneStore.receive(site, object: verified.object, timestamp: verified.timestamp)
                current = try state()
                #if DEBUG
                let verifiedCloudFingerprint = current.serverData.flatMap {
                    SiteTriggerZoneSyncPlanningPolicy.cloudFingerprint(siteID: site.id, data: $0)
                } ?? "unavailable"
                print("[SiteZoneSync][cloud] phase=get-verify site=\(site.id) zone=\(zoneID?.uuidString ?? "all") version=\(verified.timestamp) cloudFingerprint=\(verifiedCloudFingerprint) targetMatch=\(current.serverData == pending.target) pending=\(current.pending?.operationId.uuidString ?? "none") retainedChanges=\(current.deviceSyncChanges?.count ?? 0) conflict=\(current.conflict) ambiguous=\(current.hasAmbiguousRemote)")
                #endif
                guard verified.canEdit else { return .failure(.permission) }
                guard !current.hasAmbiguousRemote else { return .failure(.ambiguousRemote) }
                if current.conflict { return .failure(.conflict) }
                if zoneID != nil {
                    guard current.serverData == pending.target else { return .failure(.unconfirmed) }
                    // Other pending zones remain local; a row Save never drains the entire Site.
                    return .success(())
                }
                if current.pending == nil {
                    return .success(())
                }
                guard current.pending?.operationId != pending.operationId else { return .failure(.unconfirmed) }
                // A second local edit arrived while awaiting HTTP. Revalidate and submit that snapshot.
            }
        } catch let failure as Failure { return .failure(failure) }
        catch { return .failure(.storage) }
    }

    private func validateCurrentMembers(_ members: [SiteTriggerZoneMember]) async -> Bool {
        guard !members.isEmpty else { return true }
        let spaces = SpaceData.load(siteId: site.id)
        let ids = Set(members.map(\.identity.spaceID))
        let requests = spaces.filter { ids.contains($0.id) }.map { space in
            SiteTriggerZoneCandidateReader.Request(siteID: site.id, meshUUID: space.meshUUID,
                subnetID: space.meshNetworkId,
                space: .init(id: space.id, name: space.name,
                    accessLabelKey: nil,
                    availability: space.siteId == site.id && space.meshUUID == site.meshUUID && space.canEditing
                        ? .loading : .restricted), expectedGroupCount: space.groupCount)
        }
        guard requests.count == ids.count else { return false }
        let source = SiteTriggerZoneCandidateReader.Source(
            appPath: NSHomeDirectory() + "/Documents/\(account)/sunsmart.sqlite3",
            meshPath: MeshDataManager.customDatabasePath ?? NSHomeDirectory() + "/Documents/mesh.sqlite3",
            eligibleProfileTypes: [Profile.ProfileType.proximityLighting.rawValue,
                                   Profile.ProfileType.proximityLightingWithPhotocell.rawValue],
            excludedGroupAddresses: [.meshOTAGroupAddress, .localClientGroupAddress,
                                     .subElementBroadcastGroupAddress])
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: SiteTriggerZoneCandidateReader.validates(
                    members, requests: requests, source: source))
            }
        }
    }

}
