import Foundation
import NordicSigMeshSDK

enum HDBZoneControlAction {
    case auto, on, off, brightness(Int)
}

enum HDBZoneControlError: Error {
    case disconnected, emptyZone, emergency, invalidBrightness
}

final class HDBLightingZoneService {
    let site: SiteData
    let space: SpaceData
    var didChange: (() -> Void)?
    var didFinish: ((Error?) -> Void)?
    private let account = UserData.currentUserId
    private let region = String(describing: UserData.currentServerRegion)
    private let environment = SyncExecutionEnvironment()
    private var executor: HDBLightingZoneExecutor?
    private var expectedIntent: Data?
    private var expectedRevision: Int64?
    private var network: MeshNetwork?
    private var plans: [UUID: HDBZonePlan] = [:]
    private var capturedNodes: [UUID: (node: Node, address: UInt16, deviceKey: Data?)] = [:]
    private var dirtyNodes = Set<UUID>()
    private var activeAttempt: UUID?
    private var isStopping = false
    private var cachePersistenceError: Error?
    var isRunning: Bool { executor?.isRunning == true }
    var lastError: Error? { cachePersistenceError ?? executor?.error }

    init(site: SiteData, space: SpaceData) { self.site = site; self.space = space }

    /// Test requests use the mapped group address. They never change saved membership results.
    func control(zoneId: Int, groupAddress: UInt16, action: HDBZoneControlAction) throws {
        precondition(Thread.isMainThread)
        if case .brightness(let value) = action, !(0...100).contains(value) {
            throw HDBZoneControlError.invalidBrightness
        }
        try validateControl(zoneId: zoneId, groupAddress: groupAddress)
        switch action {
        case .auto:
            MeshAPI.sendMessage(message: LightLCLightOnOffSetUnacknowledged(true), address: groupAddress)
        case .on:
            LightGroupControlCommandSender.setGroupOnOff(address: groupAddress, isOn: true)
        case .off:
            LightGroupControlCommandSender.setGroupOnOff(address: groupAddress, isOn: false)
        case .brightness(let value):
            LightGroupControlCommandSender.setGroupLightness(address: groupAddress, lightness: Node.getLightness(lightness100: value))
        }
    }

    func validateControl(zoneId: Int, groupAddress: UInt16) throws {
        guard !isRunning, !MeshProxyMessageCommand.shared.isBusy else { throw HDBConfigurationError.busy }
        let network = try editableNetwork()
        guard let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
              latest.meshUUID == space.meshUUID else { throw HDBConfigurationError.unavailable }
        let config = try HDBConfigurationStore.load(space: space)
        guard config.lightingZones.contains(where: { $0.zoneId == zoneId && $0.groupAddress == groupAddress }),
              let group = network.group(withAddress: groupAddress), !group.isVirtual,
              group.subNetworkId == space.meshNetworkId else { throw HDBConfigurationError.unavailable }
        let members = config.devices.filter { $0.lightingZones.contains { $0.zoneId == zoneId } }
        guard !members.isEmpty else { throw HDBZoneControlError.emptyZone }
        let ids = Set(members.map(\.nodeUuid))
        guard !EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: group),
              !network.nodes.contains(where: { ids.contains($0.uuid) && EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: $0) }) else {
            throw HDBZoneControlError.emergency
        }
        guard MeshLibManager.manager.isMeshNetworkConnected else { throw HDBZoneControlError.disconnected }
    }

    func getLightingZones(nodeUuid: UUID) throws -> HDBDeviceConfiguration {
        guard account == UserData.currentUserId, region == String(describing: UserData.currentServerRegion) else { throw HDBConfigurationError.unavailable }
        let config = try HDBConfigurationStore.load(space: space)
        if let saved = HDBLightingZonePolicy.get(nodeUuid, in: config) { return saved }
        // Local metadata only; Get never starts a connection or a cloud request.
        guard let local = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
              let node = local.nodes.first(where: { $0.uuid == nodeUuid }) else { throw HDBConfigurationError.unavailable }
        return try HDBConfigurationStore.deviceConfiguration(node: node)
    }

    func setLightingZones(nodeUuid: UUID, zoneIds: [Int]) throws {
        guard !isRunning else { throw HDBConfigurationError.busy }
        let node = try editableNode(nodeUuid)
        _ = try modelTargets(node)
        guard let context = try HDBDeviceSyncContext.resolve(space: space, node: node) else {
            throw HDBConfigurationError.unavailable
        }
        let current = try HDBConfigurationStore.load(space: space)
        if !zoneIds.isEmpty {
            guard try HDBDeviceSyncService.canSetZones(context: context, config: current) else { throw HDBLightingError.notPrepared }
        }
        let next = try HDBLightingZonePolicy.replacingZones(zoneIds, for: HDBConfigurationStore.deviceConfiguration(node: node), in: current)
        // Validate Sensor allocation and shared-list targets before replacing durable intent.
        let operations = try context.zoneOperations(in: next)
        try HDBConfigurationStore.update(space: space) { config in
            guard config == current else { throw HDBConfigurationError.unavailable }
            config = next
        }
        node.clearSyncStateCache()
        try run(operations, config: next)
    }

    /// Manual replay is allowed even when the last saved result is synced.
    func retry(nodeUuid: UUID) throws {
        let device = try getLightingZones(nodeUuid: nodeUuid)
        try setLightingZones(nodeUuid: nodeUuid, zoneIds: device.lightingZones.map(\.zoneId))
    }

    func cancel() { executor?.cancel() }

    private func editableNode(_ uuid: UUID) throws -> Node {
        let network = try editableNetwork()
        guard let node = network.nodes.first(where: { $0.uuid == uuid }), isEditable(node) else {
            throw HDBConfigurationError.unavailable
        }
        return node
    }

    private func editableNetwork() throws -> MeshNetwork {
        guard account == UserData.currentUserId, region == String(describing: UserData.currentServerRegion),
              site.id == space.siteId, (try? site.loadIsHdbSite()) == true,
              let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
              latest.canEditing, space.groupOperates.contains(.edit), !SpaceConfigurationSafety.isBlocked(latest),
              let network = MeshNetworkManager.instance.meshNetwork, network.uuid.uuidString == space.meshUUID,
              MeshNetworkManager.instance.currentNetworkKey.networkId.hex == space.meshNetworkId else { throw HDBConfigurationError.unavailable }
        return network
    }

    private func isEditable(_ node: Node) -> Bool {
        node.subNetworkId == space.meshNetworkId && !node.isProvisioner && !node.isConfigComplete && node.deviceType == .light
    }


    func supports(_ node: Node) -> Bool { (try? modelTargets(node)) != nil }

    private func modelTargets(_ node: Node) throws -> [HDBModelTarget] {
        try HDBLightingZonePolicy.requiredZoneTargets(from: HDBConfigurationStore.modelTargets(node: node), primaryAddress: node.primaryUnicastAddress)
    }

    private func intent(_ config: HDBConfiguration) throws -> Data {
        var copy = config
        // The expected value is refreshed after our own successful result persistence.
        for d in copy.devices.indices { copy.devices[d].lightingZonesStatus = .pending }
        return try JSONSerialization.data(withJSONObject: HDBLightingZonePolicy.canonical(copy), options: .sortedKeys)
    }

    private func run(_ operations: [HDBZoneOperation], config: HDBConfiguration) throws {
        #if DEBUG
        print("[HDB][LightingZones] plan zoneTasks=\(operations.count)")
        #endif
        network = MeshNetworkManager.instance.meshNetwork
        capturedNodes = [:]; plans = [:]; dirtyNodes = []; activeAttempt = nil; isStopping = false; cachePersistenceError = nil
        for op in operations {
            let node = try editableNode(op.nodeUuid)
            guard node.primaryUnicastAddress == op.nodeAddress, try modelTargets(node) == op.targets else {
                throw HDBConfigurationError.unavailable
            }
            plans[op.nodeUuid] = op.plan
            capturedNodes[op.nodeUuid] = (node, node.primaryUnicastAddress, node.deviceKey)
        }
        expectedIntent = try intent(config)
        expectedRevision = try HDBConfigurationStore.revision(space: space)
        let executor = HDBLightingZoneExecutor(send: { [weak self] op, done in self?.send(op, completion: done) },
            stop: { [weak self] done in
                guard let self = self else { done(); return }
                self.isStopping = true
                self.environment.stop {
                    self.activeAttempt = nil; self.isStopping = false
                    do { try self.flushAcknowledgedSubscriptions() }
                    catch { self.cachePersistenceError = error }
                    done()
                }
            }, isCurrent: { [weak self] in self?.isCurrent() == true },
            persist: { [weak self] receipt in
                guard let self = self else { throw HDBConfigurationError.unavailable }
                try self.persist(receipt)
            })
        self.executor = executor
        didChange?()
        executor.start(operations) { [weak self] in
            guard let self else { return }
            self.didChange?(); self.didFinish?(self.lastError)
        }
    }

    private func isCurrent(checkIntent: Bool = true) -> Bool {
        guard account == UserData.currentUserId, region == String(describing: UserData.currentServerRegion),
              network === MeshNetworkManager.instance.meshNetwork,
              MeshNetworkManager.instance.currentNetworkKey.networkId.hex == space.meshNetworkId,
              let config = try? HDBConfigurationStore.load(space: space),
              let current = try? editableNetwork() else { return false }
        if checkIntent, (try? intent(config)) != expectedIntent
            || (try? HDBConfigurationStore.revision(space: space)) != expectedRevision { return false }
        guard !capturedNodes.isEmpty else { return true }
        // Read one persisted snapshot per check, not an entire Mesh per member.
        guard let saved = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else { return false }
        let currentByUUID = Dictionary(current.nodes.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        let savedByUUID = Dictionary(saved.nodes.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        return capturedNodes.allSatisfy { uuid, captured in
            guard let node = currentByUUID[uuid], node === captured.node, isEditable(node),
                  let persisted = savedByUUID[uuid], persisted.subNetworkId == space.meshNetworkId else { return false }
            if checkIntent {
                guard let plan = plans[uuid], HDBLightingZonePolicy.matches(plan, in: config),
                  (try? modelTargets(node)) == plan.targets,
                  let context = try? HDBDeviceSyncContext.resolve(space: space, node: node),
                  (try? context.zoneSensorTargets(in: config)) == plan.sensorTargets,
                  (try? context.zoneBroadcastTargets()) == plan.broadcastTargets else { return false }
            }
            return node.primaryUnicastAddress == captured.address && node.deviceKey == captured.deviceKey
                && persisted.primaryUnicastAddress == captured.address && persisted.deviceKey == captured.deviceKey
        }
    }

    private func persist(_ receipt: HDBZoneReceipt) throws {
        try flushAcknowledgedSubscriptions()
        guard receipt.successful else { return }
        let op = receipt.operation
        guard let node = capturedNodes[op.nodeUuid]?.node else { throw HDBConfigurationError.unavailable }
        if op.isLast {
            try HDBConfigurationStore.update(space: space) { config in
                try HDBLightingZonePolicy.complete(op, in: &config)
            }
            expectedIntent = try intent(HDBConfigurationStore.load(space: space))
            expectedRevision = try HDBConfigurationStore.revision(space: space)
        }
        node.clearSyncStateCache()
        didChange?()
    }

    private func flushAcknowledgedSubscriptions() throws {
        guard !dirtyNodes.isEmpty else { return }
        guard isCurrent(checkIntent: false) else { throw HDBConfigurationError.unavailable }
        for uuid in Array(dirtyNodes) {
            guard let node = capturedNodes[uuid]?.node, node.save() else { throw HDBConfigurationError.persistenceFailed }
            dirtyNodes.remove(uuid)
            node.clearSyncStateCache()
        }
        didChange?()
    }

    static func handles(for operation: HDBZoneOperation) throws -> [MeshMessageHandle] {
        try operation.subscriptions.map { subscription in
            let message: MeshMessage?
            switch subscription.command {
            case .deleteAll: message = ConfigModelSubscriptionDeleteAll(parameters: subscription.parameters)
            case .add: message = ConfigModelSubscriptionAdd(parameters: subscription.parameters)
            }
            guard let message else { throw HDBConfigurationError.invalidData }
            let handle = MeshMessageHandle(message: message, address: operation.nodeAddress)
            handle.continuous = false
            return handle
        }
    }

    static func matches(_ subscription: HDBZoneSubscription, status: ConfigModelSubscriptionStatus) -> Bool {
        status.isSuccess && status.address == subscription.address
            && status.elementAddress == subscription.target.elementAddress
            && status.modelIdentifier == subscription.target.modelIdentifier
            && status.companyIdentifier == subscription.target.companyIdentifier
    }

    /// HDB firmware clears the full extension chain; SDK Add/Get caches remain per element.
    /// Call only after a current, strictly matched successful acknowledgement.
    static func applyAcknowledgedSubscription(_ subscription: HDBZoneSubscription, to node: Node) {
        guard subscription.command == .deleteAll,
              let model = node.elements.first(where: { $0.unicastAddress == subscription.target.elementAddress })?.models.first(where: {
                  $0.modelIdentifier == subscription.target.modelIdentifier && $0.companyIdentifier == subscription.target.companyIdentifier
              }) else { return }
        for affected in Set([model] + model.relatedModels) { affected.unsubscribeFromAll() }
    }

    private func send(_ op: HDBZoneOperation, completion: @escaping (HDBZoneReceipt) -> Void) {
        guard isCurrent(), let captured = capturedNodes[op.nodeUuid],
              captured.address == op.nodeAddress, (try? modelTargets(captured.node)) == op.targets,
              !op.subscriptions.isEmpty else { completion(.init(operation: op, successful: false)); return }
        let handles: [MeshMessageHandle]
        do { handles = try Self.handles(for: op) }
        catch { completion(.init(operation: op, successful: false, error: error)); return }
        let attempt = UUID()
        activeAttempt = attempt
        var acknowledgements = HDBZoneAcknowledgements(operation: op)
        environment.addMessage(messageHandles: handles, successfulBack: { [weak self] handle, message in
            guard let self, self.isRunning, self.activeAttempt == attempt, self.isCurrent(checkIntent: !self.isStopping),
                  let index = handles.firstIndex(where: { $0 === handle }),
                  let status = message as? ConfigModelSubscriptionStatus,
                  handle.address == op.nodeAddress,
                  Self.matches(op.subscriptions[index], status: status) else { acknowledgements.reject(); return }
            Self.applyAcknowledgedSubscription(op.subscriptions[index], to: captured.node)
            self.dirtyNodes.insert(op.nodeUuid)
            acknowledgements.receive(target: op.subscriptions[index].target, nodeAddress: op.nodeAddress,
                groupAddress: status.address, successful: true)
        }, failedBack: { _ in acknowledgements.reject() }, finishedBack: { [weak self] _ in
            guard let self, self.activeAttempt == attempt else { return }
            self.activeAttempt = nil
            completion(.init(operation: op, successful: acknowledgements.successful))
        })
    }
}
