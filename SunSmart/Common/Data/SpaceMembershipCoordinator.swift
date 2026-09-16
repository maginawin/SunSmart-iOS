import Foundation
import NordicSigMeshSDK
import CryptoKit

enum SpaceMembershipCoordinator {
    static let store = SpaceMembershipStore(root: URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/SpaceMembership"))

    static func scope(_ space: SpaceData) -> SpaceMembershipRecord.Scope {
        .init(account: UserData.currentUserId, region: String(describing: UserData.currentServerRegion),
              siteID: space.siteId, spaceID: space.id)
    }
    static func current(_ record: SpaceMembershipRecord) -> Bool {
        record.scope.account == UserData.currentUserId
            && record.scope.region == String(describing: UserData.currentServerRegion)
            && (try? store.read(record.scope)) == record
    }
    static func allowsConfiguration(_ space: SpaceData) -> Bool {
        do {
            guard let record = try store.read(scope(space)) else {
                return space.permission == .owner || space.lastUploadCloudTimestamp != nil
            }
            return record.phase == .joined && record.initialized
                && (space.permission == .owner || space.lastUploadCloudTimestamp != nil)
        } catch { return false }
    }
    static func isLeaving(_ space: SpaceData) -> Bool {
        do { return try store.read(scope(space))?.isLeaving == true }
        catch { return true }
    }
    static func canJoin(_ space: SpaceData) -> Bool {
        do {
            guard let record = try store.read(scope(space)) else { return true }
            return record.phase == .joined || record.phase == .left
        } catch { return false }
    }
    @discardableResult static func authorizeJoin(_ space: SpaceData) -> Bool {
        guard canJoin(space) else { return false }
        do {
            var record = SpaceMembershipRecord(scope: scope(space))
            if let previous = try store.read(record.scope), previous.phase == .joined {
                record = previous
                record.generation = UUID()
            }
            try store.write(record)
            SpaceMembershipResponseContext.invalidate()
            return true
        } catch { return false }
    }
    static func accepts(_ payload: [String: Any]) -> Bool {
        guard let context = payload[SpaceMembershipResponseContext.payloadKey] as? [String: String] else { return true }
        return SpaceMembershipResponseContext.matches(context, account: UserData.currentUserId,
            region: String(describing: UserData.currentServerRegion))
    }

    static func canReceiveSite(_ siteID: String) -> Bool {
        guard let records = try? store.records(account: UserData.currentUserId,
            region: String(describing: UserData.currentServerRegion)) else { return false }
        return !records.contains { $0.scope.siteID == siteID && $0.isLeaving && $0.phase != .left }
    }

    /// An explicit successful ownership transfer authorizes a fresh membership.
    static func authorizeSiteReceipt(_ siteID: String) -> Bool {
        guard canReceiveSite(siteID) else { return false }
        do {
            for previous in try store.records(account: UserData.currentUserId,
                region: String(describing: UserData.currentServerRegion)) where previous.scope.siteID == siteID && previous.phase == .left {
                try store.replace(SpaceMembershipRecord(scope: previous.scope), expected: previous)
            }
            SpaceMembershipResponseContext.invalidate()
            return true
        } catch { return false }
    }

    static func preparedRecord(_ space: SpaceData, networkID: String) throws -> SpaceMembershipRecord {
        var record = try store.read(scope(space)) ?? SpaceMembershipRecord(scope: scope(space))
        guard record.phase == .joined else { throw CocoaError(.userCancelled) }
        if let previous = record.networkID, previous != networkID { throw CocoaError(.fileReadCorruptFile) }
        record.networkID = networkID
        // Existing complete installations need no data migration.
        if space.lastUploadCloudTimestamp != nil { record.initialized = true }
        try store.write(record)
        return record
    }

    static var savedCopiesDirectory: URL {
        let context = SpaceMembershipRecord.Scope(account: UserData.currentUserId,
            region: String(describing: UserData.currentServerRegion), siteID: "", spaceID: "")
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let name = (try? encoder.encode(context)).map { Data(SHA256.hash(data: $0)).hex } ?? "unavailable"
        return store.root.appendingPathComponent("copies").appendingPathComponent(name)
    }

    @MainActor static func preserveCopy(_ space: SpaceData) async throws -> URL {
        guard let revision = ConfigurationSnapshotRevision.current() else { throw CocoaError(.fileReadUnknown) }
        let context = SpaceMembershipResponseContext.capture(account: UserData.currentUserId,
            region: String(describing: UserData.currentServerRegion))
        let candidate = space.copy()
        if let record = try store.read(scope(space)), let networkID = record.networkID { candidate.meshNetworkId = networkID }
        let raw = try DebugCloudJSONRecords.space(candidate)
        let complete = await candidate.export(purpose: .localBackup)
        guard revision == ConfigurationSnapshotRevision.current(),
            SpaceMembershipResponseContext.matches(context, account: UserData.currentUserId,
            region: String(describing: UserData.currentServerRegion)) else { throw CocoaError(.userCancelled) }
        var value: [String: Any] = ["formatVersion": 1, "siteId": space.siteId, "spaceId": space.id,
                                  "spaceName": space.name, "rawLocal": raw,
                                  "capturedAt": ISO8601DateFormatter().string(from: Date()), "uploadable": false]
        // The copy is never automatically uploaded or treated as an import authorization.
        if let complete { value["spaces"] = [complete] }
        value["completeConfigurationAvailable"] = complete != nil && space.lastUploadCloudTimestamp != nil
            && !SpaceConfigurationSafety.hasPendingImport(space)
        let directory = savedCopiesDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safeName = String(space.name.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.prefix(32))
        let url = directory.appendingPathComponent(formatter.string(from: Date()) + "-" + safeName + "-" + UUID().uuidString + ".json")
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
            .write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    @MainActor static func queueLeave(_ space: SpaceData, site: SiteData, savedCopy: URL? = nil) async throws {
        guard space.permission != .owner else { throw CocoaError(.userCancelled) }
        var record = try store.read(scope(space)) ?? SpaceMembershipRecord(scope: scope(space))
        guard record.phase == .joined else { return }
        record.networkID = record.networkID ?? (space.meshNetworkId.isEmpty ? nil : space.meshNetworkId)
        record.savedCopy = savedCopy?.lastPathComponent
        // Never infer unused addresses from an incomplete configuration.
        var recycle: [String: Any] = ["device": [Int](), "group": [Int](), "scene": [Int]()]
        if site.spaces.count == 1, allowsConfiguration(space), !SpaceConfigurationSafety.isBlocked(space) {
            let data = await site.getRecycleAddressData(unbindSpaces: [space], prepareOnly: true)
            recycle = ["device": data.deviceAddresses, "group": data.groupAddresses, "scene": data.sceneAddresses]
            if let provisioner = data.provisionerData { recycle["provisioner"] = provisioner }
            if let exclusions = data.exclusionAddresses {
                recycle["exclusions"] = exclusions.map { ["ivIndex": $0.ivIndex, "addresses": $0.addresses] as [String: Any] }
            }
            recycle["releasePhone"] = true
        }
        guard record.scope == scope(space), !isLeaving(space) else { throw CocoaError(.userCancelled) }
        record.recyclePayload = try JSONSerialization.data(withJSONObject: recycle)
        record.phase = .queued; record.generation = UUID()
        try store.write(record)
        SpaceMembershipResponseContext.invalidate()
        if !space.meshNetworkId.isEmpty { _ = SpaceConfigurationSafety.beginUnbind(space) }
        CloudSynchronizationManager.shared.suspendForMembershipLeave(space: space)
    }

    @MainActor private static var leaving = Set<SpaceMembershipRecord.Scope>()

    /// Idempotent local completion is independent of configuration hydration.
    @MainActor static func finishLeave(_ record: SpaceMembershipRecord) throws {
        guard current(record), record.phase == .confirmed else { throw CocoaError(.userCancelled) }
        if let space = SpaceData.load(siteId: record.scope.siteID, spaceId: record.scope.spaceID).first {
            if let networkID = record.networkID { space.meshNetworkId = networkID }
            guard space.delete() else { throw CocoaError(.fileWriteUnknown) }
        }
        if let site = SiteData.load(siteId: record.scope.siteID), let bytes = record.recyclePayload,
           let recycle = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
            guard site.deleteProvisionerAddress(deviceAddresses: recycle["device"] as? [Int] ?? [],
                groupAddresses: recycle["group"] as? [Int] ?? [], sceneAddresses: recycle["scene"] as? [Int] ?? []) else { throw CocoaError(.fileWriteUnknown) }
            if recycle["releasePhone"] as? Bool == true,
               SpaceData.load(siteId: record.scope.siteID).isEmpty {
                if let network = MeshNetwork.load(meshUUID: site.meshUUID, allData: false) {
                    if let node = network.localProvisioner?.node { network.remove(node: node) }
                    guard network.save() else { throw CocoaError(.fileWriteUnknown) }
                }
                site.localAddress = nil
                guard site.save() else { throw CocoaError(.fileWriteUnknown) }
            }
        }
        var completed = record; completed.phase = .left
        try store.replace(completed, expected: record)
        NotificationCenter.default.post(name: .init(SitesDataRefreshNotifiacationName), object: nil)
    }

    @MainActor static func resumeLeave(_ scope: SpaceMembershipRecord.Scope) async -> NetworkApiError? {
        guard leaving.insert(scope).inserted else { return .configurationUploadUnconfirmed }
        defer { leaving.remove(scope) }
        do {
            guard var record = try store.read(scope), current(record), record.isLeaving else { return nil }
            if record.phase == .left { return nil }
            if record.phase == .confirmed { try finishLeave(record); return nil }
            guard NetworkRequest.shared.networkable else { return .noNetwork }
            if record.phase == .requesting || record.phase == .unknown {
                let space = SpaceData.load(siteId: scope.siteID, spaceId: scope.spaceID).first
                let probe = await NetworkRequest.shared.request(.spaceInfo(siteId: scope.siteID, spaceId: scope.spaceID,
                    password: space?.authorizationPassword))
                guard current(record) else { return .configurationUploadUnconfirmed }
                switch probe {
                case .success(let response):
                    guard let remote = response["data"] as? [String: Any], remote["uuid"] as? String == scope.spaceID,
                          let role = remote["role"] as? String, role == "editor" || role == "visitor" else {
                        return .configurationUploadUnconfirmed
                    }
                case .failure(let error):
                    if error == .noSpacePermission || error == .noSitePermission || error == .resourceNotFound {
                        var confirmed = record; confirmed.phase = .confirmed
                        try store.replace(confirmed, expected: record)
                        try finishLeave(confirmed)
                        return nil
                    }
                    // Configuration passwords do not authorize membership removal.
                    // Retry the independent leave request without interpreting this as success.
                    if error != .incorrectPassword && error != .spacePasswordOverdue { return error }
                }
            }
            // Retrying targets the same membership: rejoin is blocked until confirmed.
            let previous = record; record.phase = .requesting
            try store.replace(record, expected: previous)
            let recycle = record.recyclePayload.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
            let exclusions = (recycle["exclusions"] as? [[String: Any]])?.compactMap { item -> (Int, [Int])? in
                guard let iv = item["ivIndex"] as? Int, let addresses = item["addresses"] as? [Int] else { return nil }
                return (iv, addresses)
            }
            let result = await NetworkRequest.shared.request(.unbindSpaces(siteId: scope.siteID, spaceIds: [scope.spaceID],
                recycleDeviceAddresses: recycle["device"] as? [Int] ?? [],
                recycleGroupAddresses: recycle["group"] as? [Int] ?? [],
                recycleSceneAddresses: recycle["scene"] as? [Int] ?? [],
                exclusions: exclusions, provisionerData: recycle["provisioner"] as? [String: Any]))
            guard current(record) else { return .configurationUploadUnconfirmed }
            var next = record
            switch result {
            case .success: next.phase = .confirmed
            case .failure(let error):
                if error == .noSpacePermission || error == .noSitePermission || error == .resourceNotFound {
                    next.phase = .confirmed
                } else {
                    next.phase = .unknown
                    try store.replace(next, expected: record)
                    return error
                }
            }
            try store.replace(next, expected: record)
            try finishLeave(next)
            return nil
        } catch { return .configurationUploadUnconfirmed }
    }

    @MainActor static func resumeLeaves() async {
        let account = UserData.currentUserId, region = String(describing: UserData.currentServerRegion)
        guard let records = try? store.records(account: account, region: region) else { return }
        for record in records where record.isLeaving && record.phase != .left {
            guard account == UserData.currentUserId, region == String(describing: UserData.currentServerRegion) else { return }
            _ = await resumeLeave(record.scope)
        }
    }
}

extension SpaceData {
    /// Resolve identity once, before any configuration journal or Mesh lookup.
    @MainActor
    func restoreConfiguration(spaceJsonData payload: [String: Any], initialize: Bool = false) async -> SpaceImportOutcome {
        guard SpaceMembershipCoordinator.accepts(payload), payload["uuid"] as? String == id else {
            return .rejected("staleMembershipResponse")
        }
        guard !SpaceMembershipCoordinator.isLeaving(self) else { return .rejected("spaceLeaving") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let net = payload["netKey"] as? [String: Any], let app = payload["appKey"] as? [String: Any],
              let netData = try? JSONSerialization.data(withJSONObject: net),
              let appData = try? JSONSerialization.data(withJSONObject: app),
              let networkKey = try? decoder.decode(NetworkKey.self, from: netData),
              let applicationKey = try? decoder.decode(ApplicationKey.self, from: appData),
              applicationKey.boundNetworkKeyIndex == networkKey.index else { return .rejected("invalidNetworkIdentity") }
        let canonicalID = networkKey.networkId.hex
        let uninitialized = lastUploadCloudTimestamp == nil && (permission != .owner || initialize)
        guard meshNetworkId == canonicalID || uninitialized else { return .rejected("networkIdentityMismatch") }
        let candidate = copy()
        candidate.meshNetworkId = canonicalID
        do {
            let membership = try SpaceMembershipCoordinator.preparedRecord(candidate, networkID: canonicalID)
            let state = try SpaceConfigurationSafety.recoveryState(candidate)
            guard state.phase != .removing, !(state.phase == .active && state.unbindRequested == true),
                  SpaceConfigurationSafety.activateImport(candidate) else { return .rejected("spaceRemovalPending") }
            // Persist a canonical but explicitly uninitialized row before asynchronous work.
            // A crash resumes under the same identity; upload remains disabled.
            guard candidate.save() else { return .rejected("configurationPersistenceFailed") }
            var cleanPayload = payload
            cleanPayload.removeValue(forKey: SpaceMembershipResponseContext.payloadKey)
            let outcome = await candidate.update(spaceJsonData: cleanPayload, initialize: initialize || uninitialized)
            guard SpaceMembershipCoordinator.current(membership), SpaceMembershipCoordinator.accepts(payload) else {
                return .rejected("staleMembershipResponse")
            }
            if outcome.status != .rejected {
                if outcome.status == .applied {
                    var completed = membership
                    completed.initialized = true
                    try SpaceMembershipCoordinator.store.replace(completed, expected: membership)
                }
                applyConfigurationState(from: candidate)
            }
            return outcome
        } catch { return .rejected("configurationPersistenceFailed") }
    }

    /// Configuration copies must preserve authority and cloud baselines as well as UI values.
    func applyConfigurationState(from other: SpaceData) {
        name = other.name; imageId = other.imageId; create = other.create; lastUpdate = other.lastUpdate
        isFavourite = other.isFavourite; permission = other.permission; sourceType = other.sourceType
        meshUUID = other.meshUUID; meshNetworkId = other.meshNetworkId
        owner = other.owner; editor = other.editor; visitors = other.visitors
        luminairesCount = other.luminairesCount; switchesCount = other.switchesCount
        deviceCount = other.deviceCount; groupCount = other.groupCount; sceneCount = other.sceneCount
        scheheduleCount = other.scheheduleCount; deviceSortType = other.deviceSortType
        lastUploadCloudTimestamp = other.lastUploadCloudTimestamp; syncCloudError = other.syncCloudError
        lastSyncDateTimestamp = other.lastSyncDateTimestamp; state = other.state
        vistorPassword = other.vistorPassword; editorPassword = other.editorPassword
        authorizationPassword = other.authorizationPassword; requiresPasswordVerification = other.requiresPasswordVerification
        vistorPasswordEnable = other.vistorPasswordEnable; shareCode = other.shareCode
        isConfiguring = other.isConfiguring; applyDeviceAddressCount = other.applyDeviceAddressCount
        applyGroupAddressCount = other.applyGroupAddressCount; releaseAddress = other.releaseAddress
        disableEditorPermission = other.disableEditorPermission; meshOTADistribution = other.meshOTADistribution
        displayDeviceNamePrefix = other.displayDeviceNamePrefix; showCCTQuickButtons = other.showCCTQuickButtons
        controlType = other.controlType; deviceBlinkMode = other.deviceBlinkMode
        triggerZones = other.triggerZones.map { $0.copy() }; triggerZonesLoadFailed = other.triggerZonesLoadFailed
        relevanceGatewayId = other.relevanceGatewayId; gatewayStatus = other.gatewayStatus
        gatewayLastOnline = other.gatewayLastOnline
    }
}
