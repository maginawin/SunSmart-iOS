import Foundation
import UIKit
import NordicSigMeshSDK
import SwiftyJSON

/// App adapter. Mesh transport, the Space journal and Site Gateway receipts have
/// different success semantics; keep them separate until the final barrier.
@MainActor
final class LightsBatchDeletionOperation {
    struct Outcome {
        var failed = Set<String>()
        var lifecycle: [ProximityLightingLifecycleResult] = []
        var errorKey: String?
        var cleanupPending = false
        var changed = false
    }
    let site: SiteData
    let space: SpaceData
    let network: MeshNetwork
    private(set) var allNodes: [Node]
    let switches: [DeviceSwitchData]
    let gateway: GatewayModel?
    private let siteNetwork: MeshNetwork?
    private let manager: MeshNetworkManager
    private let account = UserData.currentUserId
    private let region = String(describing: UserData.currentServerRegion)
    private let executor = LightsBatchDeletionExecutor()
    private let recoveryContext: SpaceRecoveryState?
    private var backgroundObserver: NSObjectProtocol?
    private var contexts: [String: DevicePermanentDeletionContext] = [:]
    private var selected = Set<String>()
    private var deletesAll = false
    private var cancelled = false
    private var gatewayRemoved = false
    private var didRun = false
    private var acknowledged = Set<String>()
    private var latestLifecycle: ProximityLightingLifecycleResult?

    init?(site: SiteData, space: SpaceData) {
        let manager = MeshNetworkManager.instance
        guard let network = manager.meshNetwork, network.uuid.uuidString == space.meshUUID,
              manager.currentNetworkKey.networkId.hex == space.meshNetworkId else { return nil }
        self.site = site; self.space = space; self.network = network; self.manager = manager
        recoveryContext = try? SpaceConfigurationSafety.recoveryState(space)
        allNodes = network.nodes.filter { !$0.isLocalProvisioner && !$0.isProvisioner && $0.subNetworkId == space.meshNetworkId }
        switches = DeviceSwitchData.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId)
        siteNetwork = MeshNetwork.load(meshUUID: site.meshUUID, subnetworkId: site.meshNetworkId)
        gateway = space.relevanceGatewayId.flatMap { GatewayModel.load(siteId: site.id, macAddress: $0).first }
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cancel() }
            }
    }

    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
    }

    var additionalConfigurationCount: Int {
        switches.filter { configuration in
            !allNodes.contains { $0.isPowerSwitch && $0.primaryUnicastAddress == configuration.proxyNodeAddress }
        }.count
    }
    var allCount: Int { allNodes.count + additionalConfigurationCount + (space.relevanceGatewayId == nil ? 0 : 1) }
    var gatewayWarningName: String? { space.relevanceGatewayId.map { gateway?.name ?? $0 } }
    var hasReadyProxy: Bool {
        isCurrent && MeshLibManager.manager.currentProxyReadyContext != nil
            && MeshLibManager.manager.currentProxy?.isOpen == true && MeshLibManager.manager.isMeshNetworkConnected
    }
    private var isCurrent: Bool {
        !cancelled && account == UserData.currentUserId && region == String(describing: UserData.currentServerRegion)
            && MeshNetworkManager.instance === manager && manager.meshNetwork === network
            && manager.currentNetworkKey.networkId.hex == space.meshNetworkId
            && space.deviceOperates(excludingDeletionEntries: Set(contexts.values.compactMap(\.preparedEntryID))).contains(.delete)
            && recoveryContext.map { SpaceConfigurationSafety.isCurrent($0, space: space) } == true
            && !SpaceConfigurationSafety.hasPendingImport(space)
    }
    func cancel() { cancelled = true; executor.cancel() }

    func run(selectedNodes: [Node], all: Bool, forceLocal: Bool) async -> Outcome {
        guard !didRun, isCurrent, !manager.busy else { return .init(errorKey: "batch_delete_context_changed") }
        didRun = true; deletesAll = all
        defer { allNodes.removeAll() }
        let targets = all ? allNodes : selectedNodes
        guard targets.allSatisfy({ target in network.nodes.contains { $0 === target } }) else {
            return .init(errorKey: "batch_delete_context_changed")
        }
        selected = Set(targets.map { $0.uuid.uuidString })
        contexts = Dictionary(uniqueKeysWithValues: targets.map {
            ($0.uuid.uuidString, DevicePermanentDeletionContext(node: $0, space: space))
        })
        guard contexts.values.allSatisfy(\.isPrepared) else {
            contexts.values.forEach { $0.cancel() }
            return .init(errorKey: "configuration_deletion_cleanup_pending")
        }
        var meshResult: LightsBatchDeletionExecutor.Result?
        var gatewayResult: GatewayDeletionCoordinator.Result?
        if all, space.relevanceGatewayId != nil {
            guard let gateway, let siteNetwork,
                  let node = siteNetwork.nodes.first(where: { $0.primaryUnicastAddress == gateway.address }),
                  let context = GatewayDeletionContext(site: site, gateway: gateway, node: node, siteNetwork: siteNetwork) else {
                contexts.values.forEach { $0.cancel() }
                return .init(errorKey: "gateway_delete_local_failed")
            }
            selected.insert(node.uuid.uuidString)
            let deadline = ProcessInfo.processInfo.systemUptime + 30
            let restoreSync = gateway.needUploadCloud || CloudSynchronizationManager.shared.getGatewayCurrentSyncState(gateway) != nil
            gatewayResult = await GatewayDeletionCoordinator().delete(using: .init(
                isOnline: { NetworkRequest.shared.networkable },
                isCurrent: { self.isCurrent && context.isCurrent },
                serverAlreadyDeleted: { gateway.serverDeletionPendingLocalReset || context.serverAlreadyDeleted },
                permission: { await self.gatewayPermission(gateway, deadline: deadline) },
                prepare: {
                    guard context.prepare() else { return false }
                    gateway.isServerDeletionInProgress = true
                    CloudSynchronizationManager.shared.cancelSynchronizationHandle(operation: .syncGateway(gateway: gateway, node: node))
                    return true
                },
                deleteServer: {
                    await GatewayServerAuthorizationService.shared.waitForInFlightAuthorizationToFinish(gateway: gateway)
                    guard self.isCurrent else { return false }
                    let remaining = deadline - ProcessInfo.processInfo.systemUptime
                    guard remaining > 0 else { return false }
                    guard context.recordServerRequest() else { return false }
                    if case .success = await NetworkRequest.shared.request(.gatewayDelete(gatewayId: gateway.mac), maximumDuration: remaining) {
                        return true
                    }
                    return false
                },
                recordServerDeletion: {
                    // Save the pending flag even if writing the receipt fails.
                    gateway.serverDeletionPendingLocalReset = true
                    let flagSaved = gateway.save()
                    let receiptSaved = context.recordServerDeletion()
                    return flagSaved && receiptSaved
                },
                canReset: { true },
                reset: {
                    meshResult = await self.send(targets: targets, gatewayNode: node, forceLocal: forceLocal)
                    // A multicast write is not an acknowledged physical reset.
                    return self.acknowledged.contains(node.uuid.uuidString)
                },
                finishLocal: { confirmed in
                    let done = context.finish(resetConfirmed: confirmed)
                    self.gatewayRemoved = done
                    if done {
                        for item in self.site.spaces where item.relevanceGatewayId?.uppercased() == gateway.mac.uppercased() {
                            item.relevanceGatewayId = nil; item.gatewayStatus = .notBound; item.gatewayLastOnline = nil
                        }
                        self.space.relevanceGatewayId = nil; self.space.gatewayStatus = .notBound
                    }
                    return done
                },
                cancelPreparation: { context.cancelPreparation() }
            ))
            context.release()
            gateway.isServerDeletionInProgress = false
            if restoreSync, !gateway.serverDeletionPendingLocalReset,
               !GatewayDeletionContext.hasPendingDeletion(siteId: site.id, mac: gateway.mac) {
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncGateway(gateway: gateway, node: node), level: .promptly)
            }
            if meshResult == nil {
                contexts.values.forEach { $0.cancel() }
                return .init(errorKey: gatewayFailureKey(gatewayResult), cleanupPending: gateway.serverDeletionPendingLocalReset)
            }
        } else {
            meshResult = await send(targets: targets, gatewayNode: nil, forceLocal: forceLocal)
        }
        guard isCurrent, let meshResult else { return .init(errorKey: "batch_delete_context_changed") }
        // Unconfirmed devices remain in the Space. Cancel only their unexecuted
        // intents before computing the survivors' final synchronization tasks.
        // A Leave receipt, if any, is retained by cancel() for recovery.
        for id in meshResult.failed { contexts[id]?.cancel() }
        var outcome = await cleanup(ids: meshResult.succeeded)
        outcome.failed.formUnion(meshResult.failed.intersection(Set(contexts.keys)))
        outcome.changed = outcome.changed || gatewayRemoved
        if let gatewayResult, case .failed = gatewayResult {
            outcome.cleanupPending = true
            outcome.errorKey = gatewayFailureKey(gatewayResult)
        }
        cleanupSwitches(outcome: &outcome, force: forceLocal)
        finishChange(outcome.changed)
        return outcome
    }

    func forceRemaining(_ failed: Set<String>) async -> Outcome {
        guard isCurrent else { return .init(errorKey: "batch_delete_context_changed") }
        var outcome = await cleanup(ids: failed.intersection(Set(contexts.keys)))
        cleanupSwitches(outcome: &outcome, force: true)
        finishChange(outcome.changed)
        return outcome
    }

    private func send(targets: [Node], gatewayNode: Node?, forceLocal: Bool) async -> LightsBatchDeletionExecutor.Result {
        if forceLocal { return .init(succeeded: selected, failed: []) }
        let lib = MeshLibManager.manager
        guard hasReadyProxy, let ready = lib.currentProxyReadyContext, let bearer = lib.currentProxy,
              let key = network.applicationKeys.first(where: { $0.boundNetworkKey.networkId.hex == space.meshNetworkId }) else {
            return .init(succeeded: [], failed: selected)
        }
        var known = allNodes
        // Include every known Site-level AppKey holder, even if its UI association
        // is stale. Such an unselected receiver forbids broadcast/unsafe groups.
        for node in siteNetwork?.nodes ?? [] where !node.isProvisioner && node.knows(applicationKeyIndex: key.index) {
            if !known.contains(where: { $0.uuid == node.uuid }) { known.append(node) }
        }
        if let gatewayNode, !known.contains(where: { $0.uuid == gatewayNode.uuid }) { known.append(gatewayNode) }
        let groups = network.groups
        let snapshots = known.map { node -> LightsBatchDeletionPlan.Node in
            let vendors = node.elements.flatMap(\.models).filter { $0.modelId == UInt32.vensorServerModelId }
            let bound = vendors.filter { $0.isBoundTo(key) }
            let address = node.knows(applicationKeyIndex: key.index) && node.knows(networkKeyIndex: key.boundNetworkKeyIndex)
                ? bound.first?.parentElement?.unicastAddress : nil
            return .init(id: node.uuid.uuidString, address: node.primaryUnicastAddress, vendorAddress: address,
                         businessGroup: node.group?.address.address,
                         subscriptions: Set(groups.filter { group in vendors.contains { $0.isSubscribed(to: group) } }.map { $0.address.address }),
                         groupStateKnown: !node.needSync && address != nil)
        }
        let proxyID = known.first { $0.primaryUnicastAddress == ready.nodeAddress }?.uuid.uuidString
        let plan = LightsBatchDeletionPlan.make(nodes: snapshots, selected: selected,
                                                allowBroadcast: (deletesAll || selected == Set(known.map { $0.uuid.uuidString }))
                                                    && snapshots.allSatisfy(\.groupStateKnown),
                                                proxyID: proxyID)
        let observer = lib.addGlobalMessageObserver { [weak self] incomingManager, message, source, destination in
            guard let status = message as? SunricherVendorStatus, let parameters = status.parameters else { return }
            Task { @MainActor in
                guard let self, self.isCurrent, incomingManager === self.manager,
                      destination == self.manager.localNode?.primaryUnicastAddress else { return }
                self.executor.receive(source: source, parameters: parameters)
            }
        }
        defer { lib.removeGlobalMessageObserver(observer) }
        return await executor.run(plan: plan, isCurrent: {
            self.isCurrent && !self.manager.busy && lib.currentProxyReadyContext == ready && lib.currentProxy === bearer
                && Set(self.network.nodes.filter { !$0.isProvisioner && !$0.isLocalProvisioner && $0.subNetworkId == self.space.meshNetworkId }.map { $0.uuid.uuidString }) == Set(self.allNodes.map { $0.uuid.uuidString })
                && targets.allSatisfy { target in self.network.nodes.contains { $0 === target } }
        }, send: { task in
            do {
                try await self.manager.submitDeviceLeave(to: task.destination, using: key, via: bearer,
                    isCurrent: { self.isCurrent && lib.currentProxyReadyContext == ready && lib.currentProxy === bearer })
                return true
            } catch { return false }
        }, record: { ids, evidence in
            if evidence == .acknowledged { self.acknowledged.formUnion(ids) }
            return Set(ids.filter { id in
                if let context = self.contexts[id] { return context.recordLeave(evidence: evidence.rawValue) }
                return gatewayNode?.uuid.uuidString == id // Independent server receipt owns Gateway completion.
            })
        })
    }

    private func cleanup(ids: Set<String>) async -> Outcome {
        let started = ProcessInfo.processInfo.systemUptime
        let result = await DevicePermanentDeletionContext.forceRemoveBatch(
            ids.sorted().compactMap { contexts[$0] }, isCurrent: { self.isCurrent })
        if result.changed { latestLifecycle = result.lifecycle }
        for id in result.completed { contexts.removeValue(forKey: id) }
        var outcome = Outcome(failed: result.failed, cleanupPending: result.cleanupPending, changed: result.changed)
        if result.interrupted { outcome.errorKey = "batch_delete_context_changed" }
        if !result.cleanupPending && !result.interrupted, let latestLifecycle {
            outcome.lifecycle = [latestLifecycle]
        }
        #if DEBUG
        print("[LightsBatchDeletion] cleanup requested=\(ids.count) completed=\(result.completed.count) failed=\(result.failed.count) interrupted=\(result.interrupted) seconds=\(ProcessInfo.processInfo.systemUptime - started)")
        #endif
        return outcome
    }

    private func cleanupSwitches(outcome: inout Outcome, force: Bool) {
        guard deletesAll, isCurrent else { return }
        let remaining = Set(network.nodes.flatMap { $0.elements.compactMap(\.unicastAddress) })
        for item in switches {
            let proxies = Set([item.proxyNodeAddress, item.deleteProxyNodeAddress].compactMap { $0 })
            guard force || proxies.isDisjoint(with: remaining) else { outcome.cleanupPending = true; continue }
            manager.deleteSwitch(switchData: item, resetDevice: false, removeNodeAndGroups: false)
            if DeviceSwitchData.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId).contains(where: { $0.id == item.id }) {
                outcome.cleanupPending = true
            } else { outcome.changed = true }
        }
    }

    private func finishChange(_ changed: Bool) {
        guard changed, isCurrent else { return }
        space.commitLocalChangeForCloudSync(site: site, changeType: .network(type: .address))
        NotificationCenter.default.post(name: .init(SiteStateChangeNotificationName), object: nil)
    }

    private func gatewayPermission(_ gateway: GatewayModel, deadline: TimeInterval) async -> GatewayDeletionCoordinator.Permission {
        if site.permission == .owner { return .allowed }
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { return .unavailable }
        guard case .success(let response) = await NetworkRequest.shared.request(
            .gatewayAssociationSpaceList(siteId: site.id, gatewayId: gateway.mac), maximumDuration: remaining),
            let list = JSON(response)["data"]["refSpaces"].array else { return .unavailable }
        var editable: [Bool] = []
        for row in list {
            guard let id = row["spaceId"].string else { return .unavailable }
            editable.append(SpaceData.load(siteId: site.id, spaceId: id).first?.permission == .editor)
        }
        return GatewayDestructiveAccessPolicy.canPerform(isOwner: false,
            hasAnyEditableSiteSpace: site.spaces.contains(where: \.canEditGatewayAssociation),
            associatedSpaceEditableStates: editable) ? .allowed : .denied
    }

    private func gatewayFailureKey(_ result: GatewayDeletionCoordinator.Result?) -> String {
        guard case .failed(let failure) = result else { return "gateway_delete_local_failed" }
        switch failure {
        case .offline: return "phone_no_network"
        case .permission: return "no_permission"
        case .server: return "gateway_delete_server_failed"
        default: return "gateway_delete_local_failed"
        }
    }
}
