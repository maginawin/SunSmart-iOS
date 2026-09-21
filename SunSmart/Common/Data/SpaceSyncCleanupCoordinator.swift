import Foundation
import NordicSigMeshSDK

/// Runs at sync boundaries, never from needSync getters or a debug export.
@MainActor
enum SpaceSyncCleanupCoordinator {
    private struct Scope: Hashable {
        let account = UserData.currentUserId
        let region: String
        let siteID: String

        init(_ site: SiteData) {
            region = String(describing: site.region)
            siteID = site.id
        }

        var isCurrent: Bool {
            account == UserData.currentUserId
                && region == String(describing: UserData.currentServerRegion)
        }
    }

    private struct WorkKey: Hashable {
        let scope: Scope
        let spaceID: String
    }

    private struct Preparation {
        let succeeded: Bool
        let error: NetworkApiError?
    }
    private static var active: [WorkKey: _Concurrency.Task<Preparation, Never>] = [:]
    // A single-Space caller may clean while another batch is suspended, but it
    // cannot erase the durable request for that batch's future mutations.
    private static var owners: [Scope: Set<UUID>] = [:]

    @discardableResult
    static func prepare(_ space: SpaceData) async -> Bool {
        guard let site = SiteData.load(siteId: space.siteId) else { return false }
        let scope = Scope(site)
        guard scope.isCurrent, !_Concurrency.Task<Never, Never>.isCancelled,
              markCleanup(scope) else { return false }
        let owner = begin(scope)
        defer { end(scope, owner: owner) }
        let result = await prepareSpace(space, scope: scope)
        guard scope.isCurrent, !_Concurrency.Task<Never, Never>.isCancelled else { return false }
        end(scope, owner: owner)
        return finish(scope) != nil && result
    }

    /// Explicit uploads require every selected Space to be prepared. Background
    /// discovery may retain unrelated failures while selecting ready Spaces.
    static func prepareBatch(site: SiteData, spaces: [SpaceData],
                             requiringSuccessfulPreparation: Bool = true,
                             shouldContinue: () -> Bool = { true },
                             shouldPrepare: (SpaceData) -> Bool = { _ in true }) async -> SiteData? {
        let scope = Scope(site)
        func isCurrent() -> Bool {
            scope.isCurrent && !_Concurrency.Task<Never, Never>.isCancelled && shouldContinue()
        }
        guard isCurrent(), spaces.allSatisfy({ $0.siteId == site.id }) else { return nil }
        let owner = begin(scope)
        defer { end(scope, owner: owner) }
        var marked = false
        var allPrepared = true
        var visited = Set<String>()
        for space in spaces {
            guard visited.insert(space.id).inserted, shouldPrepare(space) else { continue }
            // Preserve an actual main-queue handoff and recheck queued uploads.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            guard isCurrent() else { return nil }
            guard shouldPrepare(space) else { continue }
            if !marked {
                guard markCleanup(scope) else { return nil }
                marked = true
            }
            if !(await prepareSpace(space, scope: scope)) { allPrepared = false }
            guard isCurrent() else { return nil }
        }
        guard isCurrent() else { return nil }
        end(scope, owner: owner)
        // Includes recovery with no Space candidates but an interrupted cleanup.
        let current = finish(scope)
        return allPrepared || !requiringSuccessfulPreparation ? current : nil
    }

    private static func begin(_ scope: Scope) -> UUID {
        let owner = UUID()
        owners[scope, default: []].insert(owner)
        return owner
    }

    private static func end(_ scope: Scope, owner: UUID) {
        owners[scope]?.remove(owner)
        if owners[scope]?.isEmpty == true { owners[scope] = nil }
    }

    private static func markCleanup(_ scope: Scope) -> Bool {
        guard scope.isCurrent, let site = SiteData.load(siteId: scope.siteID), site.state == .normal else { return false }
        do {
            try SiteTriggerZoneStore.update(site) { state in
                var requests = state.referenceCleanupRequests ?? [:]
                requests[scope.account] = UUID()
                state.referenceCleanupRequests = requests
            }
            return true
        } catch { return false }
    }

    private static func finish(_ scope: Scope) -> SiteData? {
        guard scope.isCurrent, let site = SiteData.load(siteId: scope.siteID), site.state == .normal else { return nil }
        do {
            if let generation = try SiteTriggerZoneStore.load(site).referenceCleanupRequests?[scope.account] {
                let result = try SiteTriggerZoneCoordinator(site: site).finishReferenceCleanup()
                if case .completed = result, owners[scope] == nil, scope.isCurrent {
                    try SiteTriggerZoneStore.update(site) { state in
                        guard state.referenceCleanupRequests?[scope.account] == generation else { return }
                        state.referenceCleanupRequests?.removeValue(forKey: scope.account)
                        if state.referenceCleanupRequests?.isEmpty == true { state.referenceCleanupRequests = nil }
                    }
                }
            }
            guard scope.isCurrent, let current = SiteData.load(siteId: scope.siteID), current.state == .normal else { return nil }
            return current
        } catch { return nil }
    }

    private static func prepareSpace(_ space: SpaceData, scope: Scope) async -> Bool {
        guard scope.isCurrent else { return false }
        let key = WorkKey(scope: scope, spaceID: space.id)
        if let task = active[key] {
            let result = await task.value
            guard scope.isCurrent else { return false }
            space.syncCloudError = result.error
            return result.succeeded
        }
        let task = _Concurrency.Task { @MainActor in
            let succeeded = await perform(space, scope: scope)
            return Preparation(succeeded: succeeded, error: space.syncCloudError)
        }
        active[key] = task
        let result = await task.value
        active[key] = nil
        return result.succeeded
    }

    private static func perform(_ space: SpaceData, scope: Scope) async -> Bool {
        let performance = AppPerformance.begin("SpaceCleanup")
        defer { performance.end() }
        guard scope.isCurrent else { return false }
        space.syncCloudError = nil
        var completed = false
        defer {
            if !completed, scope.isCurrent, !_Concurrency.Task<Never, Never>.isCancelled,
               space.syncCloudError == nil {
                SpaceConfigurationSafety.recordSyncFailure(space,
                    error: SpaceConfigurationSafety.configurationSyncError(space), stage: "cleanupPreparation")
            }
        }
        guard await SpaceConfigurationSafety.recoverUpgradeBaselineIfNeeded(space, readLocal: {
            guard let current = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
                  current.lastUpdate == space.lastUpdate else { return nil }
            return await current.export(allowsProtectedInspection: true)
        }) else { return false }
        guard scope.isCurrent, SpaceConfigurationSafety.canCleanSyncReferences(space),
              let context = try? SpaceConfigurationSafety.recoveryState(space),
              let original = await space.export(purpose: .cleanupInspection),
              scope.isCurrent else { return false }
        let cleaned: SpaceSyncCleanupPolicy.Result
        do { cleaned = try SpaceSyncCleanupPolicy.normalize(original) }
        catch {
            SpaceConfigurationSafety.block(space, reason: "entryTopologyNeedsReview")
            return SpaceConfigurationSafety.recordSyncFailure(space, error: .configurationExportInvalid,
                                                               stage: "cleanupTopology")
        }
        let timestamp = space.lastUpdate
        guard await SpaceConfigurationSafety.verifySyncCleanupBaseline(space, local: original),
              scope.isCurrent, SpaceConfigurationSafety.isCurrent(context, space: space), space.lastUpdate == timestamp,
              let persisted = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
              persisted.lastUpdate == timestamp,
              let network = ProximityLightingTopologyContext.network(for: space) else { return false }
        ProximityLightingTopologyContext.loadGroupInfo(network: network, space: space)
        let groups = network.groups.filter { !$0.isVirtual }
        let nodes = ProximityLightingTopologyContext.realNodes(in: network)
        let preparation = ProximityLightingLifecycleCoordinator.begin(space: space, groups: groups,
            nodes: nodes, network: network).prepare()
        guard preparation.isValid, SpaceSyncCleanupPolicy.equivalentTopology(preparation.normalized.snapshot, cleaned.topology.snapshot),
              Set(nodes.map { $0.uuid.uuidString.uppercased() }) == Set(cleaned.devices.map { $0.uuid.uppercased() }) else {
            return false
        }
        guard var changes = try? extensionChanges(space: space, network: network, cleaned: cleaned) else { return false }
        do {
            if let cleanup = try GroupInfo.obsoleteSyncExtensionCleanup(meshUUID: space.meshUUID,
                networkId: space.meshNetworkId, validAddresses: Set(network.groups.map { $0.address.address })) { changes.append(cleanup) }
        } catch { return false }
        let countChanged = space.deviceCount != nodes.count || space.luminairesCount != nodes.filter { $0.deviceType == .light }.count
        let didChange = cleaned.didChange || !changes.isEmpty || countChanged
        if didChange {
            guard SpaceConfigurationSafety.beginSyncReferenceCleanup(space, payload: original),
                  ProximityLightingLifecycleCoordinator.commit(preparation,
                    hasAdditionalLogicalChange: true,
                    automaticCleanupSnapshot: preparation.sourceSnapshot,
                    applyAdditionalChanges: {
                        for change in changes { try change() }
                        space.deviceCount = nodes.count
                        space.luminairesCount = nodes.filter { $0.deviceType == .light }.count
                    }) != nil else { return false }
        }
        // A deletion can now finish without absorbing unrelated historical repairs.
        DevicePermanentDeletionContext.resume(space: space)
        guard !SpaceConfigurationSafety.hasPendingDeletionCleanup(space),
              let reloaded = SpaceData.load(siteId: space.siteId, spaceId: space.id).first else { return false }
        // The caller may be an old Space object with the same second-level
        // timestamp. Reload all persisted Space fields before validating cleanup;
        // a Mesh revision alone cannot prove the first export is reusable.
        let readback = await reloaded.export(purpose: .cleanupInspection)
        guard let readback,
              scope.isCurrent,
              let validated = try? SpaceSyncCleanupPolicy.normalize(readback), !validated.didChange,
              SpaceConfigurationSafety.isCurrent(context, space: space),
              let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
              latest.lastUpdate == reloaded.lastUpdate,
              SpaceConfigurationIntegrityPolicy.integer(readback["updateTimestamp"]) == reloaded.lastUpdate,
              let savedNetwork = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else { return false }
        ProximityLightingTopologyContext.loadGroupInfo(network: savedNetwork, space: latest)
        guard let remaining = try? extensionChanges(space: latest, network: savedNetwork, cleaned: validated), remaining.isEmpty else { return false }
        space.lastUpdate = reloaded.lastUpdate
        space.deviceCount = reloaded.deviceCount
        space.luminairesCount = reloaded.luminairesCount
        guard SpaceConfigurationSafety.finishSyncReferenceCleanup(space, changed: didChange) else { return false }
        if didChange {
            nodes.forEach { $0.clearSyncStateCache() }
            let manager = MeshNetworkManager.instance
            if manager.meshNetwork === network {
                manager.schedules = Schedule.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId)
                manager.switchs = DeviceSwitchData.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId)
            }
            NotificationCenter.default.post(name: .init(proximityLightingImportSyncNotificationName),
                object: ProximityLightingImportSyncRequest(spaceId: space.id, meshUUID: space.meshUUID,
                                                           networkId: space.meshNetworkId))
            #if DEBUG
            print("[SpaceSyncCleanup] space=\(space.id) repairs=\(cleaned.repairs) extensionChanges=\(changes.count)")
            #endif
        }
        completed = !SpaceConfigurationSafety.isBlocked(space)
        return completed
    }

    static func prepareCurrentSpace() async -> Bool {
        let manager = MeshNetworkManager.instance
        guard let uuid = manager.meshNetwork?.uuid.uuidString,
              let space = SpaceData.load(siteId: uuid).first(where: {
                  $0.meshNetworkId == manager.currentNetworkKey.networkId.hex
              }) else { return false }
        return await prepare(space)
    }

    /// Every closure describes a real change. Empty targets are retained as user
    /// objects; observed device state is not fabricated to match the new target.
    private static func extensionChanges(space: SpaceData, network: MeshNetwork,
                                         cleaned: SpaceSyncCleanupPolicy.Result) throws -> [() throws -> Void] {
        var changes: [() throws -> Void] = []
        let nodes = ProximityLightingTopologyContext.realNodes(in: network)
        let addresses = Set(cleaned.devices.flatMap(\.elementAddresses))
        let groupAddresses = Set(network.groups.map { $0.address.address })
        let payloadNodes = cleaned.payload["nodes"] as! [[String: Any]]
        for node in nodes {
            guard let target = payloadNodes.first(where: { ($0["uuid"] as? String)?.uppercased() == node.uuid.uuidString.uppercased() }),
                  let state = target["groupState"] as? Int, state != node.groupState.rawValue,
                  let groupState = Node.GroupState(rawValue: state) else { continue }
            changes.append {
                node.groupState = groupState
                guard node.save() else { throw SpaceConfigurationSafety.SafetyError.persistenceFailed }
            }
        }
        for scene in network.scenes {
            let stale = scene.addresses.filter { !addresses.contains($0) }
            guard !stale.isEmpty else { continue }
            changes.append {
                stale.forEach { address in while scene.addresses.contains(address) { scene.remove(address: address) } }
                guard scene.save() else { throw SpaceConfigurationSafety.SafetyError.persistenceFailed }
            }
        }
        let sceneNumbers = Set(network.scenes.map(\.number))
        for schedule in Schedule.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId) {
            let activeNodes = schedule.nodeAddresses.filter { addresses.contains($0) }
            let activeGroups = schedule.groupAddresses.filter { groupAddresses.contains($0) }
            let pendingGroups = schedule.needDeleteGroupAddresses.filter { groupAddresses.contains($0) }
            let profiles = schedule.profiles.filter { item in
                network.groups.contains { group in
                    group.address.address == item.groupAddress
                        && group.info.profile.scenes.contains { $0.sceneNumber == item.profileSceneNumber }
                }
            }
            let scene = schedule.sceneNumber.flatMap { sceneNumbers.contains($0) ? $0 : nil }
            let pendingScenes = schedule.needDeleteSceneNumbers.filter { sceneNumbers.contains($0) }
            var pendingNodes = schedule.needDeleteNodeAddresses.filter { addresses.contains($0) }
            let removedTarget = activeGroups != schedule.groupAddresses || pendingGroups != schedule.needDeleteGroupAddresses
                || profiles != schedule.profiles || scene != schedule.sceneNumber || pendingScenes != schedule.needDeleteSceneNumbers
            if removedTarget {
                for node in nodes where !pendingNodes.contains(node.primaryUnicastAddress) {
                    let currentGroup = node.groupState == .exitFailure ? nil : node.group
                    let targetsGroup = currentGroup.map { activeGroups.contains($0.address.address) } ?? false
                    let targetsScene = currentGroup.map { group in
                        scene.map { number in group.info.sceneExecuteDatas.contains { $0.sceneNumber == number } } ?? false
                    } ?? false
                    let targeted = activeNodes.contains(node.primaryUnicastAddress) || targetsGroup || targetsScene
                    let observed = node.schedulerActions[schedule.id]?.isValid == true
                        || node.allSchedulerModelEntrys.values.contains { $0[schedule.id]?.isValid == true }
                    if !targeted && observed { pendingNodes.append(node.primaryUnicastAddress) }
                }
            }
            guard activeNodes != schedule.nodeAddresses || pendingNodes != schedule.needDeleteNodeAddresses || removedTarget else { continue }
            changes.append {
                schedule.nodeAddresses = activeNodes; schedule.needDeleteNodeAddresses = pendingNodes
                schedule.groupAddresses = activeGroups; schedule.needDeleteGroupAddresses = pendingGroups
                schedule.profiles = profiles; schedule.sceneNumber = scene; schedule.needDeleteSceneNumbers = pendingScenes
                guard schedule.save(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId) else {
                    throw SpaceConfigurationSafety.SafetyError.persistenceFailed
                }
            }
        }
        for group in network.groups where !group.isVirtual {
            let scenes = group.info.sceneExecuteDatas.filter { sceneNumbers.contains($0.sceneNumber) }
            if scenes.count != group.info.sceneExecuteDatas.count {
                changes.append {
                    group.info.sceneExecuteDatas = scenes
                    guard group.info.save(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else {
                        throw SpaceConfigurationSafety.SafetyError.persistenceFailed
                    }
                }
            }
            for template in group.info.profile.lightSensorTemplates {
                let retained = template.deviceAddresses.filter { addresses.contains($0) }
                if retained != template.deviceAddresses {
                    changes.append {
                        template.deviceAddresses = retained
                        guard group.info.save(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else {
                            throw SpaceConfigurationSafety.SafetyError.persistenceFailed
                        }
                    }
                }
            }
            if let sensor = group.info.ambientLightSensorNodeAddress, !addresses.contains(sensor) {
                changes.append {
                    group.info.ambientLightSensorNodeAddress = nil
                    guard group.info.save(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else {
                        throw SpaceConfigurationSafety.SafetyError.persistenceFailed
                    }
                }
            }
        }
        for item in DeviceSwitchData.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId) {
            let groups = item.bindGroupAddresses.filter { groupAddresses.contains($0) }
            let removedGroups = item.bindGroupAddresses.filter { !groupAddresses.contains($0) }
            let hasCleanup = nodes.contains { node in
                let stillTargeted = node.group.map { groups.contains($0.address.address) && node.groupState != .exitFailure } ?? false
                guard !stillTargeted else { return false }
                let switchAddresses = Set([item.linkGroupAddress, item.subLinkGroupAddress].compactMap { $0 })
                let subscriptions = MissingGroupSubscriptionCleanup.subscriptionAddresses(for: node)
                let proxyStillBound = (node.primaryUnicastAddress == item.proxyNodeAddress
                    || node.primaryUnicastAddress == item.deleteProxyNodeAddress)
                    && node.enOceanMacAddress != nil
                return !subscriptions.isDisjoint(with: switchAddresses) || proxyStillBound
            }
            var pending = item.unbindGroupAddresses.filter { groupAddresses.contains($0) || hasCleanup }
            if hasCleanup {
                for address in removedGroups where !pending.contains(address) { pending.append(address) }
            }
            let proxy = item.proxyNodeAddress.flatMap { addresses.contains($0) ? $0 : nil }
            let deletingProxy = item.deleteProxyNodeAddress.flatMap { addresses.contains($0) ? $0 : nil }
            guard groups != item.bindGroupAddresses || pending != item.unbindGroupAddresses
                    || proxy != item.proxyNodeAddress || deletingProxy != item.deleteProxyNodeAddress else { continue }
            changes.append {
                item.bindGroupAddresses = groups; item.unbindGroupAddresses = pending
                item.proxyNodeAddress = proxy; item.deleteProxyNodeAddress = deletingProxy
                guard item.save(meshUUID: space.meshUUID, networkId: space.meshNetworkId) else {
                    throw SpaceConfigurationSafety.SafetyError.persistenceFailed
                }
            }
        }
        return changes
    }
}

enum MissingGroupSubscriptionCleanup {
    private static func subscriptions(_ model: Model) -> [Address] {
        guard let data = try? JSONEncoder().encode(model),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let addresses = object["subscribe"] as? [String] else { return [] }
        return addresses.compactMap { Address(hex: $0) }
    }
    static func subscriptionAddresses(for node: Node) -> Set<Address> {
        Set(node.elements.flatMap(\.models).flatMap(subscriptions))
    }
    static func addresses(for node: Node) -> Set<Address> {
        guard let network = node.network else { return [] }
        let known = Set(network.groups.map { $0.address.address })
        return Set(node.elements.flatMap(\.models).flatMap { model in
            subscriptions(model).filter { SpaceSyncCleanupPolicy.isBusinessGroup($0) && !known.contains($0) }
        })
    }

    static func handles(for node: Node) -> [MeshMessageHandle] {
        let stale = addresses(for: node)
        return node.elements.flatMap(\.models).flatMap { model -> [MeshMessageHandle] in
            guard let element = model.parentElement?.unicastAddress else { return [] }
            return stale.sorted().compactMap { address in
                guard subscriptions(model).contains(address) else { return nil }
                // The SDK has a decoding initializer for the standard message;
                // no fake Group or SDK mutation is required to address a tombstone.
                var parameters = Data()
                func append(_ value: UInt16) { parameters.append(UInt8(value & 0xFF)); parameters.append(UInt8(value >> 8)) }
                append(element); append(address)
                if let company = model.companyIdentifier { append(company) }
                append(model.modelIdentifier)
                guard let message = ConfigModelSubscriptionDelete(parameters: parameters) else { return nil }
                let handle = MeshMessageHandle(message: message, address: node.primaryUnicastAddress)
                handle.continuous = false
                return handle
            }
        }
    }

    static func finish(for node: Node) -> Bool {
        guard addresses(for: node).isEmpty else { return false }
        let changed = node.group == nil && node.groupState != .none
        if changed { node.groupState = .none }
        guard node.save() else { return false }
        if changed, let network = node.network,
           let space = SpaceData.load(siteId: network.uuid.uuidString).first(where: { $0.meshNetworkId == node.subNetworkId }) {
            space.markLocalChangePendingCloudSync()
            guard space.save() else { return false }
        }
        node.clearSyncStateCache()
        return true
    }

    static func acknowledge(_ handle: MeshMessageHandle, status: StaticMeshMessage, for node: Node) -> Bool {
        guard let request = handle.message as? ConfigModelSubscriptionDelete,
              let receipt = status as? ConfigModelSubscriptionStatus, receipt.isSuccess,
              receipt.address == request.address, receipt.elementAddress == request.elementAddress,
              receipt.modelId == request.modelId,
              handle.address == node.primaryUnicastAddress,
              addresses(for: node).contains(request.address),
              let element = node.elements.first(where: { $0.unicastAddress == request.elementAddress }),
              let model = element.models.first(where: { $0.modelId == request.modelId }),
              let savedData = try? JSONEncoder().encode(model),
              let previous = try? JSONDecoder().decode(Model.self, from: savedData) else { return false }
        // The SDK's normal receipt handler looks up a Group and skips vanished
        // Groups. Apply only this acknowledged address to the captured instance.
        model.unsubscribe(from: request.address)
        node.clearSyncStateCache()
        guard node.save() else { model.copy(from: previous); return false }
        return true
    }
}

/// Captures desired configuration and provisioning instances, not observed Mesh
/// values. A response from an old plan cannot acknowledge a changed Profile.
enum SpaceSyncTaskScope {
    static func capture() -> () -> Bool {
        let manager = MeshNetworkManager.instance
        guard let network = manager.meshNetwork else { return { false } }
        let account = UserData.currentUserId
        let region = UserData.currentServerRegion
        let networkID = manager.currentNetworkKey.networkId.hex
        let groups = network.groups
        let nodes = network.nodes
        let profiles = groups.filter { !$0.isVirtual }.map { ($0, $0.info.profile.copy()) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let paths = groups.map { try? encoder.encode($0.info.proximityLightingPath) }
        func zones() -> Data? {
            guard let space = SpaceData.load(siteId: network.uuid.uuidString).first(where: { $0.meshNetworkId == networkID }) else { return nil }
            return try? encoder.encode(space.triggerZones)
        }
        let spaceZones = zones()
        return {
            guard account == UserData.currentUserId, region == UserData.currentServerRegion,
                  manager.meshNetwork === network, manager.currentNetworkKey.networkId.hex == networkID,
                  network.nodes.count == nodes.count, network.groups.count == groups.count,
                  nodes.allSatisfy({ old in network.nodes.contains { $0 === old } }),
                  groups.allSatisfy({ old in network.groups.contains { $0 === old } }),
                  profiles.allSatisfy({ group, profile in
                      group.info.profile == profile
                          && (try? encoder.encode(group.info.profile.nightData)) == (try? encoder.encode(profile.nightData))
                  }),
                  zip(groups, paths).allSatisfy({ group, path in (try? encoder.encode(group.info.proximityLightingPath)) == path }),
                  zones() == spaceZones else { return false }
            return true
        }
    }
}
