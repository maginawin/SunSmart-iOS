import Foundation
import NordicSigMeshSDK

let deviceDeletionCleanupCompletedNotification = Notification.Name("deviceDeletionCleanupCompleted")

final class DevicePermanentDeletionContext {
    private let node: Node
    private let createdTimestamp: Int64
    private let network: MeshNetwork?
    private let space: SpaceData?
    private let entry: SpaceDeletionJournal.Entry
    private let recoveryContext: SpaceRecoveryState?
    private static var activeEntries = Set<UUID>()
    private(set) var isPrepared = false
    private var didCommit = false

    /// Only the operation owning this prepared context may exclude its intent
    /// from the pending-deletion guard. Device UUIDs are not ownership tokens.
    var preparedEntryID: UUID? { isPrepared ? entry.id : nil }

    init(node: Node, space currentSpace: SpaceData? = nil) {
        self.node = node
        createdTimestamp = node.createdTimestamp
        network = node.network
        space = currentSpace ?? node.network.flatMap { network in
            SpaceData.load(siteId: network.uuid.uuidString).first { $0.meshNetworkId == node.subNetworkId }
        }
        entry = .init(id: UUID(), nodeUUID: node.uuid.uuidString,
                      primaryAddress: node.primaryUnicastAddress,
                      elementAddresses: ProximityLightingLifecycleCoordinator.topologyAddresses(for: node),
                      macAddress: node.macAddress, productId: node.productIdentifier)
        recoveryContext = space.flatMap { try? SpaceConfigurationSafety.recoveryState($0) }
        prepare()
    }

    private func prepare() {
        guard let space, let network,
              let recoveryContext, SpaceConfigurationSafety.isCurrent(recoveryContext, space: space),
              space.meshUUID == network.uuid.uuidString, space.meshNetworkId == node.subNetworkId,
              MeshNetworkManager.instance.meshNetwork === network,
              MeshNetworkManager.instance.currentNetworkKey.networkId.hex == space.meshNetworkId,
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
        var retainsEntry = false
        if SpaceConfigurationSafety.updateDeletionJournal(space, {
            $0.entries.removeAll { $0.id == entry.id && $0.stage == .prepared && $0.leaveReceipt == nil }
            retainsEntry = $0.entries.contains { $0.id == entry.id }
        }), !retainsEntry {
            // A retained receipt still belongs to this operation. Releasing its
            // ownership would make its own pending-deletion guard reject retry.
            isPrepared = false
            Self.activeEntries.remove(entry.id)
        }
    }

    deinit {
        Self.activeEntries.remove(entry.id)
        // An interrupted Reset with an absent Node must remain replayable.
        if let space, let recoveryContext, SpaceConfigurationSafety.isCurrent(recoveryContext, space: space),
           network?.nodes.contains(where: { $0.uuid == node.uuid }) == true {
            _ = SpaceConfigurationSafety.updateDeletionJournal(space) {
                $0.entries.removeAll { $0.id == entry.id && $0.stage == .prepared && $0.leaveReceipt == nil }
            }
        }
    }

    /// Persist before any local removal. A crash never causes a radio replay.
    func recordLeave(evidence: String) -> Bool {
        guard isPrepared, let space, let recoveryContext,
              SpaceConfigurationSafety.isCurrent(recoveryContext, space: space),
              node.createdTimestamp == createdTimestamp, node.primaryUnicastAddress == entry.primaryAddress,
              network?.nodes.contains(where: { $0 === node }) == true,
              (try? SpaceConfigurationSafety.deletionJournal(space).entries.contains { $0.id == entry.id && $0.stage == .prepared }) == true else { return false }
        return SpaceConfigurationSafety.updateDeletionJournal(space) { journal in
            guard let index = journal.entries.firstIndex(where: { $0.id == entry.id }) else { return }
            journal.entries[index].leaveReceipt = .init(evidence: evidence,
                notBefore: Date().timeIntervalSince1970 + 3, createdTimestamp: node.createdTimestamp)
        }
    }

    @discardableResult
    func prepareForForceRemoval() -> Bool {
        if !isPrepared { prepare() }
        return isPrepared
    }

    @discardableResult
    func forceRemove() -> ProximityLightingLifecycleResult? {
        guard removeLocally() else { return nil }
        return commit()
    }

    private func removeLocally() -> Bool {
        if !isPrepared { prepare() }
        guard isPrepared, let network, let space, let recoveryContext,
              SpaceConfigurationSafety.isCurrent(recoveryContext, space: space),
              !SpaceConfigurationSafety.hasPendingImport(space),
              MeshNetworkManager.instance.meshNetwork === network,
              MeshNetworkManager.instance.currentNetworkKey.networkId.hex == space.meshNetworkId,
              node.network == nil || node.network === network,
              node.createdTimestamp == createdTimestamp, node.primaryUnicastAddress == entry.primaryAddress,
              !network.nodes.contains(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress && $0 !== node }),
              node.delete() else { return false }
        network.remove(node: node)
        return true
    }

    struct BatchResult {
        var failed = Set<String>()
        var completed = Set<String>()
        var lifecycle: ProximityLightingLifecycleResult?
        var changed = false
        var cleanupPending = false
        var interrupted = false
    }

    /// Remove the selected instances before doing one Space-wide cleanup. Each
    /// removed Node already has a durable intent; absence is recoverable even if
    /// the process stops before the journal advances to `removed`.
    @MainActor
    static func forceRemoveBatch(_ contexts: [DevicePermanentDeletionContext],
                                 isCurrent: () -> Bool) async -> BatchResult {
        var result = BatchResult(failed: Set(contexts.map { $0.entry.nodeUUID }))
        guard let first = contexts.first, let space = first.space, let network = first.network,
              contexts.allSatisfy({ $0.space === space && $0.network === network }),
              isCurrent() else { result.interrupted = !contexts.isEmpty; return result }
        var removed: [DevicePermanentDeletionContext] = []
        var sliceStarted = ProcessInfo.processInfo.systemUptime
        for (index, context) in contexts.enumerated() {
            if context.didCommit {
                result.completed.insert(context.entry.nodeUUID)
                result.failed.remove(context.entry.nodeUUID)
                continue
            }
            if index > 0 && (index % 8 == 0 || ProcessInfo.processInfo.systemUptime - sliceStarted >= 0.008) {
                // Return to the main queue between durable mutations, never in
                // the middle of a database transaction or a shared-model write.
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
                guard isCurrent() else {
                    result.interrupted = true
                    result.cleanupPending = !removed.isEmpty
                    return result
                }
                sliceStarted = ProcessInfo.processInfo.systemUptime
            }
            if autoreleasepool(invoking: { context.removeLocally() }) {
                removed.append(context)
                result.changed = true
            } else {
                context.cancel()
            }
        }
        guard let representative = removed.first else { return result }
        guard isCurrent() else {
            result.interrupted = true; result.cleanupPending = true
            return result
        }
        let entryIDs = Set(removed.map { $0.entry.id })
        guard SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
            for index in journal.entries.indices where entryIDs.contains(journal.entries[index].id) {
                if journal.entries[index].stage != .cleaned { journal.entries[index].stage = .removed }
            }
        }) else { result.cleanupPending = true; return result }
        result.lifecycle = autoreleasepool {
            complete(entry: representative.entry, space: space)
        }
        let journal = try? SpaceConfigurationSafety.deletionJournal(space)
        let cleaned = Set(journal?.entries.filter { $0.stage == .cleaned }.map(\.id) ?? [])
        for context in removed where cleaned.contains(context.entry.id) {
            context.didCommit = true
            result.completed.insert(context.entry.nodeUUID)
            result.failed.remove(context.entry.nodeUUID)
        }
        result.cleanupPending = result.lifecycle == nil || removed.contains { !cleaned.contains($0.entry.id) }
            || SpaceConfigurationSafety.hasPendingDeletionCleanup(space)
        return result
    }

    @discardableResult
    func commit() -> ProximityLightingLifecycleResult? {
        guard isPrepared, !didCommit, let space,
              let recoveryContext, SpaceConfigurationSafety.isCurrent(recoveryContext, space: space),
              network?.nodes.contains(where: { $0.uuid == node.uuid }) == false else { return nil }
        if (try? SpaceConfigurationSafety.deletionJournal(space).entries.first { $0.id == entry.id }?.stage) == .cleaned {
            didCommit = true
            return nil
        }
        guard SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
            if let index = journal.entries.firstIndex(where: { $0.id == entry.id }) {
                journal.entries[index].stage = .removed
            }
        }) else { return nil }
        let result = Self.complete(entry: entry, space: space)
        didCommit = result != nil
        return result
    }

    /// A prepared intent is confirmed only by absence from its own persisted network.
    static func resume(space: SpaceData) {
        guard !SpaceConfigurationSafety.hasPendingImport(space),
              let journal = try? SpaceConfigurationSafety.deletionJournal(space),
              journal.entries.contains(where: { $0.stage != .cleaned && ($0.stage == .removed || !activeEntries.contains($0.id)) }),
              let persisted = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else { return }
        // A completed physical removal may still have a live UI context after
        // app-side cleanup failed. Its durable .removed stage permits recovery.
        var completionEntries: [SpaceDeletionJournal.Entry] = []
        var cancelledEntries = Set<UUID>()
        for entry in journal.entries where entry.stage != .cleaned && (entry.stage == .removed || !activeEntries.contains(entry.id)) {
            if let recorded = persisted.nodes.first(where: { isRecordedInstance($0, entry: entry) }) {
                if entry.leaveReceipt != nil {
                    guard entry.permitsLeaveRecovery(now: Date().timeIntervalSince1970,
                                                     createdTimestamp: recorded.createdTimestamp, address: recorded.primaryUnicastAddress),
                          let current = ProximityLightingTopologyContext.network(for: space),
                          !current.nodes.contains(where: {
                              $0.primaryUnicastAddress == entry.primaryAddress &&
                              (!isRecordedInstance($0, entry: entry) || $0.createdTimestamp != recorded.createdTimestamp)
                          }) else { continue }
                    autoreleasepool {
                        persisted.remove(node: recorded)
                        if let live = current.nodes.first(where: { isRecordedInstance($0, entry: entry) }) {
                            current.remove(node: live)
                        }
                    }
                    completionEntries.append(entry)
                    continue
                }
                if entry.stage == .prepared {
                    if entry.replacement != nil || entry.cloudRemoval != nil { continue } // Recheck authoritative evidence before retrying removal.
                    cancelledEntries.insert(entry.id)
                }
                continue
            }
            completionEntries.append(entry)
        }
        if !cancelledEntries.isEmpty {
            guard SpaceConfigurationSafety.updateDeletionJournal(space, {
                $0.entries.removeAll { cancelledEntries.contains($0.id) }
            }) else { return }
        }
        // An absent old instance may have had its addresses reused. It must not
        // prevent unrelated confirmed removals from sharing one completion.
        // complete() rechecks the selected entry against persisted state.
        if !completionEntries.isEmpty, let network = ProximityLightingTopologyContext.network(for: space),
           let completionEntry = completionEntries.first(where: { entry in
               !persisted.nodes.contains(where: {
                   isRecordedInstance($0, entry: entry) || !entry.elementAddresses.isDisjoint(
                       with: ProximityLightingLifecycleCoordinator.topologyAddresses(for: $0))
               }) && !network.nodes.contains(where: { isRecordedInstance($0, entry: entry) })
           }) {
            _ = autoreleasepool { complete(entry: completionEntry, space: space) }
        }
    }

    private static func complete(entry: SpaceDeletionJournal.Entry, space: SpaceData) -> ProximityLightingLifecycleResult? {
        guard !SpaceConfigurationSafety.hasPendingImport(space),
              space.lastUpdate < Int64.max, (space.lastUploadCloudTimestamp ?? 0) < Int64.max,
              let persisted = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
              let network = ProximityLightingTopologyContext.network(for: space),
              !persisted.nodes.contains(where: {
                  isRecordedInstance($0, entry: entry) || !entry.elementAddresses.isDisjoint(
                    with: ProximityLightingLifecycleCoordinator.topologyAddresses(for: $0))
              }),
              !network.nodes.contains(where: { isRecordedInstance($0, entry: entry) }) else { return nil }
        guard let journal = try? SpaceConfigurationSafety.deletionJournal(space) else { return nil }
        let removed = journal.entries.filter { candidate in
            candidate.stage != .cleaned && !persisted.nodes.contains { node in
                isRecordedInstance(node, entry: candidate) || !candidate.elementAddresses.isDisjoint(
                    with: ProximityLightingLifecycleCoordinator.topologyAddresses(for: node))
            }
        }
        let addresses = Set(removed.flatMap { $0.elementAddresses })
        guard removed.contains(where: { $0.id == entry.id }) else { return nil }
        var transaction = ProximityLightingLifecycleCoordinator.begin(space: space)
        transaction.removeConfirmedAddresses(addresses)
        let result = ProximityLightingLifecycleCoordinator.commit(
            transaction.prepare(), hasAdditionalLogicalChange: true,
            confirmedDeletionAddresses: addresses,
            applyAdditionalChanges: {
                try cleanExtensions(entries: removed, space: space, network: network)
                if let version = removed.compactMap({ $0.cloudRemoval?.remoteTimestamp }).max() {
                    guard version < Int64.max else { throw SpaceConfigurationSafety.SafetyError.persistenceFailed }
                    space.lastUpdate = max(space.lastUpdate, version + 1)
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
        guard readback.isValid, readback.normalized.repairs.isEmpty,
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
        if manager.meshNetwork === network, manager.currentNetworkKey.networkId.hex == space.meshNetworkId {
            manager.schedules = Schedule.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId)
            manager.switchs = DeviceSwitchData.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId)
        }
        NotificationCenter.default.post(name: deviceDeletionCleanupCompletedNotification, object: space)
        // The journal is now committed. Read its protection state once for this
        // immutable plan instead of decoding the same files for every survivor.
        let protection = SpaceConfigurationSafety.syncReadRequest(meshUUID: space.meshUUID, networkId: space.meshNetworkId).read()
        let datas = autoreleasepool {
            network.nodes.compactMap { node -> (node: Node, syncData: NodeSyncData)? in
                guard let data = node.getNodeSyncProximityLighting(topologyPlan: result.plan,
                                                                  protectionSnapshot: protection) else { return nil }
                return (node, data)
            }
        }
        #if DEBUG
        print("[DevicePermanentDeletion] space=\(space.id) nodes=\(removed.count) cleanup=complete proximityTasks=\(datas.count)")
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

    /// Read only this Space. Resolve the exact old key before touching a Node;
    /// a newly provisioned instance must never inherit an old deletion intent.
    static func cloudRemovalInstances(space: SpaceData,
                                      expected: [SpaceCloudNodeRemovalPolicy.Instance]) -> [SpaceCloudNodeRemovalPolicy.Instance]? {
        guard let network = ProximityLightingTopologyContext.network(for: space) else { return nil }
        var result: [SpaceCloudNodeRemovalPolicy.Instance] = []
        for var identity in expected {
            if let node = network.nodes.first(where: { $0.uuid.uuidString.uppercased() == identity.uuid
                && $0.primaryUnicastAddress == identity.address }) {
                guard let key = node.deviceKey, key.count == 16,
                      (try? SchedulerModelSnapshot.keyFingerprint(["deviceKey": key.hex])) == identity.keyFingerprint else { return nil }
                identity.elementAddresses = ProximityLightingLifecycleCoordinator.topologyAddresses(for: node)
            } else if let entry = try? SpaceConfigurationSafety.deletionJournal(space).entries.first(where: {
                $0.cloudRemoval?.instance.matches(identity) == true
            }) {
                identity.elementAddresses = entry.elementAddresses
            }
            guard !identity.elementAddresses.isEmpty,
                  network.nodes.allSatisfy({ node in
                      (node.uuid.uuidString.uppercased() == identity.uuid && node.primaryUnicastAddress == identity.address)
                        || identity.elementAddresses.isDisjoint(with: ProximityLightingLifecycleCoordinator.topologyAddresses(for: node))
                  }) else { return nil }
            result.append(identity)
        }
        return result
    }

    @discardableResult
    static func removeCloudInstances(space: SpaceData, instances: [SpaceCloudNodeRemovalPolicy.Instance],
                                     baselineTimestamp: Int64, remoteTimestamp: Int64, submissionID: UUID?) -> Bool {
        guard !instances.isEmpty, !SpaceConfigurationSafety.hasPendingImport(space),
              let checked = cloudRemovalInstances(space: space, expected: instances), checked == instances,
              let network = ProximityLightingTopologyContext.network(for: space),
              SpaceConfigurationSafety.checkpoint(space, refresh: !SpaceConfigurationSafety.hasPendingDeletionCleanup(space)) else { return false }
        var entries: [SpaceDeletionJournal.Entry] = []
        guard SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
            for identity in instances {
                if let existing = journal.entries.first(where: { $0.cloudRemoval?.instance == identity }) {
                    entries.append(existing)
                } else {
                    let node = network.nodes.first { $0.uuid.uuidString.uppercased() == identity.uuid && $0.primaryUnicastAddress == identity.address }
                    let entry = SpaceDeletionJournal.Entry(id: UUID(), nodeUUID: identity.uuid,
                        primaryAddress: identity.address, elementAddresses: identity.elementAddresses,
                        macAddress: node?.macAddress, productId: node?.productIdentifier,
                        cloudRemoval: .init(baselineTimestamp: baselineTimestamp, remoteTimestamp: remoteTimestamp,
                                            submissionID: submissionID, instance: identity))
                    journal.entries.append(entry); entries.append(entry)
                }
            }
        }) else { return false }
        for entry in entries where entry.stage != .cleaned {
            if let node = network.nodes.first(where: { $0.uuid.uuidString.uppercased() == entry.nodeUUID && $0.primaryUnicastAddress == entry.primaryAddress }) {
                guard node.delete() else { return false }
                network.remove(node: node)
            }
            guard let persisted = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
                  !persisted.nodes.contains(where: { $0.uuid.uuidString.uppercased() == entry.nodeUUID && $0.primaryUnicastAddress == entry.primaryAddress }),
                  SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
                      if let index = journal.entries.firstIndex(where: { $0.id == entry.id }) { journal.entries[index].stage = .removed }
                  }) else { return false }
        }
        // Complete as one batch after all Nodes have been removed.
        for entry in entries {
            if (try? SpaceConfigurationSafety.deletionJournal(space).entries.first(where: { $0.id == entry.id })?.stage) == .cleaned { continue }
            guard complete(entry: entry, space: space) != nil else { return false }
        }
        return true
    }

    private static func isRecordedInstance(_ node: Node, entry: SpaceDeletionJournal.Entry) -> Bool {
        node.uuid.uuidString.uppercased() == entry.nodeUUID.uppercased()
            && ((entry.cloudRemoval == nil && entry.leaveReceipt == nil) || node.primaryUnicastAddress == entry.primaryAddress)
    }

    private static func cleanExtensions(entries: [SpaceDeletionJournal.Entry], space: SpaceData, network: MeshNetwork) throws {
        let addresses = Set(entries.flatMap { $0.elementAddresses }).union(entries.map(\.primaryAddress))
        let primaryAddresses = Set(entries.map(\.primaryAddress))
        for scene in network.scenes where !addresses.isDisjoint(with: scene.addresses) {
            for address in addresses {
                while scene.addresses.contains(address) { scene.remove(address: address) }
            }
            guard scene.save() else { throw SpaceConfigurationSafety.SafetyError.persistenceFailed }
        }
        for schedule in Schedule.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId) {
            let active = schedule.nodeAddresses.filter { !addresses.contains($0) }
            let pending = schedule.needDeleteNodeAddresses.filter { !addresses.contains($0) }
            let bindings = schedule.nodeSlots?.filter { binding in
                !entries.contains { $0.nodeUUID.uppercased() == binding.identity.nodeUUID.uppercased()
                    && $0.primaryAddress.hex == binding.identity.unicastAddress }
            }
            if active != schedule.nodeAddresses || pending != schedule.needDeleteNodeAddresses || bindings != schedule.nodeSlots {
                schedule.nodeSlots = bindings
                schedule.nodeAddresses = active
                schedule.needDeleteNodeAddresses = pending
                guard schedule.save(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId) else {
                    throw SpaceConfigurationSafety.SafetyError.persistenceFailed
                }
            }
        }
        for group in network.groups where group.info.ambientLightSensorNodeAddress.map(primaryAddresses.contains) == true {
            group.info.ambientLightSensorNodeAddress = nil
            guard group.info.save(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else {
                throw SpaceConfigurationSafety.SafetyError.persistenceFailed
            }
        }
        for item in DeviceSwitchData.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId) {
            let decisions = primaryAddresses.map {
                KineticSwitchBindingPolicy.referenceCleanupDecision(node: $0,
                    current: item.proxyNodeAddress, pendingRemoval: item.deleteProxyNodeAddress)
            }
            guard decisions.contains(where: { $0.clearsCurrent || $0.clearsPendingRemoval }) else { continue }
            if decisions.contains(where: \.clearsCurrent) { item.proxyNodeAddress = nil }
            if decisions.contains(where: \.clearsCredentials) { item.enOceanMacAddress = nil; item.enOceanSecurityKey = nil }
            if decisions.contains(where: \.clearsPendingRemoval) { item.deleteProxyNodeAddress = nil }
            guard item.save(meshUUID: space.meshUUID, networkId: space.meshNetworkId) else {
                throw SpaceConfigurationSafety.SafetyError.persistenceFailed
            }
        }
        // Gateway identity is Site-wide: moving a node must not delete its new owner's association.
        for entry in entries where entry.replacement == nil && entry.cloudRemoval == nil {
            if let mac = entry.macAddress { GatewayModel.delete(siteId: space.siteId, macAddress: mac) }
        }
        for productId in Set(entries.compactMap(\.productId)) {
            guard let distribution = MeshDistributionData.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId, productId: productId),
                  entries.contains(where: { $0.productId == productId && $0.primaryAddress == distribution.distributionAddress }) else { continue }
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
