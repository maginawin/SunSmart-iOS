import Foundation
import NordicSigMeshSDK

let deviceDeletionCleanupCompletedNotification = Notification.Name("deviceDeletionCleanupCompleted")

final class DevicePermanentDeletionContext {
    private let node: Node
    private let network: MeshNetwork?
    private let space: SpaceData?
    private let entry: SpaceDeletionJournal.Entry
    private let recoveryContext: SpaceRecoveryState?
    private static var activeEntries = Set<UUID>()
    private(set) var isPrepared = false
    private var didCommit = false
    enum Outcome { case notRemoved, removedPendingCleanup, cleaned }
    private(set) var outcome = Outcome.notRemoved
    var wasRemoved: Bool { outcome != .notRemoved }

    var canReset: Bool {
        guard isPrepared, let space, let network,
              let recoveryContext, SpaceConfigurationSafety.isCurrent(recoveryContext, space: space),
              !SpaceConfigurationSafety.hasPendingImport(space),
              MeshNetworkManager.instance.meshNetwork === network,
              MeshNetworkManager.instance.currentNetworkKey.networkId.hex == space.meshNetworkId,
              MeshLibManager.manager.isMeshNetworkConnected,
              let persisted = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
              persisted.nodes.contains(where: {
                  $0.uuid.uuidString == entry.nodeUUID && $0.primaryUnicastAddress == entry.primaryAddress
                      && $0.createdTimestamp == entry.createdTimestamp
              }) else { return false }
        if case .success = SpaceMeshKeyStore.export(network: network, networkId: space.meshNetworkId) { return true }
        return false
    }

    init(node: Node, space currentSpace: SpaceData? = nil) {
        self.node = node
        network = node.network
        space = currentSpace ?? node.network.flatMap { network in
            SpaceData.load(siteId: network.uuid.uuidString).first { $0.meshNetworkId == node.subNetworkId }
        }
        entry = .init(id: UUID(), nodeUUID: node.uuid.uuidString,
                      primaryAddress: node.primaryUnicastAddress,
                      elementAddresses: ProximityLightingLifecycleCoordinator.topologyAddresses(for: node),
                      macAddress: node.macAddress, productId: node.productIdentifier,
                      createdTimestamp: node.createdTimestamp)
        recoveryContext = space.flatMap { try? SpaceConfigurationSafety.recoveryState($0) }
        prepare()
    }

    private func prepare() {
        guard let space, let network,
              let recoveryContext, SpaceConfigurationSafety.isCurrent(recoveryContext, space: space),
              space.meshUUID == network.uuid.uuidString, space.meshNetworkId == node.subNetworkId,
              !node.isProvisioner, !node.isLocalProvisioner,
              SpaceConfigurationSafety.canDeleteDeviceRecords(space),
              !SpaceConfigurationSafety.hasPendingImport(space),
              SpaceConfigurationSafety.checkpoint(space,
                refresh: (try? SpaceConfigurationSafety.deletionJournal(space).needsCleanup) == false) else { return }
        isPrepared = SpaceConfigurationSafety.updateDeletionJournal(space) {
            if !$0.entries.contains(where: { $0.id == entry.id }) { $0.entries.append(entry) }
        }
        if isPrepared { Self.activeEntries.insert(entry.id) }
    }

    func cancel() {
        // Reset may already have removed the Node even if a timeout is also
        // reported. Do not discard the only durable evidence of that deletion.
        guard let space, let recoveryContext, SpaceConfigurationSafety.isCurrent(recoveryContext, space: space),
              network?.nodes.contains(where: { $0.uuid == node.uuid }) == true else { return }
        if SpaceConfigurationSafety.updateDeletionJournal(space, {
            $0.entries.removeAll { $0.id == entry.id && $0.stage == .prepared }
        }) { isPrepared = false; Self.activeEntries.remove(entry.id) }
    }

    deinit {
        Self.activeEntries.remove(entry.id)
        // An interrupted Reset with an absent Node must remain replayable.
        if let space, let recoveryContext, SpaceConfigurationSafety.isCurrent(recoveryContext, space: space),
           network?.nodes.contains(where: { $0.uuid == node.uuid }) == true {
            _ = SpaceConfigurationSafety.updateDeletionJournal(space) {
                $0.entries.removeAll { $0.id == entry.id && $0.stage == .prepared }
            }
        }
    }

    @discardableResult
    func prepareForForceRemoval() -> Bool {
        if !isPrepared { prepare() }
        return isPrepared
    }

    @discardableResult
    func forceRemove() -> ProximityLightingLifecycleResult? {
        guard !didCommit else { return nil }
        if wasRemoved { return commit() }
        if !isPrepared { prepare() }
        guard isPrepared, let network, let space, let recoveryContext,
              SpaceConfigurationSafety.isCurrent(recoveryContext, space: space) else { return nil }
        guard SpaceConfigurationSafety.canDeleteDeviceRecords(space),
              SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
                  if let index = journal.entries.firstIndex(where: { $0.id == entry.id }) {
                      journal.entries[index].stage = .forceRequested
                  }
              }), Self.removeInstance(entry, space: space, retainedNetwork: network) else { return nil }
        return commit()
    }

    @discardableResult
    func commit() -> ProximityLightingLifecycleResult? {
        guard isPrepared, !didCommit, let space,
              let recoveryContext, SpaceConfigurationSafety.isCurrent(recoveryContext, space: space) else { return nil }
        guard let persisted = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
              !persisted.nodes.contains(where: { $0.uuid.uuidString == entry.nodeUUID }) else { return nil }
        outcome = .removedPendingCleanup
        if (try? SpaceConfigurationSafety.deletionJournal(space).entries.first { $0.id == entry.id }?.stage) == .cleaned {
            didCommit = true
            outcome = .cleaned
            return nil
        }
        guard SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
            if let index = journal.entries.firstIndex(where: { $0.id == entry.id }) {
                journal.entries[index].stage = .removed
            }
        }) else { return nil }
        let result = Self.complete(entry: entry, space: space)
        didCommit = result != nil
        if didCommit { outcome = .cleaned }
        return result
    }

    /// A prepared intent is confirmed only by absence from its own persisted network.
    static func hasActiveOperation(space: SpaceData) -> Bool {
        guard let journal = try? SpaceConfigurationSafety.deletionJournal(space) else { return true }
        return journal.entries.contains { activeEntries.contains($0.id) }
    }

    static func resume(space: SpaceData) {
        guard SpaceConfigurationSafety.canDeleteDeviceRecords(space),
              !SpaceConfigurationSafety.hasPendingImport(space),
              let journal = try? SpaceConfigurationSafety.deletionJournal(space),
              journal.entries.contains(where: { $0.stage != .cleaned && !activeEntries.contains($0.id) }),
              let persisted = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else { return }
        for entry in journal.entries where entry.stage != .cleaned && !activeEntries.contains(entry.id) {
            if entry.stage == .forceRequested {
                guard removeInstance(entry, space: space, retainedNetwork: nil) else { continue }
                _ = complete(entry: entry, space: space)
                continue
            }
            if persisted.nodes.contains(where: { $0.uuid.uuidString == entry.nodeUUID }) {
                if entry.stage == .prepared {
                    if entry.replacement != nil { continue } // Reconciler retries only after checking the new owner.
                    _ = SpaceConfigurationSafety.updateDeletionJournal(space) {
                        $0.entries.removeAll { $0.id == entry.id }
                    }
                }
                continue
            }
            _ = complete(entry: entry, space: space)
        }
    }

    /// SDK deletion is address based. Revalidate the complete Site immediately
    /// before calling it, rejecting address reuse and ambiguous ownership. No
    /// suspension is allowed between validation, removal and persisted readback.
    private static func removeInstance(_ entry: SpaceDeletionJournal.Entry, space: SpaceData,
                                       retainedNetwork: MeshNetwork?) -> Bool {
        guard let persisted = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
              let siteNetwork = MeshNetwork.load(meshUUID: space.meshUUID),
              siteNetwork.nodes.filter({ $0.primaryUnicastAddress == entry.primaryAddress }).allSatisfy({
                  $0.uuid.uuidString == entry.nodeUUID && $0.subNetworkId == space.meshNetworkId
                    && (entry.createdTimestamp == nil || $0.createdTimestamp == entry.createdTimestamp)
              }) else { return false }
        guard let current = persisted.nodes.first(where: { $0.uuid.uuidString == entry.nodeUUID }) else {
            return !siteNetwork.nodes.contains { $0.primaryUnicastAddress == entry.primaryAddress }
        }
        guard current.primaryUnicastAddress == entry.primaryAddress,
              current.subNetworkId == space.meshNetworkId,
              entry.createdTimestamp == nil || current.createdTimestamp == entry.createdTimestamp else { return false }
        let manager = MeshNetworkManager.instance
        let active = manager.meshNetwork.flatMap { network -> MeshNetwork? in
            network.uuid == persisted.uuid && manager.currentNetworkKey.networkId.hex == space.meshNetworkId ? network : nil
        }
        let retainedNetwork = active ?? retainedNetwork
        // Prefer the retained UI network only if it still contains this exact
        // provisioning instance; never resolve the target through Key index.
        if let retainedNetwork, retainedNetwork.uuid == persisted.uuid,
           let retained = retainedNetwork.nodes.first(where: {
               $0.uuid == current.uuid && $0.primaryUnicastAddress == current.primaryUnicastAddress
                   && $0.subNetworkId == current.subNetworkId && $0.createdTimestamp == current.createdTimestamp
           }) {
            retainedNetwork.remove(node: retained)
        } else {
            persisted.remove(node: current)
        }
        guard let readback = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else { return false }
        return !readback.nodes.contains { $0.uuid.uuidString == entry.nodeUUID || $0.primaryUnicastAddress == entry.primaryAddress }
    }

    private static func complete(entry: SpaceDeletionJournal.Entry, space: SpaceData) -> ProximityLightingLifecycleResult? {
        guard !SpaceConfigurationSafety.hasPendingImport(space),
              space.lastUpdate < Int64.max, (space.lastUploadCloudTimestamp ?? 0) < Int64.max,
              let persisted = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
              !persisted.nodes.contains(where: {
                  $0.uuid.uuidString == entry.nodeUUID || !entry.elementAddresses.isDisjoint(
                    with: ProximityLightingLifecycleCoordinator.topologyAddresses(for: $0))
              }) else { return nil }
        let network = persisted
        ProximityLightingTopologyContext.loadGroupInfo(network: network, space: space)
        guard let journal = try? SpaceConfigurationSafety.deletionJournal(space) else { return nil }
        let removed = journal.entries.filter { candidate in
            candidate.stage != .cleaned && !persisted.nodes.contains { node in
                node.uuid.uuidString == candidate.nodeUUID || !candidate.elementAddresses.isDisjoint(
                    with: ProximityLightingLifecycleCoordinator.topologyAddresses(for: node))
            }
        }
        let addresses = Set(removed.flatMap { $0.elementAddresses })
        guard removed.contains(where: { $0.id == entry.id }) else { return nil }
        var transaction = ProximityLightingLifecycleCoordinator.begin(space: space,
            groups: network.groups.filter { !$0.isVirtual },
            nodes: ProximityLightingTopologyContext.realNodes(in: network), network: network)
        transaction.removeConfirmedAddresses(addresses)
        let preparation = transaction.prepare()
        let result = ProximityLightingLifecycleCoordinator.commit(
            preparation, hasAdditionalLogicalChange: true,
            confirmedDeletionAddresses: addresses,
            applyAdditionalChanges: {
                for removedEntry in removed {
                    try cleanExtensions(entry: removedEntry, space: space, network: network)
                }
                let nodes = ProximityLightingTopologyContext.realNodes(in: network)
                space.deviceCount = nodes.count
                space.luminairesCount = nodes.filter { $0.deviceType == .light }.count
            })
        guard let result,
              let savedSpace = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
              let savedNetwork = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else {
            SpaceConfigurationSafety.block(space, reason: "deletionCleanupPending")
            return nil
        }
        ProximityLightingTopologyContext.loadGroupInfo(network: savedNetwork, space: savedSpace)
        let readback = ProximityLightingLifecycleCoordinator.begin(space: savedSpace,
            groups: savedNetwork.groups.filter { !$0.isVirtual },
            nodes: ProximityLightingTopologyContext.realNodes(in: savedNetwork), network: savedNetwork).prepare()
        guard readback.sourceSnapshot == preparation.deletionSnapshot,
              savedNetwork.scenes.allSatisfy({ addresses.isDisjoint(with: $0.addresses) }),
              Schedule.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId).allSatisfy({
                  addresses.isDisjoint(with: $0.nodeAddresses) && addresses.isDisjoint(with: $0.needDeleteNodeAddresses)
              }),
              SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
                  for index in journal.entries.indices where removed.contains(where: { $0.id == journal.entries[index].id }) {
                      journal.entries[index].stage = .cleaned
                      journal.entries[index].completedTimestamp = space.lastUpdate
                  }
              }) else {
            SpaceConfigurationSafety.block(space, reason: "deletionCleanupPending")
            return nil
        }
        network.nodes.forEach { $0.clearSyncStateCache() }
        let manager = MeshNetworkManager.instance
        if let active = manager.meshNetwork, active.uuid == network.uuid,
           manager.currentNetworkKey.networkId.hex == space.meshNetworkId {
            let schedules = Schedule.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId)
            for group in active.groups where group.subNetworkId == space.meshNetworkId {
                if let saved = network.groups.first(where: { $0.address.address == group.address.address }) {
                    group.info = saved.info
                    // GroupInfo.load omits this derived cache. Use persisted
                    // addresses/scene bindings, independent of the active manager.
                    group.info.bindSchedules = schedules.filter { schedule in
                        schedule.groupAddresses.contains(group.address.address) ||
                        schedule.needDeleteGroupAddresses.contains(group.address.address) ||
                        group.info.sceneExecuteDatas.contains { $0.sceneNumber == schedule.sceneNumber }
                    }
                }
            }
            active.nodes.filter { $0.subNetworkId == space.meshNetworkId }.forEach { $0.clearSyncStateCache() }
            manager.schedules = schedules
            manager.switchs = DeviceSwitchData.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId)
            manager.dongles = DeviceDongleData.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId)
        }
        NotificationCenter.default.post(name: deviceDeletionCleanupCompletedNotification, object: space)
        let datas = network.nodes.compactMap { node -> (node: Node, syncData: NodeSyncData)? in
            guard readback.isValid, readback.normalized.repairs.isEmpty,
                  let data = node.getNodeSyncProximityLighting(topologyPlan: result.plan) else { return nil }
            return (node, data)
        }
        #if DEBUG
        print("[DevicePermanentDeletion] space=\(space.id) node=\(entry.primaryAddress.hex) cleanup=complete proximityTasks=\(datas.count)")
        #endif
        return .init(didChange: result.didChange, plan: result.plan,
                     affectedDeviceAddresses: result.affectedDeviceAddresses,
                     syncDatas: datas, repairs: result.repairs)
    }

    /// Remove a superseded provisioning instance from its own persisted Space.
    /// No Mesh Reset is sent, and the currently connected subnet is never switched.
    @discardableResult
    static func removeSuperseded(node: Node, space: SpaceData,
                                 replacement: SiteDeviceOwnershipPolicy.Instance) -> Bool {
        guard let network = node.network, network.uuid.uuidString == space.meshUUID,
              node.subNetworkId == space.meshNetworkId, replacement.siteId == space.siteId,
              replacement.spaceId != space.id, replacement.address != node.primaryUnicastAddress,
              SiteDeviceOwnershipPolicy.normalizedMAC(node.macAddress) == replacement.mac,
              !SpaceConfigurationSafety.hasPendingImport(space),
              SpaceConfigurationSafety.checkpoint(space, refresh: true) else { return false }
        let existing = try? SpaceConfigurationSafety.deletionJournal(space).entries.first {
            $0.nodeUUID == node.uuid.uuidString && $0.primaryAddress == node.primaryUnicastAddress && $0.replacement != nil && $0.stage != .cleaned
        }
        var intent = existing ?? SpaceDeletionJournal.Entry(id: UUID(), nodeUUID: node.uuid.uuidString,
            primaryAddress: node.primaryUnicastAddress,
            elementAddresses: ProximityLightingLifecycleCoordinator.topologyAddresses(for: node),
            macAddress: node.macAddress, productId: node.productIdentifier)
        intent.replacement = replacement
        guard SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
            journal.entries.removeAll { $0.id == intent.id }
            journal.entries.append(intent)
        }) else { return false }
        // SDK removal clears Scene element addresses. Persist/read back the Node
        // deletion before committing app-side schedule and topology cleanup.
        guard node.delete() else { return false }
        network.remove(node: node)
        guard let persisted = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
              !persisted.nodes.contains(where: { $0.uuid.uuidString == intent.nodeUUID && $0.primaryUnicastAddress == intent.primaryAddress }) else { return false }
        guard SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
            if let index = journal.entries.firstIndex(where: { $0.id == intent.id }) { journal.entries[index].stage = .removed }
        }) else { return false }
        return complete(entry: intent, space: space) != nil
    }

    private static func cleanExtensions(entry: SpaceDeletionJournal.Entry, space: SpaceData, network: MeshNetwork) throws {
        for scene in network.scenes where !entry.elementAddresses.isDisjoint(with: scene.addresses) {
            for address in entry.elementAddresses {
                while scene.addresses.contains(address) { scene.remove(address: address) }
            }
            guard scene.save() else { throw SpaceConfigurationSafety.SafetyError.persistenceFailed }
        }
        for schedule in Schedule.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId) {
            let addresses = entry.elementAddresses.union([entry.primaryAddress])
            let active = schedule.nodeAddresses.filter { !addresses.contains($0) }
            let pending = schedule.needDeleteNodeAddresses.filter { !addresses.contains($0) }
            if active != schedule.nodeAddresses || pending != schedule.needDeleteNodeAddresses {
                schedule.nodeAddresses = active
                schedule.needDeleteNodeAddresses = pending
                guard schedule.save(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId) else {
                    throw SpaceConfigurationSafety.SafetyError.persistenceFailed
                }
            }
        }
        for group in network.groups where group.info.ambientLightSensorNodeAddress == entry.primaryAddress {
            group.info.ambientLightSensorNodeAddress = nil
            guard group.info.save(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else {
                throw SpaceConfigurationSafety.SafetyError.persistenceFailed
            }
        }
        for item in DeviceSwitchData.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId) {
            let decision = KineticSwitchBindingPolicy.referenceCleanupDecision(node: entry.primaryAddress,
                current: item.proxyNodeAddress, pendingRemoval: item.deleteProxyNodeAddress)
            guard decision.clearsCurrent || decision.clearsPendingRemoval else { continue }
            if decision.clearsCurrent { item.proxyNodeAddress = nil }
            if decision.clearsCredentials { item.enOceanMacAddress = nil; item.enOceanSecurityKey = nil }
            if decision.clearsPendingRemoval { item.deleteProxyNodeAddress = nil }
            guard item.save(meshUUID: space.meshUUID, networkId: space.meshNetworkId) else {
                throw SpaceConfigurationSafety.SafetyError.persistenceFailed
            }
        }
        for dongle in DeviceDongleData.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId)
            where dongle.bindNodeAddress == entry.primaryAddress {
            dongle.bindNodeAddress = nil
            guard dongle.save(meshUUID: space.meshUUID, networkId: space.meshNetworkId) else {
                throw SpaceConfigurationSafety.SafetyError.persistenceFailed
            }
        }
        // Gateway identity is Site-wide: moving a node must not delete its new owner's association.
        if entry.replacement == nil, let mac = entry.macAddress,
           let identity = SiteDeviceOwnershipPolicy.normalizedMAC(mac) {
            guard let siteNetwork = MeshNetwork.load(meshUUID: space.meshUUID) else {
                throw SpaceConfigurationSafety.SafetyError.persistenceFailed
            }
            if !siteNetwork.nodes.contains(where: { SiteDeviceOwnershipPolicy.normalizedMAC($0.macAddress) == identity }) {
                GatewayModel.delete(siteId: space.siteId, macAddress: mac)
            }
        }
        if let productId = entry.productId,
           let distribution = MeshDistributionData.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId, productId: productId),
           distribution.distributionAddress == entry.primaryAddress {
            distribution.delete(meshUUID: space.meshUUID, networkId: space.meshNetworkId, productId: productId)
        }
    }

    static func showCompletion(space: SpaceData) {
        if SpaceConfigurationSafety.hasPendingDeletionCleanup(space) {
            XWHUDManager.showErrorTipHUD("configuration_deletion_cleanup_pending".localizedString)
        } else {
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
        }
    }

    static func showCompletion(contexts: [DevicePermanentDeletionContext]) {
        if contexts.contains(where: { $0.space.map(SpaceConfigurationSafety.hasPendingDeletionCleanup) ?? true }) {
            XWHUDManager.showErrorTipHUD("configuration_deletion_cleanup_pending".localizedString)
        } else {
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
        }
    }
}

/// Switch rows are Space records, not lookups through the active Mesh Key.
/// Record deletion and deferred virtual-group cleanup have separate receipts.
enum SwitchRecordDeletion {
    @discardableResult
    static func remove(_ selection: DeviceSwitchData, space: SpaceData, force: Bool) -> Bool {
        guard SpaceConfigurationSafety.canDeleteDeviceRecords(space),
              !SpaceConfigurationSafety.hasPendingImport(space),
              selection.recordScope == .init(meshUUID: space.meshUUID, networkId: space.meshNetworkId),
              let records = try? DeviceSwitchData.loadForDeletion(meshUUID: space.meshUUID, networkId: space.meshNetworkId),
              let current = records.first(where: { $0.id == selection.id }),
              current.deletionFingerprint == selection.deletionFingerprint,
              let network = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
              SpaceConfigurationSafety.checkpoint(space) else { return false }

        // A real Power Switch is deleted through the existing durable Node path.
        // A lighting proxy is never treated as the device represented by this row.
        if let address = current.proxyNodeAddress,
           let node = network.nodes.first(where: { $0.primaryUnicastAddress == address && $0.subNetworkId == space.meshNetworkId }),
           node.isPowerSwitch {
            let manager = MeshNetworkManager.instance
            let active = current.recordScope?.matches(manager) == true
                ? manager.meshNetwork?.nodes.first(where: { $0.uuid == node.uuid && $0.createdTimestamp == node.createdTimestamp }) : nil
            let context = DevicePermanentDeletionContext(node: active ?? node, space: space)
            guard context.isPrepared else { return false }
            if !force {
                guard context.canReset else { context.cancel(); return false }
                do { try MeshAPI.resetNodeWithoutWaitingForStatus(address: address) }
                catch { context.cancel(); return false }
            }
            _ = context.forceRemove()
            guard context.outcome == .cleaned else { return false }
        }
        guard let row = DeviceSwitchData.load(meshUUID: space.meshUUID,
                meshNetworkId: space.meshNetworkId, id: selection.id).first,
              !row.deletionFingerprint.isEmpty else { return false }
        let existing = try? SpaceConfigurationSafety.deletionJournal(space).switches?.first {
            $0.switchId == row.id && $0.completedTimestamp == nil
        }
        let entry = existing?.fingerprint == row.deletionFingerprint ? existing! :
            SpaceDeletionJournal.SwitchEntry(id: UUID(), switchId: row.id, fingerprint: row.deletionFingerprint)
        guard SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
                  var entries = (journal.switches ?? []).filter {
                      $0.switchId != row.id || $0.completedTimestamp != nil || $0.id == entry.id
                  }
                  if !entries.contains(where: { $0.id == entry.id }) { entries.append(entry) }
                  journal.switches = entries
              }) else { return false }
        let completed = complete(entry, space: space)
        if completed { cleanVirtualGroups(space: space) }
        return completed
    }

    static func resume(space: SpaceData) {
        guard SpaceConfigurationSafety.canDeleteDeviceRecords(space),
              !SpaceConfigurationSafety.hasPendingImport(space),
              let journal = try? SpaceConfigurationSafety.deletionJournal(space) else { return }
        for entry in journal.switches ?? [] where entry.completedTimestamp == nil { _ = complete(entry, space: space) }
        cleanVirtualGroups(space: space)
    }

    private static func complete(_ entry: SpaceDeletionJournal.SwitchEntry, space: SpaceData) -> Bool {
        guard SunSmartDataManager.shared.db != nil,
              space.lastUpdate < Int64.max, (space.lastUploadCloudTimestamp ?? 0) < Int64.max,
              let network = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
              let siteNetwork = MeshNetwork.load(meshUUID: space.meshUUID) else { return false }
        guard let records = try? DeviceSwitchData.loadForDeletion(meshUUID: space.meshUUID, networkId: space.meshNetworkId) else { return false }
        if let row = records.first(where: { $0.id == entry.switchId }) {
            guard row.deletionFingerprint == entry.fingerprint else { return false }
            let addresses = KineticSwitchBindingPolicy.cleanupProxyAddresses(
                current: row.proxyNodeAddress, pendingRemoval: row.deleteProxyNodeAddress)
            for address in addresses {
                let peers = siteNetwork.nodes.filter { $0.primaryUnicastAddress == address }
                guard peers.allSatisfy({ $0.subNetworkId == space.meshNetworkId }) else { return false }
                if let proxy = network.nodes.first(where: { $0.primaryUnicastAddress == address }),
                   let mac = row.enOceanMacAddress, !mac.isEmpty, proxy.enOceanMacAddress == mac {
                    proxy.enOceanMacAddress = nil
                    proxy.enOceanProxySwitchKeys = []
                    guard proxy.savePropertys(),
                          let persistedProxy = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId)?.nodes.first(where: { $0.uuid == proxy.uuid }),
                          persistedProxy.enOceanMacAddress?.isEmpty != false,
                          persistedProxy.enOceanProxySwitchKeys.isEmpty else { return false }
                    let manager = MeshNetworkManager.instance
                    if row.recordScope?.matches(manager) == true,
                       let activeProxy = manager.meshNetwork?.nodes.first(where: { $0.uuid == proxy.uuid && $0.createdTimestamp == proxy.createdTimestamp }) {
                        activeProxy.enOceanMacAddress = nil
                        activeProxy.enOceanProxySwitchKeys = []
                    }
                }
            }
            // Persist the deferred work before deleting the row. Remote models
            // may remain subscribed after Force Delete; they must not keep the
            // Switch record or the Space's Mesh/upload barrier alive.
            let linked = Set([row.linkGroupAddress, row.subLinkGroupAddress].compactMap { $0 })
            let otherLinks = Set(records.filter { $0.id != row.id }.flatMap {
                [$0.linkGroupAddress, $0.subLinkGroupAddress].compactMap { $0 }
            })
            let groupAddresses = network.groups.filter {
                $0.isVirtual && $0.subNetworkId == space.meshNetworkId && linked.subtracting(otherLinks).contains($0.address.address)
            }.map { $0.address.address }
            guard SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
                journal.pendingVirtualGroupAddresses = (journal.pendingVirtualGroupAddresses ?? []).union(groupAddresses)
            }) else { return false }
            let timestamp = space.lastUpdate
            let count = space.switchesCount
            let saved = SunSmartDataManager.shared.configurationTransaction {
                guard PJEightKeySwitchRepository.shared.delete(for: row, meshUUID: space.meshUUID, networkId: space.meshNetworkId),
                      row.delete(meshUUID: space.meshUUID, networkId: space.meshNetworkId) else {
                    throw SpaceConfigurationSafety.SafetyError.persistenceFailed
                }
                space.switchesCount = records.count - 1
                space.markLocalChangePendingCloudSync()
                guard space.save() else { throw SpaceConfigurationSafety.SafetyError.persistenceFailed }
            }
            guard saved else { space.lastUpdate = timestamp; space.switchesCount = count; return false }
        }
        guard let readback = try? DeviceSwitchData.loadForDeletion(meshUUID: space.meshUUID, networkId: space.meshNetworkId),
              !readback.contains(where: { $0.id == entry.switchId }),
              PJEightKeySwitchRepository.shared.recordIsAbsent(switchId: entry.switchId,
                meshUUID: space.meshUUID, networkId: space.meshNetworkId),
              let savedSpace = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
              SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
                  if let index = journal.switches?.firstIndex(where: { $0.id == entry.id }) {
                      journal.switches?[index].completedTimestamp = savedSpace.lastUpdate
                  }
              }) else { return false }
        space.switchesCount = savedSpace.switchesCount
        space.lastUpdate = savedSpace.lastUpdate
        let manager = MeshNetworkManager.instance
        if DeviceSwitchData.RecordScope(meshUUID: space.meshUUID, networkId: space.meshNetworkId).matches(manager) {
            manager.switchs = DeviceSwitchData.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId)
        }
        #if DEBUG
        print("[SwitchRecordDeletion] site=\(space.siteId) space=\(space.id) switch=\(entry.switchId) remaining=\(space.switchesCount) result=cleaned")
        #endif
        return true
    }

    private static func cleanVirtualGroups(space: SpaceData) {
        guard let addresses = try? SpaceConfigurationSafety.deletionJournal(space).pendingVirtualGroupAddresses,
              !addresses.isEmpty,
              let network = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
              let siteNetwork = MeshNetwork.load(meshUUID: space.meshUUID),
              let records = try? DeviceSwitchData.loadForDeletion(meshUUID: space.meshUUID, networkId: space.meshNetworkId)
        else { return }
        let links = Set(records.flatMap { [$0.linkGroupAddress, $0.subLinkGroupAddress].compactMap { $0 } })
        var completed = Set<Address>()
        for address in addresses {
            // A new/shared Switch or another Space may now own the address.
            // Retain its subscriptions and re-evaluate on a later scoped replay.
            guard !links.contains(address),
                  siteNetwork.groups.filter({ $0.address.address == address }).allSatisfy({ $0.subNetworkId == space.meshNetworkId })
            else { continue }
            if let group = network.groups.first(where: { $0.address.address == address }) {
                guard group.isVirtual, group.subNetworkId == space.meshNetworkId else { continue }
                for element in network.localProvisioner?.node?.elements ?? [] {
                    for model in element.models where model.isSubscribed(to: group) { model.unsubscribe(from: group) }
                }
                if let local = network.localProvisioner?.node, !local.save() { continue }
                guard !group.isUsed, group.delete() else { continue }
                do { try network.remove(group: group) } catch { continue }
                guard let persisted = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
                      !persisted.groups.contains(where: { $0.address.address == address }) else { continue }
            }
            // Also repair an active cache left behind by an interruption after
            // the persisted group was deleted.
            let manager = MeshNetworkManager.instance
            if DeviceSwitchData.RecordScope(meshUUID: space.meshUUID, networkId: space.meshNetworkId).matches(manager),
               let active = manager.meshNetwork,
               let activeGroup = active.groups.first(where: { $0.address.address == address && $0.subNetworkId == space.meshNetworkId }) {
                guard activeGroup.isVirtual else { continue }
                for element in active.localProvisioner?.node?.elements ?? [] {
                    for model in element.models where model.isSubscribed(to: activeGroup) { model.unsubscribe(from: activeGroup) }
                }
                do { try active.remove(group: activeGroup) } catch { continue }
            }
            completed.insert(address)
        }
        if !completed.isEmpty {
            _ = SpaceConfigurationSafety.updateDeletionJournal(space, blocksOnFailure: false) {
                $0.pendingVirtualGroupAddresses?.subtract(completed)
            }
        }
    }
}
