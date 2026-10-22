import Foundation
import NordicSigMeshSDK

/// The page owns one operation; the shared lane owns transport until cancellation settles.
final class HDBLightingConfigurationService {
    let site: SiteData
    let space: SpaceData
    var didChange: (() -> Void)?
    var didFinish: ((Error?) -> Void)?
    private(set) var isRunning = false
    private let account = UserData.currentUserId
    private let region = String(describing: UserData.currentServerRegion)
    private let coordinator = SyncSessionCoordinator()
    private var task: Task<Void, Never>?
    private var expected: HDBConfiguration?
    private var expectedRevision: Int64?
    private var network: MeshNetwork?
    private var applicationKey: ApplicationKey?
    private var applicationKeyData: Data?
    private var identities: [(Node, UInt16, Data?, [HDBModelTarget])] = []

    init(site: SiteData, space: SpaceData) { self.site = site; self.space = space }

    func saved(nodeUuid: UUID) throws -> HDBLightingConfiguration? {
        try checkPermission(edit: false)
        return HDBLightingConfigurationPolicy.saved(nodeUuid: nodeUuid, in: try HDBConfigurationStore.load(space: space))
    }

    private func checkPermission(edit: Bool) throws {
        guard account == UserData.currentUserId, region == String(describing: UserData.currentServerRegion),
              site.id == space.siteId, (try? site.loadIsHdbSite()) == true, let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
              latest.meshUUID == space.meshUUID, latest.meshNetworkId == space.meshNetworkId,
              !SpaceConfigurationSafety.isBlocked(latest) else { throw HDBConfigurationError.unavailable }
        if edit && (!latest.canEditing || !space.groupOperates.contains(.edit)) { throw HDBConfigurationError.permissionDenied }
    }

    private func nodes(nodeUuid: UUID, network: MeshNetwork) throws -> [Node] {
        guard let node = network.nodes.first(where: {
            $0.uuid == nodeUuid && $0.subNetworkId == space.meshNetworkId
                && !$0.isProvisioner && !$0.isConfigComplete && $0.deviceType == .light
        }) else { throw HDBConfigurationError.unavailable }
        _ = try HDBConfigurationStore.deviceConfiguration(node: node)
        return [node]
    }

    private func targets(_ node: Node) -> [HDBModelTarget] {
        node.elements.flatMap { element in element.models.map {
            .init(elementAddress: element.unicastAddress, modelIdentifier: $0.modelIdentifier, companyIdentifier: $0.companyIdentifier)
        } }
    }

    private func capture(_ nodes: [Node], network: MeshNetwork) throws -> ApplicationKey {
        guard !MeshProxyMessageCommand.shared.isBusy else { throw HDBConfigurationError.busy }
        guard MeshLibManager.manager.isMeshNetworkConnected,
              network === MeshNetworkManager.instance.meshNetwork,
              network.uuid.uuidString == space.meshUUID,
              MeshNetworkManager.instance.currentNetworkKey.networkId.hex == space.meshNetworkId,
              let key = network.applicationKeys.first(where: { $0.boundNetworkKey.networkId.hex == space.meshNetworkId }) else {
            throw HDBZoneControlError.disconnected
        }
        self.network = network
        applicationKey = key; applicationKeyData = key.key
        identities = nodes.map { ($0, $0.primaryUnicastAddress, $0.deviceKey, targets($0)) }
        return key
    }

    private func isCurrent(edit: Bool) -> Bool {
        guard (try? checkPermission(edit: edit)) != nil,
              let network = network, network === MeshNetworkManager.instance.meshNetwork,
              MeshNetworkManager.instance.currentNetworkKey.networkId.hex == space.meshNetworkId,
              let key = applicationKey, key.key == applicationKeyData,
              key.boundNetworkKey.networkId.hex == space.meshNetworkId,
              network.applicationKeys.contains(where: { $0.index == key.index && $0.key == applicationKeyData }),
              (try? HDBConfigurationStore.load(space: space)) == expected,
              (try? HDBConfigurationStore.revision(space: space)) == expectedRevision,
              let persisted = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else { return false }
        return identities.allSatisfy { node, address, key, models in
            guard network.nodes.contains(where: { $0 === node }), node.primaryUnicastAddress == address,
                  node.deviceKey == key, node.subNetworkId == space.meshNetworkId,
                  !node.isConfigComplete, targets(node) == models,
                  let saved = persisted.nodes.first(where: { $0.uuid == node.uuid }) else { return false }
            return saved.primaryUnicastAddress == address && saved.deviceKey == key && saved.subNetworkId == space.meshNetworkId
        }
    }

    func set(nodeUuid: UUID, command: HDBLightingCommand, values: HDBLightingValues) throws {
        guard !isRunning else { throw HDBConfigurationError.busy }
        try checkPermission(edit: true)
        let writes = try HDBLightingConfigurationPolicy.writes(command, values: values)
        var config = try HDBConfigurationStore.load(space: space)
        let active = MeshNetworkManager.instance.meshNetwork
        guard let network = (active?.uuid.uuidString == space.meshUUID ? active : nil)
                ?? MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else { throw HDBConfigurationError.unavailable }
        let nodes = try nodes(nodeUuid: nodeUuid, network: network)
        var recipients: [HDBLightingRecipient] = []
        var key: ApplicationKey?
        if !writes.isEmpty {
            guard !nodes.isEmpty else { throw HDBZoneControlError.emptyZone }
            key = try capture(nodes, network: network)
            for node in nodes {
                guard !EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: node) else { throw HDBZoneControlError.emergency }
                let required = try HDBLightingZonePolicy.requiredTargets(from: targets(node))
                guard let context = try HDBDeviceSyncContext.resolve(space: space, node: node),
                      try HDBDeviceSyncService.isPrepared(context: context, config: config) else { throw HDBLightingError.notPrepared }
                let recipient = HDBLightingRecipient(nodeUuid: node.uuid, nodeAddress: node.primaryUnicastAddress, targets: required)
                recipients.append(recipient)
                for write in writes {
                    for target in try HDBLightingConfigurationPolicy.targets(for: write, recipient: recipient) {
                        _ = try HDBLightingMessages.model(target, node: node, key: key!)
                    }
                }
            }
        }
        let deliveries = try recipients.flatMap { try HDBLightingConfigurationPolicy.route(writes, recipient: $0) }
        expected = config
        expectedRevision = try HDBConfigurationStore.revision(space: space)
        func saveIntent() throws {
            try HDBConfigurationStore.update(space: space) { current in
                guard current == config, try HDBConfigurationStore.revision(space: space) == expectedRevision else { throw HDBConfigurationError.unavailable }
                for node in nodes where !current.devices.contains(where: { $0.nodeUuid == node.uuid }) {
                    current.devices.append(try HDBConfigurationStore.deviceConfiguration(node: node))
                }
                try HDBLightingConfigurationPolicy.record(nodeUuid: nodeUuid, command: command, values: values,
                    status: writes.isEmpty ? .synced : .pending, in: &current)
            }
            config = try HDBConfigurationStore.load(space: space)
            expected = config
            expectedRevision = try HDBConfigurationStore.revision(space: space)
            didChange?()
        }
        guard let key = key, !deliveries.isEmpty else { try saveIntent(); didFinish?(nil); return }
        begin(edit: true) { [self] in
            try saveIntent()
            var remaining = Dictionary(grouping: deliveries, by: { $0.write.fieldName }).mapValues(\.count)
            do {
                for delivery in deliveries {
                    try Task.checkCancellation()
                    guard isCurrent(edit: true) else { throw HDBConfigurationError.unavailable }
                    guard !nodes.contains(where: { EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: $0) }) else { throw HDBZoneControlError.emergency }
                    let request = HDBLightingMessages.message(delivery.write)
                    guard let node = nodes.first(where: { $0.uuid == delivery.nodeUuid }) else { throw HDBConfigurationError.unavailable }
                    let model = try HDBLightingMessages.model(delivery.target, node: node, key: key)
                    let response = try await MeshNetworkManager.instance.send(request, to: model)
                    guard HDBLightingMessages.matches(request, response: response) else { throw HDBLightingError.responseMismatch }
                    try Task.checkCancellation()
                    guard isCurrent(edit: true) else { throw HDBConfigurationError.unavailable }
                    let field = delivery.write.fieldName
                    remaining[field, default: 0] -= 1
                    if remaining[field] == 0 { try recordResult(field: field) }
                }
                try Task.checkCancellation()
                guard isCurrent(edit: true) else { throw HDBConfigurationError.unavailable }
            } catch {
                throw error
            }
            func recordResult(field: String) throws {
                try HDBConfigurationStore.update(space: space) { current in
                    guard current == expected else { throw HDBConfigurationError.unavailable }
                    try HDBLightingConfigurationPolicy.record(nodeUuid: nodeUuid, command: command, values: values.only(field),
                        status: .synced, in: &current)
                }
                expected = try HDBConfigurationStore.load(space: space)
                expectedRevision = try HDBConfigurationStore.revision(space: space)
            }
        }
    }

    func get(nodeUuid: UUID, command: HDBLightingCommand, completion: @escaping (String) -> Void) throws {
        guard !isRunning else { throw HDBConfigurationError.busy }
        try checkPermission(edit: false)
        let config = try HDBConfigurationStore.load(space: space)
        let saved = HDBLightingConfigurationPolicy.saved(nodeUuid: nodeUuid, in: config)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let savedText = String(decoding: try encoder.encode(saved?.values.selected(command) ?? HDBLightingValues()), as: UTF8.self)
        let active = MeshNetworkManager.instance.meshNetwork
        guard let availableNetwork = (active?.uuid.uuidString == space.meshUUID ? active : nil)
            ?? MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else { throw HDBConfigurationError.unavailable }
        _ = try nodes(nodeUuid: nodeUuid, network: availableNetwork)
        guard command != .installDate else { completion(savedText); return }
        guard let network = MeshNetworkManager.instance.meshNetwork else { throw HDBConfigurationError.unavailable }
        let nodes = try nodes(nodeUuid: nodeUuid, network: network)
        let key = try capture(nodes, network: network)
        expected = config
        expectedRevision = try HDBConfigurationStore.revision(space: space)
        var requests: [(Node, HDBModelTarget, AcknowledgedMeshMessage)] = []
        for node in nodes {
            let recipient = HDBLightingRecipient(nodeUuid: node.uuid, nodeAddress: node.primaryUnicastAddress, targets: targets(node))
            func target(_ write: HDBLightingWrite) throws -> HDBModelTarget {
                try HDBLightingConfigurationPolicy.targets(for: write, recipient: recipient)[0]
            }
            if command == .override {
                let lc = try target(.auto)
                requests.append((node, lc, LightLCModeGet()))
                requests.append((node, lc, LightLCLightOnOffGet()))
                requests.append((node, try target(.lightness(65535)), LightLightnessGet()))
            } else {
                for write in try HDBLightingConfigurationPolicy.writes(command, values: .defaults) {
                    if case .property(let id, _) = write {
                        requests.append((node, try target(write), LightLCPropertyGet(DeviceProperty(id))))
                    }
                }
            }
        }
        guard !requests.isEmpty else { throw HDBConfigurationError.unsupportedModels }
        let models = try requests.map { try HDBLightingMessages.model($0.1, node: $0.0, key: key) }
        begin(edit: false) { [self] in
            var rows: [[String: String]] = []
            var missing = false
            for (index, request) in requests.enumerated() {
                try Task.checkCancellation()
                guard isCurrent(edit: false) else { throw HDBConfigurationError.unavailable }
                do {
                    let response = try await MeshNetworkManager.instance.send(request.2, to: models[index])
                    let observation = try HDBLightingMessages.observation(request: request.2, response: response)
                    rows.append(["element": String(format: "%04X", request.1.elementAddress), "property": observation.0, "value": observation.1])
                } catch {
                    try Task.checkCancellation()
                    missing = true
                    rows.append(["element": String(format: "%04X", request.1.elementAddress), "error": error.localizedDescription])
                }
            }
            guard isCurrent(edit: false) else { throw HDBConfigurationError.unavailable }
            let grouped = Dictionary(grouping: rows.filter { $0["property"] != nil }, by: { $0["property"]! })
            let mixed = grouped.values.contains { Set($0.compactMap { $0["value"] }).count > 1 }
            let result: [String: Any] = ["saved": try JSONSerialization.jsonObject(with: Data(savedText.utf8)),
                                        "observed": rows, "mixed": mixed, "incomplete": missing]
            completion(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        }
    }

    private func begin(edit: Bool, operation: @escaping @MainActor () async throws -> Void) {
        isRunning = true; didChange?()
        coordinator.start { [weak self] identifier in
            guard let self = self else { return }
            self.task = Task { @MainActor [self] in
                var failure: Error?
                do { guard self.isCurrent(edit: edit) else { throw HDBConfigurationError.unavailable }; try await operation() }
                catch { failure = error }
                self.task = nil
                self.coordinator.finish(identifier, settle: { $0() }) { [self] in
                    self.isRunning = false; self.didChange?(); self.didFinish?(failure)
                }
            }
        }
    }

    func cancel() {
        guard isRunning else { return }
        let wasActive = coordinator.isRunning
        coordinator.stop { [self] done in
            guard let task = task else { isRunning = false; done(); didChange?(); return }
            task.cancel()
            Task { @MainActor in
                await task.value
                self.isRunning = false
                done()
                self.didChange?()
            }
        }
        // A queued operation has no transport to settle. An active operation stays busy
        // until its old task has finished all cancellation/result callbacks.
        if !wasActive && !coordinator.isSettling { isRunning = false; didChange?() }
    }
}

enum HDBLightingError: Error { case notPrepared, responseMismatch }
